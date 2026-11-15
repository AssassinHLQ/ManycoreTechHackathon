extends SceneTree
## Run headless before exporting. Snapshots are ignored generated runtime assets.
var game
const FILES := ["user://runtime_bake_knowledge.json", "user://runtime_bake_progress.json"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not "--rebake-runtime" in OS.get_cmdline_user_args():
		push_error("Bake requires --rebake-runtime to capture CPU-side prop transforms; no assets were changed.")
		quit(2)
		return
	# This dedicated generated directory contains no authored assets.
	var directory := "res://assets/runtime_bakes/"
	DirAccess.make_dir_recursive_absolute(directory)
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension() in ["res", "scn"]:
			var error := DirAccess.remove_absolute(directory + filename)
			if error != OK:
				push_error("Cannot clear old runtime bake: " + filename)
				quit(1)
				return
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = FILES[0]
	game.progress_path = FILES[1]
	root.add_child(game)
	await game.await_world_ready()
	while game.world_build_remaining or game.planets.size() < 20:
		await process_frame
	# Let queued removals from mesh merging finish before saving the hierarchy.
	await process_frame
	for planet in game.planets:
		var error: Error = planet.SurfaceBake.save_surface(planet)
		if error != OK:
			push_error("Terrain bake failed: %s %s" % [planet.planet_id, error_string(error)])
			quit(1)
			return
		print("BAKED TERRAIN ", planet.planet_id)
		# Store the modified terrain as plain mesh nodes. Imported scene
		# instances otherwise restore their original GLB mesh on instantiation.
		var old_surface: Node = planet._lux_root
		var children: Array = planet.get_meta("bake_children")
		children.erase(old_surface)
		old_surface.free()
		planet.surface = null
		if not planet.SurfaceBake.load_surface(planet):
			push_error("Cannot restore baked terrain: " + planet.planet_id)
			quit(1)
			return
		children.append(planet._lux_root)
		var collision: Node = planet.get_node_or_null("TerrainCollision")
		if collision != null:
			collision.free()
		planet.terrain_collision_done = false
		error = planet.RuntimeBake.save_generated(planet, "planet_" + planet.planet_id, [
			"res://scripts/main.gd", "res://scripts/planet.gd", "res://scripts/planet_surface_bake.gd",
			"res://scripts/architecture.gd", "res://scripts/underground.gd",
			"res://scripts/procedural_geometry.gd", "res://scripts/procedural_dressing.gd",
			"res://scripts/prop_placement.gd", "res://scripts/settings.gd"], planet.SurfaceBake._signature(planet))
		if error != OK:
			push_error("Planet snapshot failed: %s %s" % [planet.planet_id, error_string(error)])
			quit(1)
			return
		print("BAKED WORLD ", planet.planet_id)
		await process_frame
	var error: Error = game.station.RuntimeBake.save_generated(game.station, "station", [
		"res://scripts/station.gd", "res://scripts/procedural_geometry.gd",
		"res://scripts/procedural_dressing.gd", "res://scripts/prop_placement.gd"])
	if error != OK:
		push_error("Station bake failed: " + error_string(error))
		quit(1)
		return
	print("BAKED STATION")
	error = preload("res://tools/bake_runtime_lods.gd").generate()
	if error != OK:
		push_error("Visual LOD bake failed: " + error_string(error))
		quit(1)
		return
	game.free()
	for path in FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RUNTIME BAKE COMPLETE: 20 terrains and homecoming station")
	quit()
