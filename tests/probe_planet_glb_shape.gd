extends SceneTree
# 探针：量 Lux3D 生成的星球 GLB 的几何，判断它能不能当「可着陆星球」用。
#
# 背景：游戏里所有地面交互（着陆、行走、撞击、建筑摆放、洞穴裁剪）都走
#   planet.gd 的 _raw_terrain_height(direction) -> float
# 那是个**按方向取高度**的函数，等价于「星球是星形的」（从球心任一方向
# 只穿出一次）。Lux3D 给的是静态网格，要有这个性质才能接。
#
# 本探针量四件事：
#   1. 顶点数 / 三角面数 / 包围盒
#   2. 是否星形：统计每个方向上 max(r)/min(r) 的比值
#      —— 全为 1 附近 = 干净的星形体；出现大比值 = 有凹槽/悬垂，采样会错
#   3. 离心率：最远/最近顶点距离之比（判断是不是接近球形）
#   4. 表面半径的分布（是否平滑，还是有尖锐突起）
#
#   godot --headless --path . --script res://tests/probe_planet_glb_shape.gd

const GLB_DEFAULT := "res://assets/models/qinglan-planet/model.glb"
## 方向采样粒度：纬度分多少格（经度是它的 2 倍）
const LAT_BINS := 64
const LON_BINS := 128


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# 允许用命令行覆盖模型路径：
	#   --script res://tests/probe_planet_glb_shape.gd -- res://assets/models/xxx/model.glb
	var args := OS.get_cmdline_user_args()
	var glb: String = args[0] if args.size() > 0 else GLB_DEFAULT
	print("模型: %s" % glb)
	var packed: PackedScene = load(glb)
	if packed == null:
		print("FAIL: 加载失败 %s" % glb)
		quit(1)
		return
	var root_node := packed.instantiate() as Node3D

	# ── 收集所有顶点到模型根的局部空间 ──
	var all: PackedVector3Array = PackedVector3Array()
	var tri_total := 0
	var mesh_count := 0
	var root_inv := root_node.global_transform.affine_inverse()
	for mi in root_node.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		mesh_count += 1
		# 这个 mesh 相对模型根的变换
		var rel: Transform3D = root_inv * node.global_transform
		for s in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tri_total += (idx as PackedInt32Array).size() / 3
			else:
				tri_total += verts.size() / 3
			for v in verts:
				all.append(rel * v)

	print("=== 几何 ===")
	print("  网格节点 = %d" % mesh_count)
	print("  顶点总数 = %d" % all.size())
	print("  三角面   = %d" % tri_total)
	if all.is_empty():
		print("FAIL: 没有顶点")
		quit(1)
		return

	# ── 包围盒 / 离心率 ──
	var mn := Vector3(1e18, 1e18, 1e18)
	var mx := Vector3(-1e18, -1e18, -1e18)
	var r_min := INF
	var r_max := 0.0
	for v in all:
		mn = mn.min(v)
		mx = mx.max(v)
		var r: float = v.length()
		r_min = minf(r_min, r)
		r_max = maxf(r_max, r)
	print("")
	print("=== 球形度 ===")
	print("  包围盒 size = %s" % (mx - mn))
	print("  最近顶点 r = %.5f / 最远顶点 r = %.5f" % [r_min, r_max])
	print("  半径比 = %.3f（1.0 = 完美球）" % (r_max / maxf(r_min, 1e-9)))

	# ── 星形性：按方向分格，比较同格内 max(r)/min(r) ──
	# 用「顶点归一化方向」分格；同格里如果有几个顶点 r 差很多，
	# 说明这个方向上表面有折叠（凹槽、悬垂、内部壳层）。
	print("")
	print("=== 星形性（每个方向格内的 r 极差）===")
	var bins_max := {}
	var bins_min := {}
	for v in all:
		var r: float = v.length()
		if r < 1e-6:
			continue
		var d: Vector3 = v / r
		var lat: float = asin(clampf(d.y, -1.0, 1.0))       # -pi/2 .. pi/2
		var lon: float = atan2(d.z, d.x)                     # -pi .. pi
		var li: int = clampi(int((lat / PI + 0.5) * LAT_BINS), 0, LAT_BINS - 1)
		var oi: int = clampi(int((lon / TAU + 0.5) * LON_BINS), 0, LON_BINS - 1)
		var key: int = li * LON_BINS + oi
		if not bins_max.has(key):
			bins_max[key] = r
			bins_min[key] = r
		else:
			bins_max[key] = maxf(bins_max[key], r)
			bins_min[key] = minf(bins_min[key], r)

	var filled := bins_max.size()
	var total_bins := LAT_BINS * LON_BINS
	var worst_ratio := 1.0
	var bad_bins := 0
	var ratios: Array[float] = []
	for key in bins_max:
		var ratio: float = bins_max[key] / maxf(bins_min[key], 1e-9)
		ratios.append(ratio)
		worst_ratio = maxf(worst_ratio, ratio)
		# 同格里 r 差超过 15% 视为「这个方向有折叠」
		if ratio > 1.15:
			bad_bins += 1
	ratios.sort()
	var median := ratios[ratios.size() / 2]
	var p99 := ratios[int(float(ratios.size() - 1) * 0.99)]
	print("  有顶点的方向格 = %d / %d（填充率 %.0f%%）" % [
		filled, total_bins, 100.0 * float(filled) / float(total_bins)])
	print("  同格 r 极差：中位数 %.4f / 99分位 %.4f / 最差 %.4f" % [
		median, p99, worst_ratio])
	print("  折叠格（极差 > 1.15）= %d（%.1f%%）" % [
		bad_bins, 100.0 * float(bad_bins) / maxf(float(filled), 1.0)])

	print("")
	print("=== 判定 ===")
	if filled < total_bins * 0.5:
		print("  ✗ 方向格填充率太低 —— 采样会大面积空洞，不适合做可着陆表面")
	elif bad_bins > filled * 0.10:
		print("  ✗ 折叠格太多（>10%%）—— 有凹槽/悬垂，'按方向取高度'会取错面")
	else:
		print("  ✓ 基本是星形体，可以做「按方向取高度」的采样")

	root_node.free()
	quit(0)
