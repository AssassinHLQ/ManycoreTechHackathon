extends SceneTree
# 探针：细化找尾部发动机喷口的**横向分布**（几个喷口、各在什么 x）。
# 用法：godot --headless --path . --script res://tests/probe_ship_nozzles.gd

func _initialize() -> void:
	call_deferred("_run")


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
	var size := mx - mn
	print("size=(%.4f, %.4f, %.4f)" % [size.x, size.y, size.z])

	# 只看最尾部 3%（喷口所在的平面）
	var z_cut: float = mx.z - size.z * 0.03
	print("尾部 3%% 切片（z >= %.4f）" % z_cut)
	var hist := {}
	var ys: Array = []
	for v in verts:
		if v.z >= z_cut:
			var key: int = int(round(v.x / (size.x / 24.0)))
			hist[key] = hist.get(key, 0) + 1
			ys.append(v.y)
	var keys: Array = hist.keys()
	keys.sort()
	print("沿 X 的直方图（每格 = 翼展/24 = %.4f m）：" % (size.x / 24.0))
	for k in keys:
		var bar := ""
		for i in range(mini(int(hist[k]), 40)):
			bar += "#"
		print("  x=%+.4f  n=%-4d %s" % [float(k) * size.x / 24.0, hist[k], bar])

	# 按「空档」分段，找出独立的喷口簇
	print("\n=== 按空档切分（连续 ≥2 格为空才算断开）===")
	var clusters: Array = []
	var cur: Array = []
	var gap := 0
	for k in keys:
		if hist[k] > 0:
			if gap >= 2 and not cur.is_empty():
				clusters.append(cur)
				cur = []
			cur.append(k)
			gap = 0
		else:
			gap += 1
	if not cur.is_empty():
		clusters.append(cur)
	for i in range(clusters.size()):
		var c: Array = clusters[i]
		var lo: float = float(c[0]) * size.x / 24.0
		var hi: float = float(c[c.size() - 1]) * size.x / 24.0
		var total := 0
		for k in c:
			total += hist[k]
		print("  簇%d: x ∈ [%+.4f, %+.4f]  中心 %+.4f  点数 %d" % [
			i + 1, lo, hi, (lo + hi) * 0.5, total])
	quit(0)
