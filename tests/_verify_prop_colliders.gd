extends SceneTree
# 验证：道具碰撞是否与可见网格对齐（抽射线），登船判定是否覆盖 70 m 船体，
# 以及新碰撞体的物理开销。
# 用法：godot --headless --path . --script res://tests/_verify_prop_colliders.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var save := "user://verify_prop_col.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	print("=== 建场耗时 %d ms ===" % (Time.get_ticks_msec() - t0))

	var home = game.home
	var bodies: Array = home.find_children("PropCollision_*", "StaticBody3D", true, false)
	var shapes := 0
	for b in bodies:
		shapes += b.get_child_count()
	print("=== 碰撞体：StaticBody=%d，形状=%d ===" % [bodies.size(), shapes])

	# 抽样射线：从形状原点正上方打下来，命中应该就是它自己的 body
	var checked := 0
	var ok := 0
	for b in bodies:
		if checked >= 12:
			break
		var ch: CollisionShape3D = null
		for c in b.get_children():
			if c is CollisionShape3D:
				ch = c
				break
		if ch == null:
			continue
		var wpos: Vector3 = (b as Node3D).global_transform * ch.position
		var up: Vector3 = (wpos - home.global_position).normalized()
		var q := PhysicsRayQueryParameters3D.create(wpos + up * 200.0, wpos - up * 30.0)
		var hit: Dictionary = home.get_world_3d().direct_space_state.intersect_ray(q)
		var hit_name := "(无)"
		if not hit.is_empty() and hit.get("collider") is Node:
			hit_name = String((hit.get("collider") as Node).name)
		var good: bool = hit_name == String((b as Node).name)
		if good:
			ok += 1
		checked += 1
		print("  %s -> 命中 %s  %s" % [String((b as Node).name), hit_name,
			"OK" if good else "MISALIGNED"])
	print("=== 抽样 %d 个，命中自己 %d 个 ===" % [checked, ok])

	print("=== 登船判定 ===")
	var ship = game.ship
	print("  玩家到船体原点 = %.2f m" % game.player.global_position.distance_to(ship.global_position))
	print("  现场: near_ship_to_board() = %s（旧阈值 8.0 时为 false）" % str(game.near_ship_to_board()))
	var wing: Vector3 = ship.global_position + ship.global_transform.basis.x.normalized() * 30.0
	game.player.global_position = wing
	print("  挪到机翼旁 30 m: %s" % str(game.near_ship_to_board()))
	game.player.global_position = ship.global_position + ship.global_transform.basis.x.normalized() * 40.0
	print("  挪到 40 m（超出）: %s" % str(game.near_ship_to_board()))

	await _frames(60)
	print("=== 物理 ===")
	print("  PHYSICS_PROCESS_TIME = %.2f ms" % (
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0))

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
