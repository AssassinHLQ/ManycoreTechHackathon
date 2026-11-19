extends SceneTree

class MockPlanet extends Node3D:
	var radius := 400.0
	var gravity_strength := 12.0

	func terrain_height(_direction: Vector3) -> float:
		return radius

	func surface_position(direction: Vector3, altitude: float = 0.0) -> Vector3:
		return direction.normalized() * (radius + altitude)

	func orbital_velocity() -> Vector3:
		return Vector3.ZERO


class MockAudio extends RefCounted:
	func set_engine(_active: bool, _level: float) -> void:
		pass

	func play_ui(_frequency: float) -> void:
		pass

	func play_impact() -> void:
		pass


class MockHud extends RefCounted:
	func show_toast(_message: String, _duration: float) -> void:
		pass

	func set_fuel_harvest_hint(_visible: bool) -> void:
		pass


class MockPlayer extends Node3D:
	var camera: Camera3D

	func _init() -> void:
		camera = Camera3D.new()
		add_child(camera)


class MockGame extends Node:
	var state := "ship"
	var paused := false
	var supernova_active := false
	var map_open := false
	var gargantua: Node3D
	var station: Node3D
	var distant_stations: Array = []
	var sun_radius := 0.0
	var audio := MockAudio.new()
	var hud := MockHud.new()
	var player: MockPlayer
	var home: MockPlanet

	func nearest_planet(_world_position: Vector3) -> MockPlanet:
		return home

	func begin_death(_reason: String, _duration: float) -> void:
		state = "dying"


var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	print("PASS  " if condition else "FAIL  ", message)
	if not condition:
		failures += 1


func _surface_altitude(ship: Node3D, planet: MockPlanet) -> float:
	var local_offset: Vector3 = planet.global_transform.basis.inverse() \
		* (ship.global_position - planet.global_position)
	return local_offset.length() - planet.terrain_height(local_offset.normalized())


func _run() -> void:
	for action in ["move_forward", "brake", "thrust_down", "jump", "jetpack", "move_left", "move_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var game := MockGame.new()
	root.add_child(game)
	game.player = MockPlayer.new()
	game.add_child(game.player)
	var planet := MockPlanet.new()
	game.home = planet
	game.add_child(planet)
	var ship = load("res://scripts/ship.gd").new()
	ship.game = game
	planet.add_child(ship)
	await process_frame

	ship.global_transform = Transform3D(
		Basis.looking_at(Vector3.FORWARD, Vector3.UP),
		planet.surface_position(Vector3.UP, ship.ground_rest_altitude()))
	ship.landed = true
	ship.landed_planet = planet
	ship.landing_normal = Vector3.UP
	ship.docked = false
	ship.set_physics_process(false)
	ship.takeoff()
	var start_altitude := _surface_altitude(ship, planet)
	for _i in range(90):
		ship._physics_process(1.0 / 60.0)
	var final_altitude := _surface_altitude(ship, planet)
	print("Takeoff altitude %.1f m -> %.1f m" % [start_altitude, final_altitude])
	_check(final_altitude >= 70.0,
		"automatic takeoff clears the 70 m landing-hint zone without holding Space")

	var forward: Vector3 = -ship.global_transform.basis.z.normalized()
	var barrier := StaticBody3D.new()
	barrier.collision_layer = 8
	var barrier_shape := CollisionShape3D.new()
	var barrier_box := BoxShape3D.new()
	barrier_box.size = Vector3(12.0, 12.0, 3.0)
	barrier_shape.shape = barrier_box
	barrier.add_child(barrier_shape)
	game.add_child(barrier)
	barrier.global_position = ship.global_position + forward * 20.0
	await physics_frame
	var before_barrier: Vector3 = ship.global_position
	ship.hull = 100.0
	ship.impact_cooldown = 0.0
	ship.velocity = forward * 60.0
	var blocked: bool = ship._move_with_planet_asset_collision(forward * 50.0)
	_check(blocked, "ship asset collision sweep remains enabled")
	_check(ship.global_position.distance_to(before_barrier) < 50.0,
		"ship stops before a solid asset collider")
	_check(ship.hull > 80.0, "reinforced ship hull takes reduced collision damage")

	ship.landed = true
	game.state = "walk"
	var repair_direction: Vector3 = ship.global_transform.basis.x.normalized()
	var repair_camera_position: Vector3 = ship.global_position + repair_direction * 20.0
	game.player.camera.global_transform = Transform3D(
		Basis.looking_at(-repair_direction, ship.global_transform.basis.y.normalized()),
		repair_camera_position)
	ship.hull = 25.0
	ship.repair_progress = 0.25
	_check(bool(ship.repair_check()[0]),
		"repair interaction works from 20 m away when aiming at the ship")
	ship.repair_tick(0.9, true)
	_check(is_equal_approx(ship.hull, 75.0),
		"ship repair restores half its hull in 0.9 seconds")

	game.free()
	await process_frame
	quit(1 if failures > 0 else 0)
