extends SceneTree
# 探针：量行星的实际面数。
# 用法：godot --headless --path . --script res://tests/probe_planet_tris.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			total += (idx as PackedInt32Array).size() / 3
		else:
			var varr: Variant = arrays[Mesh.ARRAY_VERTEX]
			if varr != null:
				total += (varr as PackedVector3Array).size() / 3
	return total


func _node_tris(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			total += _tris((child as MeshInstance3D).mesh)
		total += _node_tris(child)
	return total


func _run() -> void:
	var save := "user://starward_planet_tris.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	print("=== 每颗行星 ===")
	var surface_total := 0
	var node_total := 0
	var idx := 0
	for planet in game.planets:
		idx += 1
		var surface := 0
		var meshes := 0
		for child in planet.get_children():
			if child is MeshInstance3D:
				meshes += 1
				surface += _tris((child as MeshInstance3D).mesh)
		var total := _node_tris(planet)
		surface_total += surface
		node_total += total
		print("  #%d  表面 %7d 面   全节点 %7d 面   直接子网格 %d" % [
			idx, surface, total, meshes])
	print("")
	print("行星表面合计   : %d 面" % surface_total)
	print("行星全节点合计 : %d 面" % node_total)
	print("场景总面数     : %d" % _tris_all(game))
	quit(0)


func _tris_all(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			total += _tris((child as MeshInstance3D).mesh)
		total += _tris_all(child)
	return total
