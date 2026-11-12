extends SceneTree
# 把每颗星球的**所有** StaticBody3D 名字 + 面数全列出来（不做任何过滤）。
#
#   godot --headless --path . --script res://tests/probe_bodies_dump.gd
#
# 目的：确认「地形碰撞体到底叫什么、在谁身上、有多少面」。
# 之前 probe_collision_bodies.gd 只按名字 == "TerrainCollision" 统计，
# 结果 19 颗星球都「没有地形碰撞体」，但另一支探针又测到 148,224 面的凹面形状 ——
# 说明名字对不上（Godot 同名子节点会自动改成 xxx2），所以这里全量打印。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _describe(b: StaticBody3D) -> String:
	var parts: Array[String] = []
	for c in b.find_children("*", "CollisionShape3D", true, false):
		var sh = (c as CollisionShape3D).shape
		if sh == null:
			parts.append("null")
			continue
		if sh is ConcavePolygonShape3D:
			parts.append("concave:%d" % ((sh as ConcavePolygonShape3D).get_faces().size() / 3))
		elif sh is ConvexPolygonShape3D:
			parts.append("convex:%d" % (sh as ConvexPolygonShape3D).points.size())
		elif sh is BoxShape3D:
			parts.append("box")
		elif sh is SphereShape3D:
			parts.append("sphere")
		elif sh is CylinderShape3D:
			parts.append("cyl")
		else:
			parts.append(sh.get_class())
	return "%s [layer %d] %s" % [String(b.name), b.collision_layer, ", ".join(parts)]


func _run() -> void:
	var save := "user://starward_dump.json"
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
	await _frames(15)

	for idx in [0, 1, 2]:
		var p = game.planets[idx]
		print("=== %s  cave=%s ===" % [p.planet_id, str(p.cave_enabled)])
		var big: Array[String] = []
		var small := 0
		for b in p.find_children("*", "StaticBody3D", true, false):
			var d := _describe(b as StaticBody3D)
			if d.contains("concave:") and not d.contains("concave:0"):
				big.append(d)
			else:
				small += 1
		print("  大凹面碰撞体 %d 个：" % big.size())
		for d in big:
			print("    %s" % d)
		print("  其它静态体 %d 个" % small)
		# 玩家实际所站的地形碰撞是否存在
		print("  direct children 里找 TerrainCollision：%s" % str(
			p.find_child("TerrainCollision", false, false) != null))

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
