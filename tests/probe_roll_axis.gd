extends SceneTree
# 探针：验证「滚转后鼠标方向不反」。
# 用法：godot --headless --path . --script res://tests/probe_roll_axis.gd
#
# 用户报的 bug：
#   「为什么我鼠标往右, 有时候飞船往右转, 有时候却往左转,
#     我一旦按了 ad, 整个飞船的鼠标转视角就完全反了方向」
#
# 根因：旧版 get_aim_basis() = Ry(yaw) * Rx(pitch) * Rz(roll) ——
#   滚转乘进去了，于是：
#     · roll = 180° 时，机身的「右」变成世界「左」
#     · 但鼠标横向输入仍然映射成绕世界 Y 的 yaw
#     · 两者参考系不一致 → 鼠标往右、飞船往左
#     · roll = 90° 时更严重（横向输入变成「绕机身轴」，方向取决于滚转角）
#
# 修法：aim_basis 不再含滚转，滚转单独一个自由度。
# 这个探针在**不同滚转角**下推同样的鼠标，验证飞船都往同一个世界方向转。

var game
var failures := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS  ", msg)
	else:
		failures += 1
		print("FAIL  ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_rollaxis.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(8):
		await physics_frame

	var ship = game.ship
	game.state = "ship"
	ship.landed = false
	ship.docked = false
	ship.autopilot = false
	ship.global_position = Vector3(60000, 0, 0)
	ship.velocity = Vector3.ZERO

	# ── 核心测试：不同滚转角下，鼠标往右都应该让机头往「世界 +右」转 ──
	print("\n=== 不同滚转角下，鼠标向右的转向方向 ===")
	var results: Array = []
	for roll_deg in [0.0, 90.0, 180.0, 270.0]:
		# 重置
		ship.fuel = 100.0
		ship.aim_yaw = 0.0
		ship.aim_pitch = 0.0
		ship._roll_angle = deg_to_rad(roll_deg)
		ship._turn_velocity = Vector3.ZERO
		ship.global_transform.basis = Basis(Vector3.FORWARD, ship._roll_angle)
		ship.global_position = Vector3(60000, 0, 0)
		ship.velocity = Vector3.ZERO

		var nose_before: Vector3 = -ship.global_transform.basis.z.normalized()
		# 鼠标向右推
		for i in range(40):
			ship.apply_look(Vector2(30.0, 0.0))
		# 跑几帧让机头转过去
		for i in range(90):
			ship.fuel = 100.0
			ship.global_position = Vector3(60000, 0, 0)
			ship._physics_process(1.0 / 60.0)

		var nose_after: Vector3 = -ship.global_transform.basis.z.normalized()
		# 机头绕世界 Y 转了多少（带符号）
		var cross_y: float = nose_before.cross(nose_after).y
		var dir_sign: float = signf(cross_y)
		results.append(dir_sign)
		print("   滚转 %5.0f°：鼠标右推 → 机头转向 y 分量符号 = %+.0f" % [roll_deg, dir_sign])

	# 所有滚转角下的转向方向必须一致
	var all_same := true
	for s in results:
		if s != results[0]:
			all_same = false
	_check(all_same, "mouse-right turns the nose the same world direction at every roll angle")

	# ── 滚转本身仍然生效 ──
	print("\n=== 滚转仍然生效 ===")
	ship.fuel = 100.0
	ship.aim_yaw = 0.0
	ship.aim_pitch = 0.0
	ship._roll_angle = 0.0
	ship._turn_velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	var up_before: Vector3 = ship.global_transform.basis.y.normalized()
	Input.action_press("move_left")
	for i in range(60):
		ship.fuel = 100.0
		ship.global_position = Vector3(60000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_left")
	var up_after: Vector3 = ship.global_transform.basis.y.normalized()
	var up_rotated: float = rad_to_deg(up_before.angle_to(up_after))
	print("   A/D 一秒：机身上方向转了 %.1f°" % up_rotated)
	_check(up_rotated > 10.0, "rolling still visually rolls the hull (%.1f deg)" % up_rotated)

	# ── 滚转不改变机头指向 ──
	print("\n=== 滚转不改变机头指向 ===")
	var nose_b: Vector3 = -ship.global_transform.basis.z.normalized()
	ship._roll_by_angle(deg_to_rad(90.0))
	var nose_a: Vector3 = -ship.global_transform.basis.z.normalized()
	var nose_drift: float = rad_to_deg(nose_b.angle_to(nose_a))
	print("   改滚转 90°：机头偏移 %.3f°（应约 0）" % nose_drift)
	_check(nose_drift < 1.0, "rolling does not move the nose direction (%.3f deg)" % nose_drift)

	print("\nROLL AXIS PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
