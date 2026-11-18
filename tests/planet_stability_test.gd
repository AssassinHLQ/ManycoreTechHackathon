extends SceneTree

var game
var failures := 0
var checked := 0
var test_save := "user://planet_stability_%d_test.json" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("PASS  " if ok else "FAIL  ", message)
	if not ok:
		failures += 1


func _physics_frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _idle(count: int) -> Dictionary:
	var lo: Vector3 = game.player.position
	var hi := lo
	var start := lo
	var previous := lo
	var step := 0.0
	var grounded := 0
	var previous_floor: bool = game.player.is_on_floor()
	for i in range(count):
		await physics_frame
		var p: Vector3 = game.player.position
		var on_floor: bool = game.player.is_on_floor()
		if "--trace-prop" in OS.get_cmdline_user_args() and on_floor != previous_floor:
			print("PROP FLOOR frame=", i, " position=", p, " velocity=", game.player.velocity)
		previous_floor = on_floor
		lo = lo.min(p)
		hi = hi.max(p)
		step = maxf(step, p.distance_to(previous))
		previous = p
		if on_floor:
			grounded += 1
	return {"span": (hi - lo).length(), "step": step, "grounded": grounded,
		"radial": absf(start.length() - previous.length())}


func _check_orbits() -> void:
	var previous: Array[Vector3] = []
	var errors: Array[float] = []
	for planet in game.planets:
		previous.append(planet.position)
		errors.append(0.0)
	for frame in range(120):
		await physics_frame
		for i in range(game.planets.size()):
			var planet = game.planets[i]
			var step: float = planet.position.distance_to(previous[i])
			var expected: float = planet.orbital_velocity().length() / Engine.physics_ticks_per_second
			errors[i] = maxf(errors[i], absf(step - expected))
			previous[i] = planet.position
	for i in range(game.planets.size()):
		_check(errors[i] < 0.06, "%s uniform orbital physics steps (error %.5f m)" % [game.planets[i].planet_id, errors[i]])


func _prop_sample(planet) -> Dictionary:
	var direction: Vector3 = planet.site_direction.normalized()
	var tangent := direction.cross(Vector3.RIGHT).normalized()
	if tangent.length_squared() < 0.1:
		tangent = direction.cross(Vector3.FORWARD).normalized()
	var space: PhysicsDirectSpaceState3D = planet.get_world_3d().direct_space_state
	var body_scale: float = planet.prop_scale if planet.prop_scale > 0.0 else 1.0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34 * body_scale
	capsule.height = 1.65 * body_scale
	for angle: float in [0.16, -0.16, 0.26, -0.26, 0.08, 0.0]:
		var d := direction.rotated(tangent, angle)
		var h: float = planet.terrain_height(d)
		var ray := PhysicsRayQueryParameters3D.create(
			planet.to_global(d * (h + 100.0)), planet.to_global(d * (h - 100.0)), 8)
		ray.exclude = [game.player.get_rid()]
		var hit := space.intersect_ray(ray)
		var world_direction: Vector3 = (planet.global_basis.orthonormalized() * d).normalized()
		# The player controller accepts slopes up to 82 degrees; test a face it can stand on.
		if not hit.is_empty() and String(hit.collider.name).begins_with("PropCollision_") \
			and (hit.normal as Vector3).dot(world_direction) > 0.14:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 8
			query.exclude = [game.player.get_rid()]
			query.transform = Transform3D(Basis(Quaternion(Vector3.UP, world_direction)),
				hit.position + world_direction * (0.4 + 0.82 * body_scale))
			query.motion = -world_direction * (0.55 * body_scale + 0.75)
			var support_sweep := space.cast_motion(query)
			if support_sweep.size() < 2 or support_sweep[0] >= 0.99:
				continue
			hit["direction"] = d
			hit["world_direction"] = world_direction
			return hit
	return {}


func _check_prop_contact() -> void:
	var planet = game.planets[9]
	_check(planet.planet_id == "jianmo", "Jianmo contact regression uses the intended planet")
	game.ship.set_physics_process(false)
	game.ship.global_position = planet.to_global(planet.site_direction.normalized() * (planet.radius + 200.0))
	await _physics_frames(3)
	var hit := _prop_sample(planet)
	_check(not hit.is_empty(), "sample a walkable face of a real planet asset")
	if hit.is_empty():
		return
	if "--trace-prop" in OS.get_cmdline_user_args():
		print("PROP SAMPLE collider=", hit.collider.name, " position=", hit.position,
			" normal=", hit.normal, " radial_dot=", (hit.normal as Vector3).dot(hit.world_direction))
	game.state = "walk"
	game.ship.set_physics_process(false)
	game.player.reparent(planet, false)
	var world_direction: Vector3 = hit.world_direction
	game.player.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, world_direction)),
		hit.position + world_direction * 0.4)
	game.player.velocity = Vector3.ZERO
	game.player.reset_physics_interpolation()
	await _physics_frames(90)
	var idle := await _idle(120)
	if "--trace-prop" in OS.get_cmdline_user_args():
		print("PROP IDLE start=", game.player.position, " result=", idle)
	_check(idle.span < 0.04 and idle.grounded >= 110,
		"asset contact stays still while orbiting (%.5f m, grounded %d/120)" % [idle.span, idle.grounded])
	await _check_ship_asset_contact(planet)


func _check_ship_asset_contact(planet) -> void:
	var current_hit := _prop_sample(planet)
	_check(not current_hit.is_empty(), "asset remains queryable after planetary rotation")
	if current_hit.is_empty():
		return
	var ship_transform: Transform3D = game.ship.global_transform
	var ship_velocity: Vector3 = game.ship.velocity
	var ship_hull: float = game.ship.hull
	var ship_cooldown: float = game.ship.impact_cooldown
	var approach: Vector3 = (current_hit.position - planet.global_position).normalized()
	var ship_up := Vector3.UP if absf(approach.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	game.ship.set_physics_process(false)
	var ship_start: Vector3 = current_hit.position + approach * 250.0
	game.ship.global_transform = Transform3D(Basis.looking_at(-approach, ship_up), ship_start)
	game.ship.velocity = planet.orbital_velocity() - approach * 5.0
	game.ship.hull = 100.0
	game.ship.impact_cooldown = 0.0
	var ship_hit: bool = game.ship._move_with_planet_asset_collision(-approach * 300.0)
	_check(ship_hit and game.ship.global_position.distance_to(ship_start) < 300.0,
		"ship hull sweep hits a real planet asset")
	game.ship.global_transform = ship_transform
	game.ship.velocity = ship_velocity
	game.ship.hull = ship_hull
	game.ship.impact_cooldown = ship_cooldown
	game.ship.set_physics_process(true)


func _ground_sample(planet) -> Dictionary:
	if "--prop-contact" in OS.get_cmdline_user_args():
		return _prop_sample(planet)
	var direction: Vector3 = planet.site_direction.normalized()
	var tangent := direction.cross(Vector3.RIGHT).normalized()
	if tangent.length_squared() < 0.1:
		tangent = direction.cross(Vector3.FORWARD).normalized()
	var scale: float = planet.prop_scale
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5 * scale
	capsule.height = 1.65 * scale
	var space: PhysicsDirectSpaceState3D = planet.get_world_3d().direct_space_state
	# Stay inside the designed level ground, with a clear capsule route away from props.
	# A ray hitting a crystal tip is not enough space for the player's entire body.
	for fraction: float in [0.55, 0.35, 0.75, 0.95, 1.15, 1.35]:
		for azimuth in range(32):
			var axis := tangent.rotated(direction, TAU * azimuth / 32.0)
			var d := direction.rotated(axis, fraction * planet.site_pad_radius / planet.radius)
			var h: float = planet.terrain_height(d)
			var ray := PhysicsRayQueryParameters3D.create(
				planet.to_global(d * (h + 100.0)), planet.to_global(d * (h - 100.0)), 1)
			ray.exclude = [game.player.get_rid()]
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or hit.collider.name != "TerrainCollision" or (hit.normal as Vector3).dot(d) < 0.98:
				continue
			var basis := Basis(Quaternion(Vector3.UP, d))
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 9
			query.exclude = [game.player.get_rid()]
			query.transform = Transform3D(basis, hit.position + d * (0.4 + 0.82 * scale))
			if not space.intersect_shape(query).is_empty():
				continue
			query.motion = -basis.z * (8.5 * scale * 1.5)
			if space.cast_motion(query)[0] < 0.99:
				continue
			# Also reserve headroom for the jump case, including low-gravity planets.
			query.motion = d * (9.5 * 9.5 * scale / (1.6 * planet.gravity_strength) + 2.0 * scale)
			if space.cast_motion(query)[0] < 0.99:
				continue
			hit["direction"] = d
			return hit
	return {}


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	game.state = "ship"
	game.ship.set_physics_process(false)
	var focused_prop_contact := "--prop-contact" in OS.get_cmdline_user_args() \
		or "--prop-contact-helper" in OS.get_cmdline_user_args()
	var requested_planets: Array[String] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--planet="):
			for planet_id in argument.trim_prefix("--planet=").split(","):
				requested_planets.append(planet_id)
	if focused_prop_contact and not requested_planets.is_empty():
		while not game.planets.any(func(planet): return requested_planets.has(planet.planet_id)):
			await process_frame
	else:
		while game.planets.size() < 20:
			await process_frame
	await _physics_frames(10)
	if not focused_prop_contact:
		await _check_orbits()
	if "--orbit-only" in OS.get_cmdline_user_args():
		print("ORBIT STABILITY TEST COMPLETE: 20 planets, %d failure(s)" % failures)
		game.queue_free()
		await process_frame
		if FileAccess.file_exists(test_save):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
		quit(0 if failures == 0 else 1)
		return
	game.in_attic = false
	game.in_station = false
	game.player.visible = true
	game.ship.landed = false
	game.ship.docked = false
	for planet in game.planets:
		var selected := ""
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--planet="):
				selected = argument.trim_prefix("--planet=")
		if not selected.is_empty() and not planet.planet_id in selected.split(","):
			continue
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--orbit-time="):
				game.elapsed = float(argument.trim_prefix("--orbit-time="))
				await _physics_frames(10)
		# Approach in the ship before querying the landing surface. Distant
		# planets intentionally keep their collision out of the physics space.
		game.ship.global_position = planet.to_global(planet.site_direction.normalized() * (planet.radius + 200.0))
		planet._ensure_terrain_collision()
		await _physics_frames(3)
		var hit := _ground_sample(planet)
		_check(not hit.is_empty(), "%s has sampled surface collision" % planet.planet_id)
		if hit.is_empty():
			continue
		var chosen: Vector3 = hit.direction
		var local_surface: Vector3 = planet.to_local(hit.position)
		print("GROUND ", planet.planet_id, " collider=", hit.collider.name,
			" slope=", rad_to_deg(acos(clampf((hit.normal as Vector3).dot(chosen), -1.0, 1.0))),
			" position=", planet.to_local(hit.position))
		game.state = "walk"
		game.player.reparent(planet, false)
		game.player.transform = Transform3D(Basis(Quaternion(Vector3.UP, chosen)), local_surface + chosen * 0.4)
		game.player.velocity = Vector3.ZERO
		game.player.reset_physics_interpolation()
		game.player.oxygen = 100.0
		await _physics_frames(90)
		var idle := await _idle(120)
		print("PLANET ", planet.planet_id, " IDLE=", idle,
			" world_radius=", planet.global_position.length())
		_check(idle.span < 0.04, "%s idle span %.5f m < 0.04" % [planet.planet_id, idle.span])
		_check(idle.grounded >= 110, "%s stays grounded (%d/120)" % [planet.planet_id, idle.grounded])
		if "--prop-contact" in OS.get_cmdline_user_args():
			_check(String(hit.collider.name).begins_with("PropCollision_"), "contact case stands on a real prop mesh")
			await _check_ship_asset_contact(planet)
			checked += 1
			continue
		if planet.planet_id in ["qinglan", "jianmo"]:
			# Holding idle coordinates must never keep the player hovering over a removed floor.
			var resting: Vector3 = game.player.position
			hit.collider.collision_layer = 0
			await _physics_frames(45)
			_check(not game.player.is_on_floor() and game.player.position.length() < resting.length() - 0.1,
				"%s falls when ground support is removed" % planet.planet_id)
			hit.collider.collision_layer = 1
			game.player.position = resting + chosen * 0.4
			game.player.velocity = Vector3.ZERO
			await _physics_frames(60)
		var before: Vector3 = game.player.position
		var previous := before
		var max_step := 0.0
		Input.action_press("move_forward")
		for i in range(90):
			if "--trace-walk" in OS.get_cmdline_user_args():
				print("BEFORE WALK ", i, " local=", game.player.position, " velocity=", game.player.velocity,
					" platform=", game.player.get_platform_velocity(), " floor=", game.player.is_on_floor())
			await physics_frame
			var step: float = game.player.position.distance_to(previous)
			if step > 1.5:
				print("WALK STEP ", planet.planet_id, " frame=", i, " delta=", game.player.position - previous,
					" velocity=", game.player.velocity, " floor=", game.player.is_on_floor(), " elapsed=", game.elapsed,
					" platform=", game.player.get_platform_velocity(), " last_motion=", game.player.get_last_motion())
				for collision_index in range(game.player.get_slide_collision_count()):
					var collision: KinematicCollision3D = game.player.get_slide_collision(collision_index)
					print("WALK CONTACT ", collision.get_collider().name, " normal=", collision.get_normal(),
						" depth=", collision.get_depth())
			max_step = maxf(max_step, step)
			previous = game.player.position
		Input.action_release("move_forward")
		_check(before.distance_to(game.player.position) > 4.0 and max_step < 1.5,
			"%s walking advances smoothly (max %.4f m/step)" % [planet.planet_id, max_step])
		# Return to the sampled open launch volume before testing jump/landing separately.
		game.player.transform = Transform3D(Basis(Quaternion(Vector3.UP, chosen)), local_surface + chosen * 0.4)
		game.player.velocity = Vector3.ZERO
		game.player.reset_physics_interpolation()
		await _physics_frames(90)
		var settled: bool = game.player.is_on_floor()
		for frame in range(120):
			if settled:
				break
			await physics_frame
			settled = game.player.is_on_floor()
		var can_jump: bool = game.player.is_on_floor()
		var start_radius: float = game.player.position.length()
		Input.action_press("jump")
		for frame in range(12):
			await physics_frame
			if "--diagnose-jump" in OS.get_cmdline_user_args():
				print("JUMP FRAME ", frame, " height=", game.player.position.length() - start_radius,
					" velocity=", game.player.velocity, " floor=", game.player.is_on_floor(),
					" just_pressed=", Input.is_action_just_pressed("jump"))
				for collision_index in range(game.player.get_slide_collision_count()):
					var collision: KinematicCollision3D = game.player.get_slide_collision(collision_index)
					print("JUMP CONTACT ", collision.get_collider().name, " normal=", collision.get_normal())
		Input.action_release("jump")
		print("JUMP ", planet.planet_id, " can_jump=", can_jump, " height=", game.player.position.length() - start_radius,
			" velocity=", game.player.velocity, " floor=", game.player.is_on_floor(), " state=", game.state)
		_check(can_jump and game.player.position.length() > start_radius + 0.5,
			"%s can jump from the sampled clear surface" % planet.planet_id)
		# A first contact can be followed by a short bounce or another fall off a mesh edge.
		# Measure rest only after continuous grounded contact, not the first floor flag.
		var grounded_frames := 0
		for frame in range(900):
			await physics_frame
			if game.player.is_on_floor():
				grounded_frames += 1
			else:
				grounded_frames = 0
			if grounded_frames >= 30:
				break
		_check(grounded_frames >= 30, "%s completes the jump and settles on the ground" % planet.planet_id)
		var landed_idle := await _idle(60)
		print("LANDING IDLE ", planet.planet_id, " ", landed_idle, " velocity=", game.player.velocity)
		if landed_idle.span >= 0.04 or grounded_frames < 30:
			for collision_index in range(game.player.get_slide_collision_count()):
				var collision: KinematicCollision3D = game.player.get_slide_collision(collision_index)
				print("LANDING CONTACT ", collision.get_collider().name, " normal=", collision.get_normal())
		_check(landed_idle.span < 0.04, "%s rests after landing (span %.5f m)" % [planet.planet_id, landed_idle.span])
		game.state = "ship"
		game.ship.set_physics_process(true)
		game.ship.landed = false
		game.ship.global_position = planet.to_global(chosen * (planet.terrain_height(chosen) + 5.0))
		game.ship.land(planet)
		await _physics_frames(5)
		var ship_start: Vector3 = game.ship.position
		var ship_span := 0.0
		for i in range(60):
			await physics_frame
			ship_span = maxf(ship_span, game.ship.position.distance_to(ship_start))
		_check(ship_span < 0.005, "%s parked ship stays still (%.5f m)" % [planet.planet_id, ship_span])
		game.ship.set_physics_process(false)
		game.ship.landed = false
		checked += 1
	if not "--prop-contact" in OS.get_cmdline_user_args():
		await _check_prop_contact()
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("PLANET STABILITY TEST COMPLETE: %d planets, %d failure(s)" % [checked, failures])
	quit(0 if failures == 0 else 1)
