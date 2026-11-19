extends SceneTree
# 按世界坐标拍几个「可疑道具」的实机近景，判断是浮空、陷地还是视觉/碰撞不一致。
# 用法：godot --path . --script res://tests/_capture_props_suspect.gd

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
	var save := "user://probe_props_suspect.json"
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
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true

	# 探针里最可疑的三个位置（世界坐标）
	var spots := [
		["suspect_ruin_arch", Vector3(27425.64, 1539.73, 4090.20)],
		["suspect_mushroom", Vector3(26233.83, 1914.92, 3822.74)],
		["suspect_dead_tree", Vector3(27143.71, 1258.46, 5919.20)],
	]
	var n := 0
	for s in spots:
		var p: Vector3 = s[1]
		var up: Vector3 = (p - home.global_position).normalized()
		var side: Vector3 = up.cross(Vector3.FORWARD)
		if side.length_squared() < 0.01:
			side = up.cross(Vector3.RIGHT)
		side = side.normalized()
		cam.global_position = p + side * 220.0 + up * 45.0
		cam.look_at(p + up * 12.0, up)
		for i in range(6):
			await process_frame
		await _shot(String(s[0]))
		n += 1

	print("SUSPECT DONE")
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
