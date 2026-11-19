extends SceneTree
# 近景截图：挑几个 AI 道具（地标/树/塔），相机贴近拍，确认减面后没糊/没破面。
# 用法：godot --path . --script res://tests/_capture_prop_closeup.gd

var game


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://captures/%s.png" % name)
		print("  saved %s.png" % name)


func _run() -> void:
	var save := "user://probe_prop_closeup.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	for i in range(40):
		await process_frame

	var home = game.home
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 2000.0
	root.add_child(cam)
	cam.current = true

	var targets := ["Prop_lm2-qinglan", "Prop_alien-tree-lo", "Prop_rock-cluster"]
	var shot_n := 0
	for tname in targets:
		var mmi := home.find_child(tname, true, false) as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.instance_count < 1:
			print("  跳过 %s（没有实例）" % tname)
			continue
		var xf: Transform3D = mmi.multimesh.get_instance_transform(0)
		var world: Vector3 = mmi.global_transform * xf.origin
		# 按实例实际尺寸取景：地标几百米，小道具几米
		var mesh_aabb: AABB = mmi.multimesh.mesh.get_aabb()
		var scale_k: float = xf.basis.get_scale().x
		var extent: float = maxf(mesh_aabb.size.x,
			maxf(mesh_aabb.size.y, mesh_aabb.size.z)) * scale_k
		var dist: float = extent * 1.5 + 8.0
		var up: Vector3 = (world - home.global_position).normalized()
		var side: Vector3 = up.cross(Vector3.FORWARD)
		if side.length_squared() < 0.01:
			side = up.cross(Vector3.RIGHT)
		side = side.normalized()
		cam.global_position = world + side * dist + up * (extent * 0.35 + 3.0)
		cam.look_at(world + up * (extent * 0.25), up)
		print("  %s extent=%.1f m dist=%.1f m" % [tname, extent, dist])
		for i in range(8):
			await process_frame
		await _shot("prop_closeup_%d" % shot_n)
		shot_n += 1

	print("CLOSEUP DONE")
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
