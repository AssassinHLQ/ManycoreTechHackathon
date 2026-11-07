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
	var test_save := "user://starward_station_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(6):
		await physics_frame

	var station = game.station
	_check(station != null, "homecoming station exists in the main scene")
	_check(station.get_parent() == game, "station stays in the existing world scene")
	_check(station.ring_root != null and station.ring_root.get_child_count() > 25, "station builds a detailed rotating ring")
	_check(station.ring_root.find_child("ContinuousRing", true, false) != null, "the rotating ring is one continuous mesh")
	_check(station.corridor_roots.size() == 6, "station builds six radial corridors")
	_check(station.hub_root != null and station.door_panels.size() == 6, "station builds a central hub with six doors")
	var port_local: Vector3 = station.to_local(station.docking_point())
	var dock_local: Vector3 = station.to_local(station.dock_ship_position())
	_check(port_local.y > 80.0, "docking port sits on the central command tower")
	_check(dock_local.y > port_local.y and dock_local.y - port_local.y < 20.0, "docked ship parks directly above the port")
	_check(station.station_body != null and station.station_body.get_child_count() > 80, "station interior is fully collided")
	_check(station._mat_window.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "interior windows use transparent glass")
	var exterior_shapes := 0
	for node in station.find_children("*", "CollisionShape3D", true, false):
		var body = node.get_parent()
		if body is PhysicsBody3D and body.collision_layer == 4:
			exterior_shapes += 1
	_check(exterior_shapes >= 40, "station exterior builds ship collision shapes")
	var space: PhysicsDirectSpaceState3D = station.get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 1.0
	var probe_query := PhysicsShapeQueryParameters3D.new()
	probe_query.shape = probe
	probe_query.collision_mask = 4
	var hull_probes := {
		"hub": Vector3(0.0, 0.0, 0.0),
		"arm": Vector3(60.0, 0.0, 0.0),
		"lower array": Vector3(0.0, -230.0, 0.0),
	}
	for key in hull_probes:
		probe_query.transform = Transform3D(Basis.IDENTITY, station.to_global(hull_probes[key]))
		_check(not space.intersect_shape(probe_query, 1).is_empty(), "exterior collision covers " + key)
	probe_query.transform = Transform3D(Basis.IDENTITY, station.to_global(Vector3(290.5, 0.0, 0.0)))
	_check(not space.intersect_shape(probe_query, 1).is_empty(), "continuous square ring band collides")
	probe_query.transform = Transform3D(Basis.IDENTITY, station.to_global(Vector3(cos(PI / 6.0), 0.0, sin(PI / 6.0)) * 220.0))
	_check(space.intersect_shape(probe_query, 1).is_empty(), "ring hole stays open")
	_check(station.orbit_planet == game.home, "station orbits the nearest planet")
	var orbit_offset: Vector3 = station.global_position - station.orbit_planet.global_position
	_check(orbit_offset.length() > float(station.orbit_planet.radius) + 1000.0, "station keeps a distant orbit")
	_check(absf(orbit_offset.length() - station.orbit_radius) < 50.0, "station holds its orbital radius")
	var orbit_before: Vector3 = station.global_position
	for i in range(60):
		await physics_frame
	_check(orbit_before.distance_to(station.global_position) > 0.2, "station slowly orbits the planet")

	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.landed = false
	game.ship.landed_planet = null
	game.ship.autopilot = false
	game.ship.fuel = 60.0
	game.ship.hull = 100.0
	game.ship.global_position = station.docking_point() + station.up_direction() * 18.0
	game.ship.velocity = Vector3.ZERO
	for i in range(4):
		await physics_frame
	_check(game.ship.docked, "slow close approach docks automatically")
	_check(game.ship.velocity.length() < 0.1, "docking stops the ship")
	var fuel_before: float = game.ship.fuel
	for i in range(30):
		await physics_frame
	_check(game.ship.fuel > fuel_before, "the dock replenishes propellant")
	var docked_before: Vector3 = game.ship.global_position
	for i in range(60):
		await physics_frame
	_check(game.ship.global_position.distance_to(station.dock_ship_position()) < 1.0, "docked ship follows the station orbit")
	_check(docked_before.distance_to(game.ship.global_position) > 0.2, "station orbit carries the docked ship")

	game.enter_station()
	for i in range(4):
		await physics_frame
	_check(game.in_station and game.state == "walk", "entering the station switches to walking inside")
	_check(game.player.camera.current, "station interior uses the player camera")
	_check(game.station.is_inside_tree() and game.player.get_parent() == station, "entering the station keeps the same scene tree")
	var spawn_local: Vector3 = station.to_local(game.player.global_position)
	_check(Vector2(spawn_local.x, spawn_local.z).length() < 10.0 and absf(spawn_local.z) > 3.0, "player spawns in the central hub")

	# 枢纽放气门：站到门前 6 米，门要从中缝分两扇滑开，而不是瞬间消失。
	game.player.global_position = station.to_global(Vector3(24.0, -1.98, 0.0))
	game.player.velocity = Vector3.ZERO
	# 逐帧采样，只要看到一次介于 0 与 1 之间的开度就说明门是滑开而不是瞬移。
	var door_partial := false
	for i in range(24):
		await process_frame
		var value: float = station.door_openness(0)
		if value > 0.0 and value < 0.95:
			door_partial = true
	for i in range(60):
		await physics_frame
	_check(door_partial, "the hub door slides open instead of popping")
	_check(station.door_openness(0) > 0.98, "the hub door finishes opening in front of the player")
	_check(game.audio.door.stream != null and game.audio.door.stream.get_length() > 0.5, "the opening hub door triggers its servo sound")
	_check(station.door_openness(1) < 0.02 and station.door_openness(2) < 0.02, "the other hub doors stay shut until approached")
	var leaf_local: Vector3 = (station.door_panels[0].get_child(0) as Node3D).position
	_check(absf(leaf_local.z) > 3.0, "the opened leaf parks beside the doorway")
	# 枢纽细节：合并成单节点多材质网格，且每个三角面朝外（绕序反了会被背面剔除，细节整片消失）。
	var detail = station.hub_root.get_node_or_null("HubDetail")
	var detail_mesh: ArrayMesh = null
	if detail is MeshInstance3D:
		detail_mesh = detail.mesh
	_check(detail_mesh != null and detail_mesh.get_surface_count() >= 5, "hub detail merges into a few material surfaces")
	var detail_tris := 0
	var inward := 0
	if detail_mesh != null:
		for s in range(detail_mesh.get_surface_count()):
			var arrays: Array = detail_mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var order := _triangle_order(detail_mesh, s, verts)
			for t in range(order.size() / 3):
				var i0 := order[t * 3]
				var i1 := order[t * 3 + 1]
				var i2 := order[t * 3 + 2]
				var front := _front_normal(verts[i0], verts[i1], verts[i2])
				if front.length_squared() > 0.0000001 and front.normalized().dot(normals[i0]) < 0.99:
					inward += 1
			detail_tris += order.size() / 3
	_check(detail_tris > 5000, "hub detail adds thousands of triangles")
	_check(inward == 0, "every hub detail face winds outward " + str(inward) + "/" + str(detail_tris))
	_check(detail == null or detail.find_children("*", "CollisionShape3D", true, false).is_empty(), "hub detail is decoration without collision")
	# 合并网格：走廊与枢纽的静态网格按"材质签名 + 空间分块"烘焙，三角形数必须一个不差。
	var corridor_merge: Dictionary = station.merge_reports.get("CorridorMerged", {})
	var hub_merge: Dictionary = station.merge_reports.get("HubMerged", {})
	_check(int(corridor_merge.get("nodes", 0)) > 1400 and int(corridor_merge.get("chunks", 0)) >= 6, "the corridor bakes 1,400+ static meshes into chunk meshes")
	_check(int(corridor_merge.get("merged_triangles", -1)) == int(corridor_merge.get("expected_triangles", -2)) and int(corridor_merge.get("source_triangles", 0)) > 50000, "merging keeps every corridor triangle")
	_check(int(hub_merge.get("nodes", 0)) > 600 and int(hub_merge.get("merged_triangles", -1)) == int(hub_merge.get("expected_triangles", -2)), "merging keeps every hub triangle")
	var merged_0 := _merged_chunks(station.corridor_roots[0])
	var merged_1 := _merged_chunks(station.corridor_roots[1])
	var shared_chunks := 0
	for chunk in merged_1:
		for other in merged_0:
			if chunk.mesh == other.mesh:
				shared_chunks += 1
	_check(not merged_1.is_empty() and shared_chunks == merged_1.size(), "the six corridors share the merged chunk meshes")
	# 关键：兼容渲染器每个对象只取 max_lights_per_object 盏灯，分块必须保证每块范围内的灯数不超过它，
	# 否则整条走廊一个大对象时，门口的灯会被一百米外的灯挤掉而发黑。
	var light_limit: int = int(ProjectSettings.get_setting("rendering/limits/opengl/max_lights_per_object", 8))
	var corridor_lights: Array = station.corridor_roots[0].find_children("*", "OmniLight3D", true, false)
	var worst_lights := 0
	for chunk in merged_0:
		var chunk_box: AABB = chunk.get_aabb()
		var nearby := 0
		for light in corridor_lights:
			var light_local: Vector3 = station.corridor_roots[0].to_local(light.global_position)
			if chunk_box.grow(light.omni_range).has_point(light_local):
				nearby += 1
		worst_lights = maxi(worst_lights, nearby)
	print("  corridor chunks=", merged_0.size(), " worst_lights_per_chunk=", worst_lights, " limit=", light_limit)
	_check(worst_lights <= light_limit, "no merged chunk sees more lights than the per-object limit")
	_check(station.hologram != null and station.hologram.get_child_count() >= 10, "the hall hologram keeps its own meshes for rotation")
	# 复刻玩家站在门口朝里看的场景：这条走廊必须处于渲染状态（发黑只能是灯光问题，不能是根本没画）。
	game.player.global_position = station.to_global(Vector3(28.0, -1.98, 0.0))
	game.player.global_transform = Transform3D(Basis.looking_at(station.global_transform.basis.x.normalized(), station.up_direction()), game.player.global_position)
	game.player.velocity = Vector3.ZERO
	for i in range(4):
		await physics_frame
	_check(station.active_corridor == 0 and station.corridor_roots[0].visible and not station.corridor_roots[1].visible, "standing at a hub door renders the corridor behind it")
	# 等门完全滑开再检查（否则门扇自己还在门洞里）
	for i in range(60):
		await physics_frame
	# 门口必须没有站体几何挡着：门开着时，门后那一段不能有可见面。
	# 六扇门背后曾经都是方臂的实心外壳端面（在 layer 4 上不挡玩家，所以是"能穿过去的墙"）。
	var door_box := AABB(Vector3(29.9, -1.0, -1.2), Vector3(3.1, 2.0, 2.4))
	var to_station: Transform3D = station.global_transform.affine_inverse()
	var blockers: Array = []
	for node in station.find_children("*", "MeshInstance3D", true, false):
		if not node.is_visible_in_tree():
			continue
		var mesh: Mesh = node.mesh
		if mesh == null:
			continue
		var node_xform: Transform3D = to_station * node.global_transform
		if not (node_xform * mesh.get_aabb()).intersects(door_box):
			continue
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var order := _triangle_order(mesh, s, vertices)
			var found := false
			for t in range(order.size() / 3):
				var i0 := order[t * 3]
				var i1 := order[t * 3 + 1]
				var i2 := order[t * 3 + 2]
				var p0: Vector3 = node_xform * vertices[i0]
				var p1: Vector3 = node_xform * vertices[i1]
				var p2: Vector3 = node_xform * vertices[i2]
				var tri := AABB(p0, Vector3.ZERO)
				tri = tri.expand(p1)
				tri = tri.expand(p2)
				if not tri.intersects(door_box):
					continue
				# 只算朝向枢纽中心（观察者）的面：背面会被剔除，不算挡路。
				# 正面方向按 Godot 约定 = cross(p2-p0, p1-p0)；枢纽外壳球这类朝外的面因此不会误报。
				var centroid: Vector3 = (p0 + p1 + p2) / 3.0
				var front: Vector3 = _front_normal(p0, p1, p2)
				if front.length_squared() <= 0.0000001 or centroid.length_squared() <= 0.0001:
					continue
				if front.normalized().dot(-centroid.normalized()) <= 0.0:
					continue
				found = true
				break
			if found:
				var parent_label := "<none>"
				if node.get_parent() != null:
					parent_label = String(node.get_parent().name)
				blockers.append("%s parent=%s aabb_local_center=%s size=%s" % [String(node.name), parent_label, str((node_xform * mesh.get_aabb()).get_center()), str(mesh.get_aabb().size)])
				break
	_check(blockers.is_empty(), "no station geometry blocks the open hub doorway " + str(blockers) + " door_open=" + str(station.door_openness(0)))
	var unit_normals := true
	var merged_surfaces := 0
	for node in station.find_children("*", "MeshInstance3D", true, false):
		var node_name := String(node.name)
		if not (node_name.begins_with("CorridorMerged") or node_name.begins_with("HubMerged") or node_name.begins_with("ExteriorMerged") or node_name.begins_with("RingMerged")):
			continue
		var merged_corridor: ArrayMesh = node.mesh
		for s in range(merged_corridor.get_surface_count()):
			merged_surfaces += 1
			var merged_arrays: Array = merged_corridor.surface_get_arrays(s)
			var merged_normals: PackedVector3Array = merged_arrays[Mesh.ARRAY_NORMAL]
			for n in merged_normals:
				if absf(n.length() - 1.0) > 0.01:
					unit_normals = false
	_check(unit_normals and merged_surfaces > 500, "merged normals stay unit length")
	# 站外合并：飞到站点附近时画的就是这些；端舱要能隐藏、信标材质要能继续闪，都在合并之外。
	var exterior_merge: Dictionary = station.merge_reports.get("ExteriorMerged", {})
	var ring_merge: Dictionary = station.merge_reports.get("RingMerged", {})
	_check(int(exterior_merge.get("nodes", 0)) > 1200 and int(exterior_merge.get("chunks", 0)) >= 20, "the station exterior bakes 1,200+ meshes into chunk meshes")
	_check(int(exterior_merge.get("merged_triangles", -1)) == int(exterior_merge.get("expected_triangles", -2)), "merging keeps every exterior triangle")
	_check(int(ring_merge.get("nodes", 0)) > 150 and int(ring_merge.get("merged_triangles", -1)) == int(ring_merge.get("expected_triangles", -2)), "the rotating ring details merge in place")
	var ring_chunks := 0
	for child in station.ring_root.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("RingMerged"):
			ring_chunks += 1
	_check(ring_chunks >= 5, "ring chunk meshes hang under the rotating ring")
	var beacon_surfaces := 0
	for node in station.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		for s in range(node.mesh.get_surface_count()):
			if node.material_override == station._beacon_material or node.mesh.surface_get_material(s) == station._beacon_material:
				beacon_surfaces += 1
			break
	_check(beacon_surfaces > 0, "docking beacons keep the pulsing material after merging")
	var pods_kept := 0
	for pod in station.end_pods:
		if pod is MeshInstance3D and pod.mesh != null:
			pods_kept += 1
	_check(pods_kept == station.end_pods.size(), "end pods stay separate so they can be hidden")
	print("  exterior nodes merged=", exterior_merge.get("nodes", 0), " chunks=", exterior_merge.get("chunks", 0), " ring merged=", ring_merge.get("nodes", 0), " ring chunks=", ring_merge.get("chunks", 0), " station_total=", _node_count(station))

	game.player.global_position = station.to_global(Vector3(8.0, -1.98, 0.0))
	game.player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for i in range(240):
		await physics_frame
	Input.action_release("move_forward")
	var walk_local: Vector3 = station.to_local(game.player.global_position)
	_check(walk_local.x > spawn_local.x + 2.0, "player can walk down the long corridor")
	_check(walk_local.x > 30.0, "player crosses the hub door into a radial corridor")
	_check(station.active_corridor == 0, "walking into corridor A activates it")
	_check(station.corridor_roots[0].visible and not station.corridor_roots[1].visible, "only the occupied corridor is rendered")
	# 只有当前走廊的碰撞留在物理世界；玩家站在某条走廊里时，它的地板必须仍然可用。
	var active_body = station.corridor_roots[0].find_child("StationCollision", true, false)
	var active_shapes := 0
	if active_body != null:
		for shape in active_body.get_children():
			if shape is CollisionShape3D and not shape.disabled:
				active_shapes += 1
	_check(active_shapes > 200, "the occupied corridor keeps its interior collision")
	var idle_body = station.corridor_roots[1].find_child("StationCollision", true, false)
	var idle_shapes := 0
	if idle_body != null:
		for shape in idle_body.get_children():
			if shape is CollisionShape3D and not shape.disabled:
				idle_shapes += 1
	print("  active corridor shapes=", active_shapes, " idle corridor shapes=", idle_shapes)
	_check(idle_shapes == 0, "the five idle corridors drop their interior collision")
	game.player.global_position = station.to_global(Vector3(60.0, -1.95, 0.0))
	game.player.velocity = Vector3.ZERO
	for i in range(60):
		await physics_frame
	_check(station.door_openness(0) < 0.02, "the hub door closes behind the player inside the corridor")
	# 站在门洞里回头看枢纽，门不许合上夹住玩家。
	var outward: Vector3 = station.global_transform.basis.x.normalized()
	game.player.global_transform = Transform3D(Basis.looking_at(-outward, station.up_direction()), station.to_global(Vector3(30.0, -1.6, 0.0)))
	game.player.velocity = Vector3.ZERO
	for i in range(60):
		await physics_frame
	_check(station.door_openness(0) > 0.9, "the hub door will not close on a player standing in the doorway")
	_check(game.player.is_on_floor(), "station floor keeps the player grounded")
	_check(station.is_interior_position(game.player.global_position), "walking stays inside the station hull")
	var door0: Node3D = station.door_panels[0].get_parent()
	probe.radius = 0.2
	probe_query.collision_mask = 1
	probe_query.transform = Transform3D(Basis.IDENTITY, door0.global_transform * Vector3(0.0, 0.4, 3.7))
	_check(not space.intersect_shape(probe_query, 1).is_empty(), "hub door side posts block the player")
	var corridor: Node3D = station.corridor_roots[0]
	probe_query.transform = Transform3D(Basis.IDENTITY, corridor.global_transform * Vector3(-87.4, -1.2, -4.95))
	_check(not space.intersect_shape(probe_query, 1).is_empty(), "lounge plant has collision")
	probe.radius = 0.1
	probe_query.transform = Transform3D(Basis.IDENTITY, corridor.global_transform * Vector3(-58.8, -1.78, -7.05))
	_check(not space.intersect_shape(probe_query, 1).is_empty(), "canteen chairs have collision")
	probe_query.transform = Transform3D(Basis.IDENTITY, corridor.global_transform * Vector3(-102.0, 0.6, 2.8))
	_check(not space.intersect_shape(probe_query, 1).is_empty(), "strips beside the bridge gate have collision")

	game.player.global_position = station.airlock_position() + station.global_transform.basis.x.normalized() * 1.0
	game._interact()
	_check(not game.in_station and game.state == "ship", "airlock console returns to the ship")
	_check(game.ship.docked, "returning to the ship keeps the docking latch")
	game.ship.undock()
	_check(not game.ship.docked and game.ship.velocity.length() > 5.0, "undocking pushes the ship clear")
	for i in range(40):
		await physics_frame
	_check(not game.ship.docked, "undocking stays clear during the cooldown")

	game.ship.global_position = station.global_position + station.global_transform.basis * Vector3(0.0, 0.0, -120.0)
	game.ship.velocity = (station.global_position - game.ship.global_position).normalized() * 90.0
	game.ship.hull = 100.0
	game.ship.impact_cooldown = 0.0
	for i in range(20):
		game.ship._move_with_station_collision(0.1)
	var ship_local: Vector3 = station.to_local(game.ship.global_position)
	_check(Vector2(ship_local.x, ship_local.z).length() > 34.0, "ship cannot fly through the station hub")
	_check(game.ship.hull < 100.0, "station impact damages the hull")

	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("STATION TEST COMPLETE: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)


func _merged_chunks(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("CorridorMerged"):
			out.append(child)
	return out


func _triangle_order(mesh: Mesh, surface: int, vertices: PackedVector3Array) -> PackedInt32Array:
	# 索引网格必须按索引读三角形，不能按顶点顺序每三个一组。
	var arrays: Array = mesh.surface_get_arrays(surface)
	var raw: Variant = arrays[Mesh.ARRAY_INDEX]
	if raw is PackedInt32Array and (raw as PackedInt32Array).size() > 0:
		return raw
	var order := PackedInt32Array()
	order.resize(vertices.size())
	for i in range(vertices.size()):
		order[i] = i
	return order


func _front_normal(p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	# Godot 的正面约定：顶点顺时针看过去的那一侧；cross(p2-p0, p1-p0) 指向正面。
	return (p2 - p0).cross(p1 - p0)


func _node_count(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		total += 1 + _node_count(child)
	return total
