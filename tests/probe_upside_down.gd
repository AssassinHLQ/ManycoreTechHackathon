extends SceneTree
# 探针：验证「飞船倒转后，鼠标往右仍然往右」。
# 用法：godot --headless --path . --script res://tests/probe_upside_down.gd
#
# 用户报的 bug（第四次）：
#   「不行, 飞船倒转过来, 还是不能鼠标左右自由滑动」
#
# 前三版用欧拉角（yaw 绕世界 Y），根本问题是：
#   · 欧拉角默认「世界 Y 就是上」
#   · 飞船倒转 180° 后，玩家眼里的「左」是世界的「右」
#   · 但 yaw 仍绕世界 Y 转 → 鼠标往右、画面往左
#
# 现在用四元数 + **局部轴**增量旋转（绕自身 UP / RIGHT），局部轴随飞船翻。
# 这个探针在**各种翻滚姿态**下推同样的鼠标，验证**屏幕方向**一致。
#
# 判断「屏幕方向」的方法：
#   相机是飞船子节点，相机的前向 = 机头、相机的 up = 机身 up。
#   鼠标往右，机头应该朝**相机的 right** 方向偏（也就是屏幕右）。
#   所以量：nose_after 相对 nose_before 的旋转，在 camera-right 上的投影。

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
	var save := "user://starward_upsidedown.json"
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
	ship.global_position = Vector3(70000, 0, 0)
	ship.velocity = Vector3.ZERO

	# 构造各种「翻滚姿态」：绕机头轴滚 0/90/180/270
	var roll_angles: Array = [0.0, 90.0, 180.0, 270.0]
	var signs: Array = []

	print("\n=== 各种翻滚姿态下，鼠标向右 = 屏幕向右？ ===")
	for roll_deg in roll_angles:
		ship.fuel = 100.0
		ship.turn_budget = Quaternion.IDENTITY
		ship._turn_velocity = Vector3.ZERO
		ship.global_transform.basis = Basis.IDENTITY
		# 用 _roll_by_angle 造出翻滚姿态
		ship._roll_by_angle(deg_to_rad(roll_deg))
		# 让实际姿态追上 intent
		var target_q: Quaternion = ship.turn_budget
		ship.global_transform.basis = Basis(target_q).orthonormalized()
		ship._turn_velocity = Vector3.ZERO
		ship.global_position = Vector3(70000, 0, 0)
		ship.velocity = Vector3.ZERO

		# 记录推鼠标之前的机头，和**相机的 right 方向**
		var nose_before: Vector3 = -ship.global_transform.basis.z.normalized()
		var cam_right_before: Vector3 = ship.global_transform.basis.x.normalized()

		# 鼠标往右推
		for i in range(30):
			ship.apply_look(Vector2(40.0, 0.0))
		# 让飞船追上去
		for i in range(120):
			ship.fuel = 100.0
			ship.global_position = Vector3(70000, 0, 0)
			ship._physics_process(1.0 / 60.0)

		var nose_after: Vector3 = -ship.global_transform.basis.z.normalized()
		# 机头的位移方向（去掉沿原机头的分量）
		var delta: Vector3 = nose_after - nose_before
		delta -= nose_before * delta.dot(nose_before)
		# 这个位移在「原相机 right」上的投影：>0 表示朝屏幕右
		var proj: float = delta.dot(cam_right_before)
		signs.append(signf(proj))
		print("   滚转 %3.0f°：机头偏移在屏幕右方向上的投影 = %+.4f" % [roll_deg, proj])

	var all_same := true
	for sg in signs:
		if sg != signs[0]:
			all_same = false
	_check(all_same, "mouse-right always turns the nose toward screen-right, at every roll angle")
	_check(signs.size() == 4 and signs[0] > 0.0,
		"and that direction is screen-right (not left)")

	# ── 上下颠倒 + 鼠标左右 ──
	print("\n=== 完全倒过来（绕右轴翻 180°）后，鼠标往右 ===")
	ship.fuel = 100.0
	ship.turn_budget = Quaternion.IDENTITY   # 翻过来
	ship.global_transform.basis = Basis(Quaternion(Vector3.RIGHT, PI))
	ship._turn_velocity = Vector3.ZERO
	var nose_b: Vector3 = -ship.global_transform.basis.z.normalized()
	var cam_right_b: Vector3 = ship.global_transform.basis.x.normalized()
	for i in range(30):
		ship.apply_look(Vector2(40.0, 0.0))
	for i in range(120):
		ship.fuel = 100.0
		ship.global_position = Vector3(70000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	var nose_a: Vector3 = -ship.global_transform.basis.z.normalized()
	var d2: Vector3 = nose_a - nose_b
	d2 -= nose_b * d2.dot(nose_b)
	var proj2: float = d2.dot(cam_right_b)
	print("   倒转后：投影 = %+.4f（应 > 0）" % proj2)
	_check(proj2 > 0.0, "even upside down, mouse-right turns toward screen-right (%.4f)" % proj2)

	print("\nUPSIDE DOWN PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
