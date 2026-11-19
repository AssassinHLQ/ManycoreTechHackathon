extends SceneTree

const OffWin := preload("res://scripts/offscreen_window.gd")
# 量「道具是否贴合地形」：对每颗星球上每个 Prop_* 实例（抽样）从实例底面向下打射线，
# 算底面相对地表的带符号高度。正 = 浮空，负 = 陷地。
# 用法：godot --headless --path . --script res://tests/_probe_prop_ground.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://probe_prop_ground.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	for i in range(30):
		await physics_frame
	if game.home.has_method("_ensure_terrain_collision"):
		game.home._ensure_terrain_collision()
	for i in range(10):
		await physics_frame

	var planets: Array = [game.home]  # 先只量母星
	var dbg_nodes: int = 0
	var total := 0
	var floating := 0
	var sunk := 0
	var worst: Array = []   # [gap, planet_id, prop_id, dir]
	var per_prop := {}      # prop_id -> [count, sum_gap, max_abs]

	for planet in planets:
		if planet == null:
			continue
		var space: PhysicsDirectSpaceState3D = planet.get_world_3d().direct_space_state
		# 排除所有道具/飞船碰撞体，只量地形（否则射线打到道具自己身上）
		var excl: Array = []
		for b in planet.find_children("PropCollision_*", "StaticBody3D", true, false):
			excl.append((b as CollisionObject3D).get_rid())
		for b in planet.find_children("ShipCollision", "StaticBody3D", true, false):
			excl.append((b as CollisionObject3D).get_rid())
		for node in planet.find_children("Prop_*", "MultiMeshInstance3D", true, false):
			var mmi := node as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				continue
			var prop_id := String(mmi.name).trim_prefix("Prop_")
			if prop_id.contains("floating") or prop_id.contains("cloud") \
					or prop_id.contains("airship") or prop_id.contains("glider"):
				continue   # 本来就该悬空的东西
			dbg_nodes += 1
			var mesh_aabb: AABB = mmi.multimesh.mesh.get_aabb()
			var bot_local := Vector3(mesh_aabb.get_center().x, mesh_aabb.position.y,
				mesh_aabb.get_center().z)
			var count := mini(mmi.multimesh.instance_count, 40)
			for i in range(count):
				var xf: Transform3D = mmi.multimesh.get_instance_transform(i)
				var origin: Vector3 = mmi.global_transform * xf.origin
				# 模型底面中心（局部）经实例变换后的世界位置
				var bottom: Vector3 = mmi.global_transform * (xf * bot_local)
				var up: Vector3 = (origin - planet.global_position).normalized()
				var q := PhysicsRayQueryParameters3D.create(
					bottom + up * 150.0, bottom - up * 150.0)
				q.exclude = excl
				var hit: Dictionary = space.intersect_ray(q)
				if hit.is_empty():
					continue
				var surface: Vector3 = hit["position"]
				var gap: float = (bottom - surface).dot(up)
				total += 1
				if gap > 1.0:
					floating += 1
				elif gap < -1.0:
					sunk += 1
				var rec: Array = per_prop.get(prop_id, [0, 0.0, 0.0])
				rec[0] = int(rec[0]) + 1
				rec[1] = float(rec[1]) + gap
				rec[2] = maxf(float(rec[2]), absf(gap))
				per_prop[prop_id] = rec
				if worst.size() < 15 or absf(gap) > absf(float(worst[-1][0])):
					worst.append([gap, String(planet.planet_id), prop_id, str(origin)])
					worst.sort_custom(func(a, b): return absf(float(a[0])) > absf(float(b[0])))
					if worst.size() > 15:
						worst.pop_back()

	print("=== 母星道具贴地检查（每类最多抽 40 个）===")
	print("  Prop_* 节点数 = %d" % dbg_nodes)
	print("  样本 %d：浮空(>1m) %d，陷地(<-1m) %d，正常 %d" % [
		total, floating, sunk, total - floating - sunk])
	print("--- 平均偏差最大的 15 类 ---")
	var ranked: Array = []
	for pid in per_prop:
		var r: Array = per_prop[pid]
		ranked.append([float(r[1]) / float(r[0]), float(r[2]), pid, int(r[0])])
	ranked.sort_custom(func(a, b): return absf(float(a[0])) > absf(float(b[0])))
	for row in ranked.slice(0, 15):
		print("  %-24s 平均 %+7.2f m  最差 %6.2f m  (%d 个)" % [
			String(row[2]), float(row[0]), float(row[1]), int(row[3])])
	print("--- 单体最差 10 个 ---")
	for rec in worst.slice(0, 10):
		print("  %+8.2f m  %s / %s @ %s" % [
			float(rec[0]), String(rec[1]), String(rec[2]), String(rec[3])])

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
