extends SceneTree
# 探针：验证 RCS 姿态控制要烧燃料，且没燃料就转不了。
# 用法：godot --headless --path . --script res://tests/probe_rcs_fuel.gd
#
# 用户要求：「我没有施力，无法转动飞船」+「没燃料就转不了」。
# 所以：
#   1. 鼠标转向时，燃料必须下降
#   2. 燃料为 0 时，飞船姿态锁死（转不动）
#   3. 转过的角度越大，消耗的燃料越多
#   4. 滚转也消耗燃料

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
	var save := "user://starward_rcs.json"
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
	ship.global_position = Vector3(50000, 0, 0)
	ship.velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	ship.intent_quat = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO

	# ── 1. 转向消耗燃料 ──
	print("\n=== 1. 转个弯要烧油 ===")
	ship.fuel = 100.0
	ship.intent_quat = Quaternion(Vector3.UP, PI * 0.5)   # 要求转 90°
	var fuel_before: float = ship.fuel
	for i in range(120):          # 2 秒
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var fuel_after: float = ship.fuel
	print("   转 90°：燃料 %.3f -> %.3f（消耗 %.4f）" % [
		fuel_before, fuel_after, fuel_before - fuel_after])
	_check(fuel_before - fuel_after > 0.001, "turning costs fuel (used %.4f)" % (fuel_before - fuel_after))

	# ── 2. 转得越多消耗越多 ──
	#
	# ⚠ 2026-11-10 修测法：旧版固定跑 2 秒。
	#   但转 162° 的飞船 2 秒内**转不完**（√ 曲线前段慢），
	#   所以它实际只转了一半，消耗反而少。
	#   改成**转完为止**（最多 8 秒），这才能比较完成相同动作的代价。
	print("\n=== 2. 转角越大越费油 ===")
	var used_small: float = _turns_fuel(ship, Quaternion(Vector3.UP, PI * 0.25))
	var used_big: float = _turns_fuel(ship, Quaternion(Vector3.UP, PI * 0.9))
	print("   转 45° 用 %.5f；转 162° 用 %.5f" % [used_small, used_big])
	_check(used_big > used_small, "larger turns cost more fuel (%.5f vs %.5f)" % [used_small, used_big])

	# ── 3. 没燃料转不了 ──
	print("\n=== 3. 没燃料就转不动 ===")
	ship.fuel = 0.0
	ship.intent_quat = Quaternion.IDENTITY
	ship.global_transform.basis = Basis.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.intent_quat = Quaternion(Vector3.UP, PI * 0.8)    # 要求转一大圈
	var basis_before: Basis = ship.global_transform.basis
	for i in range(120):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var turned_deg: float = rad_to_deg(
		basis_before.get_rotation_quaternion()
			.angle_to(ship.global_transform.basis.get_rotation_quaternion()))
	print("   燃料 0 时，要求转 144°，实际转了 %.2f°" % turned_deg)
	_check(turned_deg < 1.0, "with no fuel the ship cannot turn (turned %.2f deg)" % turned_deg)

	# ── 4. 滚转也烧油 ──
	print("\n=== 4. 滚转也要烧油 ===")
	ship.fuel = 100.0
	ship.intent_quat = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	var f0: float = ship.fuel
	Input.action_press("move_left")
	for i in range(60):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_left")
	print("   滚转 1 秒：燃料 %.3f -> %.3f" % [f0, ship.fuel])
	_check(f0 - ship.fuel > 0.0001, "rolling costs fuel too")

	# ── 5. 完全静止时零消耗 ──
	print("\n=== 5. 完全不动时零消耗 ===")
	ship.fuel = 100.0
	ship.intent_quat = Quaternion.IDENTITY
	ship.global_transform.basis = Basis.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.velocity = -ship.global_transform.basis.z * 120.0
	# 先让它对齐好
	for i in range(120):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var fuel_idle_start: float = ship.fuel
	# 再空跑 2 秒，什么都不按
	for i in range(120):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var fuel_idle_end: float = ship.fuel
	print("   静止 2 秒：燃料 %.6f -> %.6f（应完全不变）" % [fuel_idle_start, fuel_idle_end])
	_check(absf(fuel_idle_start - fuel_idle_end) < 0.0001,
		"doing nothing costs no fuel (%.6f -> %.6f)" % [fuel_idle_start, fuel_idle_end])

	# ── 6. 速度对齐耗燃料 ──
	print("\n=== 6. 速度对齐也耗燃料 ===")
	ship.fuel = 100.0
	# 造一个「速度与机头相反」的状态：直接把速度反过来
	ship.velocity = ship.global_transform.basis.z.normalized() * 120.0   # 反向
	ship._turn_velocity = Vector3.ZERO
	var f_align0: float = ship.fuel
	for i in range(120):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var f_align1: float = ship.fuel
	print("   速度对齐 2 秒：燃料 %.5f -> %.5f（消耗 %.5f）" % [f_align0, f_align1, f_align0 - f_align1])
	_check(f_align0 - f_align1 > 0.0001, "aligning velocity to the nose costs fuel")

	# ── 7. 没燃料时不对齐（保持惯性）──
	print("\n=== 7. 没燃料时保持惯性方向 ===")
	ship.fuel = 0.0
	ship.velocity = ship.global_transform.basis.z.normalized() * 120.0   # 反向
	ship._turn_velocity = Vector3.ZERO
	var vel_before_dir: Vector3 = ship.velocity.normalized()
	for i in range(120):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var vel_after_dir: Vector3 = ship.velocity.normalized()
	var drift: float = vel_before_dir.dot(vel_after_dir)
	print("   燃料 0 时 2 秒，速度方向·原方向 = %.6f（应为 1.0，即完全不变）" % drift)
	_check(drift > 0.9999, "with no fuel the velocity direction is unchanged (drift=%.6f)" % drift)

	print("\nRCS FUEL PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)


## 让飞船从零朝向转到指定朝向（转完为止，最多 8 秒），返回消耗的燃料。
func _turns_fuel(ship, target_q: Quaternion) -> float:
	ship.fuel = 100.0
	ship.intent_quat = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	ship._sweep_progress = 0.0
	ship._sweep_total = 0.0
	# 先跑几帧让它稳定
	for i in range(10):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	ship.fuel = 100.0
	ship.intent_quat = target_q
	ship._sweep_progress = 0.0
	ship._sweep_total = 0.0
	for i in range(480):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
		var cur: Basis = ship.global_transform.basis.orthonormalized()
		var tgt: Basis = ship.get_aim_basis()
		var diff: Basis = tgt * cur.inverse()
		if rad_to_deg(diff.get_rotation_quaternion().get_angle()) < 0.3:
			break
	return 100.0 - ship.fuel
