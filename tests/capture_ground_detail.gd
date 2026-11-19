extends SceneTree
# 探针：贴地视角出图 —— 专门看「地面颗粒质感」和「起伏是否还突兀」。
#   godot --path . --resolution 1600x900 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/capture_ground_detail.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var game
var cam


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
	root.get_texture().get_image().save_png("res://captures/ground_%s.png" % label)
	print("saved ground_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_ground.json"
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
		if game.ship.camera != null:
			game.ship.camera.current = false
	for child in game.get_children():
		if child is CanvasLayer or child is Control:
			child.visible = false
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for n in game.find_children("*", "Control", true, false):
		(n as Control).visible = false
	await _frames(3)

	cam = Camera3D.new()
	cam.near = 0.4
	cam.far = 400000.0
	root.add_child(cam)
	cam.make_current()

	# 站在几颗星球的地表上看
	var targets := ["qinglan", "zheya", "jinwu", "taiyuan", "sue"]
	for pid in targets:
		var p = null
		for q in game.planets:
			if q.planet_id == pid:
				p = q
				break
		if p == null:
			continue
		var up: Vector3 = p.site_direction.normalized()
		# 站点方向有观测塔建筑，镜头会穿进墙里。
		# 沿切向偏出 260 米，站在开阔地面上看地表质感。
		var tangent: Vector3 = up.cross(Vector3.RIGHT)
		if tangent.length_squared() < 0.01:
			tangent = up.cross(Vector3.FORWARD)
		tangent = tangent.normalized()
		var view_dir: Vector3 = (up + tangent * (260.0 / float(p.radius))).normalized()
		var ground: Vector3 = p.global_position + p.surface_position(view_dir, 0.0)
		var fwd: Vector3 = up.cross(Vector3.RIGHT)
		if fwd.length_squared() < 0.01:
			fwd = up.cross(Vector3.FORWARD)
		fwd = fwd.normalized()
		# 离地 2.2 米（人眼高度），平视远方
		cam.position = ground + view_dir * 2.2
		cam.look_at(ground + view_dir * 1.6 + fwd * 400.0, view_dir)
		cam.fov = 72.0
		await _shot(pid)

	print("DONE")
	quit(0)
