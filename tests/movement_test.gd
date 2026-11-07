extends SceneTree

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_save := "user://starward_movement_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(45):
		await physics_frame
	var start: Vector3 = game.player.global_position
	print("START pos=", start, " floor=", game.player.is_on_floor(), " vel=", game.player.velocity)
	var planet = game.nearest_planet(start)
	var normal: Vector3 = (start - planet.global_position).normalized()
	print("TERRAIN height=", planet.terrain_height(normal), " radial=", start.length() - planet.global_position.length(), " normal=", normal)
	Input.action_press("move_forward")
	for i in range(120):
		await physics_frame
	Input.action_release("move_forward")
	var moved: float = start.distance_to(game.player.global_position)
	print("MOVE distance=", moved, " pos=", game.player.global_position, " floor=", game.player.is_on_floor(), " vel=", game.player.velocity)
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for i in range(10):
		await physics_frame
	print("JUMP floor=", game.player.is_on_floor(), " vel=", game.player.velocity)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0 if moved > 3.0 else 1)
