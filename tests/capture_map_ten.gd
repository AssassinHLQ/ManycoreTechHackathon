extends SceneTree
# 星图普查截图：确认十颗天体都出现在星图上。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_map_ten.gd

var game


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _run() -> void:
	var capture_save := "user://starward_capture_map.json"
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = capture_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.start_game()
	await _frames(20)

	print("BODIES ", game.planets.size(), " ANOMALIES ", game.anomalies.size())
	for planet in game.planets:
		print("  ", planet.planet_id, " ", planet.display_name, " r=", planet.radius,
			" orbit=", planet.orbit_radius, " g=", planet.gravity_strength)
	# 把十颗都点亮为已发现，星图上不会有「未探索」遮挡
	for anomaly in game.anomalies:
		game.discovered[anomaly.anomaly_id] = true
	game.map_open = true
	game.map_zoom = 1.0
	await _frames(12)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://captures/map_ten_bodies.png"
	print("CAPTURE ", path, " -> ", error_string(image.save_png(path)))
	quit(0)
