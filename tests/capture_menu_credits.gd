extends SceneTree
# 截主菜单（标题界面），确认外部素材署名真的显示出来了。
# 用法： godot --path . --script res://tests/capture_menu_credits.gd

var game


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
	if img == null:
		push_error("截图失败: " + name)
		return
	img.save_png("res://captures/%s.png" % name)
	print("  saved %s.png" % name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var test_save := "user://starward_credits_shot.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)

	# 停在标题界面（不 start_game），等 UI 铺好
	game.state = "menu"
	await _frames(40)
	await _shot("menu_credits")

	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0)
