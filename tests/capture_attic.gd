extends SceneTree

## 临时：阁楼实拍（三机位）。跑完即删。

const AtticScript = preload("res://scripts/attic.gd")

var attic
var camera: Camera3D


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(label: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://captures/attic_" + label + ".png")
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
	attic.build()

	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 200.0
	camera.fov = 72.0
	world.add_child(camera)
	camera.current = true

	# 机位一：从门口往窗（正对大门方向）
	camera.position = Vector3(0.2, 1.55, -1.6)
	camera.look_at(Vector3(0.0, 1.45, 2.4), Vector3.UP)
	await _shot("01_from_doors_to_window")

	# 机位二：从窗边回看四扇门
	camera.position = Vector3(0.1, 1.55, 1.9)
	camera.look_at(Vector3(0.0, 1.2, -2.9), Vector3.UP)
	await _shot("02_window_to_doors")

	# 机位三：茶几与旅行架
	camera.position = Vector3(-0.6, 1.5, 2.2)
	camera.look_at(Vector3(2.6, 1.0, -0.9), Vector3.UP)
	await _shot("03_table_and_shelf")

	# 机位四：镜界回廊
	camera.position = Vector3(1.4, 1.5, 0.9)
	camera.look_at(Vector3(-3.3, 1.3, 0.9), Vector3.UP)
	await _shot("04_mirror_corridor")

	print("ATTIC CAPTURE COMPLETE")
	quit(0)
