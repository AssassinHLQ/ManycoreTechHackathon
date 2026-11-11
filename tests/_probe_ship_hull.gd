extends SceneTree
# 探针：飞船的碰撞盒 vs 视觉包围盒，到底差多少。
#
# 用户截图里人已经钻进飞船模型内部 —— 典型症状是「碰撞盒比模型小很多」。
# 这里把两个尺寸都量出来对比。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _run() -> void:
	var test_save := "user://starward_hull_probe.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(25)

	var ship = game.ship
	print("=== 飞船节点 scale: ", ship.scale)
	print("=== ship_model_length = %.3f  ship_model_height = %.3f" % [
		ship.ship_model_length, ship.ship_model_height])

	# 碰撞盒
	var box: BoxShape3D = ship.hull_shape
	print("\n--- 碰撞盒（BoxShape3D）---")
	print("  size = ", box.size)
	print("  体积 = %.2f" % (box.size.x * box.size.y * box.size.z))
	var cs: CollisionShape3D = null
	for c in ship.hull_body.get_children():
		if c is CollisionShape3D:
			cs = c
			break
	if cs:
		print("  碰撞体 local position = ", cs.position)
		print("  碰撞体 global_position = ", cs.global_position)

	# 视觉包围盒：把所有 MeshInstance3D 的 AABB 合起来
	# ⚠ 必须排除尾焰（名字以 Plume 开头 / 在 engine_plumes 里）—— 它们伸到
	#   Z=10.4，而机身只有 ±7.0。算进去会让「覆盖率」看起来只有 78%，
	#   误以为碰撞盒做小了（本喵自己踩过这个坑）。
	var aabb := AABB()
	var first := true
	var mesh_count := 0
	var plume_count := 0
	for node in ship.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		# 尾焰会伸到 Z=10.4，必须排除。除了 engine_plumes 里的 3 束，
		# 还有 3 个同位置的自发光网格（它们也属于尾焰，只是没进数组），
		# 所以按「Z + mesh 尺寸」判：maxZ > 机身长度/2 就当尾焰跳过。
		var local_ab: AABB = mi.get_aabb()
		var xf0: Transform3D = ship.global_transform.affine_inverse() * mi.global_transform
		var ab0: AABB = xf0 * local_ab
		if ab0.position.z + ab0.size.z > ship.ship_model_length * 0.5 + 0.05:
			plume_count += 1
			continue
		var local_aabb: AABB = mi.get_aabb()
		# 转到 ship 的局部空间
		var xf: Transform3D = ship.global_transform.affine_inverse() * mi.global_transform
		var world_aabb: AABB = xf * local_aabb
		if first:
			aabb = world_aabb
			first = false
		else:
			aabb = aabb.merge(world_aabb)
		mesh_count += 1
	print("\n--- 视包围盒（%d 个机身 mesh，已排除 %d 束尾焰）---" % [mesh_count, plume_count])
	print("  position = ", aabb.position)
	print("  size     = ", aabb.size)
	print("  center   = ", aabb.get_center())

	print("\n--- 对比 ---")
	print("  碰撞盒 size : (%.2f, %.2f, %.2f)" % [box.size.x, box.size.y, box.size.z])
	print("  模型   size : (%.2f, %.2f, %.2f)" % [aabb.size.x, aabb.size.y, aabb.size.z])
	print("  覆盖率 X=%.1f%%  Y=%.1f%%  Z=%.1f%%" % [
		box.size.x / maxf(aabb.size.x, 0.001) * 100.0,
		box.size.y / maxf(aabb.size.y, 0.001) * 100.0,
		box.size.z / maxf(aabb.size.z, 0.001) * 100.0])

	print("\n--- 玩家能不能走进飞船 ---")
	# 把玩家放到飞船正上方 5 米，让它自由落体，看是否会穿过飞船落到地面
	var planet = game.nearest_planet(ship.global_position)
	game.state = "walk"
	game.player.visible = true
	if game.player.get_parent() != planet:
		game.player.reparent(planet, false)
	game.player.global_position = ship.global_position + Vector3(0, 5, 0)
	game.player.velocity = Vector3.ZERO
	await _frames(2)
	var start_y: float = game.player.global_position.y
	var min_dist := INF
	var inside_frames := 0
	for i in range(120):
		await physics_frame
		var d: float = game.player.global_position.distance_to(ship.global_position)
		min_dist = minf(min_dist, d)
		# 判断是否落在碰撞盒内部
		var local: Vector3 = ship.global_transform.affine_inverse() * game.player.global_position
		var half: Vector3 = box.size * 0.5
		var center: Vector3 = cs.position if cs else Vector3.ZERO
		if absf(local.x - center.x) < half.x and absf(local.y - center.y) < half.y and absf(local.z - center.z) < half.z:
			inside_frames += 1
	print("  玩家下落起点 y=%.2f，最终 y=%.2f" % [start_y, game.player.global_position.y])
	print("  与飞船中心最近距离: %.2f m" % min_dist)
	print("  在碰撞盒内部的帧数: %d / 120" % inside_frames)
	if inside_frames > 0:
		print("  !! 玩家穿进碰撞盒了 —— 碰撞没生效")
	else:
		print("  OK 玩家没穿进碰撞盒")

	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0)
