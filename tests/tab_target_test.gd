extends SceneTree

var game: Node3D
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _run() -> void:
	var save_path := "user://starward_tab_target_test.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	game.state = "ship"
	game.paused = false
	game.ship.landed = false
	var saved_planets: Array = game.planets
	var saved_target: Node3D = game.ship.target
	game.planets = []
	game.cycle_target()
	_check(game.ship.target == saved_target, "Tab target cycling is harmless before destinations are ready")
	game.planets = saved_planets
	for planet: Node3D in game.planets:
		if planet != game.home:
			planet.stream_proxy = true
	game._stream_activation_requested.clear()
	var deadline := Time.get_ticks_msec() + 60000
	while game.planets.size() < 3 and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(game.planets.size() >= 3, "target cycling has at least three destinations")
	if game.planets.size() < 2:
		game.queue_free()
		await process_frame
		quit(1)

	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	var max_frame_gap_ms := 0
	var changed_count := 0
	for i in range(3):
		var before_id := String(game.ship.target.planet_id) if game.ship.target != null else ""
		var before := Time.get_ticks_msec()
		game._unhandled_input(tab)
		await process_frame
		var frame_gap := Time.get_ticks_msec() - before
		max_frame_gap_ms = maxi(max_frame_gap_ms, frame_gap)
		var after_id := String(game.ship.target.planet_id) if game.ship.target != null else ""
		if after_id != before_id:
			changed_count += 1
		print("TAB_DIAG index=%d before=%s after=%s frame_gap_ms=%d queued=%d building=%d ready=%d" % [
			i, before_id, after_id, frame_gap,
			game._stream_prewarm_queue.size(), game._stream_build_by_id.size(), game._stream_ready_by_id.size()])
	_check(changed_count >= 2, "Tab changes the destination on repeated presses")
	_check(game._stream_activation_requested.is_empty(),
		"Tab changes the destination without starting a synchronous stream request")
	_check(max_frame_gap_ms < 1000, "Tab does not block the main loop for one second")
	print("TAB TARGET TEST COMPLETE: %d failure(s)" % failures)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0 if failures == 0 else 1)
