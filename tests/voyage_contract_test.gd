extends SceneTree

const ContractScript = preload("res://scripts/voyage_contract.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _run() -> void:
	var contract = ContractScript.new()
	_check(contract.start(), "a fresh save starts the station-return objective")
	_check(contract.phase == ContractScript.RETURN_STATION, "the first objective is returning to the station")
	_check(not contract.arrive_home(), "home cannot complete before returning to the station")
	_check(contract.arrive_at_station(), "docking completes the first objective")
	_check(contract.phase == ContractScript.GO_HOME and contract.completed_count == 1,
		"the second objective is going home from the station")
	var restored = ContractScript.new()
	restored.load_data(contract.save_data())
	_check(restored.active and restored.phase == ContractScript.GO_HOME,
		"the second objective survives save and reload")
	_check(restored.arrive_home(), "entering home completes the second objective")
	_check(not restored.active and restored.completed_count == 2,
		"the two-step route ends after exactly two objectives")
	_check(not restored.start(), "the completed two-step route does not repeat")
	var migrated = ContractScript.new()
	migrated.load_data({"active": true, "phase": "recover", "target_id": "zheya", "reward": 200,
		"completed_count": 8})
	_check(migrated.active and migrated.phase == ContractScript.RETURN_STATION
		and migrated.completed_count == 0, "legacy scan contracts migrate to the new first objective")
	_check(not migrated.save_data().has("reward"), "the new route carries no reward data")
	print("VOYAGE_CONTRACT_TEST %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures > 0 else 0)
