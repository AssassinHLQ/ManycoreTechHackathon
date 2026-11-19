extends SceneTree
# 探针：单独给「飞船系统」面板出图，检查右侧数值是否还被切断。
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/capture_hud_panel.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_hudshot.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(10):
		await process_frame
	game.start_game()
	for _i in range(30):
		await physics_frame
	if game.guide_card != null and game.guide_card.active:
		game.guide_card.skip()
		await process_frame
	# 把数值设成会撑宽的内容，验证不裁切
	game.ship.fuel = 100.0
	game.ship.hull = 100.0
	for _i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/hud_panel.png")
	print("saved hud_panel.png")
	quit(0)
