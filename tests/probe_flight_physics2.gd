extends SceneTree
# 探针：验证本次四条改动。
# 用法：godot --headless --path . --script res://tests/probe_flight_physics2.gd
#
#   1. S 是制动，不是倒车（飞船不能朝后飞）
#   2. 没有 700 的人造上限 —— 持续加速能超过 700
#   3. 制动键绑到了 S
#   4. HUD 标签有遮挡检测函数

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
	var save := "user://starward_physics2.json"
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
	ship.global_position = Vector3(30000, 0, 0)
	ship.velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	ship.turn_budget = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO

	# ── 1. S 不再倒车 ──
	print("\n=== 1. S 不能倒车 ===")
	ship.velocity = Vector3.ZERO
	Input.action_press("move_back")
	for i in range(120):     # 2 秒
		ship.fuel = 100.0
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_back")
	var fwd: Vector3 = -ship.global_transform.basis.z.normalized()
	var back_component: float = ship.velocity.dot(-fwd)
	print("   按住 S 两秒：速度 %.2f m/s，向后分量 %.2f" % [ship.velocity.length(), back_component])
	_check(back_component < 1.0, "pressing S does not push the ship backwards (back=%.2f)" % back_component)

	# ── 2. 没有 700 上限 ──
	print("\n=== 2. 持续加速能超过 700 ===")
	ship.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	Input.action_press("jetpack")
	for i in range(600):     # 10 秒全力加力
		ship.fuel = 100.0
		# ⚠ 每帧把位置钉回原处：否则飞船会飞出太阳系 / 撞上行星，
		#    本探针只想量「速度能累积多快」，不想让它在途中被碰撞逻辑干扰。
		ship.global_position = Vector3(30000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	Input.action_release("jetpack")
	var v: float = ship.velocity.length()
	print("   加力 10 秒后速度 = %.1f m/s（无任何速度上限）" % v)
	_check(v > 700.0, "the ship can accelerate past the old 700 limit (%.0f)" % v)
	# ⚠ 断言改成「没有上限」：连续加力 30 秒速度应继续显著增长。
	#   旧版这里断言 v <= SHIP_SPEED_SAFETY_CAP —— 但那个上限已被用户要求删除。
	var v10 := v
	Input.action_press("move_forward")
	Input.action_press("jetpack")
	for i in range(1200):     # 再 20 秒
		ship.fuel = 100.0
		ship.global_position = Vector3(30000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	Input.action_release("jetpack")
	var v30: float = ship.velocity.length()
	print("   再加速 20 秒 → %.1f m/s（应继续增长，没有封顶）" % v30)
	_check(v30 > v10 * 1.5, "there is no speed ceiling at all (%.0f -> %.0f)" % [v10, v30])

	# ── 3. 制动键是 S ──
	print("\n=== 3. 制动绑到 S ===")
	_check(InputMap.action_has_event("brake", _key_event(KEY_S)), "brake is bound to the S key")
	_check(InputMap.action_has_event("brake", _key_event(KEY_X)), "brake still accepts X as a backup")

	# ── 4. S 能制动 ──
	print("\n=== 4. 按 S 真的减速 ===")
	ship.velocity = -ship.global_transform.basis.z * 300.0
	var before: float = ship.velocity.length()
	Input.action_press("brake")
	for i in range(60):
		ship.fuel = 100.0
		ship._physics_process(1.0 / 60.0)
	Input.action_release("brake")
	var after: float = ship.velocity.length()
	print("   按 S 一秒：%.0f -> %.0f m/s" % [before, after])
	_check(after < before * 0.6, "S actually brakes the ship (%.0f -> %.0f)" % [before, after])

	# ── 5. HUD 有遮挡检测 ──
	print("\n=== 5. HUD 标签遮挡检测 ===")
	_check(game.hud.drawing.has_method("_is_occluded"), "the HUD painter has an occlusion check")

	print("\nFLIGHT PHYSICS 2 PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)


func _key_event(keycode: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	return ev
