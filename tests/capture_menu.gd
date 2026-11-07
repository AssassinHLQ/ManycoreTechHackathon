extends SceneTree
# 主菜单取证：确认标题已是《借一扇晴天》，英文旧名不再出现。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_menu.gd

var game


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _run() -> void:
	var save := "user://starward_capture_menu.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(30)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://captures/menu_title.png"
	print("CAPTURE ", path, " -> ", error_string(image.save_png(path)))
	print("MENU CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
