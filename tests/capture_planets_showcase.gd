extends SceneTree
# 探针：比赛用截图 —— 十颗 Lux3D 星球逐个特写 + 系统全景 + 地表视角。
#
# 窗口纪律（AGENTS.md）：运行时挪窗口到屏幕外 + 命令行带 --no-capture。
#   godot --path . --resolution 1920x1080 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/capture_planets_showcase.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var game
var cam: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame


func _shot(label: String) -> void:
	cam.make_current()
	await _frames(6)
	cam.make_current()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		"res://captures/planet_%s.png" % label)
	print("saved planet_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_cap_planets.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(10)
	game.start_game()
	for _i in range(40):
		await physics_frame
	if game.guide_card != null and game.guide_card.active:
		game.guide_card.skip()
		await _frames(5)
	game.state = "ship"
	if game.ship != null:
		game.ship.set_physics_process(false)
		game.ship.autopilot = false
		game.ship.landed = false
		game.ship.docked = false
		if game.ship.camera != null:
			game.ship.camera.current = false
	await _frames(5)

	# ⚠ 比赛截图不能带 HUD：把界面上所有 CanvasLayer / Control 全部隐藏
	#   （驾驶舱标题、提示文字、速度/船体条、星图标记都在里面）
	for child in game.get_children():
		if child is CanvasLayer or child is Control:
			child.visible = false
	# 有些面板挂在相机或玩家下面，再扫一遍全树
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for n in game.find_children("*", "Control", true, false):
		(n as Control).visible = false
	await _frames(3)

	cam = Camera3D.new()
	cam.near = 0.5
	cam.far = 400000.0
	root.add_child(cam)
	cam.make_current()

	print("=== 十颗星球 ===")
	for p in game.planets:
		print("  %-6s r=%.0f  %s" % [
			p.planet_id, float(p.radius), p.lux_model_path])

	# ── 每颗星球一张特写：3.2 倍半径、略高视角 ──
	var dir := Vector3(0.62, 0.42, 0.66).normalized()
	for p in game.planets:
		var c: Vector3 = p.global_position
		var r: float = float(p.radius)
		cam.position = c + dir * r * 3.2
		cam.look_at(c, Vector3.UP)
		cam.fov = 50.0
		await _shot("solo_%s" % p.planet_id)

	# ── 系统全景：从母星外侧拉远，看内圈几颗 ──
	var home = game.home
	var hc: Vector3 = home.global_position
	var out_dir := (hc.normalized() + Vector3(0.0, 0.55, 0.0)).normalized()
	cam.position = hc + out_dir * 42000.0
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 68.0
	await _shot("system_wide")

	# ── 青岚星地表：站在观测塔旁，平视地平线 ──
	var site_n: Vector3 = home.site_direction.normalized()
	var ground: Vector3 = hc + home.surface_position(site_n, 0.0)
	var up: Vector3 = site_n
	var fwd: Vector3 = up.cross(Vector3.RIGHT)
	if fwd.length_squared() < 0.01:
		fwd = up.cross(Vector3.FORWARD)
	fwd = fwd.normalized()
	var side: Vector3 = fwd.cross(up).normalized()
	cam.position = ground + up * 5.0 + side * 30.0
	cam.look_at(ground + up * 3.0 + side * 400.0, up)
	cam.fov = 70.0
	await _shot("ground_qinglan")

	# ── 青岚星地表 2：朝观测塔 ──
	cam.position = ground + up * 8.0 + fwd * 48.0 + side * 14.0
	cam.look_at(ground + up * 10.0, up)
	cam.fov = 62.0
	await _shot("ground_tower")

	print("DONE")
	quit(0)
