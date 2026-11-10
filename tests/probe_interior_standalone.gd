extends SceneTree
# 不加载整个世界，单独构造「远景站 + 内部舱室」验证逻辑。
#
# 为什么这样做：完整世界要建 10 颗行星 + 归航站 + 两座十几万面的空间站，
# 并行会话多的时候会卡住十几分钟。而这里要验证的只是舱室本身：
# 能不能建、落点在不在舱内、出口对不对、走出舱外能不能判出来。
#
#   godot --headless --path . --script res://tests/probe_interior_standalone.gd

const Distant = preload("res://scripts/distant_station.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# 造一座假的远景站（不加载 glb，直接给参数）
	var st: Node3D = Distant.new()
	st.name = "TestStation"
	st.display_name = "测试站 · 环塔"
	st.disk_radius = 358.0
	st.half_extent = Vector3(358.0, 450.0, 358.0)
	st.dock_offset = Vector3(0.0, 477.0, 0.0)
	root.add_child(st)

	print("=== 远景站内部舱室（独立构造）===")
	var hall: Node3D = st.ensure_interior()
	if hall == null:
		print("  ✗ 舱室没建出来")
		quit(1)
		return

	var meshes := 0
	var tris := 0
	for node in hall.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		meshes += 1
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
	var bodies := 0
	var shapes := 0
	for node in hall.find_children("*", "StaticBody3D", true, false):
		bodies += 1
		for c in node.get_children():
			if c is CollisionShape3D:
				shapes += 1
	print("  几何：%d 个网格，约 %d 三角面" % [meshes, tris])
	print("  碰撞：%d 个 StaticBody，%d 个 shape" % [bodies, shapes])
	print("  舱半径 %.1f 米，舱高 %.1f 米" % [hall.hall_radius, hall.ceiling_height])

	var spawn: Transform3D = st.interior_spawn_transform()
	print("  落点 %s -> 在舱内：%s" % [
		str(spawn.origin),
		"是 ✓" if st.is_interior_position(spawn.origin) else "否 ✗"])

	var air: Vector3 = st.airlock_position()
	print("  出口 %s -> 落点距出口 %.1f 米" % [str(air), spawn.origin.distance_to(air)])

	var outside: Vector3 = hall.to_global(Vector3(hall.hall_radius * 2.0, 0.0, 0.0))
	print("  舱外 %s -> 判为舱内：%s（应为否）" % [
		str(outside), "是 ✗" if st.is_interior_position(outside) else "否 ✓"])

	print("\nDONE")
	quit(0)
