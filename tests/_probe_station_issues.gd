extends SceneTree
# 探针：归航站内部三连查。
#  1) 玩家静止时，局部坐标是否抖动（物理/轨道运动导致）
#  2) 枢纽墙 360° 射线扫描，找出能射出去的漏洞（门关着时）
#  3) 门口看走廊 / 走廊回看枢纽，各拍一张截图
# 用法（窗口模式）：
#   Godot_v4.7.1-stable_win64_console.exe --path . --script res://tests/_probe_station_issues.gd

var game
var station
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-4000, -4000))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://captures/%s.png" % name)
		print("  saved %s.png" % name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var save_path := "user://probe_station_issues.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(6)

	station = game.station
	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.landed = false
	game.ship.landed_planet = null
	game.ship.autopilot = false
	game.ship.fuel = 80.0
	game.ship.hull = 100.0
	game.ship.global_position = station.docking_point() + station.up_direction() * 18.0
	game.ship.velocity = Vector3.ZERO
	for i in range(6):
		await physics_frame
	print("docked=", game.ship.docked)
	game.enter_station()
	for i in range(6):
		await physics_frame

	# ① 静止抖动：站在枢纽 +X 方向 20 m 处，记录 90 帧局部坐标极差
	game.player.global_position = station.to_global(Vector3(20.0, -1.0, 0.0))
	game.player.velocity = Vector3.ZERO
	for i in range(30):
		await physics_frame
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var cam_lo := Vector3(1e9, 1e9, 1e9)
	var cam_hi := Vector3(-1e9, -1e9, -1e9)
	for i in range(90):
		await physics_frame
		var p: Vector3 = station.to_local(game.player.global_position)
		lo = lo.min(p)
		hi = hi.max(p)
		var cp: Vector3 = station.to_local(game.player.camera.global_position)
		cam_lo = cam_lo.min(cp)
		cam_hi = cam_hi.max(cp)
	print("== IDLE JITTER (station-local) ==")
	print("  player local span = %.4f, %.4f, %.4f (m)" % [hi.x - lo.x, hi.y - lo.y, hi.z - lo.z])
	print("  camera local span = %.4f, %.4f, %.4f (m)" % [
		cam_hi.x - cam_lo.x, cam_hi.y - cam_lo.y, cam_hi.z - cam_lo.z])

	# ② 枢纽墙扫描：站在中心，向四周 1 m 高打射线，门关着时不该有缺口
	for i in range(station.door_panels.size()):
		print("  door[%d] openness=%.2f" % [i, station.door_openness(i)])
	var space: PhysicsDirectSpaceState3D = station.get_world_3d().direct_space_state
	var escapes: Array = []
	for k in range(720):
		var a := TAU * float(k) / 720.0
		for y in [-1.4, 0.6, 1.6]:
			var from: Vector3 = station.to_global(Vector3(0.0, y, 0.0))
			var to: Vector3 = station.to_global(Vector3(cos(a) * 45.0, y, sin(a) * 45.0))
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collision_mask = 1
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				escapes.append([a, y])
	if escapes.is_empty():
		print("== WALL SCAN == no escape rays (all 2160 rays hit)")
	else:
		# 按角度聚类输出
		escapes.sort_custom(func(p, q): return p[0] < q[0])
		var groups: Array = []
		var cur: Array = []
		var last := -10.0
		for e in escapes:
			var a: float = e[0]
			if not cur.is_empty() and a - last > 0.02:
				groups.append(cur)
				cur = []
			cur.append(e)
			last = a
		if not cur.is_empty():
			groups.append(cur)
		print("== WALL SCAN == %d escape rays in %d groups" % [escapes.size(), groups.size()])
		for g in groups:
			var a0: float = g[0][0]
			var a1: float = g[g.size() - 1][0]
			var ys: Array = []
			for e in g:
				if not ys.has(e[1]):
					ys.append(e[1])
			print("  gap at %.1f°..%.1f° (width %.2f m at r=30) heights=%s" % [
				rad_to_deg(a0), rad_to_deg(a1),
				(rad_to_deg(a1) - rad_to_deg(a0)) * PI / 180.0 * 30.0, str(ys)])

	# ③ 截图：枢纽里看 0 号门（正 +X），门开/关；走廊里回看
	var cam: Camera3D = game.player.camera
	game.player.global_position = station.to_global(Vector3(18.0, -1.0, 0.0))
	cam.rotation = Vector3(0.0, 0.0, 0.0)
	game.player.global_transform = Transform3D(
		station.global_transform.basis * Basis(Vector3.UP, -PI * 0.5), game.player.global_position)
	cam.rotation = Vector3.ZERO
	for i in range(40):
		await physics_frame
	await _frames(10)
	await _shot("station_hub_door_open")

	game.player.global_position = station.to_global(Vector3(45.0, -1.0, 0.0))
	game.player.global_transform = Transform3D(
		station.global_transform.basis * Basis(Vector3.UP, PI * 0.5), game.player.global_position)
	cam.rotation = Vector3.ZERO
	for i in range(40):
		await physics_frame
	# 走廊里挡在眼前的是什么：沿视线打一排射线，报碰撞体名字
	var cfrom: Vector3 = cam.global_position
	var cdir: Vector3 = -cam.global_transform.basis.z
	print("== CORRIDOR BLOCKERS (from %s dir %s) ==" % [str(station.to_local(cfrom)), str(station.to_local(cfrom + cdir) - station.to_local(cfrom))])
	var space2: PhysicsDirectSpaceState3D = station.get_world_3d().direct_space_state
	for dx in [-2.0, 0.0, 2.0]:
		for dy in [-1.0, 0.5, 1.5]:
			var off: Vector3 = cam.global_transform.basis.x * dx + Vector3.UP * dy
			var q2 := PhysicsRayQueryParameters3D.create(cfrom + off, cfrom + off + cdir * 25.0)
			q2.hit_from_inside = true
			var h: Dictionary = space2.intersect_ray(q2)
			if h.is_empty():
				print("  ray(%.1f,%.1f) -> nothing" % [dx, dy])
			else:
				var col = h["collider"]
				var local_hit: Vector3 = station.to_local(h["position"] as Vector3)
				print("  ray(%.1f,%.1f) -> %s (%s) local=%s d=%.1f" % [
					dx, dy, String(col.name), String(col.get_path()).get_file(),
					str(local_hit.round()), (h["position"] as Vector3).distance_to(cfrom + off)])
	# 列出视野前方 20 m 内、体量很大的可见网格
	print("  large meshes ahead:")
	for node in station.find_children("*", "MeshInstance3D", true, false):
		if not node.is_visible_in_tree() or node.mesh == null:
			continue
		var aabb_local: AABB = station.global_transform.affine_inverse() * node.global_transform * node.mesh.get_aabb()
		var center: Vector3 = aabb_local.get_center()
		if center.x < 10.0 or center.x > 55.0 or absf(center.z) > 12.0:
			continue
		var size: Vector3 = aabb_local.size
		if size.x < 1.5 and size.y < 1.5 and size.z < 1.5:
			continue
		print("    %s parent=%s center=%s size=%s" % [String(node.name), String(node.get_parent().name), str(center), str(size)])
	await _frames(10)
	await _shot("station_corridor_back")

	game.player.global_position = station.to_global(Vector3(34.0, -1.0, 5.6))
	game.player.global_transform = Transform3D(
		station.global_transform.basis * Basis(Vector3.UP, -PI * 0.35), game.player.global_position)
	cam.rotation = Vector3.ZERO
	for i in range(40):
		await physics_frame
	await _frames(10)
	await _shot("station_door_side")

	print("STATION ISSUES PROBE DONE")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
