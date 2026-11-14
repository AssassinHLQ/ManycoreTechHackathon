extends SceneTree
## Run once to create editable source scenes. Refuses to overwrite existing authored work.
const Authoring = preload("res://scripts/attic_world_authoring.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var worlds = load("res://scripts/attic_worlds.gd").new()
	worlds.use_authored_scenes = false
	root.add_child(worlds)
	worlds.build()
	DirAccess.make_dir_recursive_absolute(Authoring.DIRECTORY)
	for key in ["cloud", "firefly", "alley", "snow"]:
		var path: String = Authoring.DIRECTORY + key + ".tscn"
		if FileAccess.file_exists(path):
			push_error("Refusing to overwrite editable scene: " + path)
			quit(1)
			return
		var content: Node3D = worlds.worlds[key]["content"]
		var spawn := Marker3D.new()
		spawn.name = "PlayerSpawn"
		spawn.position = content.transform.affine_inverse() * worlds.worlds[key]["spawn"]
		content.add_child(spawn)
		var result := Authoring.save_content(content, key)
		if result != OK:
			push_error("Cannot save " + path + ": " + error_string(result))
			quit(1)
			return
		print("SAVED ", path)
	worlds.free()
	quit()
