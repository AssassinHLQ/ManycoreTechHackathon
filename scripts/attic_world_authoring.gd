extends RefCounted
## The four editable scenes replace generated content while preserving gameplay bindings.
const DIRECTORY := "res://scenes/attic_worlds/"
const LINES := {
	"cloud": "这里真的是家吗？",
	"firefly": "伪装的温柔为我点了一盏灯。",
	"alley": "逝者如斯夫，不会回来",
	"snow": "这里真的是家吗？",
}
const KEYED_FIELDS := ["device_states", "device_values", "device_nodes", "world_done", "minigame_anchors"]
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
	var scene := load(path + ".tscn") as PackedScene
	var data := load(path + "_bindings.tres") as Resource
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
	holder.add_child(content)
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
	# Keep the writing turned away from the normal route and readable only through the telescope.
	sign_root.rotation.y = PI
	sign_root.scale = Vector3.ONE * 0.45
	sign_root.position = Vector3(0, 0, -14.0)
	if key == "cloud":
		sign_root.position = Vector3(0, 0, -5.9)
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
	_own_children(content, content)
	var scene := PackedScene.new()
	var result := scene.pack(content)
	if result != OK:
		return result
	return ResourceSaver.save(scene, DIRECTORY + key + ".tscn")


static func install(worlds: Node3D, key: String) -> void:
	var path := DIRECTORY + key + ".tscn"
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var old: Node3D = worlds.worlds[key]["content"]
	var replacement := scene.instantiate() as Node3D
	if replacement == null:
		return
	var nodes := {old: replacement}
	var resources := {}
	for node in old.find_children("*", "", true, false):
		var target := replacement.get_node_or_null(old.get_path_to(node))
		if target != null:
			nodes[node] = target
			if node is GeometryInstance3D and target is GeometryInstance3D:
				if node.material_override != null and target.material_override != null:
					resources[node.material_override] = target.material_override
	var properties: Array = worlds.get_script().get_script_property_list()
	# Missing gameplay anchors must fall back safely, rather than leave stale references.
	for property in properties:
		if _missing_reference(worlds.get(property.name), old, nodes):
			push_warning("Editable world %s is missing a gameplay node; using generated content." % key)
			replacement.free()
			return
	var parent := old.get_parent()
	parent.remove_child(old)
	parent.add_child(replacement)
	replacement.name = "Content"
	for property in properties:
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			worlds.set(property.name, _rebind(worlds.get(property.name), nodes, resources))
	_sync_authored_positions(worlds, key, replacement)
	old.free()


static func _missing_reference(value, old: Node, nodes: Dictionary) -> bool:
	if value is Node:
		return (value == old or old.is_ancestor_of(value)) and not nodes.has(value)
	if value is Array:
		for item in value:
			if _missing_reference(item, old, nodes):
				return true
	elif value is Dictionary:
		for item in value.values():
			if _missing_reference(item, old, nodes):
				return true
	return false


static func _rebind(value, nodes: Dictionary, resources: Dictionary):
	if value is Node:
		return nodes.get(value, value)
	if value is Resource:
		return resources.get(value, value)
	if value is Array:
		for index in range(value.size()):
			value[index] = _rebind(value[index], nodes, resources)
	elif value is Dictionary:
		for key in value:
			value[key] = _rebind(value[key], nodes, resources)
	return value
