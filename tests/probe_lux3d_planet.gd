extends SceneTree
# 探针：验证 Lux3D 生成的星球真的接进了游戏（不只是能加载）。
#
# 验收标准（缺一条都算没接上）：
#   1. 表面用的是 Lux3D 模型，不是程序化球面
#   2. 高度表烘出来了，且不是一片常数
#   3. terrain_height 能查、结果在合理范围（行星半径附近的起伏）
#   4. 表面位置 surface_position 与高度表一致
#   5. 地形碰撞建得出来
#   6. 建筑平地（site_height）与高度表吻合 —— 否则观测塔会悬空
#
#   godot --headless --path . --script res://tests/probe_lux3d_planet.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_lux3d.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(6):
		await process_frame

	var planet = game.home
	print("=== 1. 表面来源 ===")
	print("  lux_model_path = %s" % planet.lux_model_path)
	print("  _lux_height_ready = %s" % str(planet._lux_height_ready))
	print("  _lux_root = %s" % ("有" if planet._lux_root != null else "无"))
	if planet._lux_root != null:
		var meshes: Array = planet._lux_root.find_children("*", "MeshInstance3D", true, false)
		print("  模型网格节点数 = %d" % meshes.size())
		print("  模型缩放 = %s" % str(planet._lux_root.scale))

	print("")
	print("=== 2. 高度表 ===")
	var map: PackedFloat32Array = planet._lux_height_map
	print("  格子数 = %d（%d 纬度 × %d 经度）" % [
		map.size(), planet.LUX_LAT_BINS, planet.LUX_LON_BINS])
	var lo := INF
	var hi := -INF
	var empties := 0
	var sum := 0.0
	for v in map:
		if v <= 0.0:
			empties += 1
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	print("  高度范围 = %.1f .. %.1f 米（行星半径 %.0f）" % [lo, hi, planet.radius])
	print("  平均值 = %.1f 米" % (sum / float(maxi(map.size(), 1))))
	print("  空洞格 = %d（补洞后应为 0）" % empties)

	print("")
	print("=== 3. terrain_height 抽样 ===")
	var r: float = float(planet.radius)
	var worst := 0.0
	var samples := 0
	for i in range(360):
		var ang: float = float(i) / 360.0 * TAU
		var dir := Vector3(cos(ang), 0.35 * sin(float(i) / 41.0), sin(ang)).normalized()
		var h: float = planet.terrain_height(dir)
		var deviation: float = absf(h - r) / r
		worst = maxf(worst, deviation)
		samples += 1
	print("  抽样 %d 个方向，最大偏离半径 %.2f%%" % [samples, worst * 100.0])
	if worst < 0.001:
		print("  ✗ 所有方向几乎等于半径 —— 高度表像是常数，不合理")
	elif worst > 0.35:
		print("  ✗ 偏离超过 35%% —— 高度表可能有异常尖刺")
	else:
		print("  ✓ 起伏范围合理")

	print("")
	print("=== 4. surface_position 与高度表一致性 ===")
	var d2 := Vector3(0.3, 0.8, -0.5).normalized()
	var via_surface: float = planet.surface_position(d2, 0.0).length()
	var via_height: float = planet.terrain_height(d2)
	print("  surface_position 长度 = %.2f / terrain_height = %.2f（应相等）" % [
		via_surface, via_height])

	print("")
	print("=== 5. 地形碰撞 ===")
	planet._ensure_terrain_collision()
	var body: Node = planet.get_node_or_null("TerrainCollision")
	if body == null:
		print("  ✗ 没有建出 TerrainCollision")
	else:
		var shapes: Array = body.get_children()
		var total_faces := 0
		for c in shapes:
			if c is CollisionShape3D and c.shape is ConcavePolygonShape3D:
				total_faces += (c.shape as ConcavePolygonShape3D).get_faces().size() / 3
		print("  ✓ TerrainCollision 有 %d 个碰撞形状，合计 %d 面" % [
			shapes.size(), total_faces])

	print("")
	print("=== 6. 建筑平地 ===")
	print("  site_height = %.1f 米" % float(planet.site_height))
	var at_site: float = planet._raw_terrain_height(planet.site_direction)
	print("  高度表在站点方向的值 = %.1f 米（应接近 site_height）" % at_site)
	var diff: float = absf(at_site - float(planet.site_height))
	if diff < 1.0:
		print("  ✓ 吻合（差 %.2f 米）" % diff)
	else:
		print("  ✗ 差 %.2f 米 —— 建筑会悬空或埋地" % diff)

	quit(0)
