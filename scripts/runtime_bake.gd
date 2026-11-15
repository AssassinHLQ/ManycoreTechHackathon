extends RefCounted
## Export-time snapshots of static generated geometry, with live gameplay references.
const DIRECTORY := "res://assets/runtime_bakes/"
const VERSION := 4
static var _saved_geometry: Dictionary = {}
static var _prepared_scenes: Dictionary = {}


## Deserialize the next planet on a worker while the current world keeps rendering.
## Keep a reference until load_generated consumes it, so load() cannot reload it.
static func prepare_generated(tree: SceneTree, key: String) -> void:
	if OS.has_feature("web") or "--rebake-runtime" in OS.get_cmdline_user_args():
		return
	var path := DIRECTORY + key + ".scn"
	if _prepared_scenes.has(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		return
	var status := ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_prepared_scenes[path] = ResourceLoader.load_threaded_get(path)
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		ResourceLoader.load_threaded_get(path)


static func _save_geometry(parent: Node, key: String) -> Error:
	for child in parent.get_children():
		var geometry: Resource
		if child is MultiMeshInstance3D and child.multimesh != null:
			geometry = child.multimesh.mesh
		elif child is CollisionShape3D:
			geometry = child.shape
		if geometry != null and not _saved_geometry.has(geometry.get_instance_id()):
			_saved_geometry[geometry.get_instance_id()] = true
			# Keep shared prop meshes/shapes external instead of embedding a copy
			# into every planet snapshot. Terrain meshes already have their own file.
			if not geometry.resource_path.begins_with(DIRECTORY):
				var path := DIRECTORY + "geometry_%s_%d.res" % [key, _saved_geometry.size()]
				var error := ResourceSaver.save(geometry, path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH)
				if error != OK:
					return error
				geometry.take_over_path(path)
		var error := _save_geometry(child, key)
		if error != OK:
			return error
	return OK


static func _encode(value, root: Node):
	if value is Node:
		return {"$node": String(root.get_path_to(value))}
	if value is Array:
		var result := []
		for item in value:
			result.append(_encode(item, root))
		return result
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _encode(value[key], root)
		return result
	return value


static func _decode(value, content: Node, target: Node):
	if value is Dictionary:
		if value.has("$node"):
			return target if value["$node"] == "." else content.get_node(NodePath(value["$node"]))
		var result := {}
		for key in value:
			result[key] = _decode(value[key], content, target)
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(_decode(item, content, target))
		return result
	return value


static func _own(parent: Node, root: Node) -> void:
	for child in parent.get_children():
		child.owner = root
		for group in child.get_groups():
			if not String(group).begins_with("_"):
				child.add_to_group(group, true)
		if child.scene_file_path.is_empty():
			_own(child, root)


static func _unown(parent: Node, root: Node) -> void:
	for child in parent.get_children():
		if child.owner == root:
			child.owner = null
		_unown(child, root)


static func save_generated(target: Node3D, key: String, source_paths: Array, signature := {}) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var bindings := {}
	for property in target.get_script().get_script_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or property.name in ["game", "orbit_planet", "orbit_ready", "_orbit_time", "_time", "_surface_bake",
				"_prop_mesh_cache", "_prop_cache_order", "_prop_in_use", "_prop_shape_cache", "_prop_tint_material_cache"]:
			continue
		var value = target.get(property.name)
		if value is Object and not value is Node and not value is Resource:
			continue
		bindings[property.name] = _encode(value, target)
	var hashes := {}
	for path in source_paths:
		hashes[path] = FileAccess.get_md5(path)
	var content := Node3D.new()
	content.name = "Content"
	# Only the nodes created by _ready belong to this snapshot. The live
	# world has since added its player, ship, signals and quest nodes.
	for child in target.get_meta("bake_children", []):
		if not is_instance_valid(child) or child.get_parent() != target:
			continue
		target.remove_child(child)
		content.add_child(child)
	var geometry_error := _save_geometry(content, key)
	if geometry_error != OK:
		return geometry_error
	_own(content, content)
	content.set_meta("bake_version", VERSION)
	content.set_meta("source_hashes", hashes)
	content.set_meta("bindings", bindings)
	content.set_meta("signature", signature)
	var model_path: String = signature.get("model", "")
	if not model_path.is_empty():
		content.set_meta("model_time", FileAccess.get_modified_time(model_path))
	var packed := PackedScene.new()
	var error := packed.pack(content)
	if error == OK:
		error = ResourceSaver.save(packed, DIRECTORY + key + ".scn", ResourceSaver.FLAG_COMPRESS)
	_unown(content, content)
	for child in content.get_children():
		content.remove_child(child)
		target.add_child(child)
	content.free()
	return error


static func load_generated(target: Node3D, key: String, signature := {}) -> bool:
	var path := DIRECTORY + key + ".scn"
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene
	if _prepared_scenes.has(path):
		packed = _prepared_scenes[path]
		_prepared_scenes.erase(path)
	else:
		packed = load(path) as PackedScene
	if packed == null:
		return false
	var content := packed.instantiate() as Node3D
	if content.get_meta("bake_version", 0) != VERSION or content.get_meta("signature", {}) != signature:
		content.free()
		return false
	for source in content.get_meta("source_hashes", {}):
		# Codec changes are tracked by VERSION, geometry recipes by hashes.
		if source == "res://scripts/runtime_bake.gd":
			continue
		# Raw scripts are remapped in release exports; source checks are for the editor.
		if FileAccess.file_exists(source) and FileAccess.get_md5(source) != content.get_meta("source_hashes")[source]:
			content.free()
			return false
	var model_path: String = signature.get("model", "")
	if not model_path.is_empty() and FileAccess.file_exists(model_path) and FileAccess.get_modified_time(model_path) != int(content.get_meta("model_time", 0)):
		content.free()
		return false
	var bindings: Dictionary = _decode(content.get_meta("bindings"), content, target)
	var constants: Dictionary = target.get_script().get_script_constant_map()
	var ground_cover: Array = constants.get("GROUND_COVER_PROPS", [])
	# Copy MultiMesh buffers explicitly: local-to-scene duplication sets the
	# buffer before its instance count on this engine version.
	for node in content.find_children("*", "MultiMeshInstance3D", true, false):
		# Older snapshots omitted non-persistent runtime groups.
		if String(node.name).trim_prefix("Prop_") in ground_cover:
			node.add_to_group("ground_scatter")
		var source: MultiMesh = node.multimesh
		if source == null:
			continue
		var copy := MultiMesh.new()
		copy.transform_format = source.transform_format
		copy.use_colors = source.use_colors
		copy.use_custom_data = source.use_custom_data
		copy.mesh = source.mesh
		copy.instance_count = source.instance_count
		var transforms: Array = node.get_meta("runtime_transforms", [])
		var colors: PackedColorArray = node.get_meta("runtime_colors", PackedColorArray())
		if transforms.size() == source.instance_count and colors.size() == source.instance_count:
			for i in range(source.instance_count):
				copy.set_instance_transform(i, transforms[i])
				if copy.use_colors:
					copy.set_instance_color(i, colors[i])
		elif not source.buffer.is_empty():
			copy.buffer = source.buffer
		copy.visible_instance_count = source.visible_instance_count
		node.multimesh = copy
	# The station beacon is animated. Keep its material connected to the
	# visible meshes while isolating it from other scene instances.
	var live: Array = bindings.get("merge_live_materials", [])
	for i in range(live.size()):
		var material: Material = live[i]
		if material == null:
			continue
		var isolated := material.duplicate() as Material
		for field in bindings:
			if bindings[field] is Material and bindings[field] == material:
				bindings[field] = isolated
		for node in content.find_children("*", "MeshInstance3D", true, false):
			if node.material_override == material:
				node.material_override = isolated
			elif node.mesh != null:
				for surface in range(node.mesh.get_surface_count()):
					if node.mesh.surface_get_material(surface) == material:
						node.set_surface_override_material(surface, isolated)
		live[i] = isolated
	_unown(content, content)
	for child in content.get_children():
		content.remove_child(child)
		target.add_child(child)
	for field in bindings:
		if target.get(field) is Array and bindings[field] is Array:
			target.get(field).assign(bindings[field])
		else:
			target.set(field, bindings[field])
	content.free()
	target.set_meta("runtime_baked", key)
	return true
