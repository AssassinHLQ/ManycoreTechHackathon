extends SceneTree

const KNOWLEDGE := "user://home_gate_test_knowledge.json"
const PROGRESS := "user://home_gate_test_progress.json"
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS  " if ok else "FAIL  ", label)
	if not ok:
		failures += 1

func _cleanup() -> void:
	for path in [KNOWLEDGE, PROGRESS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _run() -> void:
	_cleanup()
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = KNOWLEDGE
	game.progress_path = PROGRESS
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.player.set_physics_process(false)
	game.enter_attic()
	_check(game.state == "menu" and not game.in_attic, "title cannot enter home")
	game.start_game()
	game.player.set_physics_process(false)
	game.enter_attic()
	_check(not game.in_attic, "planetary spawn cannot enter home")
	game.discover("qinglan")
	game.request_attic_visit()
	_check(not game.in_attic, "scanning the windmill does not grant teleportation")
	game.state = "ship"
	game.ship.landed = false
	game.request_attic_visit()
	_check(not game.in_attic, "flight cannot enter home")
	game.ship.landed = true
	game.enter_attic()
	_check(not game.in_attic, "landed cockpit cannot enter home")
	game.ship.landed = false
	game.ship.dock_station(game.station)
	game.enter_attic()
	_check(not game.in_attic, "docked cockpit still requires entering the station")
	game.enter_station()
	game.enter_attic()
	_check(not game.in_attic, "hub spawn still requires approaching the home door")
	_check(game.station.hub_root.find_child("HomeDoor", true, false) != null, "station has a visible physical home door")
	game.player.global_position = game.station.airlock_position()
	_check(not game.can_visit_attic(), "airlock has no overlapping home interaction")
	game.player.position = Vector3(-10.0, game.station.FLOOR_TOP + 0.02, 16.2)
	_check(not game.can_visit_attic(), "home cannot be activated through the back of the cabin")
	game.player.global_position = game.station.home_door_position()
	game.discovered.erase("qinglan")
	game.discovered.erase("xuanyuan")
	_check(game.can_visit_attic(), "physical station door works without a windmill scan")
	var pose: Transform3D = game.player.transform
	game.ship.docked_station = game.distant_stations[0]
	game.enter_station()
	_check(game.player.get_parent() == game.distant_stations[0] and not game.can_visit_attic(),
		"actual distant-station interior cannot impersonate the homecoming station")
	game.request_attic_visit()
	_check(not game.in_attic, "public home request rejects an actual distant-station visit")
	game.player.global_position = game.active_station.airlock_position()
	_check(game.get_prompt().contains("返回飞船"), "distant-station airlock prompt uses its own location")
	game.ship.docked_station = game.station
	game.enter_station()
	game.player.transform = pose
	game.supernova_active = true
	_check(not game.can_visit_attic(), "supernova cannot be cancelled through the home door")
	game.supernova_active = false
	game.state = "dying"
	game.enter_attic()
	_check(not game.in_attic, "death sequence cannot be cancelled through the home door")
	game.state = "walk"
	await physics_frame
	# Sweep a walking body from the hub arrival point to the door approach.
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	var arrival: Vector3 = game.station.interior_spawn_transform().origin
	var destination: Vector3 = game.station.home_door_position()
	query.transform = Transform3D(game.station.global_basis.orthonormalized(), arrival + game.station.up_direction())
	query.motion = destination - arrival
	var sweep: PackedFloat32Array = game.station.get_world_3d().direct_space_state.cast_motion(query)
	_check(sweep[0] > 0.98, "walking capsule has a clear route from hub arrival to the home door")
	game.player.transform = pose
	game.player.oxygen = 47.0
	game.player.fuel = 36.0
	var clock: float = game.elapsed
	game._interact()
	_check(game.in_attic and game.player.get_parent() == game.attic, "E at the physical door enters home")
	game.player.oxygen = 100.0
	game.player.fuel = 100.0
	game.request_attic_visit()
	_check(not game.in_attic and game.in_station and game.active_station == game.station,
		"leaving home returns to the homecoming station")
	_check(game.player.transform.is_equal_approx(pose) and game.player.get_parent() == game.station,
		"return preserves position and orientation relative to the orbiting station")
	_check(game.elapsed == clock and game.player.oxygen == 47.0 and game.player.fuel == 36.0,
		"return preserves time and original suit resources")
	game.exit_station_to_ship()
	var voyage: Transform3D = game.player.transform
	game.return_to_menu()
	_check(game.state == "menu" and not game.in_attic,
		"return to title keeps the physical home gate closed")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "all checks respect --no-capture")
	game.queue_free()
	await process_frame
	_cleanup()
	print("HOME GATE TEST COMPLETE: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
