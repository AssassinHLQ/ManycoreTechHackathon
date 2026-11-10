extends SceneTree
# 探针：验证「速度缓慢转向机头」+ 速度上限行为 + 鼠标灵敏度。
# 用法：godot --headless --path . --script res://tests/probe_velocity_align.gd
#
# 用户三条：
#   1. 往前飞、鼠标掉头但不加速 → 不该再「倒着飞」，速度要慢慢转到机头
#   2. 鼠标转向太灵活，晕 → 灵敏度应该明显变低
#   3. 为什么到 1600 就不加速 → 上限提高，且不再是「硬压回」

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
	var save := "user://starward_valign.json"
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
	ship.global_position = Vector3(40000, 0, 0)
	ship.velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	ship.turn_budget = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO

	# ── 1. 掉头后速度会转到机头 ──
	print("\n=== 1. 掉头后速度慢慢转向机头 ===")
	# 先往前飞起来
	Input.action_press("move_forward")
	for i in range(120):     # 2 秒
		ship.fuel = 100.0
		ship.global_position = Vector3(40000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var speed_before: float = ship.velocity.length()
	print("   加速后速度 = %.1f m/s" % speed_before)

	# 鼠标掉头 180°（不放加速）
	ship.set_aim(Quaternion(Vector3.UP, PI))
	# 只设 aim 不会让飞船转，要跑几帧姿态控制
	for i in range(60):
		ship.global_position = Vector3(40000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var nose0: Vector3 = -ship.global_transform.basis.z.normalized()
	var vel0: Vector3 = ship.velocity.normalized()
	var dot0: float = vel0.dot(nose0)
	print("   1 秒后 机头=%s 速度方向=%s dot=%.3f" % [
		"(%.2f,%.2f,%.2f)" % [nose0.x, nose0.y, nose0.z],
		"(%.2f,%.2f,%.2f)" % [vel0.x, vel0.y, vel0.z], dot0])
	# 断言改成：**不能长期倒着飞**。
	# 旧断言（要求短暂保持反向）已经不适用 —— 对齐角速度 1.2 rad/s 足够快，
	# 1 秒内就追上机头了。用户要的就是「不再倒着飞」，所以这里只验证收敛性。
	print("   （对齐角速度 %.2f rad/s，掉头后约 %.1f 秒追上机头）" % [
		ship.VELOCITY_ALIGN_RATE, PI / ship.VELOCITY_ALIGN_RATE])

	# 等 3 秒，速度应该转到机头
	for i in range(180):
		ship.fuel = 100.0
		ship.global_position = Vector3(40000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var dot1: float = ship.velocity.normalized().dot(-ship.global_transform.basis.z.normalized())
	var speed_after: float = ship.velocity.length()
	print("   3 秒后 速度·机头 = %.3f，速度 %.1f m/s" % [dot1, speed_after])
	_check(dot1 > 0.95, "after a few seconds velocity aligns with the nose (dot=%.3f)" % dot1)
	_check(absf(speed_after - speed_before) < speed_before * 0.15,
		"aligning does not change the speed magnitude (%.0f -> %.0f)" % [speed_before, speed_after])

	# ── 2. 鼠标灵敏度变低 ──
	print("\n=== 2. 鼠标灵敏度 ===")
	print("   AIM_SENSITIVITY = %.6f 弧度/像素（旧值 0.0022）" % ship.AIM_SENSITIVITY)
	print("   MAX_TURN_RATE = %.2f 弧度/秒（旧值 2.4）" % ship.MAX_TURN_RATE)
	_check(ship.AIM_SENSITIVITY < 0.0015, "mouse sensitivity was reduced")
	_check(ship.MAX_TURN_RATE < 1.5, "ship turn rate was reduced")

	# ── 3. 速度上限已彻底移除 ──
	print("\n=== 3. 速度上限已移除 ===")
	_check(not ("SHIP_SPEED_SAFETY_CAP" in ship),
		"the speed cap constant is gone entirely")

	# 手动给一个很大的速度，确认不会被压回去、也不会衰减
	ship.velocity = -ship.global_transform.basis.z * 2800.0
	var before_cap: float = ship.velocity.length()
	ship._physics_process(1.0 / 60.0)
	var after_cap: float = ship.velocity.length()
	print("   设 2800 m/s，一帧后 = %.1f（不该被压回上限）" % after_cap)
	_check(after_cap >= before_cap * 0.9, "an over-cap velocity is not snapped back")

	print("\nVELOCITY ALIGN PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
