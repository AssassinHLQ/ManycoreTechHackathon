extends SceneTree

const AtticWorlds = preload("res://scripts/attic_worlds.gd")
const WORLD_KEYS := ["snow", "cloud", "firefly", "alley"]

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


func _run() -> void:
	var worlds = AtticWorlds.new()
	root.add_child(worlds)
	worlds.build()
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
		_check(not has_tall_wall, key + " has no tall invisible perimeter wall")

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
