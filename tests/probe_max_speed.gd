extends SceneTree
# 探针：烧光全部燃料，实测能加速到多少速度。
#
# 用户问：「现在最快多少速度，假如用完全部燃料」
#
# 理论推算（燃料 100 / 无重力）：
#   普通推进 W      : 推力 72 m/s²，耗油 0.45/s
#                     → Δv = 72 / 0.45 = 160 m/s 每单位燃料 → 100 × 160 = 16000 m/s
#   加力推进 W+Shift: 推力 150 m/s²，耗油 1.6/s
#                     → Δv = 150 / 1.6 = 93.75 m/s 每单位燃料 → 100 × 93.75 = 9375 m/s
#   （反直觉但正确：加力推力大，但比冲低，总 Δv 反而更少）
#
# 实测要排除重力/黑洞干扰，所以放在远离一切天体的位置。
var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _burn(ship, boost: bool, far: Vector3) -> Dictionary:
	ship.fuel = 100.0
	ship.velocity = Vector3.ZERO
	ship.global_position = far
	ship.global_transform.basis = Basis.IDENTITY
	ship.turn_budget = Quaternion.IDENTITY
	ship.landed = false
	ship.docked = false
	ship.autopilot = false

	Input.action_press("move_forward")
	if boost:
		Input.action_press("jetpack")
	var frames := 0
	# 上限 40000 帧（约 666 秒）足够烧完 100 燃料
	while ship.fuel > 0.0 and frames < 40000:
		# ⚠ 把位置钉住：只量速度累积，不让它飞出太阳系或撞到东西
		ship.global_position = far
		ship._physics_process(1.0 / 60.0)
		frames += 1
	Input.action_release("move_forward")
	if boost:
		Input.action_release("jetpack")
	return {
		"speed": ship.velocity.length(),
		"seconds": frames / 60.0,
		"fuel_left": ship.fuel,
	}


func _run() -> void:
	var save := "user://starward_maxspeed.json"
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
	# 放得很远，把重力降到可忽略
	var far := Vector3(600000, 0, 0)

	print("常量：普通推力 %.0f m/s²/耗油 %.2f/s ；加力 %.0f m/s²/耗油 %.2f/s" % [
		ship.SHIP_THRUST, 0.45, ship.SHIP_BOOST_THRUST, 1.6])

	var normal := _burn(ship, false, far)
	print("\n普通推进（W）：")
	print("   烧完 100 燃料用 %.1f 秒，末速 %.0f m/s（理论 16000）" % [
		normal["seconds"], normal["speed"]])
	print("   每单位燃料获得 %.1f m/s（理论 160.0）" % (float(normal["speed"]) / 100.0))

	var boosted := _burn(ship, true, far)
	print("\n加力推进（W+Shift）：")
	print("   烧完 100 燃料用 %.1f 秒，末速 %.0f m/s（理论 9375）" % [
		boosted["seconds"], boosted["speed"]])
	print("   每单位燃料获得 %.1f m/s（理论 93.75）" % (float(boosted["speed"]) / 100.0))

	# 断言：实测与理论相符（允许 3% 误差）
	if absf(float(normal["speed"]) - 16000.0) < 480.0:
		print("PASS  普通推进末速与理论一致")
	else:
		failures += 1
		print("FAIL  普通推进末速 %.0f，理论 16000" % normal["speed"])
	if absf(float(boosted["speed"]) - 9375.0) < 300.0:
		print("PASS  加力末速与理论一致")
	else:
		failures += 1
		print("FAIL  加力末速 %.0f，理论 9375" % boosted["speed"])
	if float(normal["speed"]) > float(boosted["speed"]):
		print("PASS  普通推进总 Δv 反而更大（比冲更高）")
	else:
		failures += 1
		print("FAIL  普通推进应比加力总 Δv 更大")

	print("\nMAX SPEED PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
