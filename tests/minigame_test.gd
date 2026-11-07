extends SceneTree
# 三个小游戏（风律回响 / 萤火引路 / 檐雨合拍）的接线与核心规则检查。
# 用法：godot --headless --path . --script res://tests/minigame_test.gd

var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _run() -> void:
	var save := "user://starward_minigame_test.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_minigame_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	_check(game.minigames != null, "小游戏层已创建")
	if game.minigames == null:
		quit(1)
		return
	game.enter_attic()
	await process_frame

	# --- 三个入口 ---
	for pair in [["cloud", "chime"], ["firefly", "firefly"], ["alley", "rain"]]:
		var key: String = pair[0]
		var expect_kind: String = pair[1]
		game.enter_pocket(key)
		await physics_frame
		var anchor = game.attic_worlds.minigame_anchor(key)
		_check(anchor != null, "%s：有小游戏入口" % key)
		if anchor == null:
			game.leave_pocket()
			continue
		game.player.global_position = (anchor as Node3D).global_position
		await physics_frame
		_check(game.near_minigame() == key, "%s：站在入口旁能识别" % key)
		game.open_minigame(key)
		await process_frame
		_check(game.minigame_open and game.minigames.active, "%s：小游戏已打开" % key)
		_check(game.minigames.kind == expect_kind, "%s：打开的是 %s" % [key, expect_kind])

		# --- 各游戏的核心规则 ---
		if expect_kind == "chime":
			_check(game.minigames.sequence.size() == 3, "风律第 1 轮是 3 声")
			# 播完后进入输入阶段
			game.minigames.phase = "play"
			game.minigames.play_timer = 0.0
			for i in range(12):
				game.minigames._update_chime(0.7)
				await process_frame
			_check(game.minigames.phase == "input", "风律：听完后进入输入阶段")
			# 按对整段
			var clone: Array = game.minigames.sequence.duplicate()
			for note in clone:
				game.minigames._chime_press(int(note))
				await process_frame
			_check(game.minigames.round_index == 2 or not game.minigames.active,
				"风律：一段奏完进入下一轮")
			# 按错扣心
			var before: int = game.minigames.hearts
			game.minigames.phase = "input"
			game.minigames.input_index = 0
			var wrong := (int(game.minigames.sequence[0]) + 1) % 4
			game.minigames._chime_press(wrong)
			await process_frame
			_check(game.minigames.hearts == before - 1, "风律：按错扣一颗心")
		elif expect_kind == "firefly":
			_check(game.minigames.lane == 1, "萤火：初始在中间那条树根")
			game.minigames._press("KeyW")
			await process_frame
			_check(game.minigames.lane == 0, "萤火：W 上移到第一条树根")
			game.minigames._press("KeyS")
			game.minigames._press("KeyS")
			await process_frame
			_check(game.minigames.lane == 2, "萤火：S 下移到第三条树根")
			# lane_pos 是按帧插值追过去的，测试里直接对齐，等价于玩家已经站稳在那条树根上
			game.minigames.lane_pos = float(game.minigames.lane)
			# 收集微光
			game.minigames.glints.clear()
			game.minigames.glint_timer = 99.0  # 别让这一帧顺手刷出新的微光，干扰计数
			game.minigames.glints.append({"x": 0.28, "lane": game.minigames.lane})
			var motes_before: int = game.minigames.motes
			game.minigames._update_firefly(0.016)
			await process_frame
			_check(game.minigames.motes == motes_before + 1, "萤火：碰到微光会收集")
			# 撞横枝扣心
			game.minigames.obstacles.clear()
			game.minigames.spawn_timer = 99.0  # 同上：别让随机生成的横枝干扰这次判定
			game.minigames.obstacles.append({"x": 0.28, "lane": game.minigames.lane, "wide": false})
			game.minigames.invuln = 0.0
			game.minigames.time = 2.0
			var hearts_before: int = game.minigames.hearts
			game.minigames._update_firefly(0.016)
			await process_frame
			_check(game.minigames.hearts == hearts_before - 1, "萤火：撞到横枝扣一颗心")
		else:
			_check(game.minigames.notes.size() > 5, "檐雨：生成了音符序列")
			# 命中一个音符
			var note: Dictionary = game.minigames.notes[0]
			game.minigames.time = float(note["at"])
			var score_before: int = game.minigames.score
			game.minigames._rain_press(int(note["lane"]))
			await process_frame
			_check(bool(note["hit"]), "檐雨：按对节拍能接住")
			_check(game.minigames.score > score_before, "檐雨：接住会加分")
			_check(game.minigames.combo >= 1, "檐雨：连击计数")
			# 漏掉会扣心
			var missed := 0
			for other in game.minigames.notes:
				if bool(other["hit"]) or bool(other["missed"]):
					continue
				game.minigames.time = float(other["at"]) + 0.5
				var hearts_now: int = game.minigames.hearts
				game.minigames._update_rain(0.016)
				await process_frame
				if game.minigames.hearts < hearts_now:
					missed += 1
				break
			_check(missed == 1, "檐雨：漏掉会扣一颗心")

		game.minigames.close()
		game.minigame_open = false
		await process_frame
		_check(not game.minigames.active, "%s：小游戏可以关闭" % key)
		game.leave_pocket()
		await physics_frame

	# --- 结束回写最高分 ---
	game.enter_pocket("cloud")
	await physics_frame
	game.open_minigame("cloud")
	await process_frame
	game.minigames.score = 123
	game.minigames._finish(true, "测试收尾")
	await process_frame
	_check(int(game.minigames.best.get("chime", 0)) == 123, "结束后记录最高分")
	_check(not game.minigame_open, "结束后自动关闭小游戏层")
	game.leave_pocket()
	await physics_frame

	game.leave_attic()
	await physics_frame
	print("MINIGAME TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	if FileAccess.file_exists("user://starward_minigame_progress.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_minigame_progress.json"))
	quit(0 if failures == 0 else 1)
