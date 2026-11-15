extends SceneTree
## Rebuild default gameplay paths from generated templates. Geometry is never overwritten.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var worlds = load("res://scripts/attic_worlds.gd").new()
	worlds.use_authored_scenes = false
	root.add_child(worlds)
	worlds.build()
	for key in ["cloud", "firefly", "alley", "snow"]:
		var result: Error = worlds.Authoring.save_bindings(worlds, key)
		if result != OK:
			push_error(error_string(result))
			quit(1)
			return
		print("BINDINGS SAVED ", key)
	worlds.free()
	quit()
