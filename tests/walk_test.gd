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


func _walk(action: String, frames: int) -> Array:
	var previous: Vector3 = game.player.global_position
	var max_step := 0.0
	var total := 0.0
	Input.action_press(action)
	for i in range(frames):
		await physics_frame
		var step: float = previous.distance_to(game.player.global_position)
		max_step = maxf(max_step, step)
		total += step
		previous = game.player.global_position
	Input.action_release(action)
	return [max_step, total]


func _place(arch: Node3D, local: Vector3) -> void:
	if game.player.get_parent() != arch.get_parent():
		game.player.reparent(arch.get_parent(), false)
	game.player.global_transform = Transform3D(arch.global_transform.basis.orthonormalized(), arch.global_transform * local)
	game.player.velocity = Vector3.ZERO


func _run() -> void:
	var test_save := "user://starward_walk_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(20):
		await physics_frame
	var arch: Node3D = game.home.find_child("Architecture_Qinglan", true, false)

	_place(arch, Vector3(8.0, 1.9, 0.0))
	for i in range(10):
		await physics_frame
	_check(game.player.is_on_floor(), "player stands on the observatory platform")
	var wall_run: Array = await _walk("move_left", 180)
	var wall_local: Vector3 = arch.global_transform.affine_inverse() * game.player.global_position
	_check(wall_run[0] < 1.5, "pushing into a wall does not teleport the player")
	_check(wall_local.x > 6.0, "the platform wall stops the player outside the tower")

	_place(arch, Vector3(0.5, 1.78, 3.0))
	for i in range(10):
		await physics_frame
	var exit_run: Array = await _walk("move_back", 180)
	var exit_local: Vector3 = arch.global_transform.affine_inverse() * game.player.global_position
	_check(exit_run[0] < 1.5, "walking out of the observatory is continuous")
	_check(exit_local.z > 6.0, "the player leaves through the front doorway")

	_place(arch, Vector3(0.5, 1.9, 8.0))
	for i in range(10):
		await physics_frame
	var enter_run: Array = await _walk("move_forward", 150)
	var enter_local: Vector3 = arch.global_transform.affine_inverse() * game.player.global_position
	_check(enter_run[0] < 1.5, "walking into the observatory is continuous")
	_check(enter_local.z < 5.0, "the player enters through the front doorway")

	var tide_arch: Node3D = game.planets[2].find_child("Architecture_Cangbo", true, false)
	if game.player.get_parent() != game.planets[2]:
		game.player.reparent(game.planets[2], false)
	game.player.global_transform = Transform3D(tide_arch.global_transform.basis.orthonormalized(), tide_arch.global_transform * Vector3(-1.5, 11.7, 6.4))
	game.player.velocity = Vector3.ZERO
	for i in range(12):
		await physics_frame
	var tide_run: Array = await _walk("move_forward", 150)
	var tide_local: Vector3 = tide_arch.global_transform.affine_inverse() * game.player.global_position
	_check(tide_run[0] < 1.5, "tide station stairs are climbable")
	_check(tide_local.z < 3.6, "the player enters the tide station")

	_place(arch, Vector3(8.0, 1.9, 0.0))
	for i in range(6):
		await physics_frame
	var surface_run: Array = await _walk("move_forward", 120)
	_check(surface_run[0] < 1.5, "surface walking never snaps")
	_check(surface_run[1] > 5.0, "surface walking covers ground")

	var cave: Node3D = game.home.find_child("Cave_Qinglan", true, false)
	for sample in [24, 64, 104, 144]:
		var t := float(sample) / 160.0
		var angle := PI * 0.5 - 0.30 + 0.36 * 40.0 * t
		var expected_y := lerpf(-0.2, -12.85, t)
		game.player.reparent(game.home, false)
		game.player.global_position = cave.global_transform * Vector3(cos(angle) * 8.4, expected_y + 1.2, sin(angle) * 8.4)
		game.player.velocity = Vector3.ZERO
		for i in range(45):
			await physics_frame
		var local: Vector3 = cave.global_transform.affine_inverse() * game.player.global_position
		_check(game.player.is_on_floor() and absf(local.y - expected_y) < 0.9, "spiral ramp supports the player at sample %d" % sample)

	game.discovered = {}
	game._save_knowledge()
	print("WALK TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0 if failures == 0 else 1)
