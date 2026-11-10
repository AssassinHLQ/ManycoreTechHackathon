extends SceneTree
# 出一维星（A Windy Day 点云）的预览图。
# 用法：godot --path . --no-capture --script res://tests/capture_one_dim_pointcloud.gd
#
# ⚠ 必须 --no-capture（见 AGENTS.md「绝对不许抢用户前台」）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const MODEL := "res://assets/models/one-dim-star/model.glb"

var cam: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://captures/onedim_pc_%s.png" % name)
	print("saved res://captures/onedim_pc_%s.png" % name)


func _run() -> void:
	await OffWin.apply(self)
	print("窗口安全检查: ", OffWin.is_safe()[1])

	var packed: PackedScene = load(MODEL)
	if packed == null:
		print("加载失败")
		quit(1)
		return
	var star := packed.instantiate() as Node3D
	root.add_child(star)

	# 深色背景，点云才看得清
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.025)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.06, 0.09)
	env.environment = e
	root.add_child(env)

	cam = Camera3D.new()
	cam.near = 0.01
	cam.far = 1000.0
	cam.fov = 50.0
	root.add_child(cam)
	cam.current = true

	var shots := [
		["full", Vector3(0, 0.9, 7.0)],
		["side", Vector3(7.0, 0.3, 0.0)],
		["close", Vector3(0, 0.5, 3.6)],
	]
	for entry in shots:
		var name: String = entry[0]
		var pos: Vector3 = entry[1]
		cam.position = pos
		cam.look_at(Vector3.ZERO, Vector3.UP)
		await _frames(5)
		await _shot(name)

	print("POINTCLOUD CAPTURE COMPLETE")
	quit(0)
