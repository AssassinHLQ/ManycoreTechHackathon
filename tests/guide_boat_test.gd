extends SceneTree
# 新手引导 / 结算画面 / 云舟划桨 / 最近远行记录。
# 用法：godot --headless --path . --script res://tests/guide_boat_test.gd

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
	var test_save := "user://starward_guideboat_test.json"
	var test_progress := "user://starward_guideboat_progress.json"
	_cleanup(test_save)
	_cleanup(test_progress)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	game.progress_path = test_progress
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	# ---------- 一、新手引导 ----------
	_check(game.guide_card != null, "引导卡片已创建")
	_check(game.guide_card.STEP_COUNT == 4, "引导分四步")
	_check(not game.guide_card.active, "引导初始不显示")
	_check(game.guide_card.STEPS[0][0] == "先走两步", "第一步标题照原作")
	_check(String(game.guide_card.STEPS[1][1]).contains("黄铜天气旋钮"), "第二步提到天气旋钮")
	_check(String(game.guide_card.STEPS[2][1]).contains("跨过门槛"), "第三步提到跨门槛")
	_check(String(game.guide_card.STEPS[3][0]).contains("此刻的小事"), "第四步标题提到此刻的小事")
	_check(String(game.guide_card.STEPS[3][1]).contains("纪念"), "第四步正文提到纪念")

	game.progress.reset()
	game.guide_card.begin()
	await process_frame
	_check(game.guide_card.active, "能开始引导")
	_check(game.guide_card.step == 0, "从第一步开始")
	_check(game.guide_card.painter.visible, "引导画面可见")

	# 推进
	game.guide_card.advance(1)
	await process_frame
	_check(game.guide_card.step == 1, "能推进到第二步")
	game.guide_card.advance(0)
	await process_frame
	_check(game.guide_card.step == 1, "不能往回退")
	game.guide_card.advance(4)
	await process_frame
	_check(game.guide_card.step == 1, "超出范围的步骤被忽略")
	game.guide_card.advance(3)
	await process_frame
	_check(game.guide_card.step == 3, "能推进到最后一步")
	_check(game.guide_card.auto_timer > 0.0, "到最后一步后开始自动收尾计时")

	# 跳过
	game.guide_card.skip()
	await process_frame
	_check(not game.guide_card.active, "G 跳过能收尾")
	_check(game.progress.guide_done, "看过之后记进存档")
	_check(not game.guide_card.painter.visible, "收尾后引导画面隐藏")

	# 重播
	game.replay_guide()
	await process_frame
	_check(game.guide_card.active and game.guide_card.step == 0, "能重播引导")
	game.guide_card.finish()
	await process_frame

	# ---------- 二、结算画面 ----------
	_check(game.run_summary != null, "结算画面已创建")
	_check(not game.run_summary.open, "结算画面初始不显示")
	game.run_summary.show_summary({
		"cleared": true, "failed": false, "rank": "S", "rank_name": "无瑕",
		"rank_note": "无伤且 7 分钟内通关", "time_text": "04:31",
		"hits": 0, "kills": 12, "coins": 96, "rooms": 6, "boons": 2, "depth": 6,
		"best_rank": "S", "best_seconds": 271.0, "is_best": true, "has_best": true,
	})
	await process_frame
	_check(game.run_summary.open, "能弹出结算画面")
	_check(game.run_summary.painter.visible, "结算画面可见")
	_check(String(game.run_summary.data["rank"]) == "S", "记下了 S 评级")
	game.run_summary.close()
	await process_frame
	_check(not game.run_summary.open, "能收起结算画面")

	# 未通关形态也能画
	game.run_summary.show_summary({
		"cleared": false, "failed": true, "rank": "B", "rank_name": "初净",
		"time_text": "02:10", "hits": 5, "kills": 3, "coins": 24,
		"rooms": 3, "boons": 1, "depth": 3,
		"best_rank": "", "best_seconds": 0.0, "is_best": false, "has_best": false,
	})
	await process_frame
	_check(true, "未通关形态也能画出来")
	game.run_summary.close()
	await process_frame

	# ---------- 三、最近 5 次远行 ----------
	game.progress.reset()
	_check(game.progress.recent_runs.is_empty(), "远行记录初始为空")
	for i in range(7):
		game.progress.push_recent_run(100.0 + float(i), 4, true, 10, 0, 48, "A")
	_check(game.progress.recent_runs.size() == 5, "远行记录只保留最近 5 次")
	_check(float(game.progress.recent_runs[0]["seconds"]) == 106.0, "最新的排在最前")
	_check(float(game.progress.recent_runs[4]["seconds"]) == 102.0, "最旧的一笔被挤出")

	# ---------- 四、云舟划桨 ----------
	var worlds = game.attic_worlds
	_check(worlds.boat_node != null, "云舟已建造")
	_check(worlds.buoy_nodes.size() == 3, "三盏云灯浮标已建造")
	_check(not worlds.boat_active, "初始不在船上")

	# 离太远不能上船
	var far_board: Dictionary = worlds.board_boat(Vector3(80.0, 0.0, 80.0))
	_check(not bool(far_board["ok"]), "离得远上不了船")
	_check(String(far_board["message"]).contains("靠近"), "提示再靠近一些")

	# 靠近上船。board_boat 收的是世界坐标（main 传的是 player.global_position），
	# 而 boat_pos 在内容层，所以要换算过去。
	var near_pos: Vector3 = worlds.world_point("cloud",
		Vector3(worlds.boat_pos.x, 0.0, worlds.boat_pos.y))
	var board: Dictionary = worlds.board_boat(near_pos)
	_check(bool(board["ok"]), "靠近云舟能上船")
	_check(worlds.boat_active, "上船后 boat_active 为真")
	_check(String(board["message"]).contains("划桨"), "上船提示讲清划桨键位")

	# 再上船
	var board2: Dictionary = worlds.board_boat(near_pos)
	_check(not bool(board2["ok"]), "已经在船上不能再上")
	_check(String(board2["message"]).contains("已经在"), "提示已经在船上")

	# 划桨会动
	var start_pos: Vector2 = worlds.boat_pos
	for i in range(40):
		worlds.update_boat(1.0, 0.0, 0.05)
	_check(worlds.boat_pos.distance_to(start_pos) > 0.3, "划桨能推动云舟")

	# 后退
	worlds.boat_speed = 0.0
	var back_start: Vector2 = worlds.boat_pos
	for i in range(30):
		worlds.update_boat(-1.0, 0.0, 0.05)
	_check(worlds.boat_pos.distance_to(back_start) > 0.1, "W/S 都能划")

	# 转向改变朝向
	var heading_before: float = worlds.boat_heading
	for i in range(20):
		worlds.update_boat(0.0, 1.0, 0.05)
	_check(absf(worlds.boat_heading - heading_before) > 0.1, "A/D 能转向")

	# 速度有上限
	worlds.boat_speed = 0.0
	for i in range(200):
		worlds.update_boat(1.0, 0.0, 0.05)
	_check(worlds.boat_speed <= worlds.BOAT_MAX_SPEED + 0.001, "划桨速度有上限")

	# 不在栈桥附近不能系舟
	_check(worlds.boat_pos.distance_to(worlds.BOAT_DOCK) > worlds.DOCK_REACH, "此刻不在栈桥附近")
	var leave_far: Dictionary = worlds.leave_boat()
	_check(not bool(leave_far["ok"]), "离栈桥远时系不了舟")
	_check(String(leave_far["message"]).contains("木栈桥"), "提示要划回木栈桥")

	# 划回栈桥再系舟
	worlds.boat_pos = worlds.BOAT_DOCK
	worlds.update_boat(0.0, 0.0, 0.016)
	var leave_ok: Dictionary = worlds.leave_boat()
	_check(bool(leave_ok["ok"]), "划回栈桥能系舟")
	_check(not worlds.boat_active, "系舟后不在船上")
	_check(String(leave_ok["message"]).contains("木板"), "系舟文案对")

	# 三盏云灯
	worlds.buoy_lit = [false, false, false]
	worlds.boat_active = true
	var lit1: Dictionary = worlds.light_buoy(0)
	_check(bool(lit1["ok"]), "能点亮第一盏云灯")
	_check(int(lit1["lit"]) == 1, "已亮 1 盏")
	var lit1_again: Dictionary = worlds.light_buoy(0)
	_check(not bool(lit1_again["ok"]), "同一盏不能重复点")
	_check(String(lit1_again["message"]).contains("已经亮着"), "重复点亮有提示")
	var lit2: Dictionary = worlds.light_buoy(1)
	_check(not bool(lit2["solved"]), "两盏还不算连成航路")
	var lit3: Dictionary = worlds.light_buoy(2)
	_check(bool(lit3["solved"]), "三盏点亮即连成航路")
	_check(String(lit3["message"]).contains("金色"), "三盏文案提到金色")

	# 靠近浮标能识别
	worlds.boat_pos = worlds._buoy_position(1)
	worlds.update_boat(0.0, 0.0, 0.016)
	_check(worlds.near_buoy() == 1, "划到第二盏旁边能识别")
	worlds.boat_pos = Vector2(0.0, 0.0)
	worlds.update_boat(0.0, 0.0, 0.016)
	_check(worlds.near_buoy() == -1, "离远了识别不到浮标")

	# 上船后玩家必须落在云世界里，而不是被丢到太阳系原点（那里是恒星，会判死）
	worlds.boat_active = false
	worlds.boat_pos = Vector2(1.0, -6.0)
	worlds.update_boat(0.0, 0.0, 0.016)
	game.enter_attic()
	await physics_frame
	game.enter_pocket("cloud")
	await physics_frame
	var cloud_world: Node3D = worlds.world_node("cloud")
	# 云舟坐标在内容层，要用 world_point 换算到世界坐标
	var seat_world_pos: Vector3 = worlds.world_point("cloud",
		Vector3(worlds.boat_pos.x, 1.05, worlds.boat_pos.y))
	game.player.global_position = worlds.world_point("cloud",
		Vector3(worlds.boat_pos.x, 1.05, worlds.boat_pos.y - 1.0))
	await physics_frame
	var board_ok: Dictionary = worlds.board_boat(game.player.global_position)
	if bool(board_ok["ok"]):
		game._enter_boat_seat()
		await physics_frame
		var dist_ok: float = game.player.global_position.distance_to(seat_world_pos)
		_check(dist_ok < 0.6, "上船后玩家落在船上（偏差 %.2f m）" % dist_ok)
		_check(game.player.global_position.y < -40000.0,
			"上船后玩家仍在口袋世界的高度（没被丢回太阳系原点）")
	else:
		_check(false, "靠近云舟能上船（世界坐标）")
	game.leave_pocket()
	await physics_frame

	game.queue_free()
	await process_frame
	_cleanup(test_save)
	_cleanup(test_progress)
	if failures > 0:
		print("GUIDE BOAT TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("GUIDE BOAT TEST: all clear")
		quit(0)


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
