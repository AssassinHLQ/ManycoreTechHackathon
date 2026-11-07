extends SceneTree
# 镜牢战斗取证：镜影与 HUD / 镜心余影三相。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_combat.gd

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
	var save := "user://starward_capture_combat.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_capture_combat_progress.json"
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
	await _frames(14)

	var camera := Camera3D.new()
	camera.near = 0.06
	camera.far = 60000.0
	camera.fov = 62.0
	game.add_child(camera)
	camera.current = true

	var combat = game.dungeon_controller
	var world: Node3D = game.attic_worlds.world_node("dungeon")
	# 第一间（镜影 + HUD）
	var room0 = game.attic_worlds.dungeon_room_anchor(0)
	if room0 != null:
		var p: Vector3 = (room0 as Node3D).global_position
		camera.global_position = p + Vector3(0.0, 2.0, 6.5)
		camera.look_at(p + Vector3(0, 1.0, 0), Vector3.UP)
		await _frames(12)
		await _capture("combat_shades")

	# 走到 BOSS 房，拍初相与逆光相
	var boss_anchor = game.attic_worlds.dungeon_room_anchor(5)
	if boss_anchor != null:
		game.player.global_position = (boss_anchor as Node3D).global_position
		game.dungeon_controller._spawn_room_enemies(5)
		await _frames(8)
		var bp: Vector3 = (boss_anchor as Node3D).global_position
		camera.global_position = bp + Vector3(0.0, 2.2, 8.0)
		camera.look_at(bp + Vector3(0, 1.4, -2.5), Vector3.UP)
		await _frames(10)
		await _capture("combat_boss_first")
		game.dungeon_controller.damage_enemy(game.dungeon_controller.boss, 220.0)
		await _frames(10)
		await _capture("combat_boss_third")

	print("COMBAT CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_capture_combat_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)
