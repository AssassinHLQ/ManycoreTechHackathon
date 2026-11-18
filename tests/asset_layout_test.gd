extends SceneTree

const Attic := preload("res://scripts/attic.gd")
const Worlds := preload("res://scripts/attic_worlds.gd")
const Placement := preload("res://scripts/prop_placement.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)


func _run() -> void:
	var attic := Attic.new()
	root.add_child(attic)
	await attic.build()
	var worlds := Worlds.new()
	worlds.use_authored_scenes = false
	root.add_child(worlds)
	await worlds.build()
	await physics_frame
	await physics_frame
	var used := {}
	for node in attic.find_children("*", "Node3D", true, false) + worlds.find_children("*", "Node3D", true, false):
		if node.has_meta("generated_asset"):
			used[node.get_meta("generated_asset")] = true
	var available := 0
	for directory in [Attic.PROP_DIR, Worlds.WORLD_PROP_DIR]:
		for name in DirAccess.get_directories_at(directory):
			for filename in ["model.glb", "model_glb.glb"]:
				var path: String = directory + name + "/" + filename
				if ResourceLoader.exists(path):
					available += 1
					_check(used.has(path), "generated asset is instantiated: " + path)
					break
	print("ASSET COVERAGE: %d available, %d instantiated paths" % [available, used.size()])
	var cabinet_a := attic.prop("side-cabinet", 0.52)
	var cabinet_b := attic.prop("side-cabinet", 0.66)
	if cabinet_a != null and cabinet_b != null:
		_check(absf(Placement.bounds(cabinet_a).size.y - 0.52) < 0.001, "small cabinet size")
		_check(absf(Placement.bounds(cabinet_b).size.y - 0.66) < 0.001, "cache preserves different requested sizes")
		cabinet_a.free()
		cabinet_b.free()
	for i in range(13):
		var a: MeshInstance3D = attic.root.get_node("Floorboard_%02d" % i)
		var b: MeshInstance3D = attic.root.get_node("Floorboard_%02d" % (i + 1))
		_check(a.position.z + a.mesh.size.z * 0.5 >= b.position.z - b.mesh.size.z * 0.5,
			"floor seam %d closed" % i)
	_check(attic.root.get_node("Roof_Left").rotation.z > 0 and attic.root.get_node("Roof_Right").rotation.z < 0,
		"roof rises toward the ridge")
	var mirror_plinth := attic.root.get_node_or_null("MirrorCorridor/Prop_mirror-plinth") as Node3D
	if ResourceLoader.exists("res://assets/models/props/attic/mirror-plinth/model.glb"):
		_check(mirror_plinth != null, "mirror entrance uses its generated plinth")
	if mirror_plinth != null:
		var plinth_bounds := Placement.bounds(mirror_plinth)
		_check(absf(mirror_plinth.position.y + plinth_bounds.position.y) < 0.002,
			"mirror plinth rests on the floor")
		_check(attic.body.get_node_or_null("Prop_mirror-plinthCollision") != null,
			"mirror plinth has a matching collision")
	var space := attic.get_world_3d().direct_space_state
	for y in [1.2, 2.7]:
		for i in range(72):
			var direction := Vector3(cos(float(i) * TAU / 72), 0, sin(float(i) * TAU / 72))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, y, 0), Vector3(0, y, 0) + direction * 12))
			_check(not hit.is_empty(), "room perimeter sealed at y=%.1f angle=%d" % [y, i * 5])
	var table: Node3D = attic.root.get_node("TeaTable")
	var table_model := table.get_node_or_null("Prop_tea-table") as Node3D
	if table_model != null:
		for node in table.get_children():
			if not node.has_meta("generated_asset") or node == table_model or node.name.begins_with("Prop_teacup"):
				continue
			var box: AABB = node.transform * Placement.bounds(node)
			var supported := true
			for corner in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
				Vector2(box.position.x, box.end.z), Vector2(box.end.x, box.end.z)]:
				var height := Placement.support_y(table_model, corner, 0.8)
				supported = supported and is_finite(height) and absf(box.position.y - height) < 0.012
			_check(supported, "table supports " + String(node.name))
	var shelf: Node3D = attic.root.get_node("TravelShelf")
	var shelf_model := shelf.get_node_or_null("Prop_bookshelf") as Node3D
	if shelf_model != null:
		for stand in shelf.find_children("KeepsakeStand_*", "MeshInstance3D", false, false):
			var y := Placement.support_y(shelf_model, Vector2(stand.position.x, stand.position.z), 1.35)
			_check(absf(stand.position.y - 0.006 - y) < 0.001, "shelf supports " + String(stand.name))
	for i in range(3):
		attic.advance_tea()
	_check(attic.tea_step == 3 and attic.tea_cups.size() == 2, "tea completes with generated cups")
	for cup in attic.tea_cups:
		_check(cup is MeshInstance3D and cup.visible, "tea liquid feedback exists")
	attic.show_swallow()
	attic.greet_swallow()
	for i in range(180):
		attic.update_swallow(1.0 / 60.0)
	var perch: Node3D = attic.anchors["AtticAnchor_HearthPerch"]
	_check(attic.swallow_node.global_position.distance_to(perch.global_position) < 0.001, "bird lands on cabinet in correct coordinates")
	_check(worlds.bridge_node != null, "generated winch retains bridge")
	worlds.use_winch()
	for i in range(120):
		worlds.update_bridge(1.0 / 60)
	_check(worlds.bridge_node != null and worlds.bridge_node.visible and worlds.bridge_down, "winch unfolds visible bridge")
	for id in worlds.prop_ids_in("alley"):
		var anchor: Node3D = worlds.prop_anchor(id)
		var box := Placement.bounds(anchor)
		_check(anchor.position.x + box.position.x > -3.15 and anchor.position.x + box.end.x < 3.15,
			"alley prop is inside walls: " + id)
	print("ASSET LAYOUT TEST COMPLETE: %d checks, %d failure(s)" % [checks, failures])
	attic.queue_free()
	worlds.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
