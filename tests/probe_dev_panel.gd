extends SceneTree
# 开发者面板的目视验证：开一局 → 真的连按 5 次 F3 → 截一张带面板的图。
# 用法（要真实渲染，不能 headless）：
#   godot --path . --resolution 1280x720 --script res://tests/probe_dev_panel.gd

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
	var save := "user://starward_dev_probe.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.start_game()
	await _frames(20)
	# 不直接写 dev_mode，正经走一遍按键链路：连按 5 次 F3
	var tap := InputEventKey.new()
	tap.physical_keycode = KEY_F3
	tap.pressed = true
	for _i in range(5):
		game._unhandled_input(tap)
		await process_frame
	print("[devprobe] dev_mode = ", game.dev_mode, "  面板可见 = ", game.hud.dev_panel.visible)
	# 跑满一秒，让「最低帧率」那一格真的有数
	await _frames(90)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	print("[devprobe] save -> ", error_string(image.save_png("res://captures/probe_dev_panel.png")))
	print("[devprobe] ---- 面板文字 ----")
	print(game.hud.dev_label.text)
	print("[devprobe] ------------------")
	# 面板的实测尺寸 vs 面板本身，看有没有溢出
	print("[devprobe] 面板 %.0f x %.0f   文字 %.0f x %.0f" % [
		game.hud.dev_panel.size.x, game.hud.dev_panel.size.y,
		game.hud.dev_label.get_minimum_size().x, game.hud.dev_label.get_minimum_size().y])
	game.queue_free()
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
