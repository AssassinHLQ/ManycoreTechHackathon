extends SceneTree

var game
var failures := 0


func _initialize() -> void:
	print("MESH COLLISION TEST START")
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _run() -> void:
	var suffix := str(Time.get_ticks_usec())
	var test_save := "user://mesh_collision_test_%s.json" % suffix
	var test_progress := "user://mesh_collision_progress_%s.json" % suffix
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	if packed_scene == null:
		_check(false, "main scene loads for collision inspection")
		quit(1)
		return
	game = packed_scene.instantiate()
	game.save_path = test_save
	game.progress_path = test_progress
	root.add_child(game)
	var ready_deadline := Time.get_ticks_msec() + 120000
	while not game.world_ready and Time.get_ticks_msec() < ready_deadline:
		await process_frame
	_check(game.world_ready, "main world becomes ready")
	var deadline_ms := Time.get_ticks_msec() + 180000
	while game.planets.size() < 20 and Time.get_ticks_msec() < deadline_ms:
		await process_frame
	_check(game.planets.size() == 20, "all planets finish building before collision inspection")
	_check(game.ship.planet_asset_sweep_shapes.size() > 1,
		"ship asset sweep uses multiple mesh-decomposed convex pieces")

	var exact_mesh_shape_count := 0
	var simplified_shape_count := 0
	for planet in game.planets:
		for body_node in planet.find_children("*", "StaticBody3D", true, false):
			var body := body_node as StaticBody3D
			if (body.collision_layer & 8) == 0:
				continue
			for shape_node in body.find_children("*", "CollisionShape3D", true, false):
				var collision := shape_node as CollisionShape3D
				if collision.shape is ConcavePolygonShape3D:
					exact_mesh_shape_count += 1
				else:
					simplified_shape_count += 1
	_check(exact_mesh_shape_count == 0, "planet asset colliders do not use full render-mesh triangle shapes")
	_check(simplified_shape_count > 0, "planet asset colliders use simplified mesh-derived shapes")
	await _test_sweep_contact_validation()

	game.queue_free()
	await process_frame
	for path in [test_save, test_progress]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MESH COLLISION TEST COMPLETE: ", failures, " failures")
	quit(0 if failures == 0 else 1)


func _test_sweep_contact_validation() -> void:
	var ship = game.ship
	var planet = game.planets[0]
	var planet_basis: Basis = planet.global_basis.orthonormalized()
	var up := (planet_basis * Vector3.UP).normalized()
	var tangent := (planet_basis * Vector3.RIGHT).normalized()
	var side := tangent.cross(up).normalized()
	var test_basis := Basis(tangent, up, side)
	var start: Vector3 = planet.global_position + up * (planet.terrain_height(Vector3.UP) + 500.0)
	var motion := tangent * 8.0
	var sweep_shape := BoxShape3D.new()
	sweep_shape.size = Vector3.ONE
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 8.0, 8.0)
	var target := StaticBody3D.new()
	target.name = "MeshCollisionTestTarget"
	target.collision_layer = 8
	target.collision_mask = 0
	var visible_mesh := MeshInstance3D.new()
	visible_mesh.mesh = mesh
	target.add_child(visible_mesh)
	var target_shape := CollisionShape3D.new()
	target_shape.shape = mesh.create_trimesh_shape()
	target.add_child(target_shape)
	game.add_child(target)

	var original_transform: Transform3D = ship.global_transform
	var original_velocity: Vector3 = ship.velocity
	var original_hull: float = ship.hull
	var original_impact_cooldown: float = ship.impact_cooldown
	var original_autopilot: bool = ship.autopilot
	var original_shapes: Array[Dictionary] = ship.planet_asset_sweep_shapes.duplicate()
	ship.global_transform = Transform3D(test_basis, start)
	ship.velocity = tangent * 15.0
	ship.hull = 100.0
	ship.impact_cooldown = 5.0
	ship.autopilot = false
	ship.planet_asset_sweep_shapes.clear()
	ship.planet_asset_sweep_shapes.append({"shape": sweep_shape, "transform": Transform3D.IDENTITY})

	target.global_transform = Transform3D(test_basis, start + tangent * 4.0 + up * 10.0)
	await physics_frame
	var clear_path_hit: bool = ship._move_with_planet_asset_collision(motion)
	_check(not clear_path_hit, "mesh sweep ignores a clear path beside the visible mesh")
	_check(ship.global_position.is_equal_approx(start), "clear sweep leaves the ship position unchanged")

	target.global_transform = Transform3D(test_basis, start + tangent * 4.0)
	await physics_frame
	var mesh_hit: bool = ship._move_with_planet_asset_collision(motion)
	var stopped_distance: float = (ship.global_position - start).dot(tangent)
	_check(mesh_hit, "mesh sweep detects contact with the visible triangle mesh")
	_check(stopped_distance < 4.0, "mesh sweep stops before crossing the mesh")
	_check(is_equal_approx(ship.hull, 100.0), "verified contact respects the active impact cooldown")

	ship.global_transform = original_transform
	ship.velocity = original_velocity
	ship.hull = original_hull
	ship.impact_cooldown = original_impact_cooldown
	ship.autopilot = original_autopilot
	ship.planet_asset_sweep_shapes = original_shapes
	target.queue_free()
	await process_frame
