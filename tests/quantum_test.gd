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
	var test_save := "user://starward_quantum_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(30):
		await physics_frame
	var quantum = game.quantum
	_check(quantum != null, "quantum shard exists")
	if quantum == null:
		quit(1)
		return
	var shard: Node3D = quantum.get_parent()
	_check(quantum.positions.size() == 5, "shard has five candidate positions")
	_check(game.anomalies.has(quantum), "quantum shard is a scan target")

	game.player.reparent(shard, false)
	var normal: Vector3 = (quantum.global_position - shard.global_position).normalized()
	var tangent: Vector3 = normal.cross(Vector3.FORWARD).normalized()
	game.player.global_position = quantum.global_position + tangent * 14.0 + normal * 1.6
	game.player.velocity = Vector3.ZERO
	for i in range(6):
		await physics_frame
	var up: Vector3 = (game.player.global_position - shard.global_position).normalized()
	game.player.camera.look_at(quantum.crystal.global_position, up)
	await physics_frame
	_check(quantum._observed(), "looking at the shard counts as observation")
	quantum.unobserved_time = 5.0
	var held_index: int = quantum.index
	quantum._process(0.016)
	_check(quantum.index == held_index, "observed shard does not teleport")

	game.player.camera.rotation.y += PI
	await physics_frame
	_check(not quantum._observed(), "looking away ends observation")
	quantum.unobserved_time = 5.0
	quantum._process(0.016)
	_check(quantum.index != held_index, "unobserved shard moves to another position")

	game.discovered["quantum"] = true
	quantum.unobserved_time = 5.0
	var locked_index: int = quantum.index
	quantum._process(0.016)
	_check(quantum.index == locked_index, "understood quantum rule keeps it in place")

	game.discovered.erase("quantum")
	game.discovered = {}
	game._save_knowledge()
	print("QUANTUM TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0 if failures == 0 else 1)
