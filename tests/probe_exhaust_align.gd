extends SceneTree
# 探针：核对尾焰（holder 局部坐标）与模型实际机尾的相对位置。
# 用法：godot --headless --path . --script res://tests/probe_exhaust_align.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/models/ship-fighter/model.glb")
	var model := packed.instantiate() as Node3D
	var verts: Array = []
	_collect(model, verts)
	var mn := Vector3(1e18, 1e18, 1e18)
	var mx := Vector3(-1e18, -1e18, -1e18)
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	print("模型包围盒 position=%s size=%s" % [mn, mx - mn])
	print("机尾平面 z = %.4f" % mx.z)
	print("")

	# 尾部 3% 切片里，按 y 分层看喷口高度
	var z_cut: float = mx.z - (mx.z - mn.z) * 0.03
	print("尾部切片 z>=%.4f 的 y 分布：" % z_cut)
	var hist := {}
	for v in verts:
		if v.z >= z_cut:
			var k: int = int(round(v.y / ((mx.y - mn.y) / 12.0)))
			hist[k] = hist.get(k, 0) + 1
	var keys: Array = hist.keys()
	keys.sort()
	for k in keys:
		var y: float = float(k) * (mx.y - mn.y) / 12.0
		var bar := ""
		for i in range(mini(int(hist[k]), 50)):
			bar += "#"
		print("  y=%+.4f  n=%-4d %s" % [y, hist[k], bar])
	print("")
	print("当前 _build_external_exhaust 用的 nozzle_y = bounds.y + size.y*0.37")
	print("                                      = %.4f" % (mn.y + (mx.y - mn.y) * 0.37))
	quit(0)


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for s in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(s)
				for v in arrays[Mesh.ARRAY_VERTEX]:
					out.append(v)
	for c in node.get_children():
		_collect(c, out)
