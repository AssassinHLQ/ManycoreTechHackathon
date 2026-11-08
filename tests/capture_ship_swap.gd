extends SceneTree
# 换船后的取证：把相机摆到飞船前后左右，各拍一张。
#   godot --path . --script res://tests/capture_ship_swap.gd

var game


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
	var img: Image = root.get_texture().get_image()
	img.save_png("res://captures/shipswap_%s.png" % name)
	print("saved res://captures/shipswap_%s.png" % name)


func _run() -> void:
	var save := "user://starward_shipswap.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(16)
	game.start_game()
	await _frames(16)
	game.hud.visible = false

	var ship = game.ship
	print("船模型 长=%.2f 翼展=%.2f 高=%.2f" % [ship.ship_model_length, ship.ship_model_span, ship.ship_model_height])
	print("船位置 = ", ship.global_position)

	# 用飞船自己的相机（驾驶舱视角）
	ship.camera.current = true
	await _frames(10)
	await _shot("cockpit")

	# 外部环绕：拿玩家相机摆到船周围
	var cam: Camera3D = game.player.camera
	cam.current = true
	var base: Vector3 = ship.global_transform.origin
	var up: Vector3 = ship.global_transform.basis.y.normalized()
	var fwd: Vector3 = -ship.global_transform.basis.z.normalized()
	var right: Vector3 = ship.global_transform.basis.x.normalized()
	var views := {
		"front": fwd * 14.0 + up * 4.0,
		"rear": -fwd * 14.0 + up * 4.0,
		"side": right * 14.0 + up * 3.0,
		"top": up * 16.0 + fwd * 1.0,
	}
	for key in views:
		var pos: Vector3 = base + (views[key] as Vector3)
		cam.global_transform = Transform3D(Basis.looking_at((base - pos).normalized(), up), pos)
		await _frames(8)
		await _shot(key)

	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
