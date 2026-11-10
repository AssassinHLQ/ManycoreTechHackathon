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
	ship.aim_yaw = 0.0
	ship.aim_pitch = 0.0
	ship._roll_angle = 0.0
	ship._turn_velocity = Vector3.ZERO

	# ── 1. 转向消耗燃料 ──
	print("\n=== 1. 转个弯要烧油 ===")
	ship.fuel = 100.0
	ship.aim_yaw = PI * 0.5      # 要求转 90°
	var fuel_before: float = ship.fuel
	for i in range(120):          # 2 秒
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var fuel_after: float = ship.fuel
	print("   转 90°：燃料 %.3f -> %.3f（消耗 %.4f）" % [
		fuel_before, fuel_after, fuel_before - fuel_after])
	_check(fuel_before - fuel_after > 0.001, "turning costs fuel (used %.4f)" % (fuel_before - fuel_after))

	# ── 2. 转得越多消耗越多 ──
	print("\n=== 2. 转角越大越费油 ===")
	ship.fuel = 100.0
	ship.aim_yaw = 0.0
	ship._turn_velocity = Vector3.ZERO
	for i in range(120):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var used_small: float = 100.0 - ship.fuel

	ship.fuel = 100.0
	ship.aim_yaw = PI * 0.9      # 更大的转角
	ship._turn_velocity = Vector3.ZERO
	for i in range(120):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var used_big: float = 100.0 - ship.fuel
	print("   转约 90° 用 %.4f；转约 162° 用 %.4f" % [used_small, used_big])
	_check(used_big > used_small, "larger turns cost more fuel")

	# ── 3. 没燃料转不了 ──
	print("\n=== 3. 没燃料就转不动 ===")
	ship.fuel = 0.0
	ship.aim_yaw = 0.0
	ship.aim_pitch = 0.0
	ship.global_transform.basis = Basis.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.aim_yaw = PI * 0.8       # 要求转一大圈
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
	ship.aim_yaw = 0.0
	ship._turn_velocity = Vector3.ZERO
	var f0: float = ship.fuel
	Input.action_press("move_left")
	for i in range(60):
		ship.global_position = Vector3(50000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_left")
	print("   滚转 1 秒：燃料 %.3f -> %.3f" % [f0, ship.fuel])
	_check(f0 - ship.fuel > 0.0001, "rolling costs fuel too")

	print("\nRCS FUEL PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
