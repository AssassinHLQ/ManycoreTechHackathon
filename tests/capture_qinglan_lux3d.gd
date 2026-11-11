extends SceneTree
# 探针：给青岚星（Lux3D v2 模型）出游戏内截图。
#
# ⚠ 两个坑（第一版都踩了）：
#   ① 只 await_world_ready 还停在主菜单 → 菜单面板盖满画面。必须先 start_game()。
#   ② 借用飞船的相机不行 —— 飞船 `_physics_process` 每帧把相机摆回座舱，
#      外部摆的机位立刻被覆盖。必须**自建 Camera3D 并 make_current()**。
#
# 拍五个视角：太空远景 / 中距 / 低空 / 地表两向。
#
# 窗口纪律（AGENTS.md）：运行时挪窗口到屏幕外 + 命令行带 --no-capture。
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/capture_qinglan_lux3d.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var game
var cam: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _shot(label: String) -> void:
	# 每张都重新抢一次 current，防被飞船相机抢回去
	cam.make_current()
	await _frames(6)
	cam.make_current()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://captures/qinglan_lux3d_%s.png" % label)
	print("saved res://captures/qinglan_lux3d_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)

	var save := "user://starward_capture_qinglan.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(10)

	# 真的进游戏，并跳过开场引导卡
	game.start_game()
	for _i in range(30):
		await physics_frame
	if game.guide_card != null and game.guide_card.active:
		game.guide_card.skip()
		await _frames(5)
	game.state = "ship"

	# 冻结飞船：否则它每帧更新相机、还可能自己着陆
	if game.ship != null:
		game.ship.set_physics_process(false)
		game.ship.autopilot = false
		game.ship.landed = false
		game.ship.docked = false
		if game.ship.camera != null:
			game.ship.camera.current = false
	await _frames(5)

	var planet = game.home
	var center: Vector3 = planet.global_position
	var r: float = float(planet.radius)
	print("青岚星：半径 %.0f，位置 %s" % [r, str(center)])
	print("Lux3D 路径 = %s（height_ready=%s）" % [
		planet.lux_model_path, str(planet._lux_height_ready)])

	# ── 自建相机，挂在场景根上，绝不与飞船相机纠缠 ──
	cam = Camera3D.new()
	cam.name = "CaptureCam"
	cam.near = 0.5
	cam.far = 400000.0
	root.add_child(cam)
	cam.make_current()

	# ── 1. 太空远景：4.2 倍半径 ──
	var dir_out := Vector3(0.55, 0.35, 0.75).normalized()
	cam.position = center + dir_out * r * 4.2
	cam.look_at(center, Vector3.UP)
	cam.fov = 55.0
	await _shot("01_space_far")

	# ── 2. 中距：2.1 倍半径 ──
	cam.position = center + dir_out * r * 2.1
	cam.look_at(center, Vector3.UP)
	cam.fov = 55.0
	await _shot("02_space_mid")

	# ── 3. 低空：1.3 倍半径，略偏地平线 ──
	var low_dir := Vector3(0.32, 0.86, 0.40).normalized()
	var tangent_a := low_dir.cross(Vector3.UP).normalized()
	cam.position = center + low_dir * r * 1.30
	cam.look_at(center + low_dir * r * 0.55 + tangent_a * r * 0.62, Vector3.UP)
	cam.fov = 70.0
	await _shot("03_low_altitude")

	# ── 4/5. 地表：站在观测塔平台旁边，朝两个切向看地平线 ──
	var site_n: Vector3 = planet.site_direction.normalized()
	var ground: Vector3 = center + planet.surface_position(site_n, 0.0)
	var up: Vector3 = site_n
	var fwd: Vector3 = up.cross(Vector3.RIGHT)
	if fwd.length_squared() < 0.01:
		fwd = up.cross(Vector3.FORWARD)
	fwd = fwd.normalized()
	var side: Vector3 = fwd.cross(up).normalized()

	# 4：站在平台外 40 米，平视远方 —— 看地面贴图与起伏
	cam.position = ground + up * 4.0 + side * 40.0
	cam.look_at(ground + up * 2.0 + side * 300.0, up)
	cam.fov = 72.0
	await _shot("04_ground")

	# 5：另一个方向，能看见观测塔本体
	cam.position = ground + up * 6.0 + fwd * 55.0 + side * 20.0
	cam.look_at(ground + up * 8.0, up)
	cam.fov = 65.0
	await _shot("05_ground_tower")

	print("DONE")
	quit(0)
