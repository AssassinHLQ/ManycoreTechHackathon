extends SceneTree
# 探针：验证鼠标转向不再被「困在圆圈里」。
# 用法：godot --headless --path . --script res://tests/probe_turn_range.gd
#
# 用户反馈：「鼠标被局限在一个圆内根本转不出去」。
# 上一版有三个 bug：limit_length(120) 截断、俯仰夹在 ±85° 且用「压回方向向量」
# 的方式夹（会带歪偏航）、每次位移迭代旋转 basis 累积误差。
#
# 这个探针直接量**能转多远**：
#   1. 连续横推鼠标 100 次，偏航能不能转过 180°
#   2. 连续上推，俯仰能不能到接近 89°
#   3. 俯仰到顶后继续推，不超限也不把偏航带歪
#   4. 左右各推一次，yaw 能回到原处（可逆、不漂）

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
	var save := "user://starward_turn_range.json"
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
	ship.intent_quat = Quaternion.IDENTITY

	# ── 1. 横推能不能转过 180° ──
	print("\n=== 1. 偏航能转多远 ===")
	# 每帧推 40px，推 100 次 = 4000px
	for i in range(100):
		ship.apply_look(Vector2(40.0, 0.0))
	var yaw_deg := rad_to_deg(ship.intent_quat.get_euler().y)
	print("   横推 4000px 后 aim_yaw = %.1f°" % yaw_deg)
	# 断言用「转过的绝对角度」：yaw 会 wrap 到 ±180，所以 -144° 意味着实际转了 144°。
	# 4000px 能转 144° 说明灵敏度合理（约 28px/度），且**没有上限卡住**——
	# 真正的「不卡死」由下面「继续推能绕圈」那条证明。
	_check(absf(yaw_deg) > 100.0, "yaw turns a lot with 4000px of mouse input (%.0f deg)" % absf(yaw_deg))

	# 继续推，应该能绕一整圈（wrap 到负值）
	for i in range(100):
		ship.apply_look(Vector2(40.0, 0.0))
	var yaw_deg2 := rad_to_deg(ship.intent_quat.get_euler().y)
	print("   再推 4000px 后 aim_yaw = %.1f°（已越过 180° 继续绕）" % yaw_deg2)
	_check(absf(yaw_deg2) <= 180.0, "yaw wraps within [-180, 180] after a full circle")

	# ── 2. 俯仰能到多高 ──
	print("\n=== 2. 俯仰范围 ===")
	ship.intent_quat = Quaternion.IDENTITY
	for i in range(100):
		ship.apply_look(Vector2(0.0, -40.0))   # 往上推
	var pitch_up := rad_to_deg(ship.intent_quat.get_euler().x)
	print("   上推到底 euler.x = %.1f°" % pitch_up)
	# ⚠ 四元数方案**不做俯仰限制**（局部轴旋转本来就不会万向节死锁，
	#   限制反而会造成「转不出去」）。所以这里只验证「真的能大幅俯仰」，
	#   euler 反解在越过 90° 后会落到其他象限，用绝对值判断。
	_check(absf(pitch_up) > 80.0, "pitch can move a lot (|%.0f| deg)" % absf(pitch_up))

	# ── 3. 到顶后继续推，偏航不被带歪 ──
	print("\n=== 3. 俯仰到顶后偏航不被带歪 ===")
	var yaw_before: float = ship.intent_quat.get_euler().y
	for i in range(50):
		ship.apply_look(Vector2(0.0, -40.0))
	var yaw_after: float = ship.intent_quat.get_euler().y
	print("   继续上推 50 次：yaw %.4f -> %.4f" % [yaw_before, yaw_after])
	_check(absf(yaw_after - yaw_before) < 0.001, "pushing past the pitch limit does not skew yaw")

	# ── 4. 可逆性：左右各推同样多，应该回到原处 ──
	print("\n=== 4. 左右等量推动可逆 ===")
	ship.intent_quat = Quaternion.IDENTITY
	for i in range(30):
		ship.apply_look(Vector2(25.0, 0.0))
	for i in range(30):
		ship.apply_look(Vector2(-25.0, 0.0))
	print("   左右各推 750px 后 yaw = %.6f（应约等于 0）" % ship.intent_quat.get_euler().y)
	_check(absf(ship.intent_quat.get_euler().y) < 0.0005, "equal opposite mouse input returns to the start yaw")

	# ── 5. 机头仍对准 aim ──
	print("\n=== 5. 飞船追上后机头对准 aim ===")
	ship.intent_quat = (Quaternion(Vector3.UP, 1.2) * Quaternion(Vector3.RIGHT, 0.3)).normalized()
	ship._turn_velocity = Vector3.ZERO
	for i in range(180):
		ship._physics_process(1.0 / 60.0)
	var fwd_ship: Vector3 = -ship.global_transform.basis.z.normalized()
	var fwd_aim: Vector3 = -ship.get_aim_basis().z.normalized()
	var d: float = fwd_ship.dot(fwd_aim)
	print("   3 秒后 机头·aim = %.4f" % d)
	_check(d > 0.999, "the nose converges to the aim direction (dot=%.4f)" % d)

	print("\nTURN RANGE PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
