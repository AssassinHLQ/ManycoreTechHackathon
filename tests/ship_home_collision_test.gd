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
	var building_shape: CollisionShape3D = null
	for node in building.find_children("*", "CollisionShape3D", true, false):
		var candidate := node as CollisionShape3D
		if candidate.shape is ConcavePolygonShape3D:
			building_shape = candidate
			break
	_check(building_shape != null and building_shape.shape is ConcavePolygonShape3D,
		"opening village uses collision generated from its visible architecture")
	if building_shape == null or not building_shape.shape is ConcavePolygonShape3D:
		quit(1)
		return
	var faces := (building_shape.shape as ConcavePolygonShape3D).get_faces()
	var angle := TAU * 0.09
	var hut_center := Vector3(cos(angle) * 18.0, 0.0, sin(angle) * 18.0)
	var hit_point_local := Vector3.ZERO
	var hit_normal_local := Vector3.ZERO
	var best_score := INF
	for i in range(0, faces.size(), 3):
		var a: Vector3 = faces[i]
		var b: Vector3 = faces[i + 1]
		var c: Vector3 = faces[i + 2]
		var face_center := (a + b + c) / 3.0
		var outward := Vector3(face_center.x - hut_center.x, 0.0, face_center.z - hut_center.z)
		var horizontal_distance := outward.length()
		if horizontal_distance < 1.8 or horizontal_distance > 2.8 or face_center.y < 0.5 or face_center.y > 3.5:
			continue
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 0.0001:
			continue
		normal = normal.normalized()
		if Vector2(normal.x, normal.z).length() < 0.9:
			continue
		if normal.dot(outward) < 0.0:
			normal = -normal
		var score := horizontal_distance + absf(face_center.y - 1.8) * 0.2
		if score < best_score:
			best_score = score
			hit_point_local = face_center
			hit_normal_local = normal
	_check(best_score < INF, "locate a visible village hut wall in the combined collider")
	if best_score == INF:
		quit(1)
		return

	for node in game.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body != building and (body.collision_layer & 8) != 0:
			body.collision_layer = 0
	await physics_frame

	var ship = game.ship
	ship.set_physics_process(false)
	var center: Vector3 = building_shape.global_transform * hit_point_local
	var normal: Vector3 = (building_shape.global_transform.basis * hit_normal_local).normalized()
	var up: Vector3 = (center - game.home.global_position).normalized()
	var start := center + normal * 50.0
	ship.global_transform = Transform3D(Basis.looking_at(-normal, up), start)
	ship.velocity = -normal * 120.0
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

	while game.world_build_remaining or game.planets.size() < 20:
		await process_frame
	game.queue_free()
	await process_frame
	if FileAccess.file_exists("user://ship_home_collision_test.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ship_home_collision_test.json"))
	if FileAccess.file_exists("user://ship_home_collision_progress_test.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ship_home_collision_progress_test.json"))
	quit(1 if failures > 0 else 0)
