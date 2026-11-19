extends SceneTree
# 验证脚本（临时，不进仓库）：
#   确认 smoke_test 那 3 条 FAIL 是「多阶段降落」改造后测试没跟上，
#   而不是本次尾焰/滚轮/修理/氧气改动引入的。
#
# 做法：完全复刻 smoke_test 的第 367-373 行，但**多跑若干帧 _process_landing**，
# 看 landed 会不会变 true、exit_ship 会不会生效。
#
# 用法：
#   godot --headless --path . --script res://tests/_verify_landing_stages.gd

var game
var failures := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		failures += 1
		print("FAIL  ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://verify_landing_stages.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	# ── 复刻 smoke_test 367-370 ──
	game.state = "ship"
	game.ship.landed = false
	game.ship.land_phase = 0
	game.ship.global_position = game.home.global_position + game.home.surface_position(Vector3.UP, 20.0)
	game.ship.velocity = Vector3.ZERO
	game.ship.try_land()
	print("--- try_land 之后立刻检查 ---")
	_check(game.ship.landed, "try_land 后立刻 landed（旧版测试的期望）")
	print("    land_phase = %d（0=NONE 1=APPROACH 2=FLARE 3=TOUCHDOWN）" % game.ship.land_phase)

	# ── 跑降落阶段：每帧调 _physics_process，最多 900 帧 ──
	print("--- 开始逐帧推进 _process_landing（最多 900 帧）---")
	var frames := 0
	while frames < 900 and not game.ship.landed:
		game.ship._physics_process(1.0 / 60.0)
		frames += 1
	print("    用了 %d 帧（%.1f 秒 @60fps）" % [frames, frames / 60.0])
	print("    最终 land_phase = %d, landed = %s" % [game.ship.land_phase, str(game.ship.landed)])
	_check(game.ship.landed, "跑完多阶段降落后 landed 变 true")

	if game.ship.landed:
		# ── 下船 ──
		game.exit_ship()
		_check(game.state == "walk" and game.player.visible, "player exits landed ship（跑完降落后）")

	# ── 燃料三条：这些跟降落无关，单独验 ──
	# ⚠ 必须先把 landed 置回 false：_physics_process 的 landed 分支在最前面
	#   return，不然 brake / autopilot 的代码根本走不到。
	game.state = "ship"
	game.ship.landed = false
	game.ship.docked = false
	game.ship.land_phase = 0
	game.ship.velocity = Vector3(100.0, 0.0, 0.0)
	game.ship.fuel = 50.0
	Input.action_press("brake")
	game.ship._physics_process(0.1)
	Input.action_release("brake")
	_check(game.ship.fuel < 49.95 and game.ship.velocity.length() < 100.0,
		"manual brake burns propellant")

	game.ship.velocity = Vector3.ZERO
	game.ship.target = game.planets[0]
	game.ship.autopilot = true
	game.ship.fuel = 0.0
	game.ship._physics_process(0.1)
	_check(not game.ship.autopilot, "autopilot stops when the tank is empty")

	game.ship.fuel = 0.0
	game.ship.fuel_empty_time = 89.5
	game.ship.landed = false
	game.ship.land_phase = 0
	game.ship._physics_process(1.0)
	_check(game.state == "dying" and game.death_reason.find("推进剂") >= 0,
		"fuel exhaustion ends the expedition")

	print("")
	print("VERIFY COMPLETE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
