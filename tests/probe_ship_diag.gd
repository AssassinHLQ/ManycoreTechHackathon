extends SceneTree
# 探针：核对飞船的三个问题
#   1. 实际尺寸 vs 玩家身高
#   2. 第三人称停在**着陆状态**时鼠标能不能绕船转（「平移」感）
#   3. 外部模型下 engine_materials 是不是空的（没有尾焰）
# 用法：godot --headless --path . --script res://tests/probe_ship_diag.gd

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


func _drag(ship, dx: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, 0.0)
	ship.apply_look(ev.relative)


func _run() -> void:
	var save := "user://starward_diag.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for i in range(10):
		await physics_frame
	game.start_game()
	for i in range(10):
		await physics_frame

	var ship = game.ship
	var player = game.player
	print("=== 1. 尺寸 ===")
	print("  飞船 长=%.2f 翼展=%.2f 高=%.2f" % [ship.ship_model_length, ship.ship_model_span, ship.ship_model_height])
	print("  玩家胶囊身高 1.65 m")
	print("  机高/玩家身高 = %.2f" % (ship.ship_model_height / 1.65))
	_check(ship.ship_model_height > 1.65, "机高应当高于玩家身高")

	print("\n=== 2. 着陆状态下第三人称能不能绕船转 ===")
	game.state = "ship"
	player.visible = false
	ship.camera.current = true
	ship.landed = true
	ship.toggle_third_person()
	var yaw0: float = ship.orbit_yaw
	var pitch0: float = ship.orbit_pitch
	_drag(ship, 60.0)
	print("  着陆时拖动后 yaw: %.4f -> %.4f" % [yaw0, ship.orbit_yaw])
	_check(absf(ship.orbit_yaw - yaw0) > 0.001, "landed: dragging the mouse orbits the camera")

	print("\n=== 3. 飞行状态下第三人称能不能绕船转 ===")
	ship.landed = false
	var yaw1: float = ship.orbit_yaw
	_drag(ship, 60.0)
	print("  飞行时拖动后 yaw: %.4f -> %.4f" % [yaw1, ship.orbit_yaw])
	_check(absf(ship.orbit_yaw - yaw1) > 0.001, "flying: dragging the mouse orbits the camera")

	print("\n=== 4. 尾焰 ===")
	ship.landed = true
	print("  engine_materials = %d 个" % ship.engine_materials.size())
	print("  engine_lights    = %d 个" % ship.engine_lights.size())
	_check(ship.engine_materials.size() > 0, "the ship has engine glow materials")
	_check(ship.engine_lights.size() > 0, "the ship has engine lights")

	print("\nDIAG: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	quit(0)
