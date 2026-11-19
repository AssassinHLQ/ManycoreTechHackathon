extends SceneTree
# 出一维星的三个距离的图：远 / 中 / 贴脸。
# 用法：godot --path . --no-capture --script res://tests/capture_one_dim_star.gd
#
# ⚠ 必须 --no-capture（见 AGENTS.md「绝对不许抢用户前台」）。
# 窗口会被 OffscreenWindow 丢到屏幕外。

const OffWin := preload("res://scripts/offscreen_window.gd")

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://captures/onedim_%s.png" % name)
	print("saved res://captures/onedim_%s.png" % name)


func _run() -> void:
	await OffWin.apply(self)
	print("窗口安全检查: ", OffWin.is_safe()[1])

	var save := "user://starward_onedim_shot.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(16)
	game.start_game()
	await _frames(20)
	game.hud.visible = false
	game.hud.menu.visible = false

	var star = game.one_dim_star
	var cam := Camera3D.new()
	cam.near = 0.5
	cam.far = 60000.0
	cam.fov = 55.0
	game.add_child(cam)
	cam.current = true

	# 相机绕着星放，三个距离
	var shots := [
		["far", 900.0],
		["mid", 380.0],
		["near", 140.0],
	]
	for entry in shots:
		var name: String = entry[0]
		var d: float = entry[1]
		cam.global_position = star.global_position + Vector3(0, d * 0.18, d)
		cam.look_at(star.global_position, Vector3.UP)
		# 让 process 跑一下，更新可见点数
		star._process(0.016)
		print("%s: 距离 %.0f m, 可见 %d 点" % [
			name, d, star.cloud.multimesh.visible_instance_count])
		await _frames(4)
		await _shot(name)

	print("ONEDIM CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
