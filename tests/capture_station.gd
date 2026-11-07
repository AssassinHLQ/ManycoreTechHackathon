extends SceneTree

var game
var review_camera: Camera3D


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
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


func _run() -> void:
	var capture_save := "user://starward_capture_station.json"
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = capture_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.start_game()
	await _frames(20)
	game.hud.menu.visible = false
	game.hud.toast_timer = 0.0
	game.hud.toast.visible = false

	var station = game.station
	review_camera = Camera3D.new()
	review_camera.near = 0.5
	review_camera.far = 60000.0
	review_camera.fov = 55.0
	game.add_child(review_camera)
	review_camera.current = true
	game.state = "capture"
	game.hud.visible = false

	review_camera.global_position = station.to_global(Vector3(760.0, 480.0, 760.0))
	review_camera.look_at(station.to_global(Vector3(0.0, 50.0, 0.0)), station.up_direction())
	await _frames(8)
	await _capture("station_exterior")

	review_camera.global_position = station.to_global(Vector3(480.0, 80.0, 480.0))
	review_camera.look_at(station.to_global(Vector3(0.0, 60.0, 0.0)), station.up_direction())
	review_camera.fov = 55.0
	await _frames(8)
	await _capture("station_axis")

	review_camera.global_position = station.to_global(Vector3(55.0, -105.0, 65.0))
	review_camera.look_at(station.to_global(Vector3(0.0, -58.0, 0.0)), station.up_direction())
	review_camera.fov = 50.0
	await _frames(8)
	await _capture("station_spine")

	review_camera.global_position = station.to_global(Vector3(182.0, 34.0, 56.0))
	review_camera.look_at(station.to_global(Vector3(214.0, -2.0, -16.0)), station.up_direction())
	review_camera.fov = 48.0
	await _frames(8)
	await _capture("station_hull")

	review_camera.global_position = station.to_global(Vector3(55.0, 292.0, 95.0))
	review_camera.look_at(station.to_global(Vector3(0.0, 250.0, 0.0)), station.up_direction())
	review_camera.fov = 55.0
	await _frames(8)
	await _capture("station_dock")

	game.ship.landed = false
	game.ship.landed_planet = null
	game.ship.set_physics_process(false)
	game.ship.dock_station(station)
	game.hud.toast_timer = 0.0
	game.hud.toast.visible = false
	review_camera.global_position = station.to_global(Vector3(45.0, 292.0, 70.0))
	review_camera.look_at(station.to_global(Vector3(0.0, 258.0, 0.0)), station.up_direction())
	review_camera.fov = 48.0
	await _frames(8)
	await _capture("station_docked")

	game.in_station = true
	await _frames(4)
	review_camera.global_position = station.to_global(Vector3(16.0, 6.8, 21.0))
	review_camera.look_at(station.to_global(Vector3(0.0, -1.8, 0.0)), station.up_direction())
	review_camera.fov = 82.0
	await _frames(8)
	await _capture("station_hub_overview")

	game.hud.visible = true
	game.hud.menu.visible = false
	game.state = "walk"
	game.player.set_physics_process(false)
	game.player.reparent(station, false)
	game.player.camera.current = true

	_place_player(Vector3(18.0, -1.95, 0.0), Vector3(-4.0, 0.3, -18.0))
	await _frames(8)
	await _capture("station_hub")

	_place_player(Vector3(35.0, -1.97, 0.0), Vector3(120.0, -0.4, 0.0))
	await _frames(8)
	await _capture("station_corridor")

	_place_player(Vector3(145.0, -1.95, 0.0), Vector3(130.0, 0.9, -10.5))
	await _frames(8)
	await _capture("station_hall")

	_place_player(Vector3(45.0, -1.5, 0.0), Vector3(51.0, 1.9, -3.5))
	await _frames(8)
	await _capture("station_sign")

	_place_player(Vector3(51.0, -1.95, -4.0), Vector3(51.0, 0.9, -12.0))
	await _frames(8)
	await _capture("station_window")

	_place_player(Vector3(245.0, -1.95, 0.0), Vector3(256.0, 1.0, 0.0))
	await _frames(8)
	await _capture("station_bridge")

	_place_player(Vector3(233.0, -1.95, 0.0), Vector3(245.0, 0.8, 0.0))
	await _frames(8)
	await _capture("station_bridge_entry")

	_place_player(Vector3(248.0, -1.95, 0.0), Vector3(239.0, 0.8, 0.0))
	await _frames(8)
	await _capture("station_bridge_back")

	# 枢纽 A 门：关门、滑开途中、全开三种状态各拍一张。
	_place_player(Vector3(12.0, -1.95, 0.0), Vector3(40.0, 0.4, 0.0))
	await _frames(30)
	await _capture("station_hub_door_closed")
	_place_player(Vector3(22.0, -1.95, 0.0), Vector3(40.0, 0.4, 0.0))
	await _frames(8)
	await _capture("station_hub_door")
	await _frames(45)
	await _capture("station_hub_door_open")

	print("CAPTURE STATION COMPLETE")
	game.queue_free()
	await _frames(2)
	quit()


func _place_player(local_position: Vector3, look_local: Vector3) -> void:
	var station = game.station
	var world_position: Vector3 = station.to_global(local_position)
	var look_target: Vector3 = station.to_global(look_local)
	var direction := (look_target - world_position).normalized()
	game.player.global_transform = Transform3D(Basis.looking_at(direction, station.up_direction()), world_position)
	game.player.camera.rotation = Vector3.ZERO
	game.player.velocity = Vector3.ZERO
