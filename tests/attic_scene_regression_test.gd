extends SceneTree

var game
var checks := 0
var failures := 0
const FILES := ["user://attic_scene_regression_knowledge.json", "user://attic_scene_regression_progress.json"]


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)


func _cleanup() -> void:
	for path in FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	_cleanup()
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = FILES[0]
	game.progress_path = FILES[1]
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	game.player.set_physics_process(false)
	game.player._apply_body_scale(game.home.prop_scale)
	game.paused = true
	await physics_frame
	game.paused = false
	var tower: Node3D = game.home.get_node("Architecture_Qinglan")
	var signal_node: Node3D = game.anomalies[0]
	var camera: Camera3D = game.player.camera
	var target: Vector3 = signal_node.scan_position()
	var up := tower.global_basis.y.normalized()
	var height: float = tower.to_local(target).y - 1.76
	_check(height > 0.5 and height < 2.0, "signal is readable at human eye height above the entrance platform")
	for at in [Vector3(0, 1.76, 10), Vector3(0, 1.76, 12), Vector3(-6, 1.76, 9), Vector3(-3.2, 1.76, 12.5)]:
		game.player.global_transform = Transform3D(tower.global_basis.orthonormalized(), tower.to_global(at))
		camera.look_at(target, up)
		_check(game._has_line_of_sight(camera.global_position, target), "entrance has clear scan ray from " + str(at))
		_check(game._find_scan_target() == signal_node, "scanner finds the visible signal from " + str(at))
	Input.action_press("scan")
	game._update_scanner(signal_node.scan_time + 0.1)
	Input.action_release("scan")
	_check(game.discovered.has("qinglan"), "holding F completes the windmill scan")
	_check(not game.in_attic, "scan preserves the physical homecoming-station entrance")
	game.route_link.decoded["cloud"] = true
	game.route_link.refresh()
	var echo: Node3D = game.route_link.echoes.cloud
	game.player.global_transform = Transform3D(tower.global_basis.orthonormalized(), tower.to_global(Vector3(3.2, 1.76, 12)))
	camera.look_at(echo.to_global(Vector3(0, 3, 0)), up)
	_check(game._find_scan_target() == echo, "decoded cloud echo is also reachable from the windmill entrance")
	preload("res://tests/home_fixture.gd").enter(game)
	game.player.set_physics_process(false)
	var planet_count: int = game.planets.size()
	var content_ids := {}
	for key in ["cloud", "firefly", "alley", "snow"]:
		content_ids[key] = game.attic_worlds.worlds[key].content.get_instance_id()
	for visit in range(2):
		for key in ["cloud", "firefly", "alley", "snow"]:
			var start := Time.get_ticks_usec()
			game.enter_pocket(key)
			print("ENTER_US ", key, " ", Time.get_ticks_usec() - start)
			_check(game.player.can_process(), key + " player inherits an enabled world")
			_check(camera.far == game.LOCAL_SCENE_FAR, key + " cannot render distant universe geometry")
			_check(is_equal_approx(float(game.sky_material.get_shader_parameter("star_density")), float(game.SKY_PRESETS[key].stars)), key + " keeps its designed star density")
			_check(is_equal_approx(float(game.sky_material.get_shader_parameter("meteor_rate")), float(game.SKY_PRESETS[key].meteor)), key + " keeps its designed meteors")
			_check(is_equal_approx(float(game.sky_material.get_shader_parameter("nebula_structure")), float(game.SKY_PRESETS[key].n_struct)), key + " keeps its designed sky structure")
			_check(not game.attic.visible, key + " hides the attic")
			for other in game.attic_worlds.worlds:
				var holder: Node3D = game.attic_worlds.world_node(other)
				_check(holder.visible == (other == key), key + " isolates visibility from " + other)
				_check(holder.can_process() == (other == key), key + " isolates processing from " + other)
			await process_frame
			await process_frame
			_check(game.planets.size() == planet_count, "planet construction yields while inside " + key)
			_check(game.attic_worlds.worlds[key].content.get_instance_id() == content_ids[key], key + " reuses its loaded scene")
			if key == "alley":
				var rain: CPUParticles3D = game.attic_worlds.worlds[key].content.get_node("Rain")
				_check(rain.mesh is BoxMesh and rain.mesh.size.y > rain.mesh.size.x * 10, "rain is a streak rather than a star-like sphere")
			elif key == "snow":
				var snow: CPUParticles3D = game.attic_worlds.worlds[key].content.get_node("Snowfall")
				_check(snow.mesh.radius < 0.03 and snow.mesh.material.albedo_color.a < 1.0, "snowflakes are small and translucent")
			game.leave_pocket()
			_check(game.player.can_process() and game.attic.visible, "return to attic restores visibility and processing")
	game.leave_attic()
	_check(camera.far == 400000.0, "return to universe restores camera distance")
	_check(float(game.sky_material.get_shader_parameter("star_density")) == 1.0, "return to universe restores stars")
	await process_frame
	await process_frame
	_check(game.planets.size() > planet_count, "planet construction resumes after returning to universe")
	_cleanup()
	print("ATTIC SCENE REGRESSION: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
