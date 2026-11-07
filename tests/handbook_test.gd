extends SceneTree
# 旅人手册（H 键）与「下一件值得做的事」。
# 用法：godot --headless --path . --script res://tests/handbook_test.gd

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
	var test_save := "user://starward_handbook_test.json"
	var test_progress := "user://starward_handbook_progress.json"
	_cleanup(test_save)
	_cleanup(test_progress)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	game.progress_path = test_progress
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	# 手册已创建
	_check(game.handbook != null, "旅人手册已创建")
	_check(game.handbook.SECTIONS.size() == 7, "手册有七节")
	_check(not game.handbook.open, "手册默认合着")

	# H 打开
	game.toggle_handbook()
	await process_frame
	_check(game.handbook.open, "按 H 打开手册")
	_check(game.handbook_open, "游戏侧记录了手册已打开")
	_check(game.handbook.painter.visible, "手册画面可见")
	_check(game.handbook.section == 0, "默认停在第一节")

	# 翻节
	game.handbook.step_section(1)
	await process_frame
	_check(game.handbook.section == 1, "→ 翻到第二节")
	game.handbook.step_section(-1)
	await process_frame
	_check(game.handbook.section == 0, "← 翻回第一节")
	_check(not game.handbook.step_section(-1), "第一节再往左不越界")
	for i in range(20):
		game.handbook.step_section(1)
	_check(game.handbook.section == 6, "翻到底停在最后一节")

	# 每一节都能画出来（不崩）
	for i in range(7):
		game.handbook.section = i
		game.handbook.painter.queue_redraw()
		await process_frame
	_check(true, "七节都能画出来")

	# 再按 H 合上
	game.toggle_handbook()
	await process_frame
	_check(not game.handbook.open, "再按 H 合上手册")

	# 手册打开时会盖住行囊
	game.toggle_bag()
	await process_frame
	_check(game.bag_open, "先打开行囊")
	game.toggle_handbook()
	await process_frame
	_check(not game.bag.open, "打开手册时行囊自动收起")
	game.toggle_handbook()
	await process_frame

	# ---------- 下一件值得做的事 ----------
	game.enter_attic()
	await physics_frame
	game.progress.reset()
	game.keepsakes.clear()

	var step0: String = game.next_worth_doing()
	_check(step0.contains("雪夜小屋"), "开局提示去雪夜小屋")

	game.keepsakes["snow"] = true
	var step1: String = game.next_worth_doing()
	_check(step1.contains("云海"), "雪夜之后指向云海")

	game.keepsakes["cloud"] = true
	var step2: String = game.next_worth_doing()
	_check(step2.contains("萤火森林"), "云海之后指向萤火森林")

	game.keepsakes["firefly"] = true
	var step3: String = game.next_worth_doing()
	_check(step3.contains("雨巷"), "萤火之后指向雨巷")

	game.keepsakes["alley"] = true
	var step4: String = game.next_worth_doing()
	_check(step4.contains("茶"), "四件纪念齐了指向茶席")

	# 茶席完成后指向镜界
	game.attic.tea_step = 3
	game.has_prism_heart = false
	var step5: String = game.next_worth_doing()
	_check(step5.contains("镜"), "茶席之后指向镜界")

	# 棱镜之心拿到后指向小游戏
	game.has_prism_heart = true
	var step6: String = game.next_worth_doing()
	_check(step6.contains("小游戏") or step6.contains("风律"), "镜界之后指向小游戏")

	# 小游戏都有成绩后指向听雨院
	game.progress.game_best = {"chime": 10, "firefly": 10, "rain": 10}
	if game.attic_worlds != null:
		game.attic_worlds.court_rested = false
	var step7: String = game.next_worth_doing()
	_check(step7.contains("听雨院"), "小游戏之后指向听雨院")

	game.attic_worlds.court_rested = true
	game.progress.dungeon = {"runs": 0, "clears": 0, "best_rank": "", "best_seconds": 0.0, "total_boons": 0}
	var step8: String = game.next_worth_doing()
	_check(step8.contains("镜牢"), "听雨院之后指向镜牢")

	game.progress.dungeon = {"runs": 1, "clears": 1, "best_rank": "B", "best_seconds": 300.0, "total_boons": 1}
	game.progress.wind_solved = false
	var step9: String = game.next_worth_doing()
	_check(step9.contains("风琴礁"), "镜牢通关后指向风琴礁")

	game.progress.wind_solved = true
	game.progress.dungeon["flawless"] = false
	var step10: String = game.next_worth_doing()
	_check(step10.contains("无伤"), "最后指向无伤通关")

	game.queue_free()
	await process_frame
	_cleanup(test_save)
	_cleanup(test_progress)
	if failures > 0:
		print("HANDBOOK TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("HANDBOOK TEST: all clear")
		quit(0)


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
