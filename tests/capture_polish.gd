extends SceneTree

var game
var review_camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://captures/" + name + ".png"
	var result := image.save_png(path)
	print("CAPTURE ", path, " -> ", error_string(result))


func _ensure_camera() -> void:
	if review_camera == null:
		review_camera = Camera3D.new()
		review_camera.near = 0.8
		review_camera.far = 60000.0
		review_camera.fov = 54.0
		game.add_child(review_camera)
	game.state = "capture"


func _run() -> void:
	var capture_save := "user://starward_capture_polish.json"
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = capture_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(30)
	game.start_game()
	await _frames(40)

	_ensure_camera()
	game.hud.menu.visible = false
	review_camera.current = true
	review_camera.fov = 52.0
	review_camera.global_position = Vector3(0.0, 360.0, 1500.0)
	review_camera.look_at(Vector3.ZERO, Vector3.UP)
	await _frames(6)
	await _capture("sun_detail")

	review_camera.global_position = Vector3(0.0, 700.0, 3050.0)
	review_camera.look_at(Vector3.ZERO, Vector3.UP)
	await _frames(6)
	await _capture("sun_far")

	var comet: Node3D = game.comet
	var tail_dir: Vector3 = comet.global_position.normalized()
	var side: Vector3 = tail_dir.cross(Vector3.UP).normalized()
	review_camera.global_position = comet.global_position + side * 900.0 - tail_dir * 260.0
	review_camera.look_at(comet.global_position + tail_dir * 260.0, Vector3.UP)
	review_camera.fov = 50.0
	await _frames(6)
	await _capture("comet_single")

	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.zoom = 6.0
	game.ship.look_at(comet.global_position, Vector3.UP)
	game.ship._physics_process(0.4)
	await _frames(4)
	await _capture("zoom_view")

	review_camera.current = true
	review_camera.global_position = Vector3(0.0, 6000.0, 9000.0)
	review_camera.look_at(Vector3(0.0, 6200.0, -20000.0), Vector3.UP)
	review_camera.fov = 72.0
	await _frames(8)
	await _capture("stars_normal")

	game.state = "ship"
	game.ship.camera.current = true
	game.ship.global_position = Vector3(0.0, 6000.0, 9000.0)
	game.ship.look_at(Vector3(0.0, 6200.0, -20000.0), Vector3.UP)
	game.ship.zoom = 8.0
	game.ship.camera.fov = 9.0
	await _frames(8)
	await _capture("stars_zoom")

	game.state = "walk"
	game.player.set_physics_process(false)
	game.player.global_position = Vector3(0.0, 6000.0, 9000.0)
	game.player.look_at(game.planets[2].global_position, Vector3.UP)
	game.player.focus = true
	game.player.scope_zoom = 8.0
	game.player.camera.current = true
	game.player.camera.fov = 35.0 / 8.0
	await _frames(6)
	await _capture("scope_zoom")

	game.player.focus = false
	game.state = "ship"
	game.ship.camera.current = true
	game.ship.zoom = 16.0
	game.ship.camera.fov = 72.0 / 16.0
	game.ship.look_at(game.planets[2].global_position, Vector3.UP)
	await _frames(6)
	await _capture("ship_16x")

	game.ship.look_at(Vector3(0.0, 6200.0, -20000.0), Vector3.UP)
	await _frames(6)
	await _capture("stars_16x")
	print("CAPTURE POLISH COMPLETE")
	game.queue_free()
	await _frames(2)
	quit()
