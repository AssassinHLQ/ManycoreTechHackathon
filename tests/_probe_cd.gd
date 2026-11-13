extends SceneTree
# 验证 C（LRU 缓存上限）与 D（LOD 绘制距离）是否生效。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _mb(b: int) -> String:
	return "%.0f MB" % (float(b) / 1048576.0)


func _run() -> void:
	var save_path := "user://starward_cd.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()

	var deadline := Time.get_ticks_msec() + 180000
	while game.planets.size() < 20 and Time.get_ticks_msec() < deadline:
		await process_frame
	await _frames(10)

	print("=== C: PROP MESH CACHE ===")
	var PlanetScript = load("res://scripts/planet.gd")
	var cache: Dictionary = PlanetScript._prop_mesh_cache
	var order: Array = PlanetScript._prop_cache_order
	print("  cache entries = %d   (limit %d)" % [cache.size(), PlanetScript.PROP_CACHE_LIMIT])
	print("  lru order len = %d" % order.size())
	print("  over limit ?  %s" % str(cache.size() > PlanetScript.PROP_CACHE_LIMIT))
	print("  memory        = %s peak=%s" % [
		_mb(OS.get_static_memory_usage()), _mb(OS.get_static_memory_peak_usage())])

	print("\n=== D: VISIBILITY RANGE ===")
	var lod_level: int = 2
	if game.settings != null:
		lod_level = clampi(int(game.settings.values.lod), 0, 3)
	print("  current lod level = %d  (expect base %.0f)" % [
		lod_level, float(load("res://scripts/settings.gd").LOD_DISTANCE[lod_level])])

	var seen := {}
	for planet in game.planets:
		if planet == null:
			continue
		for node in planet.find_children("Prop_*", "MultiMeshInstance3D", true, false):
			var mmi := node as MultiMeshInstance3D
			if mmi == null:
				continue
			var v: float = mmi.visibility_range_end
			seen[v] = int(seen.get(v, 0)) + 1
	var keys: Array = seen.keys()
	keys.sort()
	for k in keys:
		print("    range=%.1f m -> %d nodes" % [float(k), int(seen[k])])

	print("\nCD DONE")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
