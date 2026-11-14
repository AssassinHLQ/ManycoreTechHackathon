extends SceneTree
# 探针：尾焰喷口对位检查。
# 在 engine_plumes 的三个实际起点放红色发光球，分别拍「尾焰开 / 关」两组图，
# 看火焰根部是否落在机身发动机口上（尤其垂直方向）。
# 用法（必须窗口模式，headless 出不了图）：
#   Godot_v4.7.1-stable_win64_console.exe --path . --script res://tests/_probe_plume_align.gd

var game
var cam: Camera3D


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-4000, -4000))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://captures/%s.png" % name)
		print("  saved %s.png (%dx%d)" % [name, img.get_width(), img.get_height()])


func _marker(at: Vector3, color: Color) -> Node3D:
	# 无深度测试的十字准星：不受遮挡，能直接叠在喷口圆心上比较
	var root := Node3D.new()
	root.position = at
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	var arm := 5.0
	var thick := 0.12
	for horizontal in [true, false]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(arm * 2.0, thick, thick) if horizontal else Vector3(thick, arm * 2.0, thick)
		mi.mesh = bm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var save_path := "user://probe_plume_align.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	await _frames(10)
	game.start_game()
	await _frames(30)

	var ship = game.ship
	if ship == null:
		print("!! no ship")
		quit(1)
		return

	var L: float = ship.ship_model_length
	var H: float = ship.ship_model_height
	print("=== PLUME ALIGN (len=%.2f height=%.2f span=%.2f sink=%.2f) ===" % [
		L, H, ship.ship_model_span, ship.SHIP_MODEL_GROUND_SINK])
	print("hull y range: [%.2f, %.2f]" % [
		-ship.SHIP_MODEL_GROUND_SINK, H - ship.SHIP_MODEL_GROUND_SINK])
	for i in range(ship.engine_plumes.size()):
		var p: Node3D = ship.engine_plumes[i]
		print("  plume[%d] local=%s  (pct_height_from_bottom=%.1f%%)" % [
			i, str(p.position),
			100.0 * (p.position.y + ship.SHIP_MODEL_GROUND_SINK) / maxf(H, 0.001)])

	# 手动点亮尾焰，避免依赖物理状态
	ship.thrust_level = 1.0
	ship.engine_level = 1.0
	for p in ship.engine_plumes:
		(p as Node3D).visible = true
	for h in ship.engine_halos:
		(h as Node3D).visible = true

	# 黄色准星 = 当前尾焰起点；洋红准星 = 下移 0.65 m 的候选
	for i in range(ship.engine_plumes.size()):
		var p: Node3D = ship.engine_plumes[i]
		ship.add_child(_marker(p.position, Color(1.0, 0.95, 0.1)))
		ship.add_child(_marker(p.position + Vector3(0, -0.65, 0), Color(1.0, 0.1, 0.9)))

	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 1200.0
	root.add_child(cam)
	cam.current = true

	var sp: Vector3 = ship.global_position
	var nozzle_mid := Vector3(0.0, -4.7, L * 0.47)
	# 玩家视角：站在船尾正后 13 m、水面以上 1.65 m（船原点距水面 SINK）
	var eye_y: float = -ship.SHIP_MODEL_GROUND_SINK + 1.65
	var shots := [
		["plume_dbg_eye_off", Vector3(0, eye_y, L * 0.5 + 13.0), nozzle_mid],
		["plume_dbg_eye_on", Vector3(0, eye_y, L * 0.5 + 13.0), nozzle_mid],
		["plume_dbg_back_off", Vector3(0, 6, 62), nozzle_mid],
		["plume_dbg_back_on", Vector3(0, 6, 62), nozzle_mid],
		["plume_dbg_side_off", Vector3(55, 4, L * 0.42), nozzle_mid],
		["plume_dbg_side_on", Vector3(55, 4, L * 0.42), nozzle_mid],
	]
	for spec in shots:
		var with_plume: bool = String(spec[0]).ends_with("_on")
		for p in ship.engine_plumes:
			(p as Node3D).visible = with_plume
		for h in ship.engine_halos:
			(h as Node3D).visible = with_plume
			# 软壳和火舌同亮，关的时候一起关
		for p in ship.ventral_plumes:
			(p as Node3D).visible = false
		cam.global_position = sp + (spec[1] as Vector3)
		cam.look_at(sp + (spec[2] as Vector3), Vector3.UP)
		await _frames(12)
		await _shot(String(spec[0]))

	print("PLUME ALIGN DONE")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
