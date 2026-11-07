extends SceneTree
# 旅行架取证：四件纪念 + 棱镜之心全部带回后拍特写。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_shelf.gd

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
	var save := "user://starward_capture_shelf.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_capture_shelf_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await _frames(18)
	game.hud.visible = false
	game.enter_attic()
	await _frames(12)

	# 四件纪念 + 棱镜之心都带回
	for key in ["snow", "cloud", "firefly", "alley"]:
		game.collect_keepsake(key)
	game.has_prism_heart = true
	game.attic.show_prism_heart()
	await _frames(10)

	var camera := Camera3D.new()
	camera.near = 0.05
	camera.far = 60000.0
	camera.fov = 40.0
	game.add_child(camera)
	camera.current = true
	var target: Vector3 = game.attic.to_global(Vector3(3.1, 1.12, -1.2))
	camera.global_position = game.attic.to_global(Vector3(1.75, 1.35, -1.2))
	camera.look_at(target, game.attic.up_direction())
	await _frames(12)
	await _capture("shelf_keepsakes")

	# 再拍一张侧一点的角度，能看到各件的高低错落
	camera.global_position = game.attic.to_global(Vector3(1.9, 1.28, -2.15))
	camera.look_at(game.attic.to_global(Vector3(3.12, 1.06, -1.05)), game.attic.up_direction())
	await _frames(10)
	await _capture("shelf_keepsakes_side")

	print("SHELF CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_capture_shelf_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)
