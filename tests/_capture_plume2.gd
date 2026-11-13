extends SceneTree
# 截图：尾焰与喷口的对位（船尾正后 / 侧后 45 度两种视角）
# 用 ASCII 输出，避免控制台编码问题。

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
		print("  saved %s.png" % name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var save_path := "user://starward_plume.json"
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

	print("=== PLUME PROBE ===")
	print("  model_length=%.2f span=%.2f height=%.2f" % [
		ship.ship_model_length, ship.ship_model_span, ship.ship_model_height])
	print("  nozzles:")
	for i in range(ship.EXHAUST_NOZZLES.size()):
		var nz: Vector3 = ship.EXHAUST_NOZZLES[i]
		print("    [%d] %s" % [i, str(nz)])

	# 强制点火（无视输入）
	ship.thrust_level = 1.0
	ship.engine_level = 1.0
	# 直接点亮所有尾焰节点：不依赖输入系统，保证截图里一定有火焰
	for p in ship.engine_plumes:
		(p as Node3D).visible = true
	for h in ship.engine_halos:
		(h as Node3D).visible = true

	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 500.0
	root.add_child(cam)
	cam.current = true

	var sp: Vector3 = ship.global_position
	# 假设船头朝 -Z，船尾在 +Z。从 +Z 正后方看。
	for spec in [["plume_back", Vector3(0, 1.2, 18.0)], ["plume_side", Vector3(11.0, 3.0, 13.0)]]:
		cam.global_position = sp + (spec[1] as Vector3)
		cam.look_at(sp + Vector3(0, 0.4, 0), Vector3.UP)
		await _frames(10)
		await _shot(String(spec[0]))

	print("PLUME DONE")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
