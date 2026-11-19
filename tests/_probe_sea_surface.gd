extends SceneTree
# 探针：飞船停靠点处，Lux3D 可见模型的外层半径 vs terrain_height（碰撞/落地高度）。
# 用来判断蓝面是「分离的水面」还是「贴图」，以及船要抬多高才能「浮在海上」。
# 用法：godot --headless --path . --script res://tests/_probe_sea_surface.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://probe_sea_surface.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	for i in range(30):
		await process_frame

	var home = game.home
	var ship = game.ship
	var ship_dir: Vector3 = (ship.global_position - home.global_position).normalized()
	var site_dir: Vector3 = home.site_direction.normalized()
	var terrain: float = home.terrain_height(ship_dir)
	var ship_r: float = ship.global_position.distance_to(home.global_position)
	print("=== 飞船停靠点（start_game 后 30 帧）===")
	print("  landed=%s landing_normal=%s" % [str(ship.landed), str(ship.landing_normal)])
	print("  site_direction 与 UP 夹角 = %.2f°" % rad_to_deg(site_dir.angle_to(Vector3.UP)))
	print("  与站点方向夹角 = %.2f°" % rad_to_deg(ship_dir.angle_to(site_dir)))
	print("  船体原点半径 = %.2f m，terrain_height = %.2f m，原点离地 = %.2f m" % [
		ship_r, terrain, ship_r - terrain])

	var lux = home.get_node_or_null("Lux3dSurface")
	if lux == null:
		print("  没有 Lux3dSurface 节点")
		quit(0)
		return

	# 收集可见网格顶点到行星局部空间
	var verts := PackedVector3Array()
	var inv: Transform3D = home.global_transform.affine_inverse()
	for mi in lux.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		var rel: Transform3D = inv * node.global_transform
		for s in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in vv:
				verts.append(rel * v)
	print("  可见网格顶点数 = %d" % verts.size())

	# 飞船方向 ±2° 内的顶点半径分布（外层/中位）
	var near: Array = []
	for v in verts:
		var r: float = v.length()
		if r < 0.001:
			continue
		if (v / r).angle_to(ship_dir) < deg_to_rad(2.0):
			near.append(r)
	near.sort()
	print("  飞船方向 ±2° 内顶点 = %d 个" % near.size())
	if not near.is_empty():
		print("  外层半径 max = %.2f，中位 = %.2f，min = %.2f" % [
			float(near[near.size() - 1]), float(near[near.size() / 2]), float(near[0])])
		print("  可见面比 terrain 高 = %.2f m（外层）/ %.2f m（中位）" % [
			float(near[near.size() - 1]) - terrain, float(near[near.size() / 2]) - terrain])

	# 沿站点→飞船方向采样地形，看海岸剖面
	print("=== 站点 → 飞船 剖面（每 20 m 弧长）===")
	var line: Vector3 = site_dir.slerp(ship_dir, 0.5).normalized()
	for t in range(-4, 5):
		var d: Vector3 = site_dir.slerp(ship_dir, clampf(0.5 + float(t) * 0.0125, 0.0, 1.0)).normalized()
		print("  t=%+d  terrain=%.1f" % [t, home.terrain_height(d)])

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
