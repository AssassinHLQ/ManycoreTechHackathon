extends SceneTree

## 临时：验证 gl_compatibility 下能否开 glow / 加雾。跑完即删。

const AtticScript = preload("res://scripts/attic.gd")


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(label: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://captures/glowtest_" + label + ".png")
	var total := 0.0
	var count := 0
	for x in range(0, image.get_width(), 16):
		for y in range(0, image.get_height(), 16):
			var pixel := image.get_pixel(x, y)
			total += (pixel.r + pixel.g + pixel.b) / 3.0
			count += 1
	print("SHOT ", label, " luma=", total / maxf(1.0, float(count)))


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("141310")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c8b795")
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	# 关键实验：Compatibility 后端下开 glow 与雾
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.25
	e.glow_hdr_threshold = 0.85
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.fog_enabled = true
	e.fog_light_color = Color("6b5f4a")
	e.fog_density = 0.035
	env_node.environment = e
	world.add_child(env_node)

	var attic = AtticScript.new()
	world.add_child(attic)
	attic.build()

	var camera := Camera3D.new()
	camera.near = 0.05
	camera.far = 200.0
	camera.fov = 72.0
	world.add_child(camera)
	camera.current = true
	camera.position = Vector3(0.0, 1.05, 1.6)
	camera.look_at(Vector3(0.0, 1.1, -2.9), Vector3.UP)
	await _shot("with_glow_and_fog")

	print("GLOW TEST COMPLETE renderer=", RenderingServer.get_video_adapter_name())
	quit(0)
