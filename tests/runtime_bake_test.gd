extends SceneTree

const Bake = preload("res://scripts/runtime_bake.gd")
const Planet = preload("res://scripts/planet.gd")
var game
var failures := 0
var checks := 0
const FILES := ["user://runtime_bake_test_knowledge.json", "user://runtime_bake_test_progress.json"]

class TransformCounter extends Node3D:
	var changes := 0
	func _init() -> void:
		set_notify_transform(true)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSFORM_CHANGED:
			changes += 1


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = FILES[0]
	game.progress_path = FILES[1]
	root.add_child(game)
	await game.await_world_ready()
	while game.world_build_remaining or game.planets.size() < 20:
		await process_frame
	await physics_frame
	_check(game.station.get_meta("runtime_baked", "") == "station", "station loads its export snapshot")
	_check(game.station.orbit_planet == game.home, "cached station binds its orbit to the current home planet")
	_check(game.station.door_panels.size() == 6, "all six live station doors remain bound")
	_check(game.station.merge_live_materials[0] == game.station._beacon_material, "station beacon keeps its live material binding")
	for host in [game.home, game.station]:
		var watch := TransformCounter.new()
		host.add_child(watch)
		watch.force_update_transform()
		watch.changes = 0
		for tick in range(12):
			host._update_orbit()
			watch.force_update_transform()
		_check(watch.changes == 0, host.name + " frozen orbit does not dirty descendant transforms")
		var original_time: float = host._orbit_time
		host._orbit_time += 1.0
		host._update_orbit()
		watch.force_update_transform()
		_check(watch.changes > 0, host.name + " advancing orbit still updates descendant transforms")
		host._orbit_time = original_time
		host._update_orbit()
		watch.free()
	var players := 0
	for body in game.find_children("*", "CharacterBody3D", true, false):
		if body.get_script() == game.player.get_script():
			players += 1
	_check(players == 1, "snapshot does not duplicate the live player")
	for door in game.station.door_panels:
		_check(is_instance_valid(door) and game.station.is_ancestor_of(door), "door belongs to the current station instance")
	for planet in game.planets:
		_check(planet.get_meta("runtime_baked", "") == "planet_" + planet.planet_id, planet.planet_id + " uses a baked world")
		var props_valid := true
		for prop in planet.find_children("Prop_*", "MultiMeshInstance3D", true, false):
			props_valid = props_valid and prop.get_meta("runtime_transforms", []).size() == prop.multimesh.instance_count \
				and prop.get_meta("runtime_colors", PackedColorArray()).size() == prop.multimesh.instance_count
		_check(props_valid, planet.planet_id + " preserves every cached prop transform and tint")
		_check(planet.surface != null and planet._lux_height_ready, planet.planet_id + " retains its visual terrain and height queries")
		_check(int(planet.surface.mesh.get_meta("runtime_lod_levels", 0)) > 0, planet.planet_id + " has offline visual LODs")
		planet._ensure_terrain_collision()
		_check(planet.get_node_or_null("TerrainCollision") != null and planet.terrain_collision_done, planet.planet_id + " restores its landing collision")
		for spot in planet.interactive_spots:
			if spot.node != null:
				_check(is_instance_valid(spot.node) and planet.is_ancestor_of(spot.node), planet.planet_id + " interaction points at its own scene")
				break
	var home = game.home
	var bodies_before: int = home.find_children("*", "StaticBody3D", true, false).size()
	preload("res://scripts/web_static_batch.gd").apply(home, true)
	var report: Dictionary = home.get_node("Architecture_Qinglan").get_meta("web_batched", {})
	_check(int(report.get("sources", 0)) > 50 and int(report.get("batches", 0)) < int(report.get("sources", 0)), "real windmill landmark reduces its draw batches")
	_check(report.get("triangles", -1) == report.get("output_triangles", -2), "windmill batching preserves every source triangle")
	_check(home.find_children("*", "StaticBody3D", true, false).size() == bodies_before, "windmill batching preserves every collision body")
	var clone = Planet.new()
	await Bake.prepare_generated(self, "planet_" + home.planet_id)
	_check(await Bake.load_generated(clone, "planet_" + home.planet_id, home.SurfaceBake._signature(home)), "a second copy of the same planet can load")
	_check(Bake._prepared_scenes.is_empty(), "prepared snapshots are consumed without retaining a second world")
	var collision_enabled := true
	for body in clone.find_children("*", "StaticBody3D", true, false):
		collision_enabled = collision_enabled and body.process_mode != Node.PROCESS_MODE_DISABLED
	_check(collision_enabled, "snapshots retain enabled collision before the proximity budget runs")
	var unscaled_ranges := true
	for node in clone.find_children("*", "GeometryInstance3D", true, false):
		if node.visibility_range_end > 0.0 and node.visibility_range_end < 119.9:
			unscaled_ranges = false
	_check(unscaled_ranges, "snapshots do not embed a developer's reduced viewing distance")
	_check(clone._lux_height_map == home._lux_height_map, "cached terrain keeps identical height samples across instances")
	var tested := false
	for i in range(home.interactive_spots.size()):
		var original: Dictionary = home.interactive_spots[i]
		if i >= clone.interactive_spots.size():
			_check(false, "cached planet preserves every interactive point")
			break
		var copied: Dictionary = clone.interactive_spots[i]
		if original.node is MultiMeshInstance3D and int(original.mi) >= 0:
			var original_mm: MultiMesh = original.node.multimesh
			var copied_mm: MultiMesh = copied.node.multimesh
			var transforms: Array = original.node.get_meta("runtime_transforms", [])
			var colors: PackedColorArray = original.node.get_meta("runtime_colors", PackedColorArray())
			_check(transforms.size() == original_mm.instance_count and colors.size() == original_mm.instance_count, "headless bake preserves every prop transform and tint")
			_check(not transforms.is_empty() and transforms[0].origin.length() > home.radius * 0.8, "surface prop transforms remain on the planet instead of collapsing to the origin")
			_check(original_mm != copied_mm, "interactive instance colors are isolated between games")
			var before := original_mm.get_instance_color(int(original.mi))
			for charge in range(int(copied.charges)):
				clone.consume_interactive(i)
			_check(original_mm.get_instance_color(int(original.mi)) == before and int(original.charges) > 0,
				"using a cached prop does not consume or recolor the other game")
			tested = true
			break
	_check(tested, "exercise a real surface prop interaction")
	clone.free()
	var invalid := Node3D.new()
	_check(not (await Bake.load_generated(invalid, "planet_" + home.planet_id, {"radius": -1})), "changed geometry parameters reject stale snapshots")
	_check(invalid.get_child_count() == 0, "a rejected snapshot leaves no partial scene")
	invalid.free()
	game.free()
	for path in FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RUNTIME BAKE TEST COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
