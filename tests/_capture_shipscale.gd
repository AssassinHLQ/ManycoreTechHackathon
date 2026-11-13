extends SceneTree
# 截图：新尺寸下飞船与玩家/建筑的相对比例

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
	var save_path := "user://starward_scale.json"
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
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.1
	cam.far = 2000.0
	root.add_child(cam)
	cam.current = true

	# 把玩家放到飞船旁边当地标（不隐藏），站到船侧
	if game.player != null:
		game.player.global_position = ship.global_position + Vector3(40.0, 4.0, 0.0)
		await _frames(10)

	var sp: Vector3 = ship.global_position
	# ① 第三人称视角（默认跟随距离 11.5 m 已不适配 70 m 船，这里按 90 m 看全貌）
	cam.global_position = sp + Vector3(0.0, 40.0, 95.0)
	cam.look_at(sp + Vector3(0, 8, 0), Vector3.UP)
	await _frames(10)
	await _shot("ship_new_scale_wide")

	# ② 侧面，玩家站在旁边做参照
	cam.global_position = sp + Vector3(75.0, 12.0, 25.0)
	cam.look_at(sp + Vector3(0, 8, 0), Vector3.UP)
	await _frames(10)
	await _shot("ship_new_scale_side")

	print("SCALE SHOT DONE")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
