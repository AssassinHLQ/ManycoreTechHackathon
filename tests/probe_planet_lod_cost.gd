extends SceneTree
# 探针：量行星表面网格「全精度常驻」的代价。
# 用法：godot --headless --path . --script res://tests/probe_planet_lod_cost.gd
#
# 为什么需要它：
#   行星表面是 SphereMesh + 顶点位移（radial_segments=128/64 或 256/128），
#   **没有 visibility_range、也没有 LOD** —— 哪怕飞到星球背面、
#   哪怕离它十万公里，那 4 万～8 万面的网格照样每帧送进渲染管线。
#   这个探针量三件事：
#     1. 每颗行星表面占多少显存（顶点+索引）；
#     2. 十颗都常驻一共多少；
#     3. 换成低一档分辨率能省多少。

var game


func _initialize() -> void:
	call_deferred("_run")


func _mesh_stats(mesh: Mesh) -> Dictionary:
	var verts := 0
	var idx := 0
	var tris := 0
	if mesh == null:
		return {"verts": 0, "idx": 0, "tris": 0}
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var v: Variant = arrays[Mesh.ARRAY_VERTEX]
		var i: Variant = arrays[Mesh.ARRAY_INDEX]
		verts += (v as PackedVector3Array).size() if v != null else 0
		idx += (i as PackedInt32Array).size() if i != null else 0
		if i != null and (i as PackedInt32Array).size() > 0:
			tris += (i as PackedInt32Array).size() / 3
		elif v != null:
			tris += (v as PackedVector3Array).size() / 3
	return {"verts": verts, "idx": idx, "tris": tris}


func _run() -> void:
	var save := "user://starward_plc.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	print("=== 每颗行星的表面网格 ===")
	print("%-6s %10s %10s %12s %10s" % ["#", "面数", "顶点数", "显存约(KB)", "visibility_range"])
	var total_tris := 0
	var total_mem := 0
	var i := 0
	for planet in game.planets:
		i += 1
		var st := _mesh_stats(planet.surface.mesh)
		# 顶点 12B (pos) + 法线 12B + uv 8B ≈ 32B；索引 4B/个
		var mem: int = int(st["verts"]) * 32 + int(st["idx"]) * 4
		total_tris += int(st["tris"])
		total_mem += mem
		print("%-6d %10d %10d %12d %10s" % [
			i, st["tris"], st["verts"], mem / 1024,
			"%.0f" % planet.surface.visibility_range_end])
	print("")
	print("十颗行星表面合计: %d 面，显存约 %.1f MB" % [total_tris, total_mem / 1048576.0])
	print("")
	print("=== 若全部降一档（256/128 → 128/64，128/64 → 64/32）===")
	# 球面网格面数 ≈ 2 * radial * rings
	var half := total_tris / 4
	print("  面数约 %d → %d（省 %.0f%%）" % [total_tris, half, 100.0 - 100.0 * half / total_tris])
	print("  显存约 %.1f MB → %.1f MB" % [total_mem / 1048576.0, total_mem / 4.0 / 1048576.0])
	print("")
	print("=== 顺带看看远景星球是不是也全精度 ===")
	for planet in game.planets:
		print("  #%d 半径 %.0f m  cave=%s  表面 visibility_range_end=%.0f" % [
			game.planets.find(planet) + 1, planet.radius, planet.cave_enabled,
			planet.surface.visibility_range_end])
	quit(0)
