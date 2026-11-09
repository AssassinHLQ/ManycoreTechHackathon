extends SceneTree
# 探针：找飞船尾部（+Z）的发动机喷口位置，用来摆尾焰。
# 用法：godot --headless --path . --script res://tests/probe_ship_engines.gd

func _initialize() -> void:
	call_deferred("_run")


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for s in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(s)
				var varr: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in varr:
					out.append(v)
	for c in node.get_children():
		_collect(c, out)


func _report(label: String, arr: Array, size: Vector3) -> void:
	if arr.is_empty():
		print("  %s: 空" % label)
		return
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var zmax := -1e18
	for v in arr:
		sx += v.x
		sy += v.y
		sz += v.z
		if v.z > zmax:
			zmax = v.z
	var n := arr.size()
	print("  %s: %d 点  中心=(%.4f, %.4f, %.4f)  最深z=%.4f" % [
		label, n, sx / n, sy / n, sz / n, zmax])


func _run() -> void:
	var packed: PackedScene = load("res://assets/models/ship-fighter/model.glb")
	if packed == null:
		print("加载失败")
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	var verts: Array = []
	_collect(model, verts)
	print("顶点数 ", verts.size())
	var mn := Vector3(1e18, 1e18, 1e18)
	var mx := Vector3(-1e18, -1e18, -1e18)
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	var size := mx - mn
	print("包围盒 position=%s size=%s" % [mn, size])
	print("轴语义: 翼展X=%.4f 机高Y=%.4f 机长Z=%.4f" % [size.x, size.y, size.z])

	var z_cut := mx.z - size.z * 0.08
	var rear: Array = []
	for v in verts:
		if v.z >= z_cut:
			rear.append(v)
	print("\n尾部切片（+Z 端 8%%）顶点数 %d" % rear.size())
	var left: Array = []
	var mid: Array = []
	var right: Array = []
	for v in rear:
		if v.x < -size.x * 0.10:
			left.append(v)
		elif v.x > size.x * 0.10:
			right.append(v)
		else:
			mid.append(v)
	_report("左簇", left, size)
	_report("中簇", mid, size)
	_report("右簇", right, size)

	print("\n=== 候选机长对应的实际尺寸（玩家身高 1.65 m）===")
	for L in [6.5, 10.0, 12.0, 14.0, 16.0, 18.0]:
		var f: float = L / size.z
		print("  机长 %5.1f m → 翼展 %5.2f m  机高 %5.2f m" % [L, size.x * f, size.y * f])
	quit(0)
