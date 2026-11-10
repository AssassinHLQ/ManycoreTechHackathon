extends SceneTree
# 探针：验证新版飞行姿态控制（鼠标推 aim、飞船缓慢追、机头朝屏幕中心）。
# 用法：godot --headless --path . --script res://tests/probe_flight_attitude.gd
#
# 检查：
#   1. 鼠标动一下，**飞船当帧不立刻转向**（要慢慢转）—— 这是「不是平移」的关键
#   2. 持续若干帧后，飞船朝向**收敛到**期望朝向
#   3. 转向过程中角速度不超过 MAX_TURN_RATE
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
	ship.aim_basis = Basis.IDENTITY
	ship._turn_velocity = Vector3.ZERO

	# ── 1. 鼠标推动 aim，飞船不该当帧就转到位 ──
	print("\n=== 1. 鼠标只推 aim，不直接转飞船 ===")
	var before: Basis = ship.global_transform.basis
	ship.apply_look(Vector2(400.0, 0.0))       # 大幅左右移鼠标
	var aim_after: Basis = ship.aim_basis
	var ship_after: Basis = ship.global_transform.basis
	var aim_delta := _angle_between(before, aim_after)
	var ship_delta := _angle_between(before, ship_after)
	print("   aim 转了 %.1f°，飞船转了 %.1f°" % [aim_delta, ship_delta])
	_check(aim_delta > 5.0, "mouse moves the aim direction (%.1f deg)" % aim_delta)
	_check(ship_delta < 1.0, "the ship does NOT snap-turn instantly (%.2f deg)" % ship_delta)

	# ── 2. 持续若干帧后收敛到 aim ──
	print("\n=== 2. 飞船缓慢转向并收敛 ===")
	var first_frame_basis: Basis = ship.global_transform.basis
	ship._physics_process(1.0 / 60.0)
	var after_one := _angle_between(first_frame_basis, ship.global_transform.basis)
	print("   一帧内转了 %.2f°（有角速度上限）" % after_one)
	_check(after_one < 10.0, "one frame turns only a little (%.2f deg)" % after_one)

	# 跑 2 秒让飞船追上去
	for i in range(120):
		ship._physics_process(1.0 / 60.0)
	var final_delta := _angle_between(ship.global_transform.basis, ship.aim_basis)
	print("   2 秒后 飞船与 aim 差 %.3f°" % final_delta)
	_check(final_delta < 3.0, "the ship converges to the aim direction (%.2f deg)" % final_delta)

	# ── 3. 机头朝 aim 前方（即「屏幕中心」）──
	var ship_forward: Vector3 = -ship.global_transform.basis.z.normalized()
	var aim_forward: Vector3 = -ship.aim_basis.z.normalized()
	var dot: float = ship_forward.dot(aim_forward)
	print("\n=== 3. 机头对准屏幕中心 ===")
	print("   机头·期望前向 = %.4f（1.0 = 完全对齐）" % dot)
	_check(dot > 0.99, "nose points at the view center (dot=%.4f)" % dot)

	# ── 4. A/D 不再横移 ──
	print("\n=== 4. A/D 不再是横移 ===")
	ship.velocity = Vector3.ZERO
	ship.aim_basis = ship.global_transform.basis
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
