extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var worlds = load("res://scripts/attic_worlds.gd").new()
	root.add_child(worlds)
	worlds.build()
	for key in ["cloud", "firefly", "alley", "snow"]:
		var content: Node3D = worlds.worlds[key]["content"]
		_check(content.scene_file_path.ends_with(key + ".tscn"), key + " uses the editable scene")
		_check(content.is_ancestor_of(worlds.return_anchor(key)), key + " return portal rebound")
		_check(content.get_node("StorySign/Text").text == worlds.Authoring.LINES[key], key + " sign text")
		for id in worlds.prop_ids_in(key):
			_check(content.is_ancestor_of(worlds.prop_anchor(id)), key + " prop anchor " + id)
		for index in range(3):
			var device: Dictionary = worlds.device_nodes[key][index]
			_check(content.is_ancestor_of(device["anchor"]), key + " device anchor")
			_check(device["mesh"].material_override == device["material"], key + " device material rebound")
			worlds.activate_device(key, index)
	worlds.use_winch()
	worlds.update_bridge(0.2)
	_check(worlds.worlds.cloud.content.is_ancestor_of(worlds.bridge_node), "bridge animation uses editable node")
	worlds.use_hearth()
	_check(worlds.worlds.snow.content.is_ancestor_of(worlds.hearth_light), "hearth light rebound")
	for index in range(3):
		worlds.light_court_lamp(index)
		_check(worlds.court_lamps[index].lamp.material_override == worlds.court_lamps[index].material,
			"rain court material rebound")
	worlds.board_boat(worlds.boat_node.global_position)
	worlds.update_boat(1.0, 0.2, 0.1)
	_check(worlds.worlds.cloud.content.is_ancestor_of(worlds.boat_node), "boat uses editable node")
	worlds.update_airship(0.1)
	_check(worlds.worlds.cloud.content.is_ancestor_of(worlds.airship_node), "airship uses editable node")
	# The editable source includes the complete scenery hierarchy.
	var path := "res://scenes/attic_worlds/firefly.tscn"
	var scene: PackedScene = load(path)
	var state := scene.get_state()
	_check(state.get_node_count() > 100, "editable scene contains scenery, not just a preview")
	worlds.free()
	print("ATTIC AUTHORING TEST: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
