extends SceneTree
# 探针：直接列出枢纽里所有 CollisionShape3D 的**世界位置**，看墙到底在哪。
#
#   godot --headless --path . --script res://tests/probe_hub_shapes.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_hubshapes.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(10):
		await process_frame

	var st: Node3D = game.station
	var hub: Node = st.get_node_or_null("StationHub")
	hub.visible = true

	print("=== 枢纽里所有碰撞体（世界坐标）===")
	var count := 0
	for node in hub.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		var wp: Vector3 = cs.global_position
		var local_to_hub: Vector3 = hub.to_local(wp)
		var r: float = Vector2(local_to_hub.x, local_to_hub.z).length()
		var shape_desc := "?"
		if cs.shape is BoxShape3D:
			shape_desc = "Box %s" % str((cs.shape as BoxShape3D).size)
		elif cs.shape is CylinderShape3D:
			shape_desc = "Cyl %.1f h%.1f" % [(cs.shape as CylinderShape3D).radius, (cs.shape as CylinderShape3D).height]
		# 只打印半径 25~35 之间的（间隔墙应该在半径 30）
		if r > 25.0 and r < 35.0:
			count += 1
			print("  %-28s  半径 %5.2f  y=%6.2f  %s" % [
				cs.get_parent().name, r, local_to_hub.y, shape_desc])
	print("  半径 25~35 之间的碰撞体：%d 个" % count)
	quit(0)
