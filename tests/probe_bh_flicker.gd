extends SceneTree
# 探针：验证「吸积盘内部闪烁的三角形」修掉了没有。
#
# 做法：从多个角度拍同一颗黑洞。修复前，内部三角面会随角度大幅明暗跳变；
# 修复后每个角度都应该是干净的分层丝带，没有碎裂的三角形。
#
# 窗口纪律（AGENTS.md）：运行时用 OffscreenWindow 把窗口丢到屏幕外，
# 命令行必须带 --no-capture，否则会抢用户前台。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --no-capture \
#         --script res://tests/probe_bh_flicker.gd

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "res://captures"

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/bh_flicker_%s.png" % [OUT_DIR, label])
	print("saved %s/bh_flicker_%s.png" % [OUT_DIR, label])


func _run() -> void:
	await OffWin.apply(self)
	var safe: Array = OffWin.is_safe()
	print("窗口自检：%s" % str(safe[1]))
	if not bool(safe[0]):
		print("⚠ 窗口纪律不合格，中止")
		quit(1)
		return

	var save := "user://starward_probe_bh_flicker.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(30)
	game.hud.visible = false
	game.set_process(false)
	game.state = "capture"

	var target: Node3D = game.gargantua
	if target == null:
		print("卡冈图雅没建出来")
		quit(1)
		return
	var center: Vector3 = target.global_position

	var cam := Camera3D.new()
	cam.near = 1.0
	cam.far = 200000.0
	cam.fov = 55.0
	game.add_child(cam)
	cam.current = true

	# 六个角度绕黑洞一圈 + 两个俯仰：如果内部三角面还在闪，
	# 相邻两张之间会出现某一块突然亮/暗。
	var angles := [
		["a_0", deg_to_rad(0.0), deg_to_rad(20.0)],
		["b_60", deg_to_rad(60.0), deg_to_rad(20.0)],
		["c_120", deg_to_rad(120.0), deg_to_rad(20.0)],
		["d_180", deg_to_rad(180.0), deg_to_rad(20.0)],
		["e_240", deg_to_rad(240.0), deg_to_rad(20.0)],
		["f_300", deg_to_rad(300.0), deg_to_rad(20.0)],
		["g_low", deg_to_rad(45.0), deg_to_rad(3.0)],
		["h_high", deg_to_rad(45.0), deg_to_rad(55.0)],
	]
	var dist := 2600.0
	for entry in angles:
		var label: String = entry[0]
		var yaw: float = entry[1]
		var pitch: float = entry[2]
		var offset := Vector3(
			cos(pitch) * cos(yaw) * dist,
			sin(pitch) * dist,
			cos(pitch) * sin(yaw) * dist)
		cam.global_position = center + offset
		cam.look_at(center, Vector3.UP)
		await _frames(8)
		await _shot(label)

	print("DONE")
	quit(0)
