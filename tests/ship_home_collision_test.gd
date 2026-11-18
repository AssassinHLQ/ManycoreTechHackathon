extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("PASS  " if ok else "FAIL  ", message)
	if not ok:
		failures += 1


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://ship_home_collision_test.json"
	game.progress_path = "user://ship_home_collision_progress_test.json"
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	for _i in range(8):
		await physics_frame

	var arch: Node3D = game.home.find_child("Architecture_Qinglan", true, false)
	var building: StaticBody3D = arch.find_child("BuildingCollision", true, false)
	var hut_shape: CollisionShape3D = null
	for node in building.find_children("*", "CollisionShape3D", true, false):
		var candidate := node as CollisionShape3D
		if candidate.shape is BoxShape3D and (candidate.shape as BoxShape3D).size.is_equal_approx(Vector3(4.4, 5.9, 4.0)):
			hut_shape = candidate
			break
	_check(hut_shape != null, "find a real opening-village hut collider")
	if hut_shape == null:
		quit(1)
		return

	for node in game.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body != building and (body.collision_layer & 8) != 0:
			body.collision_layer = 0
	for node in building.find_children("*", "CollisionShape3D", true, false):
		if node != hut_shape:
			(node as CollisionShape3D).disabled = true
	await physics_frame

	var ship = game.ship
	ship.set_physics_process(false)
	var center: Vector3 = hut_shape.global_position
	var direction: Vector3 = hut_shape.global_basis.x.normalized()
	var up: Vector3 = hut_shape.global_basis.y.normalized()
	var start := center - direction * 50.0
	ship.global_transform = Transform3D(Basis.looking_at(direction, up), start)
	ship.velocity = direction * 120.0
	ship.hull = 100.0
	ship.impact_cooldown = 0.0
	ship.landed = false
	ship.landed_planet = null
	game.state = "ship"
	game.player.visible = false
	var stopped: bool = ship._move_with_station_collision(100.0 / 120.0)
	var travel: float = ship.global_position.distance_to(start)
	_check(stopped, "swept ship hull registers contact with the hut")
	_check(travel < 100.0, "ship does not cross the hut in one physics step")
	_check(ship.hull < 100.0, "a hard hut impact damages the ship")

	if FileAccess.file_exists("user://ship_home_collision_test.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ship_home_collision_test.json"))
	if FileAccess.file_exists("user://ship_home_collision_progress_test.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ship_home_collision_progress_test.json"))
	quit(1 if failures > 0 else 0)
