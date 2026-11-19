extends SceneTree
# 验证：站到船体旁边按 E 能登船（船体表面判定）。
# 用法：godot --headless --path . --script res://tests/_verify_boarding.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://verify_boarding.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	game.start_game()
	for i in range(30):
		await physics_frame

	var ship = game.ship
	print("state=%s  near=%s  距离=%.1f m" % [
		game.state, str(game.near_ship_to_board()),
		game.player.global_position.distance_to(ship.global_position)])

	# 出生点原地按 E（应登不上：离船 29 m）
	game._interact()
	await physics_frame
	print("出生点按 E: state=%s" % game.state)

	# 挪到机身侧面（船体半宽 + 3 m）
	var side: Vector3 = ship.global_transform.basis.x.normalized()
	game.player.global_position = ship.global_position + side * (ship.ship_model_span * 0.5 + 3.0)
	game.player.velocity = Vector3.ZERO
	await physics_frame
	print("机身旁: near=%s" % str(game.near_ship_to_board()))
	game._interact()
	await physics_frame
	print("机身旁按 E: state=%s（期望 ship）" % game.state)

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
