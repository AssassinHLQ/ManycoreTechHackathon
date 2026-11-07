extends SceneTree
# 天气旋钮取证：四档各拍一张「窗外」。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_weather.gd

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
	var path := "res://captures/" + name + ".png"
	print("CAPTURE ", path, " -> ", error_string(image.save_png(path)))


func _run() -> void:
	var save := "user://starward_capture_weather.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_capture_weather_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.hud.visible = false
	game.enter_attic()
	await _frames(16)

	var camera := Camera3D.new()
	camera.near = 0.05
	camera.far = 60000.0
	camera.fov = 58.0
	game.add_child(camera)
	camera.current = true
	# 站在屋子中间偏后，正对窗户（+Z 墙）
	camera.global_position = game.attic.to_global(Vector3(0.0, 1.62, -1.1))
	camera.look_at(game.attic.to_global(Vector3(0.0, 1.72, 3.2)), game.attic.up_direction())

	for i in range(game.attic.WEATHER_ORDER.size()):
		var key: String = game.attic.WEATHER_ORDER[i]
		game.attic.set_dial(i)
		await _frames(10)
		await _capture("weather_%d_%s" % [i, key])

	print("WEATHER CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_capture_weather_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)
