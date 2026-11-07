extends SceneTree

var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _run() -> void:
	var test_save := "user://starward_autopilot_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(10):
		await physics_frame

	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.reparent(game, true)
	game.ship.landed = false
	game.ship.autopilot = true
	game.ship.fuel = 100.0
	game.ship.hull = 100.0
	var eye = game.planets[4]
	game.ship.target = eye
	var eye_direction: Vector3 = eye.global_position.normalized()
	var start_position: Vector3 = -eye_direction * 2600.0
	game.ship.global_position = start_position
	game.ship.velocity = Vector3.ZERO
	await physics_frame

	var aim: Vector3 = game.ship._autopilot_aim(eye.global_position)
	var aim_direction: Vector3 = (aim - start_position).normalized()
	var closest_t: float = clampf(-start_position.dot(aim_direction), 0.0, start_position.distance_to(aim))
	var closest: Vector3 = start_position + aim_direction * closest_t
	_check(closest.length() > game.sun_radius + 700.0, "autopilot aim steers around the sun")

	var fuel_start: float = game.ship.fuel
	var fuel_after_accel: float = fuel_start
	var minimum_distance := INF
	for i in range(720):
		await physics_frame
		if i == 20:
			fuel_after_accel = game.ship.fuel
		minimum_distance = minf(minimum_distance, game.ship.global_position.length())
		if game.state == "dying":
			break
	print("autopilot fuel start=", fuel_start, " after_accel=", fuel_after_accel, " final=", game.ship.fuel)
	_check(fuel_after_accel < fuel_start - 0.2, "autopilot acceleration burns propellant")
	_check(minimum_distance > game.sun_radius + 500.0, "autopilot keeps the ship out of the sun")
	_check(game.state != "dying" and game.ship.hull > 50.0, "autopilot does not burn up the ship")
	_check(game.ship.global_position.distance_to(start_position) > 800.0, "autopilot still makes progress")

	game.state = "walk"
	game.discovered = {}
	game._save_knowledge()
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("AUTOPILOT TEST COMPLETE: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
