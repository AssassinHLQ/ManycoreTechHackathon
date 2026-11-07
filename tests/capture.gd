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


func _look_at_planet(planet, direction: Vector3, distance_scale := 2.2) -> void:
	if review_camera == null:
		review_camera = Camera3D.new()
		review_camera.near = 0.2
		review_camera.far = 60000.0
		review_camera.fov = 55.0
		game.add_child(review_camera)
	game.state = "capture"
	game.hud.menu.visible = false
	review_camera.current = true
	var outward := direction.normalized()
	var tangent := outward.cross(Vector3.UP)
	if tangent.length_squared() < 0.01:
		tangent = outward.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	review_camera.global_position = planet.global_position + outward * planet.radius * distance_scale + tangent * planet.radius * 0.22
	review_camera.look_at(planet.global_position, outward)


func _look_at_landmark(planet, direction: Vector3) -> void:
	if review_camera == null:
		review_camera = Camera3D.new()
		review_camera.near = 0.2
		review_camera.far = 60000.0
		review_camera.fov = 58.0
		game.add_child(review_camera)
	game.state = "capture"
	game.hud.menu.visible = false
	review_camera.current = true
	var outward := direction.normalized()
	var tangent := outward.cross(Vector3.UP)
	if tangent.length_squared() < 0.01:
		tangent = outward.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var ground: Vector3 = planet.global_position + planet.surface_position(outward, 0.0)
	review_camera.global_position = ground + outward * 22.0 + tangent * 78.0
	review_camera.look_at(ground + outward * 10.0, outward)


func _look_inside(root: Node3D, eye: Vector3, target: Vector3, fov := 72.0) -> void:
	if review_camera == null:
		review_camera = Camera3D.new()
		review_camera.near = 0.06
		review_camera.far = 60000.0
		game.add_child(review_camera)
	game.state = "capture"
	game.hud.menu.visible = false
	review_camera.current = true
	review_camera.fov = fov
	review_camera.near = 0.06
	review_camera.global_position = root.global_transform * eye
	review_camera.look_at(root.global_transform * target, root.global_transform.basis.y)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://captures")
	var capture_save := "user://starward_capture.json"
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = capture_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(30)
	await _capture("01_title")
	game.start_game()
	await _frames(45)
	var anomaly = game._anomaly_by_id("qinglan")
	var up: Vector3 = (game.player.global_position - game.home.global_position).normalized()
	game.player.camera.look_at(anomaly.global_position + Vector3.UP * 4.0, up)
	await _frames(3)
	await _capture("02_exploration")
	game.map_open = true
	game.map_selected = 3
	game.map_zoom = 1.12
	game.map_pan = Vector2.ZERO
	await _frames(3)
	await _capture("03_star_map")
	game.map_open = false
	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.takeoff()
	await _frames(70)
	await _capture("04_flight")

	var home_dir := Vector3(-0.06, 1.0, -0.04).normalized()
	_look_at_landmark(game.home, home_dir)
	await _frames(4)
	await _capture("05_qinglan_windmill")
	var ember = game.planets[1]
	_look_at_landmark(ember, Vector3.UP)
	await _frames(4)
	await _capture("06_ember_station")
	var tide = game.planets[2]
	_look_at_landmark(tide, Vector3.UP)
	await _frames(4)
	await _capture("07_tide_station")
	var shard = game.planets[3]
	_look_at_landmark(shard, Vector3.UP)
	await _frames(4)
	await _capture("08_shard_temple")
	var eye = game.planets[4]
	_look_at_landmark(eye, Vector3.UP)
	await _frames(4)
	await _capture("09_eye_gate")

	var home_arch: Node3D = game.home.find_child("Architecture_Qinglan", true, false)
	_look_inside(home_arch, Vector3(0.0, 3.4, 4.7), Vector3(-0.4, 3.0, -2.2), 70.0)
	await _frames(4)
	await _capture("12_home_interior")
	_look_inside(home_arch, Vector3(8.0, 5.0, 20.0), Vector3(0.0, 0.1, 24.0), 62.0)
	await _frames(4)
	await _capture("19_village_path")
	var cave: Node3D = game.home.find_child("Cave_Qinglan", true, false)
	_look_inside(cave, Vector3(3.4, 3.6, 18.5), Vector3(0.0, 1.0, 8.6), 62.0)
	await _frames(4)
	await _capture("13_cave_mouth")
	_look_inside(cave, Vector3(0.0, -10.4, 11.0), Vector3(0.0, -12.2, -6.0), 74.0)
	await _frames(4)
	await _capture("14_cave_chamber")
	var tide_arch: Node3D = game.planets[2].find_child("Architecture_Cangbo", true, false)
	_look_inside(tide_arch, Vector3(2.4, 14.0, 2.6), Vector3(-4.4, 13.2, -1.8), 74.0)
	await _frames(4)
	await _capture("15_tide_interior")
	var quantum = game.quantum
	var q_normal: Vector3 = (quantum.global_position - quantum.get_parent().global_position).normalized()
	var q_tangent: Vector3 = q_normal.cross(Vector3.FORWARD).normalized()
	review_camera.global_position = quantum.global_position + q_tangent * 9.5 + q_normal * 2.2
	review_camera.look_at(quantum.global_position + q_normal * 2.7, q_normal)
	review_camera.fov = 58.0
	await _frames(4)
	await _capture("16_quantum_shard")
	var tail_dir: Vector3 = game.comet.global_position.normalized()
	var side: Vector3 = tail_dir.cross(Vector3.UP).normalized()
	review_camera.global_position = game.comet.global_position + side * 900.0 - tail_dir * 260.0
	review_camera.look_at(game.comet.global_position + tail_dir * 260.0, Vector3.UP)
	review_camera.fov = 55.0
	await _frames(4)
	await _capture("17_comet")
	game.hud.show_help()
	await _frames(4)
	await _capture("18_help_panel")
	game.hud.help.visible = false
	game.hud.show_settings()
	await _frames(4)
	await _capture("20_settings")
	game.hud.hide_settings()

	review_camera.global_position = Vector3(1450.0, 420.0, 1050.0)
	review_camera.look_at(Vector3.ZERO, Vector3.UP)
	await _frames(3)
	await _capture("10_sun_corona")
	game.state = "dying"
	game.death_timer = 1.9
	game.death_reason = "飞船坠入了恒星"
	await _frames(3)
	await _capture("11_consciousness_lost")
	print("CAPTURE COMPLETE")
	game.queue_free()
	await _frames(2)
	quit()
