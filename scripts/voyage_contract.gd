extends RefCounted

## One-time two-step route from the starting world to home.
const RETURN_STATION := "return_station"
const GO_HOME := "go_home"
const COMPLETE := "complete"

var active := false
var phase := COMPLETE
var completed_count := 0


func load_data(value) -> void:
	active = false
	phase = COMPLETE
	completed_count = 0
	if not (value is Dictionary):
		return
	var data: Dictionary = value
	var saved_phase := String(data.get("phase", ""))
	if saved_phase == COMPLETE and int(data.get("completed_count", 0)) >= 2:
		completed_count = 2
		return
	if saved_phase == GO_HOME:
		completed_count = 1
		phase = GO_HOME
	else:
		# Old saves counted repeatable scan-and-beacon contracts. Their count
		# does not imply completion of either new objective.
		phase = RETURN_STATION
	active = bool(data.get("active", false)) or not data.is_empty()


func save_data() -> Dictionary:
	return {
		"active": active,
		"phase": phase,
		"completed_count": completed_count,
	}


func start(_discovered: Dictionary = {}) -> bool:
	if active or completed_count >= 2:
		return false
	active = true
	phase = RETURN_STATION if completed_count == 0 else GO_HOME
	return true


func arrive_at_station() -> bool:
	if not active or phase != RETURN_STATION:
		return false
	completed_count = 1
	phase = GO_HOME
	return true


func arrive_home() -> bool:
	if not active or phase != GO_HOME:
		return false
	active = false
	phase = COMPLETE
	completed_count = 2
	return true


func status(_discovered: Dictionary = {}, _in_attic := false) -> Dictionary:
	if phase == GO_HOME:
		return {"active": true, "title": "归家", "progress": "从归航站回家", "hint": ""}
	if phase == RETURN_STATION:
		return {"active": true, "title": "返回归航站", "progress": "前往归航站", "hint": ""}
	return {"active": false, "title": "", "progress": "", "hint": ""}
