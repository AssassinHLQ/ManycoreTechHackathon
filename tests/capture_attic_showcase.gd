extends SceneTree
# 探针：阁楼（地面线）全景出图 —— 看清这条线路有哪些玩法。
#
# 布局（attic.gd 实测）：
#   · 房间 X ±3.4、Z ±2.9、墙高 2.5
#   · 后墙（-Z）四扇门：雪夜(-2.1) / 云海(-0.7) / 萤火(0.7) / 雨巷(2.1)
#   · 左墙（-X 3.3）镜界回廊，z=0.9
#   · 窗与天气转盘：后墙 z=-2.0 上方
#   · 茶几 (1.05, 0, 1.35)：茶席三步 + 手册
#   · 旅行架 (2.8, 1.0, -1.2)：放四件纪念
#
# 窗口纪律：运行时把窗口挪到屏幕外 + 命令行带 --no-capture。
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/capture_attic_showcase.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const AtticScript = preload("res://scripts/attic.gd")

var attic
var camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(label: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://captures/showcase_attic_%s.png" % label)
	print("saved res://captures/showcase_attic_%s.png" % label)


## 摆一台相机看向目标点
func _look(from: Vector3, to: Vector3) -> void:
	camera.position = from
	camera.look_at(to, Vector3.UP)


func _run() -> void:
	await OffWin.apply(self)

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1b1a18")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b9a98c")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)

	attic = AtticScript.new()
	world.add_child(attic)
	await attic.build()

	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 200.0
	camera.fov = 72.0
	world.add_child(camera)
	camera.current = true

	# ① 全景：从门口上方俯瞰整间阁楼
	_look(Vector3(0.0, 2.35, 2.55), Vector3(0.0, 0.9, -1.6))
	await _shot("01_overview")

	# ② 四扇门（后墙）：一扇通向一个独立小世界
	_look(Vector3(0.0, 1.5, 1.5), Vector3(0.0, 1.05, -2.85))
	await _shot("02_four_doors")

	# ③ 窗与天气转盘：让窗外换一个世界
	_look(Vector3(0.35, 1.5, -0.5), Vector3(0.0, 1.45, -2.9))
	await _shot("03_window_dial")

	# ④ 镜界回廊（左墙）
	_look(Vector3(0.9, 1.5, 0.9), Vector3(-3.4, 1.25, 0.9))
	await _shot("04_mirror_corridor")

	# ⑤ 茶几 + 茶席三步 + 手册
	_look(Vector3(-0.5, 1.45, 0.15), Vector3(1.6, 0.85, 1.5))
	await _shot("05_tea_table")

	# ⑥ 旅行架（四件纪念的托座）
	_look(Vector3(0.9, 1.35, 0.6), Vector3(3.1, 1.05, -1.25))
	await _shot("06_shelf")

	# ⑦ 走过去看看四扇门的近景（雪夜 + 云海）
	_look(Vector3(-1.4, 1.45, -0.6), Vector3(-1.4, 1.05, -2.85))
	await _shot("07_door_snow_close")

	# ⑧  fireplace / 壁炉一侧
	_look(Vector3(-1.2, 1.5, 0.4), Vector3(-3.3, 0.9, -1.9))
	await _shot("08_hearth")

	print("ATTIC SHOWCASE COMPLETE")
	quit(0)
