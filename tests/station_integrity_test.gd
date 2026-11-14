extends SceneTree

var game
var station
var failures := 0


# Minimal world around the production station/player scripts, at orbital world coordinates.
# Full docking, scene transitions, audio and mesh merging are covered by station_test.gd.
class TestAudio extends RefCounted:
	func set_jetpack(_enabled: bool) -> void:
		pass
	func play_door(_position: Vector3, _opening: bool) -> void:
		pass


class TestHud extends RefCounted:
	func show_toast(_message: String, _duration: float) -> void:
		pass


class TestPlanet extends Node3D:
	var radius := 2000.0
	var orbit_radius := 43000.0
	var orbit_height := 11800.0
	var orbit_phase := 0.2
	var orbit_speed := 0.001


class TestWorld extends Node3D:
	var state := "walk"
	var paused := false
	var supernova_active := false
	var map_open := false
	var minigame_open := false
	var bag_open := false
	var in_attic := false
	var in_station := true
	var elapsed := 0.0
	var sun_radius := 0.0
	var station
	var player
	var ship = null
	var audio := TestAudio.new()
	var hud := TestHud.new()
	var planets: Array = []
	func _process(delta: float) -> void:
		elapsed += delta


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	print("PASS  " if condition else "FAIL  ", message)
	if not condition:
		failures += 1


func _run() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back", "thrust_down", "jump", "jetpack"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	game = TestWorld.new()
	root.add_child(game)
	var planet := TestPlanet.new()
	game.add_child(planet)
	game.planets.append(planet)
	station = load("res://scripts/station.gd").new()
	station.game = game
	station.position = Vector3(43000.0, 11800.0, -15000.0)
	station.rotation.y = 0.42
	game.station = station
	game.add_child(station)
	game.player = load("res://scripts/player.gd").new()
	game.player.game = game
	station.add_child(game.player)
	game.player.position = Vector3(20.0, -1.97, 0.0)
	game.player.velocity = Vector3.ZERO
	game.player.reset_physics_interpolation()
	for i in range(60):
		await physics_frame
	var lo: Vector3 = game.player.position
	var hi := lo
	var cam_lo: Vector3 = station.to_local(game.player.camera.global_position)
	var cam_hi := cam_lo
	var orbit_before: Vector3 = station.global_position
	for i in range(180):
		await physics_frame
		lo = lo.min(game.player.position)
		hi = hi.max(game.player.position)
		var cp: Vector3 = station.to_local(game.player.camera.global_position)
		cam_lo = cam_lo.min(cp)
		cam_hi = cam_hi.max(cp)
	print("IDLE player_span=", hi - lo, " camera_span=", cam_hi - cam_lo,
		" platform_velocity=", game.player.get_platform_velocity())
	_check((hi - lo).length() < 0.02, "idle player stays within 2 cm of its station position")
	_check((cam_hi - cam_lo).length() < 0.02, "idle camera stays within 2 cm of its station position")
	_check(station.global_position.distance_to(orbit_before) > 1.0, "station keeps orbiting during the idle check")

	# Close every door before scanning the entire perimeter, including above the door headers.
	game.player.position = Vector3(20.0, -1.97, 0.0)
	for i in range(60):
		await physics_frame
	var space: PhysicsDirectSpaceState3D = station.get_world_3d().direct_space_state
	var holes := 0
	for k in range(1440):
		var angle := TAU * float(k) / 1440.0
		for y: float in [-1.6, 0.0, 1.6, 3.2, 5.5, 7.7]:
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			var query := PhysicsRayQueryParameters3D.create(
				station.to_global(direction * 25.0 + Vector3.UP * y),
				station.to_global(direction * 40.0 + Vector3.UP * y), 1)
			if space.intersect_ray(query).is_empty():
				if holes < 12:
					print("HOLE angle=", rad_to_deg(angle), " y=", y)
				holes += 1
	_check(holes == 0, "closed hub perimeter: %d escape rays out of 8640" % holes)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.65
	var capsule_holes := 0
	for k in range(360):
		var angle := TAU * float(k) / 360.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.collision_mask = 1
		query.transform = station.global_transform * Transform3D(Basis.IDENTITY, direction * 25.0 + Vector3(0.0, -0.9, 0.0))
		query.motion = station.global_basis * direction * 15.0
		var motion := space.cast_motion(query)
		if motion[0] > 0.99:
			capsule_holes += 1
	_check(capsule_holes == 0, "player capsule cannot escape: %d holes in 360 sweeps" % capsule_holes)

	# Sample actual mesh triangles along the player passage, including the exterior shell.
	var triangles: Array = []
	for node in station.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		triangles.append([mi, mi.mesh.get_faces()])
	for door in range(6):
		var angle := TAU * float(door) / 6.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		game.player.position = direction * 27.0 + Vector3(0.0, -1.97, 0.0)
		game.player.velocity = Vector3.ZERO
		for i in range(60):
			await physics_frame
		_check(station.door_openness(door) > 0.98, "door %d opens fully" % door)
		var side_holes := 0
		var door_basis := Basis(Vector3.UP, -angle)
		for z: float in [-9.0, -6.0, -5.0, -4.1, 4.1, 5.0, 6.0, 9.0]:
			for y: float in [-1.6, 0.0, 1.6, 3.2, 7.7]:
				var query := PhysicsRayQueryParameters3D.create(
					station.to_global(door_basis * Vector3(25.0, y, z)),
					station.to_global(door_basis * Vector3(40.0, y, z)), 1)
				if space.intersect_ray(query).is_empty():
					side_holes += 1
		_check(side_holes == 0, "open door %d side walls have %d escape rays out of 40" % [door, side_holes])
		var blocked := 0
		var first := ""
		for entry in triangles:
			var mi: MeshInstance3D = entry[0]
			if not mi.is_visible_in_tree():
				continue
			var faces: PackedVector3Array = entry[1]
			var xf: Transform3D = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * station.global_transform.affine_inverse() * mi.global_transform
			var passage := AABB(Vector3(29.0, -1.7, -1.9), Vector3(25.0, 4.0, 3.8))
			if not (xf * mi.mesh.get_aabb()).intersects(passage):
				continue
			for t in range(0, faces.size(), 3):
				var a := xf * faces[t]
				var b := xf * faces[t + 1]
				var c := xf * faces[t + 2]
				# Rays across the walking lane catch large faces even when their vertices lie outside it.
				for z: float in [-1.8, 0.0, 1.8]:
					for y: float in [-1.4, 0.2, 1.8]:
						if Geometry3D.segment_intersects_triangle(Vector3(29.0, y, z), Vector3(54.0, y, z), a, b, c) != null:
							blocked += 1
							if first.is_empty():
								first = String(mi.name)
		_check(blocked == 0, "door %d passage: %d visual intersections (%s)" % [door, blocked, first])
		# Walk through each actual door with the real player controller and collisions enabled.
		game.player.global_basis = Basis.looking_at(station.global_basis * direction, station.up_direction())
		Input.action_press("move_forward")
		for i in range(150):
			await physics_frame
		Input.action_release("move_forward")
		var walked: Vector3 = game.player.position
		_check(walked.dot(direction) > 43.0 and absf(walked.y + 1.97) < 0.1,
			"player walks through door %d and stays on the corridor floor (%s)" % [door, walked])
		for i in range(30):
			await physics_frame
		lo = game.player.position
		hi = lo
		for i in range(90):
			await physics_frame
			lo = lo.min(game.player.position)
			hi = hi.max(game.player.position)
		_check((hi - lo).length() < 0.02, "idle corridor %d span %s stays below 2 cm" % [door, hi - lo])
		if door == 0:
			for i in range(10):
				if game.player.is_on_floor():
					break
				await physics_frame
			var floor_y: float = game.player.position.y
			Input.action_press("jump")
			for i in range(12):
				await physics_frame
			Input.action_release("jump")
			_check(game.player.position.y > floor_y + 0.5, "station idle stability still allows jumping")
			for i in range(100):
				await physics_frame

	game.in_station = false
	game.state = "ship"
	for i in range(3):
		await physics_frame
	var shell := station.get_node_or_null("ExteriorHubShell") as Node3D
	_check(shell != null and shell.is_visible_in_tree(), "returning to the ship restores the exterior hub shell")

	game.queue_free()
	await process_frame
	print("STATION INTEGRITY TEST COMPLETE: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
