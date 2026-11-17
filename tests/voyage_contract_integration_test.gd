extends SceneTree

const KNOWLEDGE := "user://voyage_contract_integration_knowledge.json"
const PROGRESS := "user://voyage_contract_integration_progress.json"

var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


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
	var build_deadline: int = Time.get_ticks_msec() + 180000
	while game._planet_by_id("zheya") == null and Time.get_ticks_msec() < build_deadline:
		await process_frame

	game.start_game()
	_check(game.voyage_contract.active, "starting a new game creates a readable contract")
	_check(game.hud.voyage_panel.visible, "the contract is visible in the live HUD")
	_check(game.voyage_contract.phase == "scan_home", "fresh contract starts at the windmill scan")
	game.discover("qinglan")
	_check(game.voyage_contract.phase == "scan_target" and game.voyage_contract.target_id == "zheya",
		"the windmill scan selects the first real destination")
	game.discover("zheya")
	_check(game.voyage_contract.phase == "recover", "the destination scan requests a ground beacon")

	var target = game._planet_by_id("zheya")
	var beacon := -1
	for i in range(target.interactive_spots.size()):
		if String(target.interactive_spots[i].get("kind", "")) == "beacon":
			beacon = i
			break
	_check(beacon >= 0, "the destination has a real beacon interaction")
	if beacon >= 0:
		var spot: Dictionary = target.interactive_spots[beacon]
		var local_pos: Vector3 = spot["local_pos"] if spot.has("local_pos") else target.surface_position(spot["dir"], float(spot["altitude"]))
		game.player.reparent(target, false)
		game.player.position = local_pos
		game.state = "walk"
		game.in_attic = false
		game._planet_interact()
	_check(game.voyage_contract.phase == "return", "the real beacon interaction advances the contract")

	game.state = "ship"
	game.ship.docked = true
	game.ship.docked_station = game.station
	var before_coins: int = game.progress.coins
	game._update_voyage_contract()
	_check(not game.voyage_contract.active, "homecoming-station docking completes the contract")
	_check(game.progress.coins > before_coins, "completion awards coins in the existing wallet")
	_check(game.progress.is_unlocked("voyage_first"), "the first completed voyage unlocks its achievement")
	game.queue_free()
	await process_frame
	_cleanup()
	print("VOYAGE_CONTRACT_INTEGRATION %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures > 0 else 0)
