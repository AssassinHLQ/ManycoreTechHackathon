extends SceneTree
# 一次性探针：归航站走廊里到底被什么挡住、门旁边为什么是空的。
#   godot --path . --script res://tests/probe_corridor_block.gd
#
# 注意必须像 capture_station.gd 那样先对接、再 enter_station()、再把玩家 reparent 到站上 ——
# 只设 in_station 不 reparent 的话，玩家还在行星节点下，每帧会被行走逻辑拉回枢纽，
# 拍出来的照片会全停在枢纽里（这个坑踩过一次）。

var game


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("res://captures/probe_%s.png" % name)
	print("saved res://captures/probe_%s.png" % name)


func _place(local_position: Vector3, look_local: Vector3) -> void:
	var station = game.station
	var world_position: Vector3 = station.to_global(local_position)
	var look_target: Vector3 = station.to_global(look_local)
	var direction := (look_target - world_position).normalized()
	game.player.global_transform = Transform3D(Basis.looking_at(direction, station.up_direction()), world_position)
	game.player.camera.rotation = Vector3.ZERO
	game.player.velocity = Vector3.ZERO


func _run() -> void:
	var save := "user://starward_probe_corridor.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(16)
	game.start_game()
	await _frames(16)
	game.hud.visible = false

	var station = game.station
	game.ship.landed = false
	game.ship.landed_planet = null
	game.ship.set_physics_process(false)
	game.ship.dock_station(station)
	game.enter_station()
	await _frames(16)
	game.player.set_physics_process(false)
	game.state = "walk"
	game.player.camera.current = true
	print("玩家站内坐标 = ", station.to_local(game.player.global_position))
	print("当前激活走廊 = ", station.active_corridor)

	# 走廊沿 +X 铺开：枢纽门在 x≈30，气闸 x≈34，中央大厅 x≈135，舰桥 x≈247。
	# -- 一、走廊内：从门口往里看（复现「进去被挡住」）---------------
	for spec in [[36.0, 120.0], [60.0, 130.0], [118.0, 140.0]]:
		_place(Vector3(spec[0], -1.9, 0.0), Vector3(spec[1], -1.2, 0.0))
		await _frames(10)
		await _shot("corridor_%03.0f" % spec[0])

	# -- 二、走廊内：贴着中线的碰撞体清点 ----------------------------
	print("\n-- 走廊 0 中线附近（|z|<1.8）的碰撞体 --")
	print("%8s %8s %8s   %s" % ["x", "y", "z", "尺寸"])
	var dump: Array = []
	var root0 = station.corridor_roots[0]
	var body = root0.find_child("StationCollision", true, false)
	for node in body.get_children():
		if not (node is CollisionShape3D):
			continue
		var shape: Shape3D = (node as CollisionShape3D).shape
		if not (shape is BoxShape3D):
			continue
		var local: Vector3 = station.to_local((node as CollisionShape3D).global_position)
		if absf(local.z) > 1.8 or local.x < 25.0 or local.x > 250.0:
			continue
		dump.append({"x": local.x, "y": local.y, "z": local.z, "size": (shape as BoxShape3D).size})
	dump.sort_custom(func(a, b): return a["x"] < b["x"])
	for d in dump:
		print("%8.2f %8.2f %8.2f   %s" % [d["x"], d["y"], d["z"], str(d["size"])])

	# -- 三、射线：从走廊中线往前打 ----------------------------------
	var space2: PhysicsDirectSpaceState3D = game.get_viewport().world_3d.direct_space_state
	print("\n-- 射线（站内中线，y=-1.2 约 0.8 m 高，往前 220 m）--")
	for start_x: float in [36.0, 60.0, 100.0, 120.0, 128.0]:
		var from: Vector3 = station.to_global(Vector3(start_x, -1.2, 0.0))
		var to: Vector3 = station.to_global(Vector3(start_x + 220.0, -1.2, 0.0))
		var query := PhysicsRayQueryParameters3D.create(from, to)
		var hit: Dictionary = space2.intersect_ray(query)
		if hit.is_empty():
			print("  x=%6.1f  一路无阻" % start_x)
			continue
		var hp: Vector3 = station.to_local(hit["position"])
		var collider: Object = hit.get("collider")
		print("  x=%6.1f  →  命中 x=%.2f y=%.2f z=%.2f  距离 %.1f m  %s" % [
			start_x, hp.x, hp.y, hp.z, from.distance_to(hit["position"]),
			(collider as Node).name if collider is Node else "?"])

	# -- 四、枢纽里：贴着门框边缘往缝里看（复现「门旁边是空的」）------
	# 门框在半径 30（HUB_RADIUS），墙板在半径 28.5 且宽 21 m 的**直板**，
	# 两者角位置差 30°，按尺寸算每侧漏出约 1.2 m 的全高缝。
	# 这里就贴着那道缝往里看，确认后面是不是真的什么都没有。
	print("\n-- 门边视角 --")
	for spec in [
		[Vector3(25.0, -1.9, 2.2), Vector3(30.0, -0.2, 10.0), "door_edge_a"],
		[Vector3(22.0, -1.9, 8.0), Vector3(26.5, 0.4, 17.0), "door_edge_b"],
		[Vector3(6.0, -1.9, 6.0), Vector3(30.0, 0.0, 6.0), "hub_door_front"],
		[Vector3(31.0, -0.5, 0.0), Vector3(200.0, -0.5, 0.0), "eye_31"],
		[Vector3(34.0, -0.5, 0.0), Vector3(200.0, -0.5, 0.0), "eye_34"],
		[Vector3(38.0, -0.5, 0.0), Vector3(200.0, -0.5, 0.0), "eye_38"],
		[Vector3(42.0, -0.5, 0.0), Vector3(200.0, -0.5, 0.0), "eye_42"],
	]:
		_place(spec[0], spec[1])
		await _frames(12)
		await _shot(spec[2])

	# -- 五、射线细扫：把走道正中被挡的那块东西描出来（排除玩家自己）--
	var space3: PhysicsDirectSpaceState3D = game.get_viewport().world_3d.direct_space_state
	var exclude: Array[RID] = [(game.player as CollisionObject3D).get_rid()]
	print("\n-- 射线细扫（x 从 32 起，排除玩家）--")
	for start_x: float in [32.0, 36.0, 50.0]:
		var row := ""
		for y: float in [-1.6, -1.0, -0.4, 0.2, 1.0]:
			var from: Vector3 = station.to_global(Vector3(start_x, y, 0.0))
			var to: Vector3 = station.to_global(Vector3(start_x + 200.0, y, 0.0))
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.exclude = exclude
			var hit: Dictionary = space3.intersect_ray(q)
			if hit.is_empty():
				row += "  y%+.1f=无阻" % y
			else:
				var hp: Vector3 = station.to_local(hit["position"])
				var n: Vector3 = station.to_local(hit["position"] + (hit["normal"] as Vector3)) - hp
				row += "  y%+.1f→x%.1f(n.x%+.1f)" % [y, hp.x, n.x]
		print("  x=%.0f %s" % [start_x, row])

	quit(0)






