extends SceneTree
# 全场扫描：星球表面哪里会穿模。
#
#   godot --headless --path . --script res://tests/probe_ground_sweep.gd
#
# 对每颗星球在 30 个随机方向 + 洞口方向放人下落，报告：
#   · 掉到地表以下的（差值 < -3）
#   · 落在洞穴井里的（差值 < -30）
# 顺便检查洞穴内部有没有地面。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _probe_dir(p, dir: Vector3) -> Dictionary:
	var spawn: Vector3 = p.global_position + p.surface_position(dir, 8.0)
	game.player.reparent(p, false)
	game.player.global_transform = Transform3D(
		Basis(Quaternion(Vector3.UP, dir)), spawn)
	game.player.velocity = Vector3.ZERO
	await _frames(90)
	var rel: Vector3 = p.global_transform.affine_inverse() * game.player.global_position
	var th: float = p.terrain_height(dir)
	return {"dist": rel.length(), "th": th, "floor": game.player.is_on_floor()}


func _run() -> void:
	var save := "user://starward_sweep.json"
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

	seed(20261112)
	var bad := 0
	print("=== 地表穿透扫描（每球 30 个随机方向）===")
	for p in game.planets:
		var worst := 0.0
		var worst_dir := Vector3.UP
		var sunk := 0
		for i in range(30):
			var dir := Vector3(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0,
				randf() * 2.0 - 1.0)
			if dir.length_squared() < 0.01:
				continue
			dir = dir.normalized()
			var r: Dictionary = await _probe_dir(p, dir)
			var d: float = r["dist"] - r["th"]
			if d < worst:
				worst = d
				worst_dir = dir
			if d < -3.0:
				sunk += 1
		var tag := ""
		if sunk > 0:
			tag = "  \u26a0 %d/30 \u4e0b\u6c89" % sunk
			bad += sunk
		print("%-10s \u6700\u5dee\u5dee\u503c %+7.1f  m%s" % [p.planet_id, worst, tag])
	print("")
	print("\u5171 %d \u4e2a\u843d\u70b9\u7a7f\u6a21" % bad)

	# 洞穴内部有没有地面
	print("")
	print("=== 洞穴内部 ===")
	for p in game.planets:
		if not p.has_method("cave_entry_position"):
			continue
		var cave = p.find_child("Underground", true, false)
		if cave == null:
			continue
		var bodies: Array = cave.find_children("*", "StaticBody3D", true, false)
		var faces := 0
		for b in bodies:
			for c in (b as StaticBody3D).find_children("*", "CollisionShape3D", true, false):
				var sh = (c as CollisionShape3D).shape
				if sh is ConcavePolygonShape3D:
					faces += (sh as ConcavePolygonShape3D).get_faces().size() / 3
		print("%-10s 洞穴静态体 %d 个，凹面碰撞面 %d" % [p.planet_id, bodies.size(), faces])

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
