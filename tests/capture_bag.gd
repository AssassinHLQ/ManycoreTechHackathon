extends SceneTree
# 行囊面板取证：塞一些进度后打开 B 面板截图。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_bag.gd

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
	var path := "res://captures/" + name + ".png"
	print("CAPTURE ", path, " -> ", error_string(image.save_png(path)))


func _run() -> void:
	var save := "user://starward_capture_bag.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.progress.save_path = "user://starward_capture_bag_progress.json"
	game.progress.reset()
	# 塞几笔像样的进度，让面板有内容
	# 塞九种鱼，让图鉴是满的；再留几尾在鱼篓里
	for id in ["ice-crucian", "snow-lamp", "bell-carp", "star-scale", "moon-perch",
			"aurora-trout", "cloud-ray", "galaxy-eel", "mirror-koi"]:
		game.progress.add_fish(id)
	game.progress.add_fish("ice-crucian")
	game.progress.add_fish("aurora-trout")
	game.progress.coins = 300
	game.progress.buy_rod("brass")
	for id in ["first_fish", "keepsake_snow", "keepsake_cloud", "tea_full", "court_rest",
			"dex-all", "angler", "rich", "listening-court", "three-faces"]:
		game.progress.unlock(id)
	game.progress.record_game("chime", 132)
	game.progress.record_game("rain", 96)
	game.enter_attic()
	await _frames(10)
	game.hud.visible = false
	game.toggle_bag()
	await _frames(14)
	await _capture("bag_panel")
	print("BAG CAPTURE COMPLETE")
	quit(0)
