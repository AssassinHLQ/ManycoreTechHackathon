extends SceneTree
# 探针：近距离看黑洞内部，找「静止可见的三角块」。
#
# 用户反馈：静止看黑洞内部就有三角块。之前 2600 距离的多角度出图没拍到，
# 说明得贴近了看 —— 用户的截图里盘面是铺满屏幕的。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/probe_bh_close.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("res://captures/bh_close_%s.png" % label)
	print("saved res://captures/bh_close_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_probe_bh_close.json"
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
	cam.fov = 70.0
	game.add_child(cam)
	cam.current = true

	# 近距离 + 多个俯仰：用户的截图里盘面铺满屏幕，说明镜头很近。
	var shots := [
		["d400_p10", 400.0, 10.0],
		["d400_p30", 400.0, 30.0],
		["d800_p10", 800.0, 10.0],
		["d800_p30", 800.0, 30.0],
		["d1500_p8", 1500.0, 8.0],
		["d1500_p25", 1500.0, 25.0],
	]
	for entry in shots:
		var label: String = entry[0]
		var dist: float = entry[1]
		var pitch: float = deg_to_rad(float(entry[2]))
		var yaw := deg_to_rad(35.0)
		cam.global_position = center + Vector3(
			cos(pitch) * cos(yaw) * dist,
			sin(pitch) * dist,
			cos(pitch) * sin(yaw) * dist)
		cam.look_at(center, Vector3.UP)
		await _frames(8)
		await _shot(label)

	print("DONE")
	quit(0)
