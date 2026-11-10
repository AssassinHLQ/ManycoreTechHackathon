extends SceneTree
# 探针：给远景站内部舱室出图，确认能走进去、看着像个舱室。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/probe_interior_shot.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const Distant = preload("res://scripts/distant_station.gd")


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("res://captures/interior_%s.png" % label)
	print("saved res://captures/interior_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)

	# 造一座站 + 舱室（不加载整个游戏世界，太重）
	var st: Node3D = Distant.new()
	st.display_name = "远景站 · 环塔"
	st.disk_radius = 358.0
	st.half_extent = Vector3(358.0, 450.0, 358.0)
	st.dock_offset = Vector3(0.0, 477.0, 0.0)
	st.spin_rate = 0.0
	root.add_child(st)
	var hall: Node3D = st.ensure_interior()

	# 补光：独立构造的舱室没有场景环境光，纯靠一盏顶灯会黑成一片。
	# （真实游戏里由 WorldEnvironment 的环境光 + 天空提供照明。）
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.78)
	e.ambient_light_energy = 1.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)

	var lamp := OmniLight3D.new()
	lamp.light_energy = 2.4
	lamp.omni_range = hall.hall_radius * 2.2
	lamp.position = Vector3(0.0, hall.ceiling_height - 0.6, 0.0)
	hall.add_child(lamp)

	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 20000.0
	cam.fov = 72.0
	root.add_child(cam)
	cam.current = true
	await _frames(4)

	var r: float = hall.hall_radius
	var cy: float = hall.ceiling_height
	# 视线高度按人眼 1.6 米
	var eye := 1.6

	# ① 站在落点（舱边）看向舱中心，稍微抬头 —— 让环窗占画面上半
	cam.global_position = hall.to_global(Vector3(0.0, eye, r * 0.62))
	cam.look_at(hall.to_global(Vector3(0.0, eye + r * 0.18, -r * 0.5)), Vector3.UP)
	await _frames(6)
	await _shot("stand_spawn")

	# ② 靠近控制台，平视
	cam.global_position = hall.to_global(Vector3(0.0, eye, r * 0.5))
	cam.look_at(hall.to_global(Vector3(0.0, 1.15, 0.0)), Vector3.UP)
	await _frames(6)
	await _shot("look_console")

	# ③ 抬头看天花板与顶部灯环
	cam.global_position = hall.to_global(Vector3(r * 0.4, eye, 0.0))
	cam.look_at(hall.to_global(Vector3(0.0, cy * 1.4, 0.0)), Vector3.UP)
	await _frames(6)
	await _shot("look_ceiling")

	# ④ 站在出口环上俯视（能看到发光环）
	cam.global_position = hall.to_global(Vector3(0.0, 3.0, 7.0))
	cam.look_at(hall.to_global(Vector3(0.0, 0.0, 0.0)), Vector3.UP)
	await _frames(6)
	await _shot("look_exit")

	print("DONE")
	quit(0)
