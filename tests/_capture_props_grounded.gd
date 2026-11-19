extends SceneTree
# 按「模型底面 + 实际尺寸」取景，拍 3 个大件道具，确认是浮空还是陷地。
# 用法：godot --path . --script res://tests/_capture_props_grounded.gd

const OffWin := preload("res://scripts/offscreen_window.gd")

var game


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://captures/%s.png" % name)
		print("  saved %s.png" % name)


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://probe_props_grounded.json"
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
	cam.fov = 60.0
	cam.near = 0.2
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true

	var wanted := ["Prop_alien-tree-lo", "Prop_alien-mushroom", "Prop_rock-cluster"]
	var n := 0
	for tname in wanted:
		var mmi := home.find_child(tname, true, false) as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.instance_count < 1:
			print("  跳过 %s" % tname)
			continue
		var aabb: AABB = mmi.multimesh.mesh.get_aabb()
		var bot_local := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
		var xf: Transform3D = mmi.multimesh.get_instance_transform(0)
		var bottom: Vector3 = mmi.global_transform * (xf * bot_local)
		var extent: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * xf.basis.get_scale().x
		var up: Vector3 = (bottom - home.global_position).normalized()
		var side: Vector3 = up.cross(Vector3.FORWARD)
		if side.length_squared() < 0.01:
			side = up.cross(Vector3.RIGHT)
		side = side.normalized()
		cam.global_position = bottom + side * (extent * 1.4) + up * (extent * 0.45)
		cam.look_at(bottom + up * (extent * 0.35), up)
		print("  %s bottom=%s extent=%.1f" % [tname, str(bottom), extent])
		for i in range(6):
			await process_frame
		await _shot("grounded_%d" % n)
		n += 1

	print("GROUNDED DONE")
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
