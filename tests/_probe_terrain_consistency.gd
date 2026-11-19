extends SceneTree
# 量三套地形表示之间的偏差：
#   ① terrain_height(dir)（解析高度表，道具摆放用它）
#   ② 地形碰撞球面（射线实际打到的半径）
#   ③ Lux3D 可视网格的外层半径（视觉表面）
# 用法：godot --headless --path . --script res://tests/_probe_terrain_consistency.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://probe_terrain_consistency.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	for i in range(30):
		await physics_frame
	game.home._ensure_terrain_collision()
	for i in range(10):
		await physics_frame

	var home = game.home
	# ① 解析
	# ② 碰撞：逐方向射线
	var space: PhysicsDirectSpaceState3D = home.get_world_3d().direct_space_state
	# 排除道具/飞船碰撞
	var excl: Array = []
	for b in home.find_children("PropCollision_*", "StaticBody3D", true, false):
		excl.append((b as CollisionObject3D).get_rid())
	for b in home.find_children("ShipCollision", "StaticBody3D", true, false):
		excl.append((b as CollisionObject3D).get_rid())

	# ③ 可视网格：按 192×384 格子取最大半径（和引擎烘焙时同法）
	var lux = home.get_node_or_null("Lux3dSurface")
	var LAT := 192
	var LON := 384
	var grid := PackedFloat32Array()
	grid.resize(LAT * LON)
	grid.fill(-1.0)
	var inv: Transform3D = home.global_transform.affine_inverse()
	var vcount := 0
	if lux != null:
		for mi in lux.find_children("*", "MeshInstance3D", true, false):
			var node := mi as MeshInstance3D
			if node.mesh == null:
				continue
			var rel: Transform3D = inv * node.global_transform
			for s in range(node.mesh.get_surface_count()):
				var arrays: Array = node.mesh.surface_get_arrays(s)
				var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in vv:
					var w: Vector3 = rel * v
					var r: float = w.length()
					if r < 0.001:
						continue
					vcount += 1
					var d: Vector3 = w / r
					var li := clampi(int((asin(clampf(d.y, -1.0, 1.0)) / PI + 0.5) * LAT), 0, LAT - 1)
					var oi := clampi(int((atan2(d.z, d.x) / TAU + 0.5) * LON), 0, LON - 1)
					var k := li * LON + oi
					if r > grid[k]:
						grid[k] = r

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	var n := 0
	var stat_coll := 0.0    # |碰撞 - 解析|
	var stat_vis := 0.0     # |可视 - 解析|
	var stat_vc := 0.0      # |可视 - 碰撞|
	var max_coll := 0.0
	var max_vis := 0.0
	var max_vc := 0.0
	for i in range(300):
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1),
			rng.randf_range(-1, 1))
		if d.length_squared() < 0.001:
			continue
		d = d.normalized()
		var analytic: float = home.terrain_height(d)
		var base: Vector3 = home.global_position
		var q := PhysicsRayQueryParameters3D.create(base + d * 2600.0, base + d * 1200.0)
		q.exclude = excl
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		var coll_r: float = (hit["position"] - home.global_position).length()
		# 可视半径：最近格子
		var li := clampi(int((asin(clampf(d.y, -1.0, 1.0)) / PI + 0.5) * LAT), 0, LAT - 1)
		var oi := clampi(int((atan2(d.z, d.x) / TAU + 0.5) * LON), 0, LON - 1)
		var vis_r: float = grid[li * LON + oi]
		if vis_r < 0.0:
			continue
		n += 1
		var dc: float = absf(coll_r - analytic)
		var dv: float = absf(vis_r - analytic)
		var dvc: float = absf(vis_r - coll_r)
		stat_coll += dc
		stat_vis += dv
		stat_vc += dvc
		max_coll = maxf(max_coll, dc)
		max_vis = maxf(max_vis, dv)
		max_vc = maxf(max_vc, dvc)

	print("=== 地形三表示一致性（母星，%d 方向）===" % n)
	print("  可视顶点读取 %d 个" % vcount)
	print("  |碰撞 - 解析|  平均 %.2f m  最大 %.2f m" % [stat_coll / n, max_coll])
	print("  |可视 - 解析|  平均 %.2f m  最大 %.2f m" % [stat_vis / n, max_vis])
	print("  |可视 - 碰撞|  平均 %.2f m  最大 %.2f m" % [stat_vc / n, max_vc])

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
