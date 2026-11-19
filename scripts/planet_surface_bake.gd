extends RefCounted
## Preserve the exact terrain and collision geometry; calculate it before export.
const DIRECTORY := "res://assets/runtime_bakes/streamed/"
const VERSION := 2


static func _signature(planet: Node3D) -> Dictionary:
	return {"version": VERSION, "model": planet.lux_model_path, "kind": planet.kind,
		"radius": planet.radius, "reference": planet.terrain_reference_radius,
		"pad": planet.site_pad_radius, "site": planet.site_direction,
		"cave": planet.cave_enabled, "cave_direction": planet.cave_direction,
		"cave_radius": planet.cave_mouth_radius, "prop_scale": planet.prop_scale,
		"collision_resolution": Vector2i(256, 128)}


static func load_surface(planet: Node3D) -> bool:
	var path: String = DIRECTORY + "planet_" + planet.planet_id + ".res"
	if not ResourceLoader.exists(path):
		return false
	var data := load(path) as Resource
	if data == null or data.get_meta("signature", {}) != _signature(planet):
		return false
	if FileAccess.file_exists(planet.lux_model_path) and FileAccess.get_modified_time(planet.lux_model_path) != int(data.get_meta("model_time", 0)):
		return false
	for source in data.get_meta("source_hashes", {}):
		if FileAccess.file_exists(source) and FileAccess.get_md5(source) != data.get_meta("source_hashes")[source]:
			return false
	planet._surface_bake = data
	planet._baked_collision_path = data.get_meta("collision_path")
	planet._lux_height_map = data.get_meta("height_map")
	planet._lux_height_ready = true
	planet._lux_pad_height = data.get_meta("pad_height")
	planet.cave_hole_angle = data.get_meta("cave_angle")
	var root := Node3D.new()
	root.name = "Lux3dSurface"
	root.scale = data.get_meta("scale")
	planet._lux_root = root
	planet.add_child(root)
	for entry in data.get_meta("meshes"):
		var node := MeshInstance3D.new()
		node.name = entry.name
		node.transform = entry.transform
		node.mesh = entry.mesh
		node.material_override = entry.material
		node.cast_shadow = entry.shadow
		root.add_child(node)
		if planet.surface == null:
			planet.surface = node
	return true


static func save_surface(planet: Node3D) -> Error:
	if planet._surface_bake != null:
		return OK
	if not planet._lux_height_ready or planet._lux_root == null:
		return ERR_UNAVAILABLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var meshes := []
	var inverse: Transform3D = planet._lux_root.global_transform.affine_inverse()
	var mesh_index := 0
	for node in planet._lux_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_path: String = DIRECTORY + "terrain_" + planet.planet_id + "_%d.res" % mesh_index
		var mesh_error := ResourceSaver.save(node.mesh, mesh_path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH)
		if mesh_error != OK:
			return mesh_error
		node.mesh.take_over_path(mesh_path)
		mesh_index += 1
		meshes.append({"name": String(node.name), "transform": inverse * node.global_transform,
			"mesh": node.mesh, "material": node.material_override, "shadow": node.cast_shadow})
	var data := Resource.new()
	data.set_meta("signature", _signature(planet))
	data.set_meta("model_time", FileAccess.get_modified_time(planet.lux_model_path))
	var hashes := {}
	for source in ["res://scripts/planet.gd", "res://scripts/planet_surface_bake.gd"]:
		hashes[source] = FileAccess.get_md5(source)
	data.set_meta("source_hashes", hashes)
	data.set_meta("height_map", planet._lux_height_map)
	data.set_meta("pad_height", planet._lux_pad_height)
	data.set_meta("cave_angle", planet.cave_hole_angle)
	data.set_meta("scale", planet._lux_root.scale)
	data.set_meta("meshes", meshes)
	planet._ensure_terrain_collision()
	var body := planet.get_node_or_null("TerrainCollision")
	if body == null:
		return ERR_CANT_CREATE
	var collision_path: String = DIRECTORY + "planet_" + planet.planet_id + "_collision.res"
	var error := ResourceSaver.save(body.get_child(0).shape, collision_path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		return error
	data.set_meta("collision_path", collision_path)
	planet._baked_collision_path = collision_path
	return ResourceSaver.save(data, DIRECTORY + "planet_" + planet.planet_id + ".res", ResourceSaver.FLAG_COMPRESS)
