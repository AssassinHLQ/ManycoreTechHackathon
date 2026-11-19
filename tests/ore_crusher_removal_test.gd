extends SceneTree

const PlanetScript := preload("res://scripts/planet.gd")


func _initialize() -> void:
	if PlanetScript.PROP_MODELS.has("cave-mine-cart"):
		push_error("PROP_MODELS still exposes the removed cave mine cart")
		quit(1)
		return
	var spawned_prop_ids: Array[String] = []
	for entry in PlanetScript.INTERACTIVE_SEED:
		spawned_prop_ids.append(String(entry[0]))
	if spawned_prop_ids.has("ore-crusher"):
		push_error("INTERACTIVE_SEED still spawns ore-crusher")
		quit(1)
		return
	print("PASS  cave mine cart is unavailable and planet seeds omit ore-crusher")
	quit(0)
