extends SceneTree
# 诊断：walk_test「walking out of the observatory is continuous」失败时，
# 玩家到底撞到了哪个碰撞体。
# 用法：godot --headless --path . --script res://tests/_diag_walk_exit.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _place(arch: Node3D, local: Vector3) -> void:
	if game.player.get_parent() != arch.get_parent():
		game.player.reparent(arch.get_parent(), false)
	game.player.global_transform = Transform3D(
		arch.global_transform.basis.orthonormalized(), arch.global_transform * local)
	game.player.velocity = Vector3.ZERO


func _run() -> void:
	var save := "user://diag_walk_exit.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(20):
		await physics_frame
	while game.planets.size() < 20:
		await process_frame
	for i in range(20):
		await physics_frame

	var arch: Node3D = game.home.find_child("Architecture_Qinglan", true, false)
	_place(arch, Vector3(0.5, 1.78, 3.0))
	for i in range(30):
		await physics_frame

	var max_step := 0.0
	var max_frame := -1
	var hits := {}
	var prev: Vector3 = game.player.position
	Input.action_press("move_back")
	for i in range(180):
		await physics_frame
		var step: float = prev.distance_to(game.player.position)
		if step > max_step:
			max_step = step
			max_frame = i
		prev = game.player.position
		for c in range(game.player.get_slide_collision_count()):
			var col = game.player.get_slide_collision(c)
			var o = col.get_collider()
			if o != null:
				var key := String(o.name)
				hits[key] = int(hits.get(key, 0)) + 1
	Input.action_release("move_back")

	var local: Vector3 = arch.global_transform.affine_inverse() * game.player.global_position
	print("=== 结果 ===")
	print("  max_step = %.3f m（阈值 1.5），第 %d 帧" % [max_step, max_frame])
	print("  最终局部坐标 = %s（期望 z > 6.0）" % str(local))
	print("  撞到的碰撞体: %s" % str(hits))

	# 出口附近 40 m 内的道具碰撞体
	print("=== 出口附近碰撞体 ===")
	var exit_pos: Vector3 = arch.global_transform * Vector3(0.5, 1.78, 7.0)
	for b in game.home.find_children("PropCollision_*", "StaticBody3D", true, false):
		var d: float = (b as Node3D).global_position.distance_to(exit_pos)
		if d < 60.0:
			print("  %s  中心距出口 %.1f m，形状 %d" % [
				String((b as Node).name), d, (b as Node).get_child_count()])

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
