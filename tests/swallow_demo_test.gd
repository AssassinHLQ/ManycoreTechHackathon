extends SceneTree
# 窗台燕子。
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

	preload("res://tests/home_fixture.gd").enter(game)
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

	game.queue_free()
	await process_frame
	_cleanup(test_save)
	_cleanup(test_progress)
	if failures > 0:
		print("SWALLOW TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("SWALLOW TEST: all clear")
		quit(0)


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
