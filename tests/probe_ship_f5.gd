extends SceneTree
# 探针：F5 第三人称切换的**边界条件**。
# 用法：godot --headless --path . --script res://tests/probe_ship_f5.gd
#
# 为什么需要它：
#   F5 在这个项目里已经被开发者模式占用（解锁全部条目）。
#   需求是「只在飞船才能切换」—— 所以必须钉死三件事：
#     1. 走路时按 F5 **没有任何反应**（不能误触发第三人称）；
#     2. 开着开发者模式时 F5 仍然是开发者功能（不能被抢走）；
#     3. 只有在 state == "ship" 时才切。

var game
var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		print("FAIL  ", message)


func _initialize() -> void:
	call_deferred("_run")


func _f5() -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.pressed = true
	return key


func _run() -> void:
	var save := "user://starward_f5_probe.json"
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

	# ── 1. 走路时按 F5：不该有任何反应 ──
	game.state = "walk"
	print("\n=== 走路时按 F5 ===")
	print("  third_person 初始 = ", ship.third_person)
	game._unhandled_input(_f5())
	_check(not ship.third_person, "walking: F5 does not switch to third person")
	_check(not ship.third_person, "walking: third_person flag stays false")

	# ── 2. 开发者模式下 F5 仍然是开发者功能 ──
	print("\n=== 开发者模式下按 F5 ===")
	game.dev_mode = true
	game.discovered.clear()
	var anomalies: int = game.anomalies.size()
	game._unhandled_input(_f5())
	_check(game.discovered.size() == anomalies,
		"dev mode: F5 still unlocks every signal record")
	_check(not ship.third_person, "dev mode: F5 does not steal the third-person toggle")

	# ── 3. 驾驶飞船时按 F5：切第三人称 ──
	print("\n=== 驾驶飞船时按 F5 ===")
	game.dev_mode = false
	game.state = "ship"
	player_hide(game)
	game._unhandled_input(_f5())
	_check(ship.third_person, "in ship: F5 switches to third person")
	var dist: float = ship.camera.position.length()
	_check(dist > 5.0, "in ship: the camera moved outside the hull (%.2f m)" % dist)
	game._unhandled_input(_f5())
	_check(not ship.third_person, "in ship: F5 again switches back to the cockpit")
	# 相对船体尺寸判断，别写死米数 —— 改机长时不会误报。
	_check(ship.camera.position.length() < ship.ship_model_length * 0.5,
		"in ship: the camera returned to the cockpit")

	# ── 4. 暂停时不响应 ──
	print("\n=== 暂停时按 F5 ===")
	game.state = "ship"
	game.paused = true
	game._unhandled_input(_f5())
	_check(not ship.third_person, "paused: F5 does not switch views")
	game.paused = false

	print("\nF5 PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)


func player_hide(g) -> void:
	g.player.visible = false
	g.ship.camera.current = true
