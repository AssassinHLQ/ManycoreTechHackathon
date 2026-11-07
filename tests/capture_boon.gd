extends SceneTree
# 镜印取证：静镜室的镜印台（三枚候选）与取走一枚后的样子。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_boon.gd

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
	var save := "user://starward_capture_boon.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_capture_boon_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await _frames(18)
	game.hud.visible = false
	game.enter_attic()
	await _frames(8)
	game.enter_pocket("mirror")
	await _frames(6)
	var gate = game.attic_worlds.dungeon_gate_anchor()
	game.player.global_position = (gate as Node3D).global_position
	await _frames(4)
	game._interact()
	await _frames(12)

	var camera := Camera3D.new()
	camera.near = 0.06
	camera.far = 60000.0
	camera.fov = 58.0
	game.add_child(camera)
	camera.current = true

	# 第二间（静镜室）的镜印台
	var stand_anchor = game.attic_worlds.dungeon_boon_anchor(1, 0)
	var room_anchor = game.attic_worlds.dungeon_room_anchor(1)
	var sp := Vector3.ZERO
	if stand_anchor != null and room_anchor != null:
		sp = (stand_anchor as Node3D).global_position
		# 从侧面拍：房间中央的镜塔在 z 正方向，正面机位会被它挡住
		# 房间半宽只有 4.5 米，机位必须留在墙内；稍微侧一点避开中央镜塔
		camera.global_position = sp + Vector3(2.4, 2.3, 3.4)
		camera.look_at(sp + Vector3(0, 0.4, 0), Vector3.UP)
		await _frames(12)
		await _capture("boon_stand")

	# 取走一枚并让 HUD 显示镜印名
	game.player.global_position = sp
	game._update_dungeon(0.016)
	await _frames(4)
	game.take_dungeon_boon(0)
	await _frames(12)
	await _capture("boon_taken")

	print("BOON CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_capture_boon_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)
