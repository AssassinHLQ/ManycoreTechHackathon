extends SceneTree
# 飞船模型取证：四分之三前视 / 侧视 / 尾视 / 座舱特写。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_ship.gd

var game


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://captures/ship_" + name + ".png"
	print("CAPTURE ", path, " -> ", error_string(image.save_png(path)))


func _run() -> void:
	var capture_save := "user://starward_capture_ship.json"
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = capture_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.start_game()
	await _frames(20)
	game.hud.visible = false
	game.hud.menu.visible = false
	game.state = "capture"

	var ship = game.ship
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 60000.0
	camera.fov = 42.0
	game.add_child(camera)
	camera.current = true

	var views := [
		["three_quarter", Vector3(6.2, 3.4, -6.8)],
		["side", Vector3(9.5, 1.2, 0.6)],
		["rear", Vector3(-4.4, 2.6, 8.6)],
		["nose", Vector3(0.9, 1.6, -8.2)],
	]
	for view in views:
		var offset: Vector3 = view[1]
		camera.global_position = ship.to_global(offset)
		camera.look_at(ship.to_global(Vector3(0, 0.2, 0.2)), Vector3.UP)
		await _frames(8)
		await _capture(view[0])

	# 座舱特写
	camera.fov = 55.0
	camera.global_position = ship.to_global(Vector3(2.6, 2.0, -3.6))
	camera.look_at(ship.to_global(Vector3(0, 0.75, -1.15)), Vector3.UP)
	await _frames(8)
	await _capture("cockpit")

	print("SHIP CAPTURE COMPLETE")
	quit(0)
