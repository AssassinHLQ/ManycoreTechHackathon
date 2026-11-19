extends SceneTree
# 探针（临时关闭合并时用）：列出走廊靠近枢纽一段里的可见网格，找挡路大件。
# 用法（窗口模式）：Godot_v4.7.1-stable_win64_console.exe --path . --script res://tests/_probe_corridor_nodes.gd

var game
var station


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-4000, -4000))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://captures/%s.png" % name)
		print("  saved %s.png" % name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var save_path := "user://probe_corridor_nodes.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(6)
	station = game.station
	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.landed = false
	game.ship.landed_planet = null
	game.ship.autopilot = false
	game.ship.global_position = station.docking_point() + station.up_direction() * 18.0
	game.ship.velocity = Vector3.ZERO
	for i in range(6):
		await physics_frame
	game.enter_station()
	for i in range(6):
		await physics_frame
	game.player.global_position = station.to_global(Vector3(45.0, -1.0, 0.0))
	game.player.global_transform = Transform3D(
		station.global_transform.basis * Basis(Vector3.UP, PI * 0.5), game.player.global_position)
	game.player.camera.rotation = Vector3.ZERO
	for i in range(30):
		await physics_frame

	var inv: Transform3D = station.global_transform.affine_inverse()
	print("== CORRIDOR NODES 30..50 with material ==")
	var stack: Array = [station.corridor_roots[0]]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and node.is_visible_in_tree():
			var mi := node as MeshInstance3D
			var box: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			var c: Vector3 = box.get_center()
			var sz: Vector3 = box.size
			if c.x > 30.0 and c.x < 52.0 and absf(c.z) < 5.0 and maxf(sz.x, maxf(sz.y, sz.z)) > 0.9:
				var mat: Material = mi.material_override
				if mat == null and mi.mesh.get_surface_count() > 0:
					mat = mi.mesh.surface_get_material(0)
				var alb := "<none>"
				if mat is StandardMaterial3D:
					alb = str((mat as StandardMaterial3D).albedo_color)
				print("  %-22s parent=%-18s c=(%.1f,%.1f,%.1f) s=(%.1f,%.1f,%.1f) %s" % [
					String(mi.name), String(mi.get_parent().name), c.x, c.y, c.z, sz.x, sz.y, sz.z, alb])
		for ch in node.get_children():
			stack.append(ch)
	# 视线正中的那块大件：沿走廊中心线采样，列出 AABB 覆盖采样点的网格
	print("== CENTERLINE POINT-IN-AABB ==")
	for x in [44.0, 42.0, 40.0, 38.0, 36.0, 34.0, 32.0]:
		for y in [-1.2, 0.2, 1.2]:
			var wp: Vector3 = station.to_global(Vector3(x, y, 0.0))
			var found: Array = []
			var stack3: Array = [station.corridor_roots[0]]
			while not stack3.is_empty():
				var node: Node = stack3.pop_back()
				if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and node.is_visible_in_tree():
					var mi := node as MeshInstance3D
					var box: AABB = mi.global_transform * mi.mesh.get_aabb()
					if box.has_point(wp):
						var inv3: Transform3D = station.global_transform.affine_inverse()
						found.append("%s(p=%s s=%s)" % [String(mi.name), str((inv3 * (mi.global_transform * mi.mesh.get_aabb())).get_center()), str((mi.global_transform * mi.mesh.get_aabb()).size)])
				for ch in node.get_children():
					stack3.append(ch)
			if not found.is_empty():
				print("  x=%.1f y=%.1f -> %s" % [x, y, ", ".join(found)])
	await _frames(10)
	await _shot("station_corridor_nomerge")
	print("CORRIDOR NODES PROBE DONE")
	quit(0)
