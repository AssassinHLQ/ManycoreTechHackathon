extends SceneTree
# 窗台燕子 + 自动演示。
# 用法：godot --headless --path . --script res://tests/swallow_demo_test.gd

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
	var test_save := "user://starward_sd_test.json"
	var test_progress := "user://starward_sd_progress.json"
	_cleanup(test_save)
	_cleanup(test_progress)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	game.progress_path = test_progress
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	# ---------- 一、窗台燕子 ----------
	_check(game.attic.swallow_node != null, "燕子模型已建好")
	_check(not game.attic.swallow_node.visible, "燕子初始藏着（雨没停）")
	_check(not game.attic.swallow_on_sill(), "初始窗台上没有燕子")

	game.enter_attic()
	await physics_frame
	# 雨巷纪念归架 → 燕子出现
	game.keepsakes["alley"] = true
	var appeared: bool = game.attic.show_swallow()
	_check(appeared, "雨巷完成后燕子出现在窗台")
	_check(game.attic.swallow_node.visible, "燕子模型可见了")
	_check(game.attic.swallow_on_sill(), "燕子此刻在窗台上")
	_check(not game.attic.show_swallow(), "不会重复出现")

	# 招呼它
	var greet: Dictionary = game.attic.greet_swallow()
	_check(bool(greet["ok"]), "能招呼燕子")
	_check(String(greet["message"]).contains("掠过炉火"), "招呼文案照原作")
	var greet_again: Dictionary = game.attic.greet_swallow()
	_check(not bool(greet_again["ok"]), "飞行途中不能再招呼")

	# 飞到壁炉边
	var guard := 0
	while not game.attic.swallow_perched() and guard < 400:
		game.attic.update_swallow(0.05)
		guard += 1
	_check(game.attic.swallow_perched(), "燕子最终落到壁炉边")
	_check(not game.attic.swallow_on_sill(), "落到壁炉后就不在窗台了")

	# 落到壁炉后再招呼
	var later: Dictionary = game.attic.greet_swallow()
	_check(bool(later["ok"]), "落到壁炉后还能再看一眼")
	_check(String(later["message"]).contains("尾羽"), "壁炉边文案照原作")

	# ---------- 二、自动演示 ----------
	_check(game.demo != null, "自动演示层已创建")
	_check(not game.demo_active, "演示初始未开始")
	_check(game.demo.DEMO_DURATION == 159.0, "演示时长 159 秒（照原作）")
	_check(game.demo.DEMO_CAPTIONS.size() == 40, "40 条字幕")
	_check(game.demo.DEMO_CAMERAS.size() == 70, "70 个机位")
	_check(game.demo.DEMO_ACTIONS.size() == 40, "40 个动作")
	_check(String(game.demo.DEMO_CAPTIONS[0][1]).contains("温暖的小屋"), "首条字幕照原作")
	_check(String(game.demo.DEMO_CAPTIONS[39][1]).contains("住进家里"), "末条字幕照原作")

	# 开始演示
	game.start_demo()
	await process_frame
	_check(game.demo_active, "演示已开始")
	_check(game.demo.active, "演示层进入 active")
	_check(game.demo.painter.visible, "演示画面可见")
	_check(game.demo.clock == 0.0, "时间轴从 0 开始")

	# 推进到第 6 秒：应该已经有字幕了
	game.demo.clock = 5.6
	game.demo.tick(0.0)
	_check(game.demo.caption_index >= 1, "5.6 秒时已切到第二条字幕")
	_check(game.demo.current_caption().contains("黄铜旋钮"), "第二条字幕讲天气旋钮")

	# 推进到 16 秒：应该已经转过天气
	game.demo.clock = 16.0
	game.demo.tick(0.0)
	await process_frame
	_check(game.demo.caption_index >= 3, "16 秒时字幕推进到「第一扇」之后")

	# 快进到 60 秒附近，确认动作有被触发、且没崩
	game.demo.clock = 60.0
	game.demo.tick(0.0)
	await process_frame
	_check(game.demo.action_index > 10, "60 秒时已触发十多个动作")

	# 直接跳到结束
	game.demo.clock = 158.9
	game.demo.tick(0.2)
	await process_frame
	_check(not game.demo_active, "演示到时长自动结束")
	_check(not game.demo.active, "演示层退出 active")

	# 再开一次，测 Esc 退出
	game.start_demo()
	await process_frame
	_check(game.demo_active, "能再次开始演示")
	game.stop_demo()
	await process_frame
	_check(not game.demo_active, "stop_demo 能退出演示")

	game.queue_free()
	await process_frame
	_cleanup(test_save)
	_cleanup(test_progress)
	if failures > 0:
		print("SWALLOW DEMO TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("SWALLOW DEMO TEST: all clear")
		quit(0)


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
