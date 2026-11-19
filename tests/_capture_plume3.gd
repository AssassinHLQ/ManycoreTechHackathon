extends SceneTree
# 截图：尾焰前移后的对位（船尾正后 / 侧后两种视角）。
# 机长已放大到 ~70 m，相机距离按新尺度摆放（旧版 plume2 是 14 m 的参数）。

var game
var cam: Camera3D


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://captures/%s.png" % name)
		print("  saved %s.png (%dx%d)" % [name, img.get_width(), img.get_height()])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var save_path := "user://starward_plume3.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	await _frames(10)
	game.start_game()
	await _frames(30)

	var ship = game.ship
	if ship == null:
		print("!! no ship")
		quit(1)
		return

	var L: float = ship.ship_model_length
	print("=== PLUME CAPTURE (len=%.2f) ===" % L)
	# 前移后的实际起点 z
	for i in range(ship.EXHAUST_NOZZLES.size()):
		var base: Vector3 = (ship.EXHAUST_NOZZLES[i] as Vector3) * (L / 14.0)
		var shifted: Vector3 = base - Vector3(0, 0, L * ship.EXHAUST_PLUME_FORWARD_RATIO)
		print("  nozzle[%d] base_z=%.2f -> shifted_z=%.2f (tail=%.2f)" % [
			i, base.z, shifted.z, L * 0.5])

	# 强制点火并点亮尾焰，保证截图里一定有火焰
	ship.thrust_level = 1.0
	ship.engine_level = 1.0
	for p in ship.engine_plumes:
		(p as Node3D).visible = true
	for h in ship.engine_halos:
		(h as Node3D).visible = true

	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.1
	cam.far = 800.0
	root.add_child(cam)
	cam.current = true

	var sp: Vector3 = ship.global_position
	# [名字, 相机偏移, 看向点的相对偏移]
	var shots := [
		["plume_fix_back",  Vector3(0, 10, 75),   Vector3(0, 2, 20)],
		["plume_fix_side",  Vector3(60, 18, 55),  Vector3(0, 2, 18)],
	]
	for spec in shots:
		cam.global_position = sp + (spec[1] as Vector3)
		cam.look_at(sp + (spec[2] as Vector3), Vector3.UP)
		await _frames(10)
		await _shot(String(spec[0]))

	print("PLUME3 DONE")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
