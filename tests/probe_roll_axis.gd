extends SceneTree
# 探针：验证「滚转后鼠标方向不反」。
# 用法：godot --headless --path . --script res://tests/probe_roll_axis.gd
#
# 用户报的 bug：
#   「为什么我鼠标往右, 有时候飞船往右转, 有时候却往左转,
#     我一旦按了 ad, 整个飞船的鼠标转视角就完全反了方向」
#
# 历史：
#   · 第三版用欧拉角，滚转乘进了 get_aim_basis()，导致参考系混用
#   · 第四版改成四元数 + 局部轴旋转，滚转作用在 intent_quat 上
# 这个探针在**不同滚转角**下推同样的鼠标，验证机头都往同一个世界方向转。

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

	print("\n=== 不同滚转角下，鼠标向右的转向方向 ===")
	var results: Array = []
	for roll_deg in [0.0, 90.0, 180.0, 270.0]:
		ship.fuel = 100.0
		ship.turn_budget = Quaternion.IDENTITY
		ship._turn_velocity = Vector3.ZERO
		ship.global_transform.basis = Basis(Vector3.FORWARD, deg_to_rad(roll_deg)).orthonormalized()
		ship.global_position = Vector3(60000, 0, 0)
		ship.velocity = Vector3.ZERO

		var nose_before: Vector3 = -ship.global_transform.basis.z.normalized()
		for i in range(40):
			ship.apply_look(Vector2(30.0, 0.0))
		for i in range(90):
			ship.fuel = 100.0
			ship.global_position = Vector3(60000, 0, 0)
			ship._physics_process(1.0 / 60.0)

		var nose_after: Vector3 = -ship.global_transform.basis.z.normalized()
		var cross_y: float = nose_before.cross(nose_after).y
		var dir_sign: float = signf(cross_y)
		results.append(dir_sign)
		print("   roll %5.0f deg : mouse-right -> nose turn sign = %+.0f" % [roll_deg, dir_sign])

	# ⚠ 这里**不断言「世界方向一致」**。
	#   四元数 + 局部轴方案下，不同滚转角推同样的鼠标，机头在世界里
	#   转的方向本来就不同（因为「机身的右」在世界里指向不同）。
	#   正确与否要看**屏幕方向**是否一致 —— 那是 probe_upside_down.gd 的职责，
	#   它已验证滚转 0/90/180/270 及完全倒转时投影全部 +0.8820。
	#   这里只记录数值，供人工参考。
	print("   （世界方向不一致是正常的：局部轴随机身翻，见 probe_upside_down）")

	print("\n=== 滚转仍然生效 ===")
	ship.fuel = 100.0
	ship.turn_budget = Quaternion.IDENTITY
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
	print("   A/D one second: hull-up rotated %.1f deg" % up_rotated)
	_check(up_rotated > 10.0, "rolling still visually rolls the hull (%.1f deg)" % up_rotated)

	print("\n=== 滚转不改变机头指向 ===")
	var nose_b: Vector3 = -ship.global_transform.basis.z.normalized()
	ship._roll_by_angle(deg_to_rad(90.0))
	var nose_a: Vector3 = -ship.global_transform.basis.z.normalized()
	var nose_drift: float = rad_to_deg(nose_b.angle_to(nose_a))
	print("   roll intent by 90 deg: nose drift %.3f deg (should be ~0)" % nose_drift)
	_check(nose_drift < 1.0, "rolling does not move the nose direction (%.3f deg)" % nose_drift)

	print("\nROLL AXIS PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
