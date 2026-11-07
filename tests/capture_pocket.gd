extends SceneTree
# 口袋世界取证：雪夜 / 云海 / 萤火 / 雨巷 / 镜界 各一张。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_pocket.gd

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
	var path := "res://captures/pocket_" + name + ".png"
	print("CAPTURE ", path, " -> ", error_string(image.save_png(path)))


func _run() -> void:
	var capture_save := "user://starward_capture_pocket.json"
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = capture_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.hud.visible = false
	game.hud.menu.visible = false
	game.state = "capture"
	game.enter_attic()
	await _frames(10)

	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 60000.0
	camera.fov = 62.0
	game.add_child(camera)
	camera.current = true

	for key in ["snow", "cloud", "firefly", "alley", "mirror"]:
		game.enter_pocket(key)
		await _frames(14)
		var world: Node3D = game.attic_worlds.world_node(key)
		if world == null:
			print("MISSING ", key)
			continue
		# 站在出生点稍后方，朝场地中心看
		var center: Vector3 = world.global_position + Vector3(0, 1.6, 0)
		if key == "mirror":
			# 镜界是室内，机位要落在房间里面
			camera.global_position = world.to_global(Vector3(0.0, 2.4, 9.0))
			center = world.to_global(Vector3(0.0, 1.6, 0.0))
		else:
			var spawn: Vector3 = game.attic_worlds.spawn_position(key)
			camera.global_position = spawn + Vector3(0, 2.1, 2.6)
		camera.look_at(center, Vector3.UP)
		await _frames(10)
		await _capture(key)
		# 阁楼内视角也留一张
		game.leave_pocket()
		await _frames(6)

	# 阁楼本体（门口视角）
	camera.global_position = game.attic.to_global(Vector3(0, 1.6, 1.6))
	camera.look_at(game.attic.to_global(Vector3(0, 1.3, -2.9)), game.attic.up_direction())
	await _frames(12)
	await _capture("attic_doors")

	print("POCKET CAPTURE COMPLETE")
	quit(0)
