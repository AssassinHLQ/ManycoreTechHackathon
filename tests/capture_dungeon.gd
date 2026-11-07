extends SceneTree
# 镜牢回廊取证：入口走廊 / 中段镜室 / 镜心内厅。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_dungeon.gd

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
	var save := "user://starward_capture_dungeon.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_capture_dungeon_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await _frames(18)
	game.hud.visible = false
	game.enter_attic()
	await _frames(8)
	game.enter_pocket("mirror")
	await _frames(8)

	# 镜界的镜牢门
	var gate = game.attic_worlds.dungeon_gate_anchor()
	var camera := Camera3D.new()
	camera.near = 0.06
	camera.far = 60000.0
	camera.fov = 60.0
	game.add_child(camera)
	camera.current = true
	if gate != null:
		var gate_pos: Vector3 = (gate as Node3D).global_position
		camera.global_position = gate_pos + Vector3(-4.0, 2.2, 5.0)
		camera.look_at(gate_pos + Vector3(0, 1.6, 0), Vector3.UP)
		await _frames(10)
		await _capture("dungeon_gate")

	game.enter_dungeon()
	await _frames(12)
	var world: Node3D = game.attic_worlds.world_node("dungeon")
	# 入口朝走廊深处看
	camera.global_position = world.to_global(Vector3(0.0, 2.0, 6.0))
	camera.look_at(world.to_global(Vector3(0.0, 1.4, -14.0)), Vector3.UP)
	await _frames(10)
	await _capture("dungeon_corridor")

	# 中段一间镜室
	var mid = game.attic_worlds.dungeon_room_anchor(3)
	if mid != null:
		var mid_pos: Vector3 = (mid as Node3D).global_position
		camera.global_position = mid_pos + Vector3(5.4, 2.4, 5.0)
		camera.look_at(mid_pos + Vector3(0, 1.2, 0), Vector3.UP)
		await _frames(10)
		await _capture("dungeon_room")

	# 镜心内厅
	var boss = game.attic_worlds.dungeon_room_anchor(5)
	if boss != null:
		var boss_pos: Vector3 = (boss as Node3D).global_position
		camera.global_position = boss_pos + Vector3(0.0, 2.6, 7.0)
		camera.look_at(boss_pos + Vector3(0, 1.6, -4.0), Vector3.UP)
		await _frames(10)
		await _capture("dungeon_boss_hall")

	print("DUNGEON CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_capture_dungeon_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)
