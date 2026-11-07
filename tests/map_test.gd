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


func _run() -> void:
	var test_save := "user://starward_map_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(15):
		await physics_frame
	game.toggle_map()
	_check(game.map_open, "star map opens")
	_check(game.map_selected >= 0 and game.map_selected < game.planets.size(), "a body is selected by default")
	var zoom_before: float = game.map_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	game._handle_map_input(wheel)
	_check(game.map_zoom > zoom_before, "mouse wheel zooms the map")
	var selected_before: int = game.map_selected
	game._cycle_map_selection(1)
	_check(game.map_selected != selected_before, "Q/E cycling changes selection")
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var target_index := 3
	var target_screen: Vector2 = game.map_screen_of(game.planets[target_index].global_position, size)
	game._select_map_body(target_screen, size)
	_check(game.map_selected == target_index, "clicking a body selects it")
	game._set_map_target()
	_check(game.ship.target == game.planets[target_index], "T sets the ship destination")
	var pan_before: Vector2 = game.map_pan
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(500, 400)
	game._handle_map_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, -20)
	game._handle_map_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(540, 380)
	game._handle_map_input(release)
	_check(game.map_pan != pan_before, "dragging pans the map")
	var start_pos: Vector3 = game.player.position
	Input.action_press("move_forward")
	for i in range(30):
		await physics_frame
	Input.action_release("move_forward")
	_check(game.player.position.distance_to(start_pos) < 0.3, "walking is frozen while the map is open")
	game.toggle_map()
	_check(not game.map_open, "star map closes")
	game.discovered = {}
	game._save_knowledge()
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("MAP TEST COMPLETE: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
