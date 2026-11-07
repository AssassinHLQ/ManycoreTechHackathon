extends SceneTree
# 地表自然物取证：树、岩石、晶簇的近景。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_nature.gd

var game


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://captures/nature_" + name + ".png"
	print("CAPTURE ", path, " -> ", error_string(image.save_png(path)))


func _run() -> void:
	var capture_save := "user://starward_capture_nature.json"
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = capture_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.start_game()
	await _frames(20)
	game.hud.visible = false
	game.hud.menu.visible = false
	game.state = "capture"

	var camera := Camera3D.new()
	camera.near = 0.2
	camera.far = 60000.0
	camera.fov = 60.0
	game.add_child(camera)
	camera.current = true

	# 每颗星取一个地表点：沿着该星的一个随机方向俯视
	var targets := [
		["qinglan", "trees", Vector3(0.62, 1.0, 0.35)],
		["xuanjing", "crystals", Vector3(-0.55, 1.0, 0.48)],
		["zheya", "saltcrystal", Vector3(0.30, 1.0, -0.72)],
		["pansha", "rocks", Vector3(-0.68, 1.0, -0.30)],
	]
	for entry in targets:
		var planet = null
		for candidate in game.planets:
			if candidate.planet_id == entry[0]:
				planet = candidate
				break
		if planet == null:
			print("MISSING ", entry[0])
			continue
		var surface: Vector3
		var arch = planet.find_child("Architecture_*", true, false)
		surface = arch.global_position if arch != null else planet.global_position
		var dir: Vector3 = (entry[2] as Vector3).normalized()
		var up: Vector3 = dir
		var side: Vector3 = up.cross(Vector3.FORWARD).normalized()
		if side.length_squared() < 0.01:
			side = up.cross(Vector3.RIGHT).normalized()
		# 站在地表上方 6 米、向外 18 米处回看
		camera.global_position = surface + up * 22.0 + side * 46.0
		camera.look_at(surface + up * 2.0, up)
		await _frames(10)
		await _capture(entry[1])
		# 再退远一点看整体散布
		camera.global_position = surface + up * 60.0 + side * 120.0
		camera.look_at(surface, up)
		await _frames(10)
		await _capture(entry[1] + "_wide")

	print("NATURE CAPTURE COMPLETE")
	quit(0)
