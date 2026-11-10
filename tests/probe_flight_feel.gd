extends SceneTree
# 探针：量「战斗机手感」是否真的成立 —— 用数值验证，不靠感觉。
# 用法：godot --headless --path . --script res://tests/probe_flight_feel.gd
#
# 检查四件事：
#   1. 松开油门后速度是否真的衰减（旧版是永不衰减 = 「平移」的根因）
#   2. 转向后速度矢量是否跟着机头转（而不是笔直飘）
#   3. 按住前进时速度上限是否生效
#   4. 没推力时尾焰是否完全隐藏
#
# ⚠ 这些都用 _physics_process 直接驱动，不开窗口。

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
	var save := "user://starward_feel.json"
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
	# 挪到远离行星的地方，避免重力干扰
	ship.global_position = Vector3(20000, 0, 0)
	ship.velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY

	# ── 1. 松开油门后**不减速**（真实太空：不受外力就匀速直线运动）──
	print("\n=== 1. 松油门后保持匀速 ===")
	ship.velocity = -ship.global_transform.basis.z * 200.0
	var v0: float = ship.velocity.length()
	for i in range(60):                     # 1 秒
		ship._physics_process(1.0 / 60.0)
	var v1: float = ship.velocity.length()
	print("   1 秒后速度 %.2f → %.2f m/s（应当几乎不变）" % [v0, v1])
	_check(absf(v1 - v0) < 2.0, "releasing throttle keeps the speed constant in vacuum (%.1f -> %.1f)" % [v0, v1])

	# ── 2. 转向后速度跟着机头 ──
	print("\n=== 2. 转向后速度对齐机头 ===")
	ship.velocity = -ship.global_transform.basis.z * 150.0
	# 把船转 90 度
	ship.global_transform.basis = Basis(Vector3.UP, deg_to_rad(90.0))
	for i in range(90):
		ship._physics_process(1.0 / 60.0)
	var fwd: Vector3 = -ship.global_transform.basis.z.normalized()
	var dot: float = ship.velocity.normalized().dot(fwd) if ship.velocity.length() > 1.0 else 0.0
	print("   转向后 速度方向·机头 = %.3f（1.0 = 完全对齐）" % dot)
	_check(dot > 0.8, "after turning, velocity aligns with the nose (dot=%.2f)" % dot)

	# ── 3. 速度上限 ──
	print("\n=== 3. 前进速度上限 ===")
	ship.velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	Input.action_press("move_forward")
	for i in range(600):                    # 10 秒全力推进
		ship.fuel = 100.0
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var vmax: float = ship.velocity.length()
	print("   10 秒后速度 = %.1f m/s（上限 %.0f）" % [vmax, ship.SHIP_MAX_SPEED])
	_check(vmax <= ship.SHIP_MAX_SPEED + 1.0, "the ship cannot exceed its top speed")

	# ── 4. 没推力时尾焰隐藏 ──
	print("\n=== 4. 无推力时尾焰 ===")
	ship.velocity = Vector3.ZERO
	ship.thrust_level = 0.0
	for i in range(30):
		ship._physics_process(1.0 / 60.0)
	var visible_plumes := 0
	for p in ship.engine_plumes:
		if (p as Node3D).visible:
			visible_plumes += 1
	print("   engine_plumes = %d，可见 = %d" % [ship.engine_plumes.size(), visible_plumes])
	_check(ship.engine_plumes.size() > 0, "the ship has exhaust plumes")
	_check(visible_plumes == 0, "with no thrust the exhaust is fully hidden")

	# 推进时应该出现
	Input.action_press("move_forward")
	for i in range(20):
		ship.fuel = 100.0
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var firing := 0
	for p in ship.engine_plumes:
		if (p as Node3D).visible:
			firing += 1
	print("   推进时可见 = %d" % firing)
	_check(firing == ship.engine_plumes.size(), "under thrust every plume is visible")

	print("\nFLIGHT FEEL PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
