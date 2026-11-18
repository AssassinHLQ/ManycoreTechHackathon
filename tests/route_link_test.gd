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


func _has_route_board_ui() -> bool:
	for node in game.hud.find_children("*", "Label", true, false):
		if (node as Label).text.contains("航海回声台"):
			return true
	for node in game.hud.find_children("*", "Button", true, false):
		var label := (node as Button).text
		if label.contains("回声台") or label.contains("解读回声"):
			return true
	return false


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
	game.in_station = false
	game.active_station = null
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


func _check_scan_guidance_range() -> void:
	var origin: Vector3 = game.get_active_position()
	var saved_positions: Array[Vector3] = []
	var close_target: Node3D = game.anomalies[0]
	var distant_target: Node3D = game.anomalies[1]
	for index in range(game.anomalies.size()):
		var anomaly: Node3D = game.anomalies[index]
		saved_positions.append(anomaly.global_position)
		anomaly.global_position = origin + Vector3(5000.0 + index * 300.0, 0.0, 0.0)
	close_target.global_position = origin + Vector3(0.0, 0.0, -300.0)
	distant_target.global_position = origin + Vector3(0.0, 0.0, -1300.0)
	var guidance = game.hud.drawing._scan_guidance_target(origin)
	_check(guidance == close_target, "scan guidance selects the nearest eligible signal within 1200 m")
	close_target.global_position = origin + Vector3(0.0, 0.0, -1500.0)
	_check(game.hud.drawing._scan_guidance_target(origin) == null,
		"scan guidance does not point across interplanetary distances beyond 1200 m")
	for index in range(game.anomalies.size()):
		(game.anomalies[index] as Node3D).global_position = saved_positions[index]


func _run() -> void:
	_cleanup()
	await _boot()
	_check(game.route_link.echoes.size() == 4, "four real surface echoes are built")
	_check(not game.route_link.unlocked(game), "new save has no windmill route clue")
	game.hud._process(0.0)
	_check(game.hud.menu_attic.disabled, "title explains the physical home entrance without teleporting")
	game.request_attic_visit()
	_check(game.state == "menu" and not game.in_attic, "title request cannot bypass the physical station entrance")
	game.start_game()
	game.player.set_physics_process(false)
	_check_scan_guidance_range()
	var cloud: Node3D = game.route_link.echoes.cloud
	_aim_at(cloud)
	await physics_frame
	_check(not cloud.visible and game._find_scan_target() != cloud, "undecoded echo is invisible and excluded from scanner")
	game.discover(cloud.anomaly_id)
	_check(not game.discovered.has(cloud.anomaly_id), "discovery guard rejects an undecoded echo")
	game.discover("qinglan")
	_check(game.route_link.unlocked(game), "windmill discovery makes route clues available")
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
	var pause_has_home_entry := false
	for node in game.hud.pause_menu.find_children("*", "Button", true, false):
		if (node as Button).text.contains("阁楼") or (node as Button).text.contains("回家"):
			pause_has_home_entry = true
	_check(not pause_has_home_entry, "pause menu has no teleport to the attic")
	game.enter_attic()
	_check(not game.in_attic, "direct public entry also rejects a landed ship")
	game.set_paused(false)
	preload("res://tests/home_fixture.gd").enter(game)
	_check(game.in_attic and game.state == "walk", "E at the homecoming station door enters home")
	var clock: float = game.elapsed
	await process_frame
	await process_frame
	_check(is_equal_approx(game.elapsed, clock), "attic preserves the remaining loop time")
	_check(not game.route_link.can_decode(game, "cloud"), "universe discovery alone cannot decode")
	game.collect_keepsake("cloud")
	for door in game.attic.doors:
		game.player.global_position = door.anchor.global_position
		game._interact()
		_check(game.pocket_key == door.key and not _has_route_board_ui(), "music box story UI cannot intercept the %s door" % door.key)
		if game.in_pocket():
			game.leave_pocket()
	var record: Node3D = game.attic.anchors.AtticAnchor_Record
	var record_label: Label3D = game.attic.find_child("RouteRecordLabel", true, false)
	_check(record_label != null and record_label.text.contains("返回空间站"),
		"music box label gives a direct station-return instruction")
	game.player.global_position = record.global_position
	game._interact()
	_check(not game.in_attic and game.in_station and game.player.get_parent() == game.station,
		"E at the music box returns directly to the homecoming station")
	_check(not _has_route_board_ui(), "music box does not build the removed route panel")
	var route_menu_button := false
	for node in game.hud.pause_menu.find_children("*", "Button", true, false):
		if (node as Button).text.contains("回声台"):
			route_menu_button = true
	_check(not route_menu_button, "pause menu no longer exposes the route panel")
	preload("res://tests/home_fixture.gd").enter(game)
	_check(game.in_attic, "the station entrance remains the only way back into the attic")
	_check(game.route_link.decode(game, "cloud") and game.route_link.decoded.has("cloud") and cloud.visible,
		"route data can still decode a separate surface signal")
	_check(not game.discovered.has(cloud.anomaly_id), "decoding never awards universe verification")
	_check(not game.route_link.decode(game, "cloud"), "decoding is idempotent")
	game.route_link.navigate(game, "cloud")
	_check(game.ship.target == game.home and game.route_link.tracked == "cloud", "navigate button sets the real ship target and surface tracking")
	_check(not game.route_link.finish(game), "incomplete records cannot trigger the linked ending")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	game._unhandled_input(cancel)
	_check(game.paused and not _has_route_board_ui(), "Esc opens pause without restoring the removed route panel")
	game._unhandled_input(cancel)
	_check(not game.paused, "Esc closes the pause menu")
	game.leave_attic()
	_check(game.state == "walk" and game.in_station and game.player.get_parent() == game.station and not game.paused, "return restores the homecoming station interior and input")
	_check(game.elapsed == clock and game.ship.fuel == 63.5 and game.ship.hull == 74.0, "return preserves loop time, ship fuel and damage")
	await _scan("cloud")
	_check(game.route_link.tracked == "", "completed scan clears the active surface objective")
	var count: int = game.discovered.size()
	game.discover(cloud.anomaly_id)
	_check(game.discovered.size() == count, "repeated discovery grants no duplicate record")
	# Planetary entry is rejected; a subsequent real station visit preserves suit resources.
	var local_pose: Transform3D = game.player.transform
	game.player.velocity = Vector3(0.1, 0.2, 0.3)
	game.player.oxygen = 49.0
	game.player.fuel = 37.0
	game.enter_attic()
	_check(not game.in_attic, "planetary walking cannot bypass the station door")
	_check(game.player.transform.is_equal_approx(local_pose), "rejected entry does not move the player")
	preload("res://tests/home_fixture.gd").arrive(game)
	game.player.oxygen = 49.0
	game.player.fuel = 37.0
	game._interact()
	game.player.oxygen = 100.0
	game.player.fuel = 100.0
	game.leave_attic()
	_check(game.player.get_parent() == game.station, "walking return uses the station reference")
	_check(game.player.oxygen == 49.0 and game.player.fuel == 37.0, "attic refill cannot leak into original suit resources")
	# The public station path must preserve its interior reference and docked ship.
	game.ship.docked = true
	game.ship.docked_station = game.station
	game.enter_station()
	game.request_attic_visit()
	_check(not game.in_attic, "station arrival alone does not bypass its home door")
	game.player.global_position = game.station.home_door_position()
	var station_pose: Transform3D = game.player.transform
	var station_view: Transform3D = game.player.camera.transform
	game.player.velocity = Vector3(0.1, 0.2, 0.3)
	_check(game.can_visit_attic(), "physical home door is the only attic entrance")
	game._interact()
	_check(game.in_attic, "E at the physical home door enters the attic")
	game.leave_attic()
	_check(game.in_station and game.active_station == game.station and game.player.get_parent() == game.station,
		"station return restores interior and active station")
	_check(game.player.transform.is_equal_approx(station_pose) and game.ship.docked and game.ship.docked_station == game.station,
		"station return preserves local spawn and docking")
	_check(game.player.camera.transform.is_equal_approx(station_view) and game.player.velocity == Vector3(0.1, 0.2, 0.3),
		"station return restores view and velocity")
	# Test the reverse order too: keepsakes acquired before their universe records.
	game.enter_attic()
	for key in ["snow", "alley", "firefly"]:
		game.collect_keepsake(key)
		_check(not game.route_link.can_decode(game, key), "%s keepsake alone cannot decode" % key)
		game.discover(game.route_link.ROUTES[key].planet)
		_check(game.route_link.decode(game, key), "%s unlocks once both lines have contributed" % key)
	game.route_link.navigate(game, "snow")
	game.return_to_menu()
	_check(game._attic_return.is_empty(), "title return discards obsolete return snapshot")
	game.queue_free()
	await process_frame
	await _boot()
	_check(game.route_link.decoded.size() == 4 and game.route_link.verified_count(game) == 1,
		"reload preserves decoded clues separately from verified scans")
	_check(game.route_link.tracked == "snow" and game.route_link.echoes.snow.visible, "reload restores the selected objective and visible echo")
	_check(game.ship.target.planet_id == "baiyao" and game.planets[game.map_selected] == game.ship.target,
		"progressive world loading restores the tracked ship and map destination")
	game.hud._process(0.0)
	_check(game.hud.menu_attic.disabled, "saved discovery does not enable title teleportation")
	game.hud.menu_attic.pressed.emit()
	game.enter_attic()
	_check(not game.in_attic and game.state == "menu" and game._attic_return.is_empty(), "title and direct calls cannot bypass the station")
	game.start_game()
	game.player.set_physics_process(false)
	for key in ["snow", "alley", "firefly"]:
		await _scan(key)
	_check(game.route_link.verified_count(game) == 4, "all four second signals have actually been scanned")
	preload("res://tests/home_fixture.gd").enter(game)
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
	_check(not game.in_attic and game.state == "end", "universe ending cannot directly teleport home")
	game.resume_home_voyage()
	_check(not game.in_attic and game.state == "walk", "ending continues the voyage toward the station")
	preload("res://tests/home_fixture.gd").enter(game)
	_check(game.route_link.finish(game), "the completed records and heart can still close the linked ending")
	_check(game.route_link.completed and game.state == "end" and game.end_text.contains("归航图"), "completed records open the linked ending")
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
	_check(game.route_link.unlocked(game) and game.discovered.has("qinglan") and game.loop_count == 3, "legacy universe IDs retain route knowledge")
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
