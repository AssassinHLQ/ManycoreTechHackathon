extends SceneTree

var game
var review_camera: Camera3D


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _measure(label: String, frames := 120) -> void:
	for i in range(20):
		await process_frame
	var start := Time.get_ticks_usec()
	var draw_calls := 0
	var primitives := 0
	for i in range(frames):
		await process_frame
		draw_calls = maxi(draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives = maxi(primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var seconds := float(Time.get_ticks_usec() - start) / 1000000.0
	print("%s  fps=%.1f  frame=%.2f ms  draws=%d  prims=%d" % [label, float(frames) / seconds, seconds * 1000.0 / float(frames), draw_calls, primitives])


func _view_from(planet, offset: Vector3, target_offset: Vector3) -> void:
	if review_camera == null:
		review_camera = Camera3D.new()
		review_camera.near = 0.2
		review_camera.far = 60000.0
		review_camera.fov = 58.0
		game.add_child(review_camera)
	game.state = "capture"
	game.hud.menu.visible = false
	review_camera.current = true
	review_camera.global_position = planet.global_transform * offset
	review_camera.look_at(planet.global_transform * target_offset, planet.global_transform.basis.y)


func _place_station_player(local_position: Vector3, look_local: Vector3) -> void:
	var station = game.station
	var world_position: Vector3 = station.to_global(local_position)
	var look_target: Vector3 = station.to_global(look_local)
	var direction: Vector3 = (look_target - world_position).normalized()
	game.player.global_transform = Transform3D(Basis.looking_at(direction, station.up_direction()), world_position)
	game.player.camera.rotation = Vector3.ZERO
	game.player.velocity = Vector3.ZERO


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_bench.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.settings.values.vsync = false
	game.settings.values.fps_limit = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _measure("title")
	game.start_game()
	await _measure("home spawn (walk)")
	game.player.camera.look_at(game._anomaly_by_id("qinglan").global_position + Vector3.UP * 3.0, Vector3.UP)
	await _measure("home observatory")
	_view_from(game.home, Vector3(0, 26, 80), Vector3(0, 10, 0))
	await _measure("observatory three-quarter")
	var home_arch: Node3D = game.home.find_child("Architecture_Qinglan", true, false)
	game.hud.menu.visible = false
	game.state = "capture"
	review_camera.current = true
	review_camera.global_position = home_arch.global_transform * Vector3(0, 3.4, 4.7)
	review_camera.look_at(home_arch.global_transform * Vector3(-0.4, 3.0, -2.2), home_arch.global_transform.basis.y)
	await _measure("observatory interior")
	var cave: Node3D = game.home.find_child("Cave_Qinglan", true, false)
	review_camera.global_position = cave.global_transform * Vector3(0, -10.4, 11.0)
	review_camera.look_at(cave.global_transform * Vector3(0, -12.2, -6.0), cave.global_transform.basis.y)
	await _measure("cave chamber")
	_view_from(game.planets[1], Vector3(0, 26, 60), Vector3(0, 10, 0))
	await _measure("ember station")
	_view_from(game.planets[2], Vector3(0, 26, 60), Vector3(0, 12, 0))
	await _measure("tide station")
	_view_from(game.planets[3], Vector3(0, 26, 60), Vector3(0, 12, 0))
	await _measure("shard temple")
	var station = game.station
	review_camera.current = true
	game.state = "capture"
	review_camera.global_position = station.to_global(Vector3(500.0, 340.0, 500.0))
	review_camera.look_at(station.to_global(Vector3.ZERO), station.up_direction())
	await _measure("station exterior")
	game.state = "walk"
	game.in_station = true
	game.player.set_physics_process(false)
	game.player.reparent(station, false)
	game.player.camera.current = true
	_place_station_player(Vector3(18.0, -1.95, 0.0), Vector3(-4.0, 0.3, -18.0))
	await _measure("station central hub")
	_place_station_player(Vector3(35.0, -1.97, 0.0), Vector3(120.0, -0.4, 0.0))
	await _measure("station corridor")
	_place_station_player(Vector3(145.0, -1.95, 0.0), Vector3(130.0, 0.9, -10.5))
	await _measure("station central hall")
	_place_station_player(Vector3(51.0, -1.95, -4.0), Vector3(51.0, 0.9, -12.0))
	await _measure("station observation window")
	game.queue_free()
	await process_frame
	quit()
