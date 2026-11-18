extends SceneTree

const AtticWorlds = preload("res://scripts/attic_worlds.gd")
const WORLD_KEYS := ["snow", "cloud", "firefly", "alley", "mirror"]

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)


func _shape_height(shape: Shape3D) -> float:
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height
	return 0.0


func _exclude_other_bodies(holder: Node, keep: CollisionObject3D) -> Array[RID]:
	var excluded: Array[RID] = []
	for node in holder.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body != keep:
			excluded.append(body.get_rid())
	return excluded


func _ray_hits_mesh(holder: Node3D, body: StaticBody3D) -> bool:
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is ConcavePolygonShape3D:
		return false
	var faces := (collision.shape as ConcavePolygonShape3D).get_faces()
	var space := holder.get_world_3d().direct_space_state
	for i in range(0, faces.size(), 3):
		var a: Vector3 = body.global_transform * faces[i]
		var b: Vector3 = body.global_transform * faces[i + 1]
		var c: Vector3 = body.global_transform * faces[i + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 0.000001:
			continue
		normal = normal.normalized()
		var center := (a + b + c) / 3.0
		var query := PhysicsRayQueryParameters3D.create(center + normal * 0.2, center - normal * 0.2)
		query.collision_mask = body.collision_layer
		query.exclude = _exclude_other_bodies(holder, body)
		var hit := space.intersect_ray(query)
		if hit.get("collider") == body:
			return true
	return false


func _run() -> void:
	var worlds = AtticWorlds.new()
	root.add_child(worlds)
	await worlds.build()
	await physics_frame

	for key in WORLD_KEYS:
		worlds.set_active_world(key)
		await physics_frame
		var holder := worlds.world_node(key) as Node3D
		var collision := holder.find_child("WorldCollision", true, false) as StaticBody3D
		_check(collision != null, key + " has a world collision body")
		if collision == null:
			continue

		var shape_count := 0
		var has_tall_wall := false
		for node in collision.get_children():
			if node is CollisionShape3D:
				shape_count += 1
				has_tall_wall = has_tall_wall or _shape_height((node as CollisionShape3D).shape) > 1.1
		_check(shape_count > 0, key + " keeps walkable platform collision")
		if key == "mirror":
			_check(shape_count == 4, "mirror collision contains only its floor and three visible walls")
			var content: Node3D = worlds.worlds[key]["content"]
			var mirror_panels := content.find_children("MirrorPanel_*", "MeshInstance3D", true, false)
			_check(mirror_panels.size() == 5, "mirror hall has five framed mirror panels")
			_check(content.find_child("MirrorHeartHalo", true, false) != null,
				"mirror altar keeps its halo after the heart is collected")
			var space := holder.get_world_3d().direct_space_state
			var exclude := _exclude_other_bodies(holder, collision)
			var back_query := PhysicsRayQueryParameters3D.create(
				content.to_global(Vector3(0, 1.7, 0)), content.to_global(Vector3(0, 1.7, -6.0)))
			back_query.collision_mask = collision.collision_layer
			back_query.exclude = exclude
			_check(space.intersect_ray(back_query).get("collider") == collision,
				"mirror back wall blocks at its visible surface")
			var side_query := PhysicsRayQueryParameters3D.create(
				content.to_global(Vector3(0, 1.7, 0)), content.to_global(Vector3(7.0, 1.7, 0)))
			side_query.collision_mask = collision.collision_layer
			side_query.exclude = exclude
			_check(space.intersect_ray(side_query).get("collider") == collision,
				"mirror side wall blocks at its visible surface")
			var front_query := PhysicsRayQueryParameters3D.create(
				content.to_global(Vector3(0, 1.7, 0)), content.to_global(Vector3(0, 1.7, 14.0)))
			front_query.collision_mask = collision.collision_layer
			front_query.exclude = exclude
			_check(space.intersect_ray(front_query).is_empty(),
				"mirror courtyard opening has no invisible perimeter wall")
		else:
			_check(not has_tall_wall, key + " has no tall invisible perimeter wall")
		var return_portal := holder.find_child("ReturnPortal", true, false)
		_check(return_portal != null, key + " has a visible return portal")
		if return_portal != null:
			_check(return_portal.find_children("MeshSelfCollision", "StaticBody3D", true, false).is_empty(),
				key + " return portal remains passable")
		if key == "snow":
			var drift := holder.find_child("Prop_snow-drift", true, false) as Node3D
			var drift_collision := drift.get_node_or_null("MeshSelfCollision") as StaticBody3D if drift != null else null
			_check(drift_collision != null, "snow drift has mesh-derived collision")
			if drift_collision != null:
				var drift_shape := drift_collision.get_node_or_null("CollisionShape3D") as CollisionShape3D
				_check(drift_shape != null and drift_shape.shape is ConcavePolygonShape3D,
					"snow drift collision follows its rendered triangle mesh")
				_check(_ray_hits_mesh(holder, drift_collision),
					"snow drift mesh collider registers in the physics space")

		var anchor := worlds.return_anchor(key) as Node3D
		_check(anchor != null, key + " has a return anchor")
		if anchor == null:
			continue

		var query := PhysicsRayQueryParameters3D.create(
			anchor.global_position + Vector3.UP * 3.0,
			anchor.global_position - Vector3.UP * 4.0
		)
		query.collision_mask = collision.collision_layer
		query.exclude = _exclude_other_bodies(holder, collision)
		var hit := holder.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty() and hit.get("collider") == collision,
			key + " return anchor is above its walkable floor")

		if key == "cloud":
			_check(anchor.global_position.distance_to(worlds.spawn_position(key)) < 2.4,
				"cloud return anchor is within interaction reach of the entrance")

	worlds.queue_free()
	await process_frame
	print("POCKET COLLISION TEST: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)
