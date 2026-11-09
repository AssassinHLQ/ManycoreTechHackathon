extends SceneTree
# 飞船视角取证：座舱视角 + 第三人称视角，各拍几张。
# 用法：godot --path . --no-capture --script res://tests/capture_ship_views.gd
#
# ⚠ 必须带 --no-capture（放在 -- 之后也行）：不带的话窗口一拿到焦点就收鼠标，
#   会打断正在玩游戏的用户。见 AGENTS.md「绝对不许抢用户前台」。
#
# 为什么需要它：
#   座舱相机位置是**按模型几何实测**定的（tests/probe_ship_cockpit.gd），
#   第三人称是**绕船转**的相机 —— 两者都只能靠截图确认好不好看。
#   顺便验证第三人称里**没有主角**：玩家在船上时 player.visible=false。

const OffWin := preload("res://scripts/offscreen_window.gd")

var game
var camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://captures/view_%s.png" % name)
	print("saved res://captures/view_%s.png" % name)


func _run() -> void:
	# 窗口先丢到屏幕外，别抢用户前台。
	await OffWin.apply(self)
	# 出图探针会在 _initialize 之外再跑一次窗口设置，顺手确认一下没犯规。
	var safety: Array = OffWin.is_safe()
	print("窗口安全检查: ", safety[1])

	var save := "user://starward_views.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(16)
	game.start_game()
	await _frames(16)
	game.hud.visible = false
	game.hud.menu.visible = false
	# state 必须是 "ship"：toggle_third_person() 会检查它。
	game.state = "ship"

	var ship = game.ship
	print("座舱相机位置 = ", ship.camera.position)
	print("船尺寸 长=%.2f 翼展=%.2f 高=%.2f" % [
		ship.ship_model_length, ship.ship_model_span, ship.ship_model_height])
	print("尾焰材质 = %d 个，尾灯 = %d 个，喷焰网格 = %d 个" % [
		ship.engine_materials.size(), ship.engine_lights.size(), ship.engine_plumes.size()])

	# ── 座舱视角（飞船自己的相机）──
	# 不要自己 new 一个相机设 current —— 那会抢走飞船的相机。
	ship.camera.current = true
	await _frames(8)
	await _shot("cockpit")

	# ── 第三人称：F5 切换 ──
	print("按 F5 → ", ship.toggle_third_person())
	await _frames(8)
	await _shot("third_person_rear")

	# 绕到侧面
	ship.orbit_yaw = PI * 0.5
	await _frames(6)
	await _shot("third_person_side")

	# 从上往下看
	ship.orbit_yaw = 0.0
	ship.orbit_pitch = 0.9
	await _frames(6)
	await _shot("third_person_top")

	# 回到座舱
	print("再按 F5 → ", ship.toggle_third_person())
	await _frames(8)
	await _shot("cockpit_again")

	print("VIEWS CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
