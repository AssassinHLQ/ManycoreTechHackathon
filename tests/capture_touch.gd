extends SceneTree

var game


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


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_capture_touch.json"
	root.add_child(game)
	await game.await_world_ready()
	await _frames(30)
	game.start_game()
	await _frames(40)
	game.touch_controls.enabled = true
	game.touch_controls.set_process(true)
	await _frames(6)
	await _capture("touch_walk")

	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.landed = true
	game.ship.landed_planet = game.home
	game.touch_controls.current_mode = ""
	await _frames(6)
	await _capture("touch_ship")

	game.map_open = true
	game.touch_controls.current_mode = ""
	await _frames(6)
	await _capture("touch_map")
	game.map_open = false
	print("CAPTURE TOUCH COMPLETE")
	game.queue_free()
	await _frames(2)
	quit()
