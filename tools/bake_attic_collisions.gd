extends SceneTree
## Add missing static mesh collision nodes to the editable pocket-world scenes.
## This is an offline migration. Runtime loading never performs this work.
const Authoring := preload("res://scripts/attic_world_authoring.gd")
const KEYS := ["cloud", "firefly", "alley", "snow"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for key in KEYS:
		var path: String = Authoring.DIRECTORY + key + ".tscn"
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Cannot load " + path)
			quit(1)
			return
		var content := packed.instantiate() as Node3D
		if content == null:
			push_error("Cannot instantiate " + path)
			quit(1)
			return
		var result: Error = Authoring.save_content(content, key)
		content.free()
		if result != OK:
			push_error("Cannot save " + path + ": " + error_string(result))
			quit(1)
			return
		print("COLLISIONS BAKED ", path)
	quit()
