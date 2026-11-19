extends SceneTree
# 分层隐藏截图：判断走廊里那块挡路的大件属于哪一层（门扇 / 枢纽 / 走廊模板 / 站级道具）。
# 用法（窗口模式）：Godot_v4.7.1-stable_win64_console.exe --path . --script res://tests/_probe_slab_layers.gd

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
	var save_path := "user://probe_slab_layers.json"
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
	await _frames(8)
	await _shot("slab_0_all")
	# 关掉站的 _process，避免它每帧把可见性改回去
	station.set_process(false)
	station.hub_root.visible = false
	for root in station.corridor_roots:
		(root as Node3D).visible = false
	await _frames(6)
	await _shot("slab_E_nothing")

	station.corridor_roots[0].visible = true
	await _frames(6)
	await _shot("slab_F_corridor_only")
	station.corridor_roots[0].visible = false

	station.hub_root.visible = true
	await _frames(6)
	await _shot("slab_G_hub_only")
	# 枢纽/走廊都藏起来后，挡路大件是站外的哪个节点：按 AABB 覆盖中心线点列出
	station.hub_root.visible = false
	for root in station.corridor_roots:
		(root as Node3D).visible = false
	await _frames(4)
	var inv: Transform3D = station.global_transform.affine_inverse()
	print("== VISIBLE EXTERIOR NODES COVERING CENTERLINE ==")
	var stack: Array = [station]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and node.is_visible_in_tree():
			var mi := node as MeshInstance3D
			var box: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			var c: Vector3 = box.get_center()
			for x in [36.0, 40.0, 44.0]:
				if box.has_point(Vector3(x, -0.5, 0.0)):
					print("  %-24s parent=%-18s c=(%.1f,%.1f,%.1f) s=(%.1f,%.1f,%.1f)" % [
						String(mi.name), String(mi.get_parent().name), c.x, c.y, c.z, box.size.x, box.size.y, box.size.z])
					break
		for ch in node.get_children():
			stack.append(ch)
	print("SLAB LAYERS PROBE DONE")
	quit(0)
