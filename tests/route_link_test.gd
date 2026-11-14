extends SceneTree

const KNOWLEDGE := "user://route_link_test_knowledge.json"
const PROGRESS := "user://route_link_test_progress.json"
var game
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS  ", label)
	else:
		failures += 1
		push_error("FAIL  " + label)


func _cleanup() -> void:
	for path in [KNOWLEDGE, PROGRESS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _boot() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = KNOWLEDGE
	game.progress_path = PROGRESS
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	while game.world_build_remaining:
		await process_frame
	game.player.set_physics_process(false)


func _aim_at(echo: Node3D) -> void:
	game.player.reparent(echo.get_parent(), false)
	game.player.transform = Transform3D(echo.basis, echo.position + echo.basis * Vector3(0, 1, 9))
	game.player.camera.position = Vector3(0, 2, 0)
	game.player.camera.look_at(echo.global_position + echo.global_basis.y * 3.0, echo.global_basis.y)
	game.state = "walk"
	game.paused = false
	game.player.camera.current = true


func _scan(key: String) -> void:
	var echo: Node3D = game.route_link.echoes[key]
	_aim_at(echo)
	await physics_frame
	_check(game._find_scan_target() == echo, "%s is reachable through the real distance/facing/LOS scanner" % key)
	Input.action_press("scan")
	game._update_scanner(echo.scan_time + 0.1)
	Input.action_release("scan")
	_check(game.discovered.has(echo.anomaly_id), "%s requires and accepts an actual completed F scan" % key)


func _run() -> void:
	_cleanup()
	await _boot()
	_check(game.route_link.echoes.size() == 4, "four real surface echoes are built")
	_check(not game.route_link.unlocked(game), "new save does not unlock the attic")
	game.hud._process(0.0)
	_check(not game.hud.menu_attic.visible, "locked title entry is hidden")
	game.request_attic_visit()
	_check(game.state == "menu" and not game.in_attic, "locked entry cannot bypass discovery")
	game.start_game()
	game.player.set_physics_process(false)
	var cloud: Node3D = game.route_link.echoes.cloud
	_aim_at(cloud)
	await physics_frame
	_check(not cloud.visible and game._find_scan_target() != cloud, "undecoded echo is invisible and excluded from scanner")
	game.discover(cloud.anomaly_id)
	_check(not game.discovered.has(cloud.anomaly_id), "discovery guard rejects an undecoded echo")
	game.discover("qinglan")
	_check(game.route_link.unlocked(game), "windmill discovery unlocks the attic permanently")
	game.state = "ship"
	game.ship.landed = false
	game.ship.docked = false
	_check(not game.can_visit_attic(), "flight cannot be cancelled through the attic entry")
	game.request_attic_visit()
	_check(not game.in_attic, "public entry rejects flight")
	game.ship.landed = true
	game.ship.fuel = 63.5
	game.ship.hull = 74.0
	game.elapsed = 271.25
	game.set_paused(true)
	game.hud._process(0.0)
	_check(not game.hud.pause_attic.disabled, "landed ship exposes an enabled pause-menu entry")
	game.hud.pause_attic.pressed.emit()
	_check(game.in_attic and game.state == "walk", "actual pause button enters the attic")
	var clock: float = game.elapsed
	await process_frame
	await process_frame
	_check(is_equal_approx(game.elapsed, clock), "attic preserves the remaining loop time")
	_check(not game.route_link.can_decode(game, "cloud"), "universe discovery alone cannot decode")
	game.collect_keepsake("cloud")
	for door in game.attic.doors:
		game.player.global_position = door.anchor.global_position
		game._interact()
		_check(game.pocket_key == door.key and not game.route_board_open, "route record cannot intercept the %s door" % door.key)
		if game.in_pocket():
			game.leave_pocket()
	var record: Node3D = game.attic.anchors.AtticAnchor_Record
	game.player.global_position = record.global_position
	game._interact()
	_check(game.route_board_open and game.paused, "E at the generated gramophone opens the real route panel and freezes movement")
	game.player.set_physics_process(true)
	var board_pose: Transform3D = game.player.transform
	Input.action_press("move_forward")
	await physics_frame
	await physics_frame
	Input.action_release("move_forward")
	game.player.set_physics_process(false)
	_check(game.player.transform.is_equal_approx(board_pose), "movement input cannot pass through the route panel")
	_check(game.hud.route_entries.get_parent() is ScrollContainer, "route rows remain reachable through a scrolling panel")
	_check(game.hud.routes.find_child("Decode_cloud", true, false) != null, "panel exposes the route action")
	game.hud.routes.find_child("Decode_cloud", true, false).pressed.emit()
	_check(game.route_link.decoded.has("cloud") and cloud.visible, "actual decode button reveals a separate surface signal")
	_check(not game.discovered.has(cloud.anomaly_id), "decoding never awards universe verification")
	_check(not game.route_link.decode(game, "cloud"), "decoding is idempotent")
	game.hud.routes.find_child("Navigate_cloud", true, false).pressed.emit()
	_check(game.ship.target == game.home and game.route_link.tracked == "cloud", "navigate button sets the real ship target and surface tracking")
	_check(game.hud.route_finish.disabled and not game.route_link.finish(game), "incomplete records cannot trigger the linked ending")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	game._unhandled_input(cancel)
	_check(not game.route_board_open and not game.paused, "Esc closes a physical route panel without opening pause")
	game.set_paused(true)
	game.open_route_board()
	game._unhandled_input(cancel)
	_check(game.paused and not game.route_board_open, "Esc restores the pause menu when opened there")
	game.leave_attic()
	_check(game.state == "ship" and game.get_active_camera() == game.ship.camera and not game.paused, "return restores the landed cockpit and input mode")
	_check(game.elapsed == clock and game.ship.fuel == 63.5 and game.ship.hull == 74.0, "return preserves loop time, ship fuel and damage")
	await _scan("cloud")
	_check(game.route_link.tracked == "", "completed scan clears the active surface objective")
	var count: int = game.discovered.size()
	game.discover(cloud.anomaly_id)
	_check(game.discovered.size() == count, "repeated discovery grants no duplicate record")
	# A moving planet reference, body scale, view, velocity and suit resources survive a visit.
	var local_pose: Transform3D = game.player.transform
	var local_view: Transform3D = game.player.camera.transform
	game.player.velocity = Vector3(0.1, 0.2, 0.3)
	game.player.oxygen = 49.0
	game.player.fuel = 37.0
	game.enter_attic()
	game.player.oxygen = 100.0
	game.player.fuel = 100.0
	game.leave_attic()
	_check(game.player.get_parent() == game.home and game.player.transform.is_equal_approx(local_pose), "walking return restores planet-local position and orientation")
	_check(game.player.camera.transform.is_equal_approx(local_view) and game.player.velocity == Vector3(0.1, 0.2, 0.3), "walking return restores camera and velocity")
	_check(game.player.oxygen == 49.0 and game.player.fuel == 37.0, "attic refill cannot leak into original suit resources")
	# The public station path must preserve its interior reference and docked ship.
	game.ship.docked = true
	game.ship.docked_station = game.station
	game.enter_station()
	var station_pose: Transform3D = game.player.transform
	game.request_attic_visit()
	game.leave_attic()
	_check(game.in_station and game.active_station == game.station and game.player.get_parent() == game.station,
		"station return restores interior and active station")
	_check(game.player.transform.is_equal_approx(station_pose) and game.ship.docked and game.ship.docked_station == game.station,
		"station return preserves local spawn and docking")
	# Test the reverse order too: keepsakes acquired before their universe records.
	game.enter_attic()
	for key in ["snow", "alley", "firefly"]:
		game.collect_keepsake(key)
		_check(not game.route_link.can_decode(game, key), "%s keepsake alone cannot decode" % key)
		game.discover(game.route_link.ROUTES[key].planet)
		_check(game.route_link.decode(game, key), "%s unlocks once both lines have contributed" % key)
	game.route_link.navigate(game, "snow")
	game.return_to_menu()
	_check(game._attic_return.is_empty() and not game.route_board_open, "title return discards obsolete return snapshot")
	game.queue_free()
	await process_frame
	await _boot()
	_check(game.route_link.decoded.size() == 4 and game.route_link.verified_count(game) == 1,
		"reload preserves decoded clues separately from verified scans")
	_check(game.route_link.tracked == "snow" and game.route_link.echoes.snow.visible, "reload restores the selected objective and visible echo")
	_check(game.ship.target.planet_id == "baiyao" and game.planets[game.map_selected] == game.ship.target,
		"progressive world loading restores the tracked ship and map destination")
	game.hud._process(0.0)
	_check(game.hud.menu_attic.visible, "old discovery exposes persistent title entry after reload")
	game.hud.menu_attic.pressed.emit()
	_check(game.in_attic and not game._attic_return.is_empty(), "title entry prepares a safe return voyage")
	game.leave_attic()
	game.player.set_physics_process(false)
	_check(game.player.get_parent() == game.home and game.state == "walk", "title visit returns to a valid planetary spawn")
	for key in ["snow", "alley", "firefly"]:
		await _scan(key)
	_check(game.route_link.verified_count(game) == 4, "all four second signals have actually been scanned")
	game.enter_attic()
	_check(not game.route_link.finish(game), "four echoes alone cannot substitute for the heart and universe ending")
	game.enter_pocket("mirror")
	game.player.global_position = game.attic_worlds.heart_anchor("mirror").global_position
	game._interact()
	game.leave_pocket()
	_check(game.has_prism_heart and not game.route_link.finish(game), "mirror heart still requires the universe conclusion")
	game.leave_attic()
	for id in ["zheya", "xuanjing"]:
		game.discover(id)
	_check(game.missing_clues().is_empty(), "original three-coordinate universe route remains intact")
	game.discover("xuanyuan")
	_check(game.state == "end" and not game.in_attic, "original universe ending remains independently reachable")
	game.enter_attic()
	game.open_route_board()
	_check(not game.hud.route_finish.disabled, "both lines expose an enabled final action")
	game.hud.route_finish.pressed.emit()
	_check(game.route_link.completed and game.state == "end" and game.end_text.contains("归航图"), "actual heart action opens a distinct linked ending")
	_check(not game.route_link.finish(game), "linked ending cannot be awarded twice")
	_check(game.attic.tea_step == 0, "tea and optional combat are not required by the linked ending")
	game.hud._process(0.0)
	_check(game.hud.end_heading.text.contains("归航") and game.hud.end_return.visible, "linked ending has its own title and a real return button")
	await process_frame
	await process_frame
	var ending_panel: Control = game.hud.end_return.get_parent().get_parent().get_parent()
	_check(ending_panel.get_global_rect().encloses(game.hud.end_return.get_global_rect()), "linked ending return button fits inside its panel")
	game.hud.end_return.pressed.emit()
	_check(not game.in_attic and game.state == "walk", "linked ending returns to the original universe voyage")
	game._load_knowledge()
	_check(game.route_link.completed and game.route_link.verified_count(game) == 4, "completed linked ending is persisted")
	# Legacy saves have no attic_link field: discovery remains valid, verification is not fabricated.
	var legacy := FileAccess.open(KNOWLEDGE, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"logs": {"home": true, "eye": true}, "loops": 3}))
	legacy.close()
	game._load_knowledge()
	_check(game.route_link.unlocked(game) and game.discovered.has("qinglan") and game.loop_count == 3, "legacy universe IDs retain attic access")
	_check(game.route_link.decoded.is_empty() and not game.route_link.completed, "legacy save does not invent decoded clues or a final reward")
	game.return_to_menu()
	game.start_game()
	_check(game._attic_return.is_empty() and not game.in_attic, "new voyage clears old snapshots")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "every entry, panel and ending respects --no-capture")
	game.queue_free()
	await process_frame
	_cleanup()
	print("ROUTE LINK TEST COMPLETE: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
