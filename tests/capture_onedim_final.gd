extends SceneTree
# 用正式脚本 one_dim_star.gd 出图 —— 验证顶点色 + 抽稀后的实际观感。
# 用法：godot --path . --no-capture --script res://tests/capture_onedim_final.gd
#
# ⚠ 必须 --no-capture（见 AGENTS.md）。
# 说明：本探针绕开 game 主场景，单独实例化一维星脚本，
#       用独立相机在三个距离出图（对应「远 / 中 / 贴脸」）。

const OffWin := preload("res://scripts/offscreen_window.gd")

var cam: Camera3D
var star: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://captures/onedim_final_%s.png" % name)
	print("saved res://captures/onedim_final_%s.png" % name)


func _run() -> void:
	await OffWin.apply(self)

	# 深色宇宙背景
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.006, 0.009, 0.020)
	env.environment = e
	root.add_child(env)

	# 实例化一维星 —— 必须用 preload("...").new()，
	# Node3D.new() + set_script() 出来的静态类型仍是 Node3D，
	# 脚本的 _ready 会跑，但很多属性访问会走 safe 路径，行为不可靠。
	var StarScript := load("res://scripts/one_dim_star.gd")
	star = StarScript.new()
	root.add_child(star)
	await _frames(3)

	var meshes = star._meshes
	print("点云 mesh 数 = %d" % meshes.size())
	if meshes.size() > 0:
		var mm: Mesh = (meshes[0] as MeshInstance3D).mesh
		print("第一个 surface 图元类型 = %d (0=POINTS)" % mm.surface_get_primitive_type(0))

	cam = Camera3D.new()
	cam.near = 0.5
	cam.far = 8000.0
	cam.fov = 45.0
	root.add_child(cam)
	cam.current = true

	# 三档距离：远 / 中 / 贴脸
	for entry in [["far", 700.0], ["mid", 320.0], ["near", 120.0]]:
		var name: String = entry[0]
		var d: float = entry[1]
		cam.position = Vector3(0, d * 0.12, d)
		cam.look_at(Vector3.ZERO, Vector3.UP)
		await _frames(5)
		# 手动驱动一次 process，让「靠近消失」生效
		star._process(0.016)
		var vis := 0
		for mi in meshes:
			if (mi as MeshInstance3D).visible:
				vis += 1
		print("  %s: 距离 %.0f m, 可见 mesh %d / %d" % [name, d, vis, meshes.size()])
		await _shot(name)

	print("ONEDIM FINAL CAPTURE COMPLETE")
	quit(0)
