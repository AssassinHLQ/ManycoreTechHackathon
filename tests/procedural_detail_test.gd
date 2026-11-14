extends SceneTree

const Geo = preload("res://scripts/procedural_geometry.gd")
const Dressing = preload("res://scripts/procedural_dressing.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)
	else:
		print("PASS ", label)

func _geometry(mesh: Mesh, size: Vector3, label: String) -> void:
	var ab := mesh.get_aabb()
	_check(ab.size.is_equal_approx(size) and ab.get_center().length() < 0.0001, label + " exact envelope")
	var a := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var order := PackedInt32Array()
	if a[Mesh.ARRAY_INDEX] != null:
		order = a[Mesh.ARRAY_INDEX]
	else:
		for i in range(vertices.size()):
			order.append(i)
	var valid := true
	var normals_valid := true
	for i in range(0, order.size(), 3):
		var p := vertices[order[i]]
		var q := vertices[order[i + 1]]
		var r := vertices[order[i + 2]]
		var cross := (q - p).cross(r - p)
		var normal := normals[order[i]] + normals[order[i + 1]] + normals[order[i + 2]]
		valid = valid and cross.length_squared() > 0.00000000001 and cross.dot(normal) < 0.0
	for n in normals:
		normals_valid = normals_valid and n.is_finite() and absf(n.length() - 1.0) < 0.001
	_check(valid, label + " outward winding, no degenerate triangles")
	_check(normals_valid and uv.size() == vertices.size(), label + " normals and UVs")

func _run() -> void:
	for size in [Vector3(1, 2, 3), Vector3(0.08, 0.12, 0.3), Vector3(20, 0.4, 7)]:
		_geometry(Geo.box(size), size, "bevel " + str(size))
	_geometry(Geo.cylinder(0.8, 1.0, 2.0), Vector3(2, 2, 2), "turned cylinder")
	_geometry(Geo.crystal(1.0, 3.0), Vector3(2, 3, sqrt(3.0)), "faceted crystal")
	_check(Geo.box(Vector3.ONE) == Geo.box(Vector3.ONE), "box geometry is cached")
	_check(Geo.cylinder(1, 1, 2) == Geo.cylinder(1, 1, 2), "cylinder geometry is cached")
	var floor := BoxMesh.new()
	floor.size = Vector3(6.8, 0.08, 0.416)
	_check(Geo.refine(floor, true) == floor, "continuous floorboard retains all corners")
	var shard := CylinderMesh.new()
	shard.top_radius = 0.0
	shard.radial_segments = 4
	_check(Geo.refine(shard) == shard and shard.radial_segments == 4, "authored crystal facets retained")
	var imported := MeshInstance3D.new()
	imported.mesh = BoxMesh.new()
	imported.scene_file_path = "res://assets/models/props/test.glb"
	var old_mesh := imported.mesh
	Geo.finish_tree(imported)
	_check(imported.mesh == old_mesh, "imported scene mesh remains authoritative")
	imported.free()
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://procedural_detail_knowledge.json"
	game.progress_path = "user://procedural_detail_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	while game.planets.size() < 20 or game.world_build_remaining:
		await process_frame
	var landmarks := 0
	var caves := 0
	var pieces := 0
	for node in game.find_children("Precision_*", "MeshInstance3D", true, false):
		pieces += int(node.get_meta("detail_pieces", 0))
		if node.name.begins_with("Precision_Landmark_"):
			landmarks += 1
		if node.name == "Precision_CaveStrata":
			caves += 1
	_check(landmarks == 10 and caves == 3, "ten landmarks and three caves receive construction details")
	await physics_frame
	await physics_frame
	for cave in game.find_children("Cave_*", "Node3D", true, false):
		if not cave.name.begins_with("Cave_Q") and not cave.name.begins_with("Cave_Z") and not cave.name.begins_with("Cave_X"):
			continue
		# Read the authored shaft boxes, rather than assuming each planet has the same mouth.
		var shaft_radius := 0.0
		for shape in cave.get_node("CaveCollision").get_children():
			if shape is CollisionShape3D and shape.shape is BoxShape3D and absf(shape.shape.size.x - 1.4) < 0.001:
				shaft_radius = Vector2(shape.position.x, shape.position.z).length()
				break
		var clear := 0
		var space: PhysicsDirectSpaceState3D = cave.get_world_3d().direct_space_state
		for i in range(24):
			var angle := TAU * float(i) / 24.0
			var radial := Vector3(cos(angle), 0, sin(angle))
			var from: Vector3 = cave.to_global(radial * (shaft_radius - 0.5) + Vector3(0, -11.3, 0))
			var to: Vector3 = cave.to_global(radial * (shaft_radius + 2.3) + Vector3(0, -11.3, 0))
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty():
				clear += 1
		_check(shaft_radius > 0 and clear >= 8, String(cave.name) + " lower shaft opens into furnished chamber " + str(clear) + "/24")
	_check(game.attic.root.get_node_or_null("Precision_AtticJoinery") != null, "attic joinery built")
	for key in game.attic_worlds.worlds:
		var content: Node3D = game.attic_worlds.worlds[key].content
		var detail: Node = content.get_node_or_null("Precision_World_" + key)
		_check(detail != null and int(detail.get_meta("detail_pieces", 0)) > 0, "world " + key + " construction details")
	_check(game.station.hub_root.get_node_or_null("Precision_HubDoorHardware") != null, "station door hardware built")
	for radius in [358.0, 380.0]:
		var hall = load("res://scripts/distant_station_interior.gd").new()
		root.add_child(hall)
		hall.build(radius, Color("72c8df"))
		_check(hall.get_node_or_null("Precision_HallServices") != null, "distant station hall " + str(radius))
		await physics_frame
		await physics_frame
		var space: PhysicsDirectSpaceState3D = hall.get_world_3d().direct_space_state
		var clear := true
		for i in range(24):
			var angle := TAU * float(i) / 24.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 2, 0), Vector3(cos(angle) * hall.hall_radius * 1.2, 2, sin(angle) * hall.hall_radius * 1.2)))
			clear = clear and not hit.is_empty() and (hit.position as Vector3).distance_to(Vector3(0, 2, 0)) > hall.hall_radius * 0.90
		_check(clear, "distant hall has clear interior and sealed window perimeter " + str(radius))
		var foot := Vector3(hall.hall_radius * 0.4, 1.0, 0)
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(foot, foot - Vector3.UP * 3))
		_check(not floor_hit.is_empty() and absf(floor_hit.position.y) < 0.02, "distant hall floor supports player " + str(radius))
		hall.queue_free()
		await process_frame
	for is_boss in [false, true]:
		var enemy := Node3D.new()
		root.add_child(enemy)
		Dressing.enemy(enemy, is_boss)
		_check(enemy.get_child_count() == 1 and enemy.get_child(0).mesh.get_surface_count() <= 4, "enemy details batched " + str(is_boss))
		enemy.queue_free()
	# Imported textures must not disappear when station materials are merged.
	var a := StandardMaterial3D.new()
	var b := StandardMaterial3D.new()
	var im := Image.create(4, 4, false, Image.FORMAT_RGB8)
	a.albedo_texture = ImageTexture.create_from_image(im)
	b.albedo_texture = ImageTexture.create_from_image(im)
	_check(game.station._material_signature(a) != game.station._material_signature(b), "distinct imported textures do not merge")
	# Exercise the representation boundary that previously dropped entire bevels.
	var mixed := Node3D.new()
	root.add_child(mixed)
	var mat := StandardMaterial3D.new()
	for i in range(2):
		var node := MeshInstance3D.new()
		var mesh: Mesh = BoxMesh.new()
		if i == 1:
			var unindexed := SurfaceTool.new()
			unindexed.begin(Mesh.PRIMITIVE_TRIANGLES)
			unindexed.append_from(mesh, 0, Transform3D.IDENTITY)
			unindexed.deindex()
			mesh = unindexed.commit()
		node.mesh = mesh
		node.material_override = mat
		node.position.x = float(i) * 2
		mixed.add_child(node)
	game.station._merge_static_meshes(mixed, [], "MixedRepresentation")
	var report: Dictionary = game.station.merge_reports["MixedRepresentation"]
	_check(report.source_triangles == 24 and report.expected_triangles == 24 and report.merged_triangles == 24,
		"indexed and unindexed inputs retain every triangle in the same merge bucket")
	mixed.queue_free()
	print("DETAIL PIECES ", pieces)
	print("PROCEDURAL DETAIL COMPLETE: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
