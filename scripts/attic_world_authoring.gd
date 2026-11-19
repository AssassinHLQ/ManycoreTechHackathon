extends RefCounted
## The four editable scenes replace generated content while preserving gameplay bindings.
const DIRECTORY := "res://scenes/attic_worlds/"
const LINES := {
	"cloud": "这里真的是家吗？",
	"firefly": "伪装的温柔为我点了一盏灯。",
	"alley": "逝者如斯夫，不会回来",
	"snow": "若你来自人类，请告诉我，家还在吗？",
}
const SIGN_POSITIONS := {
	"cloud": Vector3(10.5, 0.0, -4.7),
	"firefly": Vector3(5.3, 0.0, -8.5),
	"alley": Vector3(0.0, 0.0, -13.0),
	"snow": Vector3(5.0, 0.0, -6.5),
}
const KEYED_FIELDS := ["device_states", "device_values", "device_nodes", "world_done", "minigame_anchors"]
# These roots are visual-only. In particular, the return portal's glowing
# pane must stay passable, otherwise its baked mesh collider becomes an
# invisible wall directly in front of the interaction anchor.
const COLLISION_EXCLUDED_ROOTS := [
	"Airship", "CloudBoat", "CloudSea", "Ground", "Snowfall", "Fireflies", "Rain", "ReturnPortal"
]
const COLLISION_EXCLUDED_NODES := ["Ember", "Flame", "LanternGlow", "LampGlow", "Moon", "Puddle"]
const CONCAVE_COLLISION_ROOTS := ["Precision_World_", "Prop_snow-drift"]
const WORLD_FIELDS := {
	"snow": ["fishing_holes", "hearth_node", "hearth_light"],
	"cloud": ["bridge_node", "boat_node", "buoy_nodes", "airship_node"],
	"alley": ["court_lamps", "court_bench"],
	"firefly": [],
}


## Load authored geometry once, without first regenerating a duplicate world.
static func load_world(worlds: Node3D, key: String, holder: Node3D) -> bool:
	var path := DIRECTORY + key
	if not WORLD_FIELDS.has(key) or not ResourceLoader.exists(path + "_bindings.tres"):
		return false
	var tree := Engine.get_main_loop() as SceneTree
	var scene_path := path + ".tscn"
	var bindings_path := path + "_bindings.tres"
	var scene_request := ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	var bindings_request := ResourceLoader.load_threaded_request(bindings_path, "Resource")
	if scene_request != OK and scene_request != ERR_BUSY:
		return false
	if bindings_request != OK and bindings_request != ERR_BUSY:
		return false
	while true:
		var scene_status := ResourceLoader.load_threaded_get_status(scene_path)
		var bindings_status := ResourceLoader.load_threaded_get_status(bindings_path)
		if scene_status == ResourceLoader.THREAD_LOAD_FAILED or bindings_status == ResourceLoader.THREAD_LOAD_FAILED:
			return false
		if scene_status == ResourceLoader.THREAD_LOAD_LOADED and bindings_status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		await tree.process_frame
	var scene := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	var data := ResourceLoader.load_threaded_get(bindings_path) as Resource
	if scene == null or data == null:
		return false
	var content := scene.instantiate() as Node3D
	if content == null:
		return false
	var status := {"valid": true, "materials": {}}
	var decoded: Dictionary = _decode(data.get_meta("bindings"), content, holder, status)
	if not status.valid:
		content.free()
		push_warning("Editable world %s has missing gameplay nodes; using generated content." % key)
		return false
	# PackedScene resources are cached; isolate mutable puzzle materials per game.
	# Preserve aliases where multiple meshes intentionally share a puzzle material.
	for node in content.find_children("*", "GeometryInstance3D", true, false):
		if status.materials.has(node.material_override):
			node.material_override = status.materials[node.material_override]
	# Authored scenes include their collision nodes. Loading only rebinds gameplay
	# references and never walks mesh faces or creates geometry.
	holder.add_child(content)
	content.set_meta("collision_ready", true)
	worlds.worlds[key] = decoded.world
	for field in decoded.keyed:
		worlds.get(field)[key] = decoded.keyed[field]
	for id in decoded.props:
		worlds.prop_anchors[id] = decoded.props[id]
		worlds.prop_used[id] = false
	for field in decoded.fields:
		worlds.set(field, decoded.fields[field])
	_sync_authored_positions(worlds, key, content)
	return true


static func _sync_authored_positions(worlds: Node3D, key: String, content: Node3D) -> void:
	var spawn := content.get_node_or_null("PlayerSpawn") as Node3D
	if spawn != null:
		worlds.worlds[key]["spawn"] = content.transform * spawn.position
	if key == "cloud" and is_instance_valid(worlds.boat_node):
		worlds.boat_pos = Vector2(worlds.boat_node.position.x, worlds.boat_node.position.z)
		worlds.airship_center = worlds.airship_node.position


## Bindings contain paths into editable scenes, never copies of their geometry.
static func save_bindings(worlds: Node3D, key: String) -> Error:
	var content: Node3D = worlds.worlds[key].content
	var keyed := {}
	for field in KEYED_FIELDS:
		if worlds.get(field).has(key):
			keyed[field] = worlds.get(field)[key]
	var props := {}
	for id in worlds.prop_ids_in(key):
		props[id] = worlds.prop_anchors[id]
	var fields := {}
	for field in WORLD_FIELDS[key]:
		fields[field] = worlds.get(field)
	var materials := {}
	for node in content.find_children("*", "GeometryInstance3D", true, false):
		if node.material_override != null:
			materials[node.material_override] = String(content.get_path_to(node))
	var source := {"world": worlds.worlds[key], "keyed": keyed, "props": props, "fields": fields}
	var data := Resource.new()
	data.set_meta("bindings", _encode(source, content, materials))
	return ResourceSaver.save(data, DIRECTORY + key + "_bindings.tres")


static func _encode(value, content: Node3D, materials: Dictionary):
	if value is Node:
		return {"$holder": true} if value == content.get_parent() \
			else {"$node": String(content.get_path_to(value))}
	if value is Material:
		assert(materials.has(value), "Gameplay material has no editable mesh")
		return {"$material": materials.get(value, "")}
	if value is Array:
		var result := []
		for item in value:
			result.append(_encode(item, content, materials))
		return result
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _encode(value[key], content, materials)
		return result
	return value


static func _decode(value, content: Node3D, holder: Node3D, status: Dictionary):
	if value is Dictionary:
		if value.has("$holder"):
			return holder
		if value.has("$node") or value.has("$material"):
			var node := content.get_node_or_null(value.get("$node", value.get("$material", "")))
			if node == null:
				status.valid = false
				return null
			if value.has("$material"):
				if not node is GeometryInstance3D or node.material_override == null:
					status.valid = false
					return null
				var material: Material = node.material_override
				if not status.materials.has(material):
					status.materials[material] = material.duplicate()
				return status.materials[material]
			return node
		var result := {}
		for key in value:
			result[key] = _decode(value[key], content, holder, status)
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(_decode(item, content, holder, status))
		return result
	return value


static func add_story_sign(content: Node3D, key: String) -> void:
	var sign_root := Node3D.new()
	sign_root.name = "StorySign"
	# Hide the board from the direct approach while keeping its reading face reachable.
	sign_root.scale = Vector3.ONE * 0.32
	sign_root.position = SIGN_POSITIONS.get(key, Vector3(0, 0, -14.0))
	content.add_child(sign_root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("302b28")
	wood.roughness = 0.9
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color("a28a65")
	rim.roughness = 0.65
	for side in [-1.0, 1.0]:
		_add_box(sign_root, "Post" + ("Left" if side < 0 else "Right"),
			Vector3(0.12, 2.5, 0.12), Vector3(side * 2.1, 0.8, 0), rim)
	_add_box(sign_root, "Frame", Vector3(5.6, 1.55, 0.2), Vector3(0, 2.0, 0), rim)
	_add_box(sign_root, "Board", Vector3(5.42, 1.37, 0.22), Vector3(0, 2.0, 0), wood)
	var label := Label3D.new()
	label.name = "Text"
	label.text = LINES[key]
	label.font = load("res://assets/ui_font.ttf")
	label.font_size = 64
	label.pixel_size = 0.0055
	label.outline_size = 5
	label.modulate = Color("f4e4bc")
	label.position = Vector3(0, 2.0, 0.125)
	label.no_depth_test = false
	sign_root.add_child(label)
	var light := OmniLight3D.new()
	light.name = "SignLight"
	light.position = Vector3(0, 2.8, 1.0)
	light.light_color = Color("ffdfa5")
	light.light_energy = 0.12
	light.omni_range = 3.5
	sign_root.add_child(light)

static func _add_box(parent: Node3D, title: String, size: Vector3,
		at: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)


static func stable_names(parent: Node) -> void:
	var index := 0
	for child in parent.get_children():
		index += 1
		if String(child.name).begins_with("@"):
			child.name = "%s_%04d" % [child.get_class(), index]
		# Imported model internals already have stable authored names.
		if child.scene_file_path.is_empty():
			stable_names(child)


static func _own_children(parent: Node, scene_root: Node) -> void:
	for child in parent.get_children():
		child.owner = scene_root
		if child.scene_file_path.is_empty():
			_own_children(child, scene_root)


static func save_content(content: Node3D, key: String) -> Error:
	clear_baked_static_mesh_collisions(content)
	bake_static_mesh_collisions(content)
	_own_children(content, content)
	var scene := PackedScene.new()
	var result := scene.pack(content)
	if result != OK:
		return result
	return ResourceSaver.save(scene, DIRECTORY + key + ".tscn")


static func clear_baked_static_mesh_collisions(content: Node3D) -> void:
	for node in content.find_children("MeshSelfCollision", "StaticBody3D", true, false):
		node.free()


static func bake_static_mesh_collisions(content: Node3D) -> void:
	for prop_root in content.get_children():
		if not prop_root is Node3D or prop_root is CollisionObject3D:
			continue
		if COLLISION_EXCLUDED_ROOTS.has(String(prop_root.name)):
			continue
		if not prop_root.find_children("*", "CollisionObject3D", true, false).is_empty():
			continue
		var faces := PackedVector3Array()
		_collect_collision_faces(prop_root, Transform3D.IDENTITY, true, faces)
		if faces.size() < 3:
			continue
		var collision_body := StaticBody3D.new()
		collision_body.name = "MeshSelfCollision"
		collision_body.collision_layer = 1
		collision_body.collision_mask = 0
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		if _use_concave_collision(prop_root):
			var mesh_shape := ConcavePolygonShape3D.new()
			mesh_shape.backface_collision = true
			mesh_shape.set_faces(faces)
			collision_shape.shape = mesh_shape
		else:
			var bounds := _collision_bounds(faces)
			if bounds.size.length_squared() < 0.000001:
				continue
			var box_shape := BoxShape3D.new()
			box_shape.size = bounds.size
			collision_shape.shape = box_shape
			collision_shape.position = bounds.position + bounds.size * 0.5
		collision_body.add_child(collision_shape)
		prop_root.add_child(collision_body)
	content.set_meta("collision_ready", true)


static func _use_concave_collision(prop_root: Node) -> bool:
	var root_name := String(prop_root.name)
	for prefix in CONCAVE_COLLISION_ROOTS:
		if root_name.begins_with(prefix):
			return true
	return false


static func _collision_bounds(faces: PackedVector3Array) -> AABB:
	var bounds := AABB(faces[0], Vector3.ZERO)
	for index in range(1, faces.size()):
		bounds = bounds.expand(faces[index])
	return bounds


static func _collect_collision_faces(node: Node, node_transform: Transform3D,
		parent_visible: bool, faces: PackedVector3Array) -> void:
	if not is_instance_valid(node) or COLLISION_EXCLUDED_NODES.has(String(node.name)):
		return
	var visible := parent_visible
	if node is GeometryInstance3D:
		visible = visible and (node as GeometryInstance3D).visible
	if visible and node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and is_instance_valid(mesh_node.mesh) and mesh_node.mesh.get_surface_count() > 0:
			var mesh_faces := mesh_node.mesh.get_faces()
			for face in mesh_faces:
				faces.append(node_transform * face)
	for child in node.get_children():
		if not is_instance_valid(child):
			continue
		var child_transform := node_transform
		if child is Node3D:
			child_transform = node_transform * (child as Node3D).transform
		_collect_collision_faces(child, child_transform, visible, faces)
