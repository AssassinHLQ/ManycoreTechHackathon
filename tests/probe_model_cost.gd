extends SceneTree
# 建模开销探针：统计飞船 / 场景节点数，用于对比细化前后的 draw call 压力。
# 用法：godot --headless --path . --script res://tests/probe_model_cost.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _tris(node: Node) -> int:
	# 一个节点的所有网格三角形数。get_faces() 返回的是三角化后的顶点表，
	# 所以对多面体 / 已三角化的网格都成立。
	# 注意：Label3D 也是 GeometryInstance3D，但它没有 mesh —— 必须用 MeshInstance3D 判。
	var total := 0
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				if arrays.is_empty():
					continue
				var indices: Variant = arrays[Mesh.ARRAY_INDEX]
				if indices != null and (indices as PackedInt32Array).size() > 0:
					total += (indices as PackedInt32Array).size() / 3
				else:
					var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
					if verts != null:
						total += (verts as PackedVector3Array).size() / 3
	return total


func _report(label: String, root_node: Node) -> void:
	var nodes := 0
	var geo := 0
	var tris := 0
	for node in root_node.find_children("*", "", true, false):
		nodes += 1
		if node is MeshInstance3D:
			geo += 1
			tris += _tris(node)
	print("%-10s nodes=%-7d mesh=%-6d triangles=%d" % [label, nodes, geo, tris])


func _run() -> void:
	var save := "user://starward_probe_cost.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	_report("SHIP", game.ship)
	if game.station != null:
		_report("STATION", game.station)
	if game.sun_mesh != null:
		print("SUN        triangles=%d（半径 %.0f）" % [_tris(game.sun_mesh), game.sun_radius])
	if not game.planets.is_empty():
		var planet_tris := 0
		for planet in game.planets:
			planet_tris += _tris(planet)
		print("PLANETS    %d 颗，合计 triangles=%d，单颗均值 %d" % [
			game.planets.size(), planet_tris, planet_tris / max(game.planets.size(), 1)])
	_report("WORLD", game)
	# 外部导入的模型单独报一次，好和上面几项对比
	var models := 0
	var model_tris := 0
	for node in game.find_children("*", "", true, false):
		if node is GeometryInstance3D and (node as GeometryInstance3D).mesh != null:
			var path: String = (node as GeometryInstance3D).mesh.resource_path
			if path.begins_with("res://assets/models/"):
				models += 1
				model_tris += _tris(node)
	print("导入模型   %d 个节点，合计 triangles=%d" % [models, model_tris])

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
