extends SceneTree
# 复现 smoke_test 的第三人称断言，打印实际数值。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _run() -> void:
	var save_path := "user://starward_tp.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	await _frames(10)
	game.start_game()
	await _frames(30)

	var ship = game.ship
	# 模拟 F5 切第三人称
	ship.third_person = true
	ship._update_third_person_camera(0.0)
	await _frames(4)
	ship._update_third_person_camera(0.0)

	var cam: Camera3D = ship.camera
	var cam_forward: Vector3 = -cam.global_transform.basis.z.normalized()
	var to_center: Vector3 = (-cam.position).normalized()
	print("=== TP CHECK ===")
	print("  third_person = %s" % str(ship.third_person))
	print("  cam.position (local) = %s  len=%.2f" % [str(cam.position), cam.position.length()])
	print("  cam.global pos       = %s" % str(cam.global_position))
	print("  ship.global pos      = %s" % str(ship.global_position))
	print("  ship rotation (deg)  = %s" % str(ship.rotation_degrees))
	print("  cam_forward (global) = %s" % str(cam_forward))
	print("  to_center   (local)  = %s" % str(to_center))
	print("  DOT = %.4f   (test wants > 0.9)" % to_center.dot(cam_forward))
	print("  orbit_distance = %.2f  target=%.2f" % [ship.orbit_distance, ship.orbit_distance_target])
	print("  ship_model_height = %.2f  base_y = %.2f" % [ship.ship_model_height, ship.ship_model_height * 0.55])

	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
