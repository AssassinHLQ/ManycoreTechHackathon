extends SceneTree
# 探针：验证鼠标**能自由转**（不被困住）+ 飞船最终精确停在目标朝向。
#
# 历史背景：用户先后报过
#   「鼠标被局限在一个圆内根本转不出去」
#   「鼠标转不动了」
#   「拖动很长一大段还是会突然回弹」
# 这个探针专门盯这几件事。
#
# ⚠ 现在没有俯仰限制了（局部轴旋转不会万向节死锁，限制反而造成「转不出去」），
#   所以旧断言「pitch 不超过 89°」已经删掉。
#   度量方式也换成「初始前向与目标前向的夹角」，避免欧拉角分解在
#   大角度下的象限跳变（旧版读 intent.get_euler() 会得到误导性的 74°）。
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


func _reset(ship) -> void:
	ship.fuel = 100.0
	ship.turn_budget = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY


func _aim_forward(ship) -> Vector3:
	return -ship.get_aim_basis().z.normalized()


func _run() -> void:
	var save := "user://starward_turnrange.json"
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

	# ── 1. 横推能转很远 ──
	print("\n=== 1. 横推能转多远 ===")
	_reset(ship)
	for i in range(100):
		ship.apply_look(Vector2(40.0, 0.0))
	var yaw_deg := rad_to_deg(Vector3.FORWARD.angle_to(_aim_forward(ship)))
	print("   横推 4000px -> 目标转了 %.1f 度" % yaw_deg)
	_check(yaw_deg > 60.0, "horizontal drag turns the aim a lot (%.0f deg)" % yaw_deg)

	# ── 2. 继续推能继续转（不被困住）──
	print("\n=== 2. 能连续转（不被困住） ===")
	# 每推一段就跑几帧让飞船消费掉待转量，模拟真实「边推边转」
	# ⚠ 累加**飞船机头**的每轮转角，不要累加「目标前向」——
	#   目标会绕圈，angle_to 永远返回小于 180° 的夹角，累加会失真。
	_reset(ship)
	var total := 0.0
	var prev_nose: Vector3 = -ship.global_transform.basis.z.normalized()
	for round in range(12):
		for i in range(20):
			ship.apply_look(Vector2(40.0, 0.0))
		for i in range(20):
			ship.fuel = 100.0
			ship.global_position = Vector3(70000, 0, 0)
			ship._physics_process(1.0 / 60.0)
		var now_nose: Vector3 = -ship.global_transform.basis.z.normalized()
		total += rad_to_deg(prev_nose.angle_to(now_nose))
		prev_nose = now_nose
	print("   分 12 轮边推边转：飞船累计转过 %.1f 度" % total)
	_check(total > 200.0, "the ship keeps turning round after round (%.0f deg)" % total)

	# ── 3. 纵向也能大幅俯仰 ──
	print("\n=== 3. 纵推能大幅俯仰 ===")
	_reset(ship)
	for i in range(100):
		ship.apply_look(Vector2(0.0, -40.0))
	var pitch_deg := rad_to_deg(Vector3.FORWARD.angle_to(_aim_forward(ship)))
	print("   上推 4000px -> 目标俯仰 %.1f 度" % pitch_deg)
	_check(pitch_deg > 60.0, "vertical drag pitches the aim a lot (%.0f deg)" % pitch_deg)

	# ── 4. 正反推动可逆 ──
	print("\n=== 4. 等量正反推动可逆 ===")
	_reset(ship)
	for i in range(30):
		ship.apply_look(Vector2(25.0, 0.0))
	for i in range(30):
		ship.apply_look(Vector2(-25.0, 0.0))
	var back_deg := rad_to_deg(Vector3.FORWARD.angle_to(_aim_forward(ship)))
	print("   右推 750px 再左推 750px -> 偏了 %.3f 度（应约 0）" % back_deg)
	_check(back_deg < 1.0, "equal opposite input returns to the start (%.3f deg)" % back_deg)

	# ── 5. 飞船精确收敛到目标，不过冲 ──
	print("\n=== 5. 飞船收敛到目标且不过冲 ===")
	# ⚠ 度量方式：转的是**纯偏航**（绕世界 +Y 90°），所以直接量机头的偏航角，
	#   看它是否单调走到 90° 且**永不越过**。
	#   旧版用「机头与目标方向的夹角」当偏差 —— 起始时它本来就是 90°，
	#   会被误报成「过冲 88°」。
	_reset(ship)
	ship.turn_budget = Quaternion(Vector3.UP, deg_to_rad(90.0))
	var max_yaw := -999.0
	for i in range(240):
		ship.fuel = 100.0
		ship.global_position = Vector3(70000, 0, 0)
		ship._physics_process(1.0 / 60.0)
		var nose: Vector3 = -ship.global_transform.basis.z.normalized()
		# 偏航角：机头朝 -Z 时是 0，绕 +Y 转 90° 后读作 +90°
		var yaw := rad_to_deg(-atan2(nose.x, -nose.z))
		max_yaw = maxf(max_yaw, yaw)
	var final_yaw := rad_to_deg(
		-atan2((-ship.global_transform.basis.z.normalized()).x,
		       -(-ship.global_transform.basis.z.normalized()).z))
	print("   转 90 度：机头最大偏航 %.3f 度，最终 %.3f 度" % [max_yaw, final_yaw])
	_check(absf(final_yaw - 90.0) < 0.5, "the ship lands exactly on 90 deg (%.3f)" % final_yaw)
	_check(max_yaw < 90.5, "and never overshoots past it (max %.3f)" % max_yaw)

	print("\nTURN RANGE PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
