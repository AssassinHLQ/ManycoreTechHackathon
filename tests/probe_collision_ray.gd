extends SceneTree
# 精确诊断：青岚星/赭崖星的碰撞面到底在哪。
#
#   godot --headless --path . --script res://tests/probe_collision_ray.gd
#
# 在每个方向上从高空向下打射线，比较：
#   · 射线命中的 y（相对球心的距离）
#   · terrain_height(dir)
#   · 可见网格的表面高度（用 mesh 顶点最近值近似）
# 差值系统性为负 = 碰撞面整体偏低；个别为负 = 局部破洞。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _probe(p, dir: Vector3) -> void:
	var th: float = p.terrain_height(dir)
	var start: Vector3 = p.global_position + dir * (th + 300.0)
	var end: Vector3 = p.global_position + dir * (th - 400.0)
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(start, end)
	q.collision_mask = 1
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("    dir %s  terrain %7.1f  →  没有命中任何碰撞" % [
			str(dir.snapped(Vector3(0.01, 0.01, 0.01))), th])
		return
	var hp: Vector3 = hit["position"]
	var rel: Vector3 = p.global_transform.affine_inverse() * hp
	print("    dir %s  terrain %7.1f  碰撞面 %7.1f  差 %+7.1f  (%s)" % [
		str(dir.snapped(Vector3(0.01, 0.01, 0.01))), th, rel.length(),
		rel.length() - th, str(hit["collider"].name)])


func _run() -> void:
	var save := "user://starward_ray.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(20)
	for i in range(1200):
		await process_frame
		if game.planets.size() >= 20:
			break
	await _frames(10)

	for idx in [0, 1, 2, 15]:
		var p = game.planets[idx]
		print("=== %s (cave=%s, radius=%.0f) ===" % [
			p.planet_id, str(p.cave_enabled), p.radius])
		var dirs := [Vector3.UP, Vector3.DOWN, Vector3.FORWARD,
			Vector3(0.6, 0.5, -0.6).normalized(),
			Vector3(-0.5, -0.7, 0.5).normalized()]
		# 站点方向也测（可能被压平过）
		if p.site_direction != null:
			dirs.append(p.site_direction.normalized())
		if p.cave_enabled:
			dirs.append(p.cave_direction.normalized())
		for d in dirs:
			await _probe(p, d)

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
