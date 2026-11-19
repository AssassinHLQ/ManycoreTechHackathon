extends SceneTree

const KNOWLEDGE := "user://voyage_contract_integration_knowledge.json"
const PROGRESS := "user://voyage_contract_integration_progress.json"
const ContractScript = preload("res://scripts/voyage_contract.gd")

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
	_check(game.voyage_contract.active, "starting a new game creates the first objective")
	_check(game.voyage_contract.phase == ContractScript.RETURN_STATION,
		"the first objective is to return to the Homecoming Station")

	game.state = "ship"
	game.ship.docked = true
	game.ship.docked_station = game.station
	var before_coins: int = game.progress.coins
	game._update_voyage_contract()
	_check(game.voyage_contract.active and game.voyage_contract.phase == ContractScript.GO_HOME,
		"docking at the Homecoming Station advances to the home objective")
	game._enter_attic_space()
	_check(not game.voyage_contract.active and game.voyage_contract.completed_count == 2,
		"entering home completes the second and final objective")
	_check(game.progress.coins == before_coins, "the two objectives award no coins")
	game.queue_free()
	await process_frame
	_cleanup()
	print("VOYAGE_CONTRACT_INTEGRATION %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures > 0 else 0)
