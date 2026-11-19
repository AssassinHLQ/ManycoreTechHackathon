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
	await worlds.build()
	var other = load("res://scripts/attic_worlds.gd").new()
	root.add_child(other)
	for key in ["cloud", "firefly", "alley", "snow"]:
		var holder := Node3D.new()
		other.add_child(holder)
		_check(await worlds.Authoring.load_world(other, key, holder), key + " second instance loads cached scene")
		var content: Node3D = worlds.worlds[key]["content"]
		_check(content.scene_file_path.ends_with(key + ".tscn"), key + " uses the editable scene")
		_check(content.is_ancestor_of(worlds.return_anchor(key)), key + " return portal rebound")
		_check(content.get_node("StorySign/Text").text == worlds.Authoring.LINES[key], key + " sign text")
		var story_sign := content.get_node("StorySign") as Node3D
		_check(story_sign.visible, key + " story sign remains physically discoverable")
		_check(story_sign.position.is_equal_approx(worlds.Authoring.SIGN_POSITIONS[key]),
			key + " story sign is placed behind the approach obstruction")
		_check(story_sign.rotation.y == 0.0, key + " story sign faces the reachable approach side")
		_check(story_sign.scale.is_equal_approx(Vector3.ONE * 0.32), key + " story sign stays subtle in scale")
		_check(content.get_node_or_null("StoryWall") == null, key + " has no runtime story wall")
		_check(content.find_children("MeshSelfCollision", "StaticBody3D", true, false).size() > 0,
			key + " loads baked mesh collisions")
		_check(content.get_meta("collision_ready", false), key + " collision state is ready on load")
		for id in worlds.prop_ids_in(key):
			_check(content.is_ancestor_of(worlds.prop_anchor(id)), key + " prop anchor " + id)
		for index in range(3):
			var device: Dictionary = worlds.device_nodes[key][index]
			_check(content.is_ancestor_of(device["anchor"]), key + " device anchor")
			_check(device["mesh"].material_override == device["material"], key + " device material rebound")
			var fresh_material: StandardMaterial3D = other.device_nodes[key][index]["material"]
			var fresh_color := fresh_material.albedo_color
			var fresh_energy := fresh_material.emission_energy_multiplier
			_check(device["material"] != fresh_material, key + " puzzle material is isolated per game")
			worlds.activate_device(key, index)
			_check(fresh_material.albedo_color == fresh_color and fresh_material.emission_energy_multiplier == fresh_energy,
				key + " puzzle changes leave the other game untouched")
	var generated_content := Node3D.new()
	worlds.Authoring.add_story_sign(generated_content, "snow")
	_check(generated_content.get_node("StorySign").visible, "generated story signs remain discoverable")
	_check(generated_content.get_node("StorySign").position.is_equal_approx(worlds.Authoring.SIGN_POSITIONS.snow),
		"generated story sign uses the hidden snow placement")
	_check(generated_content.get_node("StorySign").rotation.y == 0.0,
		"generated story signs face the reachable approach side")
	_check(generated_content.get_node_or_null("StoryWall") == null,
		"generated story signs do not create a runtime screen wall")
	generated_content.free()
	worlds.use_winch()
	worlds.update_bridge(0.2)
	_check(worlds.worlds.cloud.content.is_ancestor_of(worlds.bridge_node), "bridge animation uses editable node")
	worlds.use_hearth()
	_check(worlds.worlds.snow.content.is_ancestor_of(worlds.hearth_light), "hearth light rebound")
	for index in range(3):
		worlds.light_court_lamp(index)
		_check(worlds.court_lamps[index].lamp.material_override == worlds.court_lamps[index].material,
			"rain court material rebound")
		_check(worlds.court_lamps[index].material != other.court_lamps[index].material,
			"rain court material is isolated per game")
	worlds.board_boat(worlds.boat_node.global_position)
	worlds.update_boat(1.0, 0.2, 0.1)
	_check(worlds.worlds.cloud.content.is_ancestor_of(worlds.boat_node), "boat uses editable node")
	worlds.update_airship(0.1)
	_check(worlds.worlds.cloud.content.is_ancestor_of(worlds.airship_node), "airship uses editable node")
	_check(worlds.scope_archive != null, "telescope archive is built")
	var archive_grid: GridContainer = worlds.scope_archive.get_node("Screen/ArchiveGrid")
	_check(archive_grid.get_child_count() == 4, "telescope archive has all four inscriptions")
	for key in worlds.SCOPE_ARCHIVE_ORDER:
		var archive_label: Label = archive_grid.get_node("Archive_%s/Text" % String(key).capitalize())
		_check(archive_label.text == "%s · %s" % [worlds.SCOPE_ARCHIVE_NAMES[key], worlds.Authoring.LINES[key]],
			"telescope archive preserves the %s inscription" % key)
	_check(not worlds.scope_archive.visible, "telescope archive starts hidden")
	worlds.use_scope()
	_check(worlds.scope_archive.visible, "using the telescope reveals the archive")
	worlds.close_scope()
	_check(not worlds.scope_archive.visible, "leaving the telescope hides the archive")
	# The editable source includes the complete scenery hierarchy.
	var path := "res://scenes/attic_worlds/firefly.tscn"
	var scene: PackedScene = load(path)
	var state := scene.get_state()
	_check(state.get_node_count() > 100, "editable scene contains scenery, not just a preview")
	other.free()
	worlds.free()
	print("ATTIC AUTHORING TEST: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
