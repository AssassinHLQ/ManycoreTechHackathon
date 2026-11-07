extends SceneTree

var game
var review_camera: Camera3D
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _physics(count: int) -> void:
	for i in range(count):
		await physics_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://captures/" + name + ".png"
	var result := image.save_png(path)
	print("PLAY CAPTURE ", path, " -> ", error_string(result))


func _place_player(station: Node3D, local_position: Vector3, look_local: Vector3) -> void:
	var world_position: Vector3 = station.to_global(local_position)
	var look_target: Vector3 = station.to_global(look_local)
	var direction := (look_target - world_position).normalized()
	game.player.global_transform = Transform3D(Basis.looking_at(direction, station.up_direction()), world_position)
	game.player.camera.rotation = Vector3.ZERO
	game.player.velocity = Vector3.ZERO


func _run() -> void:
	var test_save := "user://starward_play_check.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	await _physics(10)
	var station: Node3D = game.station
	_check(station != null and station.orbit_planet != null, "station is orbiting a planet")
	var orbit_start: Vector3 = station.global_position

	# 走到飞船旁，按 E 登船，再用 Space 起飞（真实交互路径）。
	game.player.global_position = game.ship.global_position + Vector3.UP * 2.0
	await _physics(4)
	game._interact()
	_check(game.state == "ship", "player boards the ship with the interact action")
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await _physics(12)
	_check(not game.ship.landed, "ship takes off with the jump action")

	# 模拟已经飞到站点附近，随后用真实的推进/制动键接近并自动对接。
	game.ship.global_position = station.docking_point() + station.up_direction() * 120.0
	game.ship.velocity = Vector3.ZERO
	game.ship.landed = false
	game.ship.autopilot = false
	game.ship.hull = 100.0
	game.ship.fuel = 100.0
	var aim: Vector3 = station.docking_point()
	game.ship.look_at(aim, station.dock_up_direction())
	game.ship.camera.current = true
	await _physics(4)
	game.ship.velocity = game.ship.station_velocity
	await _frames(3)
	await _capture("play_station_approach")

	var dock_frames := 0
	while not game.ship.docked and dock_frames < 720:
		var port: Vector3 = station.docking_point()
		var offset: Vector3 = port - game.ship.global_position
		var distance: float = offset.length()
		game.ship.look_at(port, station.dock_up_direction())
		var desired_speed := clampf(distance * 0.4, 5.0, 12.0)
		var desired_velocity: Vector3 = game.ship.station_velocity + offset.normalized() * desired_speed
		var along: float = (desired_velocity - game.ship.velocity).dot(offset.normalized())
		if distance > 26.0 and along > 0.8:
			Input.action_press("move_forward")
			Input.action_release("brake")
		elif along < -0.8:
			Input.action_press("brake")
			Input.action_release("move_forward")
		else:
			Input.action_release("move_forward")
			Input.action_release("brake")
		if dock_frames % 120 == 0:
			print("DOCK TRY ", dock_frames, " dist=", distance, " speed=", game.ship.velocity.length(), " rel=", (game.ship.velocity - game.ship.station_velocity).length())
		await physics_frame
		dock_frames += 1
	Input.action_release("move_forward")
	Input.action_release("brake")
	await _physics(4)
	_check(game.ship.docked, "ship docks at the moving station")
	_check(dock_frames < 720, "docking happens without a long manual search")
	await _frames(4)
	await _capture("play_station_docked")

	# 真实交互：E 进站。
	game._interact()
	await _physics(6)
	_check(game.in_station and game.state == "walk", "player enters the station through the airlock")
	await _frames(3)
	await _capture("play_station_hub")

	# 绕过中央升降梯：先向前离开梯井，再横移到 A 门中线，最后走进走廊。
	Input.action_press("move_forward")
	await _physics(120)
	Input.action_release("move_forward")
	Input.action_press("move_left")
	await _physics(42)
	Input.action_release("move_left")
	Input.action_press("move_forward")
	await _physics(150)
	Input.action_release("move_forward")
	var walk_local: Vector3 = station.to_local(game.player.global_position)
	_check(walk_local.x > 35.0 and station.active_corridor == 0, "player walks through the opening hub door into corridor A")
	await _frames(3)
	await _capture("play_station_corridor")

	# 走到观景窗边看真实外景。
	_place_player(station, Vector3(51.0, -1.95, -4.0), Vector3(51.0, 0.9, -12.0))
	await _frames(6)
	await _capture("play_station_window")

	# 大厅与舰桥。
	_place_player(station, Vector3(145.0, -1.95, 0.0), Vector3(130.0, 0.9, -10.5))
	await _frames(6)
	await _capture("play_station_hall")
	_place_player(station, Vector3(245.0, -1.95, 0.0), Vector3(256.0, 1.0, 0.0))
	await _frames(6)
	await _capture("play_station_bridge")

	# 回到气闸，真实交互返回飞船并脱离对接。
	game.player.global_position = station.airlock_position() + station.global_transform.basis.x.normalized() * 1.0
	await _physics(3)
	game._interact()
	await _physics(4)
	_check(not game.in_station and game.state == "ship", "player returns to the docked ship via the airlock console")
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await _physics(10)
	_check(not game.ship.docked, "ship undocks with the jump action")

	# 手动飞一段并看连续外环；随后故意撞环，确认碰撞与船体伤害。
	game.ship.global_position = station.to_global(Vector3(420.0, 80.0, 420.0))
	game.ship.velocity = Vector3.ZERO
	game.ship.look_at(station.docking_point(), station.up_direction())
	game.ship.camera.current = true
	await _frames(4)
	await _capture("play_station_flyby")

	game.ship.hull = 100.0
	station.set_process(false)
	game.ship.global_position = station.to_global(Vector3(350.0, 0.0, 0.0))
	game.ship.velocity = (station.global_position - game.ship.global_position).normalized() * 65.0
	game.ship.look_at(station.global_position, station.up_direction())
	await _physics(90)
	var hull_local: Vector3 = station.to_local(game.ship.global_position)
	_check(Vector2(hull_local.x, hull_local.z).length() > 287.0, "ship is stopped by the continuous ring instead of passing through")
	_check(game.ship.hull < 100.0, "ring impact costs hull integrity")
	await _frames(4)
	await _capture("play_station_ring_bump")
	station.set_process(true)

	# 站点在整段实机流程中确实移动了。
	var orbit_end: Vector3 = station.global_position
	_check(orbit_start.distance_to(orbit_end) > 5.0, "station moves along its orbit during the playthrough")
	print("PLAY CHECK COMPLETE: ", failures, " failure(s), docking frames=", dock_frames)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0 if failures == 0 else 1)
