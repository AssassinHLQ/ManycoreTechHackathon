extends SceneTree
# 探针：着陆石岛（lf-mesa-plateau）到底有没有碰撞；玩家脚下踩的是什么；
# 飞船登船判定半径与 70 m 机长的实际距离差多少。
# 用法：godot --headless --path . --script res://tests/_probe_shore.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _run() -> void:
	var save := "user://probe_shore.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(30)

	var home = game.home
	var ship = game.ship
	print("=== 飞船 ===")
	print("  model_length=%.2f  span=%.2f  height=%.2f" % [
		ship.ship_model_length, ship.ship_model_span, ship.ship_model_height])
	var pdist: float = game.player.global_position.distance_to(ship.global_position)
	print("  玩家到船体原点距离 = %.2f m（登船阈值 8.0）" % pdist)
	print("  玩家在飞船局部坐标 = %s" % str(
		ship.global_transform.affine_inverse() * game.player.global_position))

	print("=== 着陆石岛 ===")
	var mesa = home.find_child("Prop_lf-mesa-plateau", true, false)
	print("  视觉节点: %s" % (str(mesa) if mesa != null else "未找到"))
	var col = home.find_child("PropCollision_lf-mesa-plateau", true, false)
	print("  碰撞节点: %s" % (str(col) if col != null else "未找到"))
	if col != null:
		for ch in col.get_children():
			if ch is CollisionShape3D:
				var sh = (ch as CollisionShape3D).shape
				print("    shape=%s  local=%s" % [
					sh.get_class() if sh != null else "null",
					str((ch as CollisionShape3D).position)])
	if mesa != null and mesa is MultiMeshInstance3D:
		var mmi := mesa as MultiMeshInstance3D
		print("  实例数=%d" % mmi.multimesh.instance_count)
		var xf: Transform3D = mmi.multimesh.get_instance_transform(0)
		var wpos: Vector3 = mmi.global_transform * xf.origin
		var up: Vector3 = (wpos - home.global_position).normalized()
		var dir: Vector3 = up
		print("  方山中心 world=%s  该处 terrain_height=%.1f" % [str(wpos), home.terrain_height(dir)])
		var q := PhysicsRayQueryParameters3D.create(wpos + up * 120.0, wpos - up * 120.0)
		var hit: Dictionary = home.get_world_3d().direct_space_state.intersect_ray(q)
		print("  方山中心向下射线: %s" % (("命中 " + str(hit.get("collider"))) if not hit.is_empty() else "无命中（没有碰撞）"))

	# 玩家脚下
	var ppos: Vector3 = game.player.global_position
	var pup: Vector3 = (ppos - home.global_position).normalized()
	var q2 := PhysicsRayQueryParameters3D.create(ppos + pup * 5.0, ppos - pup * 30.0)
	var hit2: Dictionary = home.get_world_3d().direct_space_state.intersect_ray(q2)
	var terrain: float = home.terrain_height(pup)
	var stand_alt: float = ppos.distance_to(home.global_position) - terrain
	print("=== 玩家脚下 ===")
	print("  地形高度=%.1f  玩家离地形=%.2f m" % [terrain, stand_alt])
	print("  向下射线: %s" % (("命中 " + str(hit2.get("collider"))) if not hit2.is_empty() else "无命中"))

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
