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
	var discovered := {}
	_check(contract.start(discovered), "a fresh save starts a voyage contract")
	_check(contract.phase == "scan_home", "the first step points at the home signal")
	_check(contract.on_discovered("qinglan"), "home scan advances the contract")
	_check(contract.phase == "scan_target" and contract.target_id == "zheya",
		"the first target is a real secondary planet")
	_check(contract.on_discovered("zheya"), "target scan advances the contract")
	_check(contract.phase == "recover", "target scan asks for a physical beacon interaction")
	_check(contract.on_beacon("zheya"), "the target beacon advances the contract")
	_check(contract.phase == "return", "beacon interaction asks for a homecoming return")
	var saved: Dictionary = contract.save_data()
	var restored = ContractScript.new()
	restored.load_data(saved)
	_check(restored.active and restored.phase == "return" and restored.target_id == "zheya",
		"an active contract survives save and reload")
	var earned: int = int(restored.reward)
	_check(restored.complete_at_home(), "docking completion closes the contract")
	_check(not restored.active and restored.completed_count == 1,
		"completion increments the voyage count")
	_check(earned >= 140, "completion carries a meaningful reward")
	var next = ContractScript.new()
	next.completed_count = 1
	_check(next.start({"qinglan": true, "zheya": true}), "a later voyage can start after the first target")
	_check(next.target_id == "cangbo", "later voyages rotate to another planet")
	print("VOYAGE_CONTRACT_TEST %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures > 0 else 0)
