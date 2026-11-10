extends SceneTree
# 探针：只打印「停靠位 / 站体 / 船」三者的实际坐标关系，不渲染。
# 用来判断对接点是不是浮在站外很远的地方。

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_dockpos.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(10):
		await process_frame

	print("=== 停靠位几何关系 ===")
	for st in game.distant_stations:
		var center: Vector3 = st.global_position
		var port: Vector3 = st.docking_point()
		var ship_pos: Vector3 = st.dock_ship_position()
		# 量站体的真实世界包围盒（含所有网格）
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for node in st.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var box: AABB = mi.get_aabb()
			for k in range(8):
				var corner := box.position + Vector3(
					box.size.x if (k & 1) else 0.0,
					box.size.y if (k & 2) else 0.0,
					box.size.z if (k & 4) else 0.0)
				var p: Vector3 = mi.global_transform * corner
				lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
				hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		print("\n-- %s --" % st.display_name)
		print("   站心      %s" % str(center))
		print("   世界包围盒 底 %s / 顶 %s" % [str(lo), str(hi)])
		print("   盒子尺寸   %s" % str(hi - lo))
		print("   对接端口   %s  （相对站心 %s）" % [str(port), str(port - center)])
		print("   停泊位     %s  （相对站心 %s）" % [str(ship_pos), str(ship_pos - center)])
		print("   端口是否在盒子上方：%s" % str(port.y >= hi.y - 1.0))
	quit(0)
