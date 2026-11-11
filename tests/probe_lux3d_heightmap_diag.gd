extends SceneTree
# 探针：诊断 Lux3D 高度表为什么偏低/有尖刺。
#
# 现象：高度范围 367.9..1650.4、平均 1022.3，而行星半径是 1200。
# 平均比半径低 178 米 → 整颗星球被"压扁"了。
#
# 本探针直接对 GLB 做**顶点半径分布分析**，看：
#   1. r 的直方图（是否双峰 = 有内外两层壳）
#   2. 每格 max r 的分布 vs 全模型 r 分布
#   3. 按方向分格后，有几个格子的 max r 明显落在内层
#
#   godot --headless --path . --script res://tests/probe_lux3d_heightmap_diag.gd

const GLB := "res://assets/models/qinglan-planet/model.glb"
const LAT_BINS := 96
const LON_BINS := 192


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(GLB)
	var inst := packed.instantiate() as Node3D
	root.add_child(inst)
	await process_frame

	var verts := PackedVector3Array()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var n := mi as MeshInstance3D
		if n.mesh == null:
			continue
		var rel: Transform3D = inst.global_transform.affine_inverse() * n.global_transform
		for s in range(n.mesh.get_surface_count()):
			var arr: Array = n.mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vv:
				verts.append(rel * v)

	# ── 1. r 的直方图 ──
	var rs: Array[float] = []
	for v in verts:
		rs.append(v.length())
	rs.sort()
	print("=== 顶点半径分布（共 %d 个）===" % rs.size())
	print("  最小 %.4f / 1%% %.4f / 25%% %.4f / 中位 %.4f / 75%% %.4f / 99%% %.4f / 最大 %.4f" % [
		rs[0],
		rs[int(rs.size() * 0.01)],
		rs[int(rs.size() * 0.25)],
		rs[rs.size() / 2],
		rs[int(rs.size() * 0.75)],
		rs[int(rs.size() * 0.99)],
		rs[rs.size() - 1]])

	# 直方图 20 桶
	var lo: float = rs[0]
	var hi: float = rs[rs.size() - 1]
	var buckets := PackedInt32Array()
	buckets.resize(20)
	buckets.fill(0)
	for r in rs:
		var b: int = clampi(int((r - lo) / maxf(hi - lo, 1e-9) * 19.999), 0, 19)
		buckets[b] += 1
	print("  直方图（每桶宽度 %.4f）：" % ((hi - lo) / 20.0))
	for i in range(20):
		var pct := 100.0 * float(buckets[i]) / float(rs.size())
		var bar := ""
		for _k in range(int(pct / 1.5)):
			bar += "#"
		print("    %.3f..%.3f  %6.2f%%  %s" % [
			lo + (hi - lo) * i / 20.0, lo + (hi - lo) * (i + 1) / 20.0, pct, bar])

	# ── 2. 每格 max r ──
	var cells := LAT_BINS * LON_BINS
	var mx := PackedFloat32Array()
	mx.resize(cells)
	mx.fill(-1.0)
	var counts := PackedInt32Array()
	counts.resize(cells)
	counts.fill(0)
	for v in verts:
		var r: float = v.length()
		if r < 1e-6:
			continue
		var d: Vector3 = v / r
		var li := clampi(int((asin(clampf(d.y, -1.0, 1.0)) / PI + 0.5) * LAT_BINS), 0, LAT_BINS - 1)
		var oi := clampi(int((atan2(d.z, d.x) / TAU + 0.5) * LON_BINS), 0, LON_BINS - 1)
		var k := li * LON_BINS + oi
		if r > mx[k]:
			mx[k] = r
		counts[k] += 1

	var filled := 0
	var mxvals: Array[float] = []
	for i in range(cells):
		if mx[i] > 0.0:
			filled += 1
			mxvals.append(mx[i])
	mxvals.sort()
	print("")
	print("=== 每格 max r（有顶点的格子 %d / %d）===" % [filled, cells])
	print("  最小 %.4f / 25%% %.4f / 中位 %.4f / 75%% %.4f / 最大 %.4f" % [
		mxvals[0],
		mxvals[int(mxvals.size() * 0.25)],
		mxvals[mxvals.size() / 2],
		mxvals[int(mxvals.size() * 0.75)],
		mxvals[mxvals.size() - 1]])

	# ── 3. 每格顶点数分布（稀疏格容易取错层）──
	var sparse := 0
	var dense := 0
	for i in range(cells):
		if counts[i] <= 0:
			continue
		if counts[i] < 5:
			sparse += 1
		else:
			dense += 1
	print("")
	print("=== 格子稀疏度 ===")
	print("  顶点数 < 5 的格子 = %d（占已填充的 %.1f%%）" % [
		sparse, 100.0 * float(sparse) / maxf(float(filled), 1.0)])
	print("  顶点数 >= 5 的格子 = %d" % dense)
	print("")
	print("结论提示：")
	print("  · 若直方图呈**双峰**，说明模型有内外两层壳，max 应能过滤内层")
	print("  · 若稀疏格占比高，说明填充率不足，扩散补洞会引入错误值")
	print("  · 若 max r 的中位数明显小于 99% 分位，说明多数方向取到了内层表面")

	inst.free()
	quit(0)
