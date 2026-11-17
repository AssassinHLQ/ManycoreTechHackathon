extends SceneTree

var failures := 0
var checks := 0
var game
const SAVE_FILES := ["user://export_check_knowledge.json", "user://export_check_progress.json"]


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func _run() -> void:
	_check(DisplayServer.get_name() == "headless", "verification stays headless")
	_check("--no-capture" in OS.get_cmdline_user_args(), "mouse capture is disabled")
	for path in ["THIRD_PARTY_NOTICES.md", "LICENSE", "assets/models/LICENSE_MANIFEST.json",
			"assets/licenses/godot-MIT.txt", "assets/licenses/GODOT_THIRD_PARTY.txt",
			"assets/licenses/OFL-LXGWWenKai.txt", "assets/licenses/OFL-NotoSansSymbols2.txt"]:
		_check(FileAccess.get_file_as_string("res://" + path).length() > 100, "packaged notice " + path)
	for folder in ["tests", "tools", "_tools", "captures", "build", "demo"]:
		_check(not DirAccess.dir_exists_absolute("res://" + folder), "excluded development directory " + folder)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = SAVE_FILES[0]
	game.progress_path = SAVE_FILES[1]
	root.add_child(game)
	await game.await_world_ready()
	var deadline := Time.get_ticks_msec() + 180000
	while (game.planets.size() < 20 or game.world_build_remaining) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(game.planets.size() == 20 and not game.world_build_remaining, "all twenty planets load from the package")
	_check(game.state == "menu", "main menu is ready")
	_check(game.station.get_meta("runtime_baked", "") == "station", "station uses its export snapshot")
	for planet in game.planets:
		_check(planet.get_meta("runtime_baked", "") == "planet_" + planet.planet_id,
			"baked planet " + planet.planet_id)
		_check(int(planet.surface.mesh.get_meta("runtime_lod_levels", 0)) > 0,
			"terrain LODs " + planet.planet_id)
	var credits := game.hud.menu.find_child("AssetCredits", true, false) as RichTextLabel
	_check(credits != null, "menu contains asset credits")
	if credits != null:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/LICENSE_MANIFEST.json"))
		for asset in manifest.get("assets", []):
			if asset.get("imported", false) and asset.get("license", "") == "CC BY 4.0":
				_check(credits.get_parsed_text().contains(asset.author) and credits.get_parsed_text().contains(asset.title),
					"packaged model credit " + asset.slug)
	game.start_game()
	for key in ["cloud", "firefly", "alley", "snow"]:
		_check(ResourceLoader.exists("res://scenes/attic_worlds/" + key + "_bindings.tres"), "pocket bindings " + key)
		game.enter_pocket(key)
		_check(game.player.can_process() and game.player.camera.far == game.LOCAL_SCENE_FAR,
			"pocket gameplay " + key)
		game.leave_pocket()
	game.leave_attic()
	for path in ["res://assets/models/ship-fighter/textures/base_color.png",
			"res://assets/models/space-station/textures/orm.png",
			"res://assets/models/props/attic-worlds/glow-mushroom/model_Image_0.jpg",
			"res://assets/models/qinglan-planet-v5/model_0.jpg"]:
		var texture := load(path) as Texture2D
		_check(texture != null, "packaged texture " + path)
		if texture != null:
			var image := texture.get_image()
			_check(image != null and image.is_compressed(), "GPU compressed texture " + path)
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured")
	game.queue_free()
	await process_frame
	for path in SAVE_FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("EXPORT PACKAGE COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
