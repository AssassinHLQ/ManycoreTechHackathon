extends SceneTree
# 精确量飞船的**世界尺寸**，判断是否真的变小了。
# 参照物：玩家胶囊高 1.65 m、舱门高 2.05 m。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _run() -> void:
	var save_path := "user://starward_shipworld.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	await _frames(10)
	game.start_game()
	await _frames(30)

	var ship = game.ship
	print("=== SHIP WORLD SIZE ===")
	print("  TARGET_LENGTH const : %.3f" % ship.SHIP_MODEL_TARGET_LENGTH)
	print("  measured length     : %.3f" % ship.ship_model_length)
	print("  measured span       : %.3f" % ship.ship_model_span)
	print("  measured height     : %.3f" % ship.ship_model_height)
	print("  ship.scale          : %s" % str(ship.scale))
	print("  ship.global scale   : %s" % str(ship.global_transform.basis.get_scale()))

	var holder = ship._ship_model_holder
	if holder != null:
		print("  holder.scale        : %s" % str((holder as Node3D).scale))
		print("  holder.pos          : %s" % str((holder as Node3D).position))
		# 父链缩放
		var walker: Node = holder
		while walker != null and walker != game:
			if walker is Node3D:
				var sc: Vector3 = (walker as Node3D).scale
				if sc != Vector3.ONE:
					print("  ancestor %-22s scale=%s" % [String(walker.name), str(sc)])
			walker = walker.get_parent()

	# 用 mesh 的世界 AABB 量真实渲染尺寸
	var root_node = ship._ship_model_root
	if root_node == null:
		root_node = holder
	if root_node != null:
		var aabb := AABB()
		var first := true
		for mi in (root_node as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var b: AABB = m.global_transform * m.get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		if not first:
			print("  WORLD AABB size     : %.3f x %.3f x %.3f m" % [aabb.size.x, aabb.size.y, aabb.size.z])
			print("  WORLD AABB center   : %s" % str(aabb.get_center()))
			print("  >>> 机身实际长 %.2f m / 翼展 %.2f m / 高 %.2f m" % [aabb.size.z, aabb.size.x, aabb.size.y])

	# 参照：玩家胶囊
	if game.player != null:
		for c in game.player.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			if cs.shape is CapsuleShape3D:
				var cap := cs.shape as CapsuleShape3D
				print("  ref: player capsule  height=%.2f radius=%.2f" % [cap.height, cap.radius])

	# 舱门参照（阁楼）
	print("  ref: attic DOOR_HEIGHT = 2.05 m（常量）")

	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
