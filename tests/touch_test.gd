extends SceneTree

var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _button(id: String) -> Dictionary:
	for button in game.touch_controls.buttons:
		if button.id == id:
			return button
	return {}


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_touch_test.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(12):
		await physics_frame
	var touch = game.touch_controls
	touch.enabled = true
	touch.set_process(true)
	touch._process(0.0)
	await process_frame
	touch._process(0.0)
	_check(touch.visible, "touch layer is visible in play mode")
	_check(touch.joystick_center != Vector2.ZERO, "touch joystick is laid out")

	touch._touch_start(10, touch.joystick_center + Vector2(0.0, -100.0))
	_check(Input.get_action_strength("move_forward") > 0.3, "joystick drives forward movement")
	touch._touch_end(10)
	_check(Input.get_action_strength("move_forward") < 0.01, "joystick releases movement")

	var jump := _button("jump")
	_check(not jump.is_empty(), "jump button is available on foot")
	if not jump.is_empty():
		touch._touch_start(11, jump.pos)
		_check(Input.is_action_pressed("jump"), "jump button presses the jump action")
		touch._touch_end(11)
	Input.action_release("jump")

	var yaw_before: float = game.player.rotation.y
	touch._touch_start(15, Vector2(1000.0, 400.0))
	touch._touch_drag(15, Vector2(1100.0, 400.0))
	_check(absf(game.player.rotation.y - yaw_before) > 0.01, "touch drag turns the camera")
	touch._touch_end(15)

	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.landed = true
	game.ship.landed_planet = game.home
	game.ship.velocity = Vector3.ZERO
	touch.current_mode = ""
	touch._process(0.0)
	var context := _button("context")
	_check(not context.is_empty(), "ship takeoff button is available")
	if not context.is_empty():
		touch._touch_start(12, context.pos)
		_check(not game.ship.landed, "takeoff button lifts the ship")
		touch._touch_end(12)
	touch._process(0.0)
	var autopilot := _button("autopilot")
	_check(not autopilot.is_empty(), "autopilot button appears in flight")
	if not autopilot.is_empty():
		touch._touch_start(17, autopilot.pos)
		_check(game.ship.autopilot, "autopilot button enables autopilot")
		touch._touch_end(17)
		game.ship.autopilot = false

	game.map_open = true
	touch.current_mode = ""
	await process_frame
	touch._process(0.0)
	var pan_before: Vector2 = game.map_pan
	touch._touch_start(16, Vector2(800.0, 450.0))
	touch._touch_drag(16, Vector2(870.0, 450.0))
	_check(absf(game.map_pan.x - pan_before.x) > 1.0, "touch drag pans the star map")
	touch._touch_end(16)

	var target := _button("map_target")
	_check(not target.is_empty(), "touch star map target button exists")
	if not target.is_empty():
		touch._touch_start(14, target.pos)
		_check(game.ship.target == game.planets[game.map_selected], "touch sets a map destination")
		touch._touch_end(14)
	var close := _button("map_close")
	_check(not close.is_empty(), "touch star map close button exists")
	if not close.is_empty():
		touch._touch_start(13, close.pos)
		_check(not game.map_open, "touch closes the star map")
		touch._touch_end(13)

	touch._release_all()
	game.queue_free()
	await process_frame
	print("TOUCH TEST COMPLETE: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
