extends SceneTree
# 探针：找飞船模型的**座舱位置**（座舱玻璃罩所在处），用来摆座舱相机。
# 用法：godot --headless --path . --script res://tests/probe_ship_cockpit.gd
#
# 为什么需要它：
#   修正朝向（机头从 -X 改成 -Z）之后，旧的座舱相机位置（机尾 22%、机高 78%）
#   完全对不上了 —— 镜头是从机尾上方斜看机腹，机头歪在画面角落。
#   座舱相机必须落在**机头一侧**、座舱玻璃罩的高度上。
#
# 判定座舱的办法：座舱玻璃是模型里唯一一块**朝上的深色半透明罩子**。
#   本探针从 +Y 往下看，找「机头方向那一端、朝上凸起、颜色最深」的区域。
#   更稳的判据是**局部高度场**：机头那端有个座舱隆起。
#
# 输出：沿机长轴（Z）分若干段，报告每段的最大高度与顶面顶点，
#   便于人工确认座舱所在的那一段。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/models/ship-fighter/model.glb")
	if packed == null:
		print("加载失败")
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "Holder"
	model.rotation = Vector3.ZERO
	holder.add_child(model)
	root.add_child(holder)

	# 收集世界顶点（holder 局部坐标）
	var verts: Array[Vector3] = []
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var mesh: Mesh = mi.mesh
			for surface in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var varr: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in varr:
					verts.append(v)
		for child in node.get_children():
			stack.append(child)

	if verts.is_empty():
		print("没有顶点")
		quit(1)
		return

	var mn := Vector3(1e18, 1e18, 1e18)
	var mx := Vector3(-1e18, -1e18, -1e18)
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	var size := mx - mn
	print("包围盒 position=%s size=%s" % [mn, size])

	# 沿机长轴（Z）切 20 段，报告每段：顶面最高点、该段顶点的平均高度
	const SEG := 20
	print("\n=== 沿机长轴分段（Z 从 -1=机头 到 +1=机尾）===")
	print("%6s %10s %10s %10s" % ["Z段", "区间", "最高Y", "顶面均值Y"])
	var seg_data := []
	for s in SEG:
		var z0 := mn.z + size.z * (float(s) / SEG)
		var z1 := mn.z + size.z * (float(s + 1) / SEG)
		var top := -1e18
		var sum := 0.0
		var n := 0
		for v in verts:
			if v.z >= z0 and v.z < z1:
				top = maxf(top, v.y)
				sum += v.y
				n += 1
		if n == 0:
			continue
		seg_data.append({"z": (z0 + z1) * 0.5, "top": top, "avg": sum / n, "n": n})
		print("%6d %10s %10.3f %10.3f" % [s,
			"%.2f~%.2f" % [z0, z1], top, sum / n])

	# 机头那端（Z 最小）应该最尖；找出局部隆起最高的段 —— 那多半是座舱
	print("\n=== 机头侧（Z < 中心）各段顶面高度排序 ===")
	var head_segs := []
	for d in seg_data:
		if d["z"] < mn.z + size.z * 0.5:
			head_segs.append(d)
	head_segs.sort_custom(func(a, b): return a["top"] > b["top"])
	for i in range(min(4, head_segs.size())):
		print("  #%d  Z=%.3f  顶面最高=%.3f  均值=%.3f" % [
			i + 1, head_segs[i]["z"], head_segs[i]["top"], head_segs[i]["avg"]])

	quit(0)
