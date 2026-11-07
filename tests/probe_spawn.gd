extends SceneTree
var game
func _initialize(): call_deferred("_run")
func _run():
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_spawn_probe.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(40):
		await physics_frame
	var spawn: Vector3 = game.player.global_position
	var planet = game.home
	print("spawn local=", game.player.position, " floor=", game.player.is_on_floor())
	var shape := SphereShape3D.new()
	shape.radius = 6.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, spawn + Vector3(0, 1.0, 0))
	query.collision_mask = 1
	var hits = game.get_world_3d().direct_space_state.intersect_shape(query, 32)
	for hit in hits:
		var collider = hit.collider
		var chain := ""
		var p = collider
		while p != null and p != planet:
			chain = p.name + "/" + chain
			p = p.get_parent()
		var shape_info = ""
		for child in collider.get_children():
			if child is CollisionShape3D:
				shape_info = str(child.shape)
				break
		print("  body=", collider.name, " chain=", chain, " dist=", collider.global_position.distance_to(spawn), " shape=", shape_info)
	game.queue_free()
	await process_frame
	quit()
