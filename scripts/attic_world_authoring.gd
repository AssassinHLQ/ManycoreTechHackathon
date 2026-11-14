extends RefCounted
## The four editable scenes replace generated content while preserving gameplay bindings.
const DIRECTORY := "res://scenes/attic_worlds/"
const LINES := {
	"cloud": "这里真的是家吗？",
	"firefly": "伪装的温柔为我点了一盏灯。",
	"alley": "逝者如斯夫，不会回来",
	"snow": "这里真的是家吗？",
}


static func add_story_sign(content: Node3D, key: String) -> void:
	var sign_root := Node3D.new()
	sign_root.name = "StorySign"
	# Beyond the disk, facing inward. Cloud uses the edge of its central island.
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
	light.light_energy = 0.55
	light.omni_range = 6.0
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
	var spawn := replacement.get_node_or_null("PlayerSpawn") as Node3D
	if spawn != null:
		worlds.worlds[key]["spawn"] = replacement.transform * spawn.position
	if key == "cloud" and is_instance_valid(worlds.boat_node):
		worlds.boat_pos = Vector2(worlds.boat_node.position.x, worlds.boat_node.position.z)
		worlds.airship_center = worlds.airship_node.position
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
