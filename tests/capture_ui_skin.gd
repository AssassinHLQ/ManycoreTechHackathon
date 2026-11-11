extends SceneTree
# UI 换皮验收：把 HUD 的关键界面截下来，确认 Wenrexa 九宫格贴对了。
# 用法（必须真实渲染，不能 headless）：
#   godot --path . --script res://tests/capture_ui_skin.gd

var game
var shots := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		push_error("截图失败: " + name)
		return
	img.save_png("res://captures/ui_skin_%s.png" % name)
	shots += 1
	print("  saved ui_skin_%s.png" % name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))

	var test_save := "user://starward_uiskin_shot.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(5)
	game.start_game()
	await _frames(25)

	# ── 1. 飞船 HUD：状态面板 + 氧气/燃料条 ──
	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.landed = false
	game.ship.docked = false
	if game.ship.get_parent() != game:
		game.ship.reparent(game, true)
	game.ship.velocity = Vector3.ZERO
	await _frames(45)
	await _shot("hud")

	# ── 2. 星图：面板密集，测九宫格 ──
	game.map_open = true
	game.map_selected = 3
	await _frames(30)
	await _shot("map")
	game.map_open = false
	await _frames(10)

	# ── 3. 日志：长文本面板，测纵向拉伸 ──
	game.journal_open = true
	await _frames(30)
	await _shot("journal")
	game.journal_open = false
	await _frames(10)

	# ── 4. 暂停菜单：按钮组 + 面板 ──
	game.paused = true
	await _frames(30)
	await _shot("menu")

	print("UI SKIN CAPTURE DONE: %d shots" % shots)

	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0)
