extends SceneTree
# 出图探针：验证「右下飞行读数面板」的新 UI 与「底部三角形已移除」。
#
# 严格按工作区纪律：
#   · 运行时把窗口丢到屏幕外 + 取消最大化（OffscreenWindow）
#   · 不抢焦点、不抢鼠标
#   · 跑完自己 quit()
#
# 用法（必须带 --no-capture，且放在 -- 之后）：
#   godot --path . --position -20000,-20000 -- --no-capture --script res://tests/capture_ship_hud.gd
#
# 输出：captures/hud_report/ship_stats_*.png

const OffWin := preload("res://scripts/offscreen_window.gd")

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "res://captures/hud_report/" + name + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/hud_report"))
	print("CAPTURE ", path, " -> ", error_string(img.save_png(path)))


func _run() -> void:
	await OffWin.apply(self)

	var save := "user://capture_hud_report.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(10)

	# 进飞船
	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.third_person = false
	game.ship.fuel = 62.0
	game.ship.hull = 78.0
	game.ship.velocity = Vector3(12.5, 0.0, 0.0)
	await _frames(30)

	# 1) 第一人称：看右下「飞行读数」面板
	await _capture("01_cockpit_stats")

	# 2) 第三人称：看底角三角形是否已消失
	game.ship.toggle_third_person()
	await _frames(30)
	await _capture("02_third_person")

	# 3) 下船 + 修理 UI：把船体压低，站到船边，模拟按 F
	game.ship.toggle_third_person()
	game.state = "walk"
	game.player.visible = true
	game.ship.landed = true
	game.ship.land_phase = 0
	game.ship.global_position = game.home.global_position + game.home.surface_position(Vector3.UP, 2.3)
	game.player.global_position = game.ship.global_position + Vector3(3.0, 0.3, 0.0)
	game.ship.hull = 30.0
	# 让它对准飞船：直接给 camera 朝船的方向
	await _frames(5)
	var to_ship: Vector3 = (game.ship.global_position - game.player.camera.global_position).normalized()
	game.player.look_at(game.player.global_position + to_ship, Vector3.UP)
	await _frames(5)
	game.ship.repair_progress = 0.45
	game.ship.hull = 45.0
	await _frames(10)
	await _capture("03_repair_ui")

	print("DONE")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
