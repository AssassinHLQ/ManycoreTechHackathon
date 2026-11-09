extends SceneTree
# 探针：验证 Lux3D 生成的青岚星球在 Godot 里能正确加载。
# 用法：godot --headless --path . --script res://tests/probe_qinglan_planet.gd

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


func _run() -> void:
	var packed: PackedScene = load("res://assets/models/qinglan-planet/model.glb")
	if packed == null:
		print("FAIL: 模型加载失败")
		quit(1)
		return
	var node := packed.instantiate() as Node3D
	var meshes := 0
	var tris := 0
	var materials := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		tris += _tris((child as MeshInstance3D).mesh)
		var mat := (child as MeshInstance3D).material_override
		if mat != null:
			materials += 1
	print("网格节点 = %d" % meshes)
	print("三角面   = %d" % tris)
	print("材质     = %d" % materials)

	# 包围盒
	var mn := Vector3(1e18, 1e18, 1e18)
	var mx := Vector3(-1e18, -1e18, -1e18)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (child as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var varr: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in varr:
				mn = mn.min(v)
				mx = mx.max(v)
	print("包围盒 size = %s" % (mx - mn))
	print("=> 球半径 ≈ %.3f（原始 GLB 是 0.5，需要放大到青岚星的 400 m）" % ((mx - mn).length() / 2.0))
	print("PROBE DONE")
	quit(0)
