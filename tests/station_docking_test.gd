extends SceneTree
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _approach(station: Node3D, distance: float, speed: float) -> void:
	game.in_station = false
	game.active_station = null
	game.state = "ship"
	game.ship.landed = false
	game.ship.landed_planet = null
	game.ship.docked = false
	game.ship.docked_station = null
	game.ship.dock_cooldown = 0.0
	game.ship.autopilot = false
	game.ship.global_position = station.docking_point() + station.up_direction() * distance
	game.ship.look_at(station.docking_point(), station.dock_up_direction())
	game.ship.velocity = -station.up_direction() * speed
	game.ship._station_motion.clear()
	game.ship._update_station_motion(1.0 / 60.0)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://station_docking_test.json"
	game.progress_path = "user://station_docking_progress_test.json"
	root.add_child(game)
	await game.await_world_ready()
	while game.world_build_remaining: await process_frame
	game.start_game()
	game.set_process(false)
	game.set_physics_process(false)
	game.ship.set_physics_process(false)
	game.player.set_physics_process(false)
	game.station.set_physics_process(false)
	for planet in game.planets: planet.set_physics_process(false)
	await physics_frame
	var ship = game.ship
	ship.velocity = Vector3.RIGHT * ship.LIGHT_SPEED_MPS * 1.01
	ship._clamp_collision_speed()
	_check(ship.velocity.length() <= ship.LIGHT_SPEED_MPS,
		"collision response caps a superluminal velocity at light speed")
	ship.velocity = Vector3.RIGHT * 120.0
	ship._clamp_collision_speed()
	_check(is_equal_approx(ship.velocity.length(), 120.0),
		"collision speed clamp preserves ordinary flight velocity")
	var collision_normal := Vector3.RIGHT
	_check(is_equal_approx(ship._station_normal_impact_speed(Vector3(-5.0, 0.0, 100.0), collision_normal), 5.0),
		"high-speed tangential station pass uses only its 5 m/s normal impact")
	_check(is_equal_approx(ship._station_normal_impact_speed(Vector3(-20.0, 0.0, 100.0), collision_normal), 20.0),
		"direct station impact retains its real 20 m/s normal speed")
	var stations: Array = [game.station]
	stations.append_array(game.distant_stations)
	for station in stations:
		var label: String = station.display_name
		if station.has_method("is_distant_station"):
			_check(game.ship._station_blocked(station.to_global(Vector3(0, station.half_extent.y * 0.5, 0))), label + " collision uses measured tower dimensions")
		_approach(station, 118.0, 4.8)
		var hint: String = game.get_prompt()
		_check(hint.contains(label) and hint.contains("E 对接"), label + " identifies the actual 118 m port and E action")
		game._interact()
		_check(game.ship.docked and game.ship.docked_station == station, label + " E docks at screenshot distance and speed")
		_check(not game.hud.toast.text.contains("地表"), label + " never falls through to planetary landing")
		_check(not game.ship._station_blocked(game.ship.global_position), label + " full-sized hull clears port and pylons")
		game._interact()
		_check(game.in_station and game.active_station == station and game.player.get_parent() == station, label + " next E enters its own interior")
		game.player.global_position = station.airlock_position()
		game._interact()
		_check(not game.in_station and game.state == "ship" and game.ship.docked, label + " airlock returns to the docked ship")
		game.ship.undock()
		_check(not game.ship.docked and game.ship.dock_cooldown > 0.0, label + " undock starts cooldown")
		_check(game.ship.try_dock_nearby() and not game.ship.docked, label + " E cannot undo undock cooldown")
		_approach(station, 150.0, 4.8)
		game._interact()
		_check(not game.ship.docked and game.hud.toast.text.contains("140"), label + " out-of-range interaction explains the actual distance")
		_approach(station, 118.0, 80.0)
		game._interact()
		_check(not game.ship.docked and game.hud.toast.text.contains("相对速度"), label + " fast approaches require braking")
		_approach(station, -80.0, 4.8)
		game._interact()
		_check(not game.ship.docked and game.hud.toast.text.contains("塔顶"), label + " wrong-side approach points to tower top")
		_approach(station, 63.0, 4.8)
		game.ship._physics_process(1.0 / 60.0)
		_check(game.ship.docked and game.ship.docked_station == station, label + " slow approach latches before the bow hits the tower")
	# Relative speed belongs to each target, never the homecoming station's velocity.
	var distant: Node3D = game.distant_stations[0]
	_approach(distant, 118.0, 0.0)
	game.station.global_position += Vector3(1, 0, 0)
	game.ship._update_station_motion(1.0 / 60.0)
	_check(game.ship.station_velocity.length() > 50.0 and game.ship.nearby_docking_status().relative_speed < 0.01, "distant station uses its own relative velocity")
	game._interact()
	_check(game.ship.docked, "moving homecoming station cannot prevent docking elsewhere")
	_approach(game.station, 118.0, 0.0)
	game.station.global_position += Vector3(0.5, 0, 0)
	game.ship._update_station_motion(1.0 / 60.0)
	_check(game.ship.nearby_docking_status().relative_speed > 22.0, "orbital station reports the real relative speed")
	Input.action_press("brake")
	for i in range(15):
		game.station.global_position += Vector3(0.5, 0, 0)
		game.ship._physics_process(1.0 / 60.0)
	Input.action_release("brake")
	_check(game.ship.velocity.distance_to(game.ship.station_port_velocity(game.station)) < 0.5, "X matches the nearby station velocity")
	if game.ship.velocity.distance_to(game.ship.station_port_velocity(game.station)) >= 0.5:
		print("BRAKE DIAGNOSTIC ", game.ship.velocity, " target=", game.ship.station_port_velocity(game.station))
	# Far from every station, E retains the planetary landing path.
	_approach(game.station, 3000.0, 0.0)
	game._interact()
	_check(game.hud.toast.text.contains("地表"), "planetary landing feedback remains available away from stations")
	game.free()
	for path in ["user://station_docking_test.json", "user://station_docking_progress_test.json"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("STATION DOCKING TEST COMPLETE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
