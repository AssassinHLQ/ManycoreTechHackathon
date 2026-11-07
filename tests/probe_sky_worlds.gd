extends SceneTree
# 一次性探针：把每个世界的天空单独拍下来，用来看「云形」到底一不一样。
# 不进测试套件（它不比对，只出图给人看）。
#   godot --path . --script res://tests/probe_sky_worlds.gd -- [可选:世界1 世界2 ...]
#
# 机位固定、景色固定，所以两张图之间的差别只来自天空本身 —— 这正是要比的东西。

const ALL_WORLDS := ["space", "attic", "snow", "cloud", "firefly", "alley", "mirror", "dungeon"]
# 抬高一点看天：地平线附近会被雾（haze）压住，看不出云的轮廓
const PITCH_DEG := 22.0
const YAW_DEG := 0.0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _shot(game, name: String) -> void:
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path := "res://captures/probe_sky_%s.png" % name
	img.save_png(path)
	print("saved ", path)


func _run() -> void:
	var worlds := ALL_WORLDS
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		worlds = []
		for a in argv:
			worlds.append(a)

	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	# 玩家脚本会每帧抢相机朝向，先关掉
	if game.player != null:
		game.player.set_process(false)
		game.player.set_physics_process(false)
	game.set_process(false)
	if game.hud != null:
		game.hud.visible = false

	var cam: Camera3D = game.player.camera
	cam.current = true
	var base: Vector3 = game.player.global_position
	# 抬到高处再往上看，避免地面挡视野
	cam.global_position = base + Vector3(0, 6.0, 0)
	var yaw: float = deg_to_rad(YAW_DEG)
	var pitch: float = deg_to_rad(PITCH_DEG)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.look_at(cam.global_position + dir, Vector3.UP)
	# 星盘的抗锯齿靠这个 uniform，探针自己推一遍
	var mat: ShaderMaterial = game.sky_material
	mat.set_shader_parameter("pixel_angle", 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / 720.0)

	for key in worlds:
		game.apply_sky(key)
		mat.set_shader_parameter("flow_speed", 0.0)
		print("%-8s band=%.2f scale=%.2f warp=%.2f thr=%.2f struct=%.2f axis=%s seed=%s" % [
			key,
			float(mat.get_shader_parameter("nebula_band")),
			float(mat.get_shader_parameter("nebula_scale")),
			float(mat.get_shader_parameter("nebula_warp")),
			float(mat.get_shader_parameter("nebula_threshold")),
			float(mat.get_shader_parameter("nebula_structure")),
			str(mat.get_shader_parameter("nebula_axis")),
			str(mat.get_shader_parameter("nebula_seed")),
		])
		await _shot(game, key)
	quit(0)
