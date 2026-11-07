extends SceneTree

## 一次性探针：把机位对准主光方向，确认天空着色器里的太阳真的画出来了。
## 只用来肉眼核对，不进测试套件。
##   1) 正常档：对准主光方向拍一张
##   2) 对照档：把 sun_angular 放大到 0.5 —— 若整片天变亮，说明 sun_layer 确实在跑

func _initialize() -> void:
	call_deferred("_run")


func _shot(game, cam: Camera3D, path: String) -> void:
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = game.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.apply_sky("cloud")
	game.set_process(false)
	if game.hud != null:
		game.hud.visible = false
	var mat: ShaderMaterial = game.sky_material
	print("sun_strength  = ", mat.get_shader_parameter("sun_strength"))
	print("sun_angular   = ", mat.get_shader_parameter("sun_angular"))
	print("sun_direction = ", mat.get_shader_parameter("sun_direction"))

	var cam: Camera3D = game.player.camera
	cam.current = true
	var dir: Vector3 = game.key_light.global_transform.basis.z.normalized()
	cam.global_position = game.player.global_position
	cam.look_at(cam.global_position + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	mat.set_shader_parameter("pixel_angle", 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / 720.0)
	await _shot(game, cam, "res://captures/probe_sun.png")

	# 对照：把太阳放大到包住整片天，若天变亮就说明 sun_layer 在执行
	mat.set_shader_parameter("sun_angular", 0.5)
	await _shot(game, cam, "res://captures/probe_sun_wide.png")
	quit(0)
