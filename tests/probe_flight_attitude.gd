extends SceneTree
# 探针：验证鼠标低灵敏度、飞船直接对齐鼠标与机头方向推进。
# 用法：godot --headless --path . --script res://tests/probe_flight_attitude.gd
#
# 检查：
#   1. 鼠标转角较小，飞船平滑追踪并最终对齐
#   2. 停止输入后飞船不继续追赶或过冲
#   3. 第三人称镜头与机头保持对齐
#   4. A/D 不再横移（速度矢量在侧向没有增长）
#   5. 松油门速度不变（纯物理）

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


func _angle_between(a: Basis, b: Basis) -> float:
	return rad_to_deg(a.orthonormalized().get_rotation_quaternion()
		.angle_to(b.orthonormalized().get_rotation_quaternion()))


func _run() -> void:
	var save := "user://starward_attitude.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	game.settings.values["sensitivity"] = 1.0
	for i in range(8):
		await physics_frame

	var ship = game.ship
	game.state = "ship"
	ship.landed = false
	ship.docked = false
	ship.autopilot = false
	ship.fuel = 100.0
	ship.global_position = Vector3(20000, 0, 0)
	ship.velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	ship.turn_budget = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO

	# ── 1. 鼠标输入较慢，飞船逐步追踪目标 ──
	print("\n=== 1. 低灵敏度鼠标输入 ===")
	var before: Basis = ship.global_transform.basis
	ship.apply_look(Vector2(400.0, 0.0))       # 大幅左右移鼠标
	var aim_after: Basis = ship.get_aim_basis()
	var ship_after: Basis = ship.global_transform.basis
	var aim_delta := _angle_between(before, aim_after)
	var ship_delta := _angle_between(before, ship_after)
	print("   aim 转了 %.1f°，飞船转了 %.1f°" % [aim_delta, ship_delta])
	_check(aim_delta > 0.1 and aim_delta < 5.0,
		"mouse sensitivity stays low (%.2f deg for 400 px)" % aim_delta)
	_check(ship_delta < 0.01, "the ship applies mouse input on the physics tick (%.2f deg)" % ship_delta)

	# ── 2. 姿态逐步靠近目标，停止输入后平滑收敛且不反弹 ──
	print("\n=== 2. 飞船平滑对齐鼠标目标 ===")
	ship._physics_process(1.0 / 60.0)
	var after_one := _angle_between(before, ship.global_transform.basis)
	var first_gap := _angle_between(ship.global_transform.basis, ship.get_aim_basis())
	print("   第一帧转了 %.2f°，目标 %.2f°，剩余 %.2f°" % [after_one, aim_delta, first_gap])
	_check(after_one > 0.01 and after_one < aim_delta,
		"mouse rotation begins smoothly instead of snapping (%.2f of %.2f deg)" % [after_one, aim_delta])
	var previous_gap := first_gap
	var monotonic := true
	for i in range(5):
		ship._physics_process(1.0 / 60.0)
		var current_gap := _angle_between(ship.global_transform.basis, ship.get_aim_basis())
		if current_gap > previous_gap + 0.001:
			monotonic = false
		previous_gap = current_gap
	_check(monotonic, "the ship approaches the target without reversing")

	# 连续空闲半秒后也不应继续转动。
	for i in range(24):
		ship._physics_process(1.0 / 60.0)
	var half_second_delta := _angle_between(ship.global_transform.basis, ship.get_aim_basis())
	print("   0.5 秒后 飞船与 aim 差 %.3f°" % half_second_delta)
	_check(half_second_delta < 0.05,
		"the ship settles on the mouse target while idle (%.2f deg remaining)" % half_second_delta)

	# 再跑 1.5 秒确认姿态精确收敛。
	for i in range(91):
		ship._physics_process(1.0 / 60.0)
	var final_delta := _angle_between(ship.global_transform.basis, ship.get_aim_basis())
	print("   2 秒后 飞船与 aim 差 %.3f°" % final_delta)
	_check(final_delta < 3.0, "the ship converges to the aim direction (%.2f deg)" % final_delta)

	# ── 3. 机头朝 aim 前方（即「屏幕中心」）──
	var ship_forward: Vector3 = -ship.global_transform.basis.z.normalized()
	var aim_forward: Vector3 = -ship.get_aim_basis().z.normalized()
	var dot: float = ship_forward.dot(aim_forward)
	print("\n=== 3. 机头对准屏幕中心 ===")
	print("   机头·期望前向 = %.4f（1.0 = 完全对齐）" % dot)
	_check(dot > 0.99, "nose points at the view center (dot=%.4f)" % dot)

	# ── 4. A/D 不再横移 ──
	print("\n=== 4. A/D 不再是横移 ===")
	ship.velocity = Vector3.ZERO
	var gf: Vector3 = -ship.global_transform.basis.z.normalized()
	ship.turn_budget = Quaternion.IDENTITY
	Input.action_press("move_right")
	for i in range(60):
		ship.fuel = 100.0
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	var fwd: Vector3 = -ship.global_transform.basis.z.normalized()
	var side_speed: float = (ship.velocity - fwd * ship.velocity.dot(fwd)).length()
	print("   按住 A/D 一秒后：总速度 %.2f，侧向速度 %.2f" % [ship.velocity.length(), side_speed])
	_check(side_speed < 2.0, "A/D no longer strafes sideways (side speed %.2f)" % side_speed)

	# ── 5. 松油门速度不变（纯物理）──
	print("\n=== 5. 松油门速度不变 ===")
	ship.velocity = fwd * 150.0
	ship._turn_velocity = Vector3.ZERO
	for i in range(60):
		ship._physics_process(1.0 / 60.0)
	print("   1 秒后速度 %.2f m/s（应为 150）" % ship.velocity.length())
	_check(absf(ship.velocity.length() - 150.0) < 3.0,
		"velocity is conserved with no thrust (%.1f)" % ship.velocity.length())

	# ── 6. 第三人称：准星也必须对着机头 ──
	print("\n=== 6. 第三人称准星 == 机头 ===")
	ship.toggle_third_person()
	ship._physics_process(1.0 / 60.0)
	var cam_fwd: Vector3 = -ship.camera.global_transform.basis.z.normalized()
	var nose: Vector3 = -ship.global_transform.basis.z.normalized()
	var d2: float = cam_fwd.dot(nose)
	print("   相机前向·机头 = %.4f（1.0 = 准星正对机头）" % d2)
	_check(d2 > 0.99, "third person: the crosshair points along the nose (dot=%.4f)" % d2)

	# 转向后仍然对准
	ship.apply_look(Vector2(300.0, 60.0))
	for i in range(90):
		ship._physics_process(1.0 / 60.0)
	cam_fwd = -ship.camera.global_transform.basis.z.normalized()
	nose = -ship.global_transform.basis.z.normalized()
	d2 = cam_fwd.dot(nose)
	print("   转向后 相机前向·机头 = %.4f" % d2)
	_check(d2 > 0.99, "third person: still aligned after turning (dot=%.4f)" % d2)
	ship.toggle_third_person()

	print("\nFLIGHT ATTITUDE PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
