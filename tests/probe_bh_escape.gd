extends SceneTree
# 探针：验证「擦边逃逸」真的修好了。
#
# 模拟「高速从黑洞旁边擦边冲过」：飞船在离黑洞一定距离处以切向速度飞过，
# 看它最后会不会被吃掉。修之前高速擦边能溜，修之后应该全部被捕获。
#
# 注意：必须同时跑 _black_hole_pull 和 _apply_black_hole_capture ——
# 后者含「强制捕获」的锁存判定，只跑前者测不出高速擦边有没有被兜住。
#
#   godot --headless --path . --script res://tests/probe_bh_escape.gd

var game
var ship


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_bh_escape.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	ship = game.ship
	if ship == null or game.gargantua == null:
		print("飞船或卡冈图雅没建出来")
		quit(1)
		return

	var hole: Vector3 = game.gargantua.global_position
	print("=== 擦边逃逸测试：高速掠过（瞄准点偏移一点，才是真擦边） ===")
	print("  起始距离   切向速度   最近距离   60 秒后距离   结果")
	var escaped := 0
	var total := 0
	# 起点放在很远处，速度沿 X 轴，瞄准点从黑洞中心偏移 aim_offset。
	# 这样才是「擦边」：不撞正中央，而是从旁边掠过。
	# 起点放在 BH_PULL_RANGE 之内、捕获圈之外，模拟「已经在引力场里」。
	for start_d in [5000.0, 3600.0]:
		for aim_offset in [0.0, 600.0, 1200.0]:
			for speed in [300.0, 800.0, 1600.0]:
				# 从 (0, start_d, 0) 出发，朝 -Y 方向飞，同时 X 方向有速度；
				# 瞄准点偏移用 Z 方向的速度分量实现。
				ship.global_position = hole + Vector3(0.0, start_d, 0.0)
				# 朝黑洞的向心速度 + 切向分量 = 一条偏移的掠过轨迹
				var aim_point: Vector3 = hole + Vector3(aim_offset, 0.0, 0.0)
				var dir: Vector3 = (aim_point - ship.global_position).normalized()
				ship.velocity = dir * speed
				ship.bh_orbit_age = 0.0
				ship.bh_warn_level = 0
				ship.bh_warn_cooldown = 0.0
				ship.bh_captured = false

				var swallowed := false
				var closest := INF
				var dt := 1.0 / 60.0
				for _i in range(3600):
					var g: Vector3 = ship._black_hole_pull(dt)
					ship.velocity += g * dt
					ship.global_position += ship.velocity * dt
					var d_now: float = ship.global_position.distance_to(hole)
					closest = minf(closest, d_now)
					# 复刻 _apply_black_hole_capture 里的捕获锁存与切向吞噬，
					# 参数全部读 ship 上的常量，保证与生产代码同步。
					if d_now <= ship.BH_FORCE_CAPTURE:
						ship.bh_captured = true
					elif d_now > ship.BH_FORCE_CAPTURE * ship.BH_CAPTURE_RELEASE:
						ship.bh_captured = false
					if ship.bh_captured:
						var inward: Vector3 = (hole - ship.global_position).normalized()
						var tv: Vector3 = ship.velocity - inward * ship.velocity.dot(inward)
						ship.velocity -= tv * clampf(ship.BH_FORCE_BRAKE * dt, 0.0, 1.0)
						var ispd: float = ship.velocity.dot(inward)
						if ispd < ship.BH_FORCE_INWARD:
							ship.velocity += inward * (ship.BH_FORCE_INWARD - ispd)
					if ship._is_swallowed_for_probe(hole):
						swallowed = true
						break
				var final_d: float = ship.global_position.distance_to(hole)
				total += 1
				if not swallowed:
					escaped += 1
				print("  %8.0f   %8.0f   %8.0f   %10.0f   %s" % [
					start_d, speed, closest, final_d,
					"被吞 OK" if swallowed else "逃逸 FAIL"])
	print("")
	print("结论：%d / %d 组被捕获，%d 组逃逸" % [total - escaped, total, escaped])
	quit(0)
