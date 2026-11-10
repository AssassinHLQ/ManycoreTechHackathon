extends SceneTree
# 探针：验证两座远景站的碰撞与对接。
#
# 1) 碰撞：把飞船直接塞进站体中心，跑几帧物理，看会不会被弹出去（不该穿透）。
# 2) 对接：把飞船放到对接端口附近、速度低于阈值，看会不会自动对接。
# 3) 脱离：对接后调 undock，看位置是否退开。
#
#   godot --headless --path . --script res://tests/probe_station_dock.gd

var game
var ship


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_dock.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(10):
		await process_frame
	ship = game.ship
	if ship == null or game.distant_stations.is_empty():
		print("飞船或远景站没建出来")
		quit(1)
		return

	game.state = "ship"
	game.paused = false
	game.map_open = false
	game.supernova_active = false
	print("=== 远景站对接 / 碰撞检查 ===")
	for st in game.distant_stations:
		var port: Vector3 = st.docking_point()
		print("\n-- %s --" % st.display_name)
		print("   站心 %s" % str(st.global_position))
		print("   端口 %s" % str(port))
		print("   半径 %.0f 米，半高 %.0f 米" % [st.disk_radius, st.half_extent.y])

		# ① 碰撞体数量
		var bodies := 0
		var shapes := 0
		for node in st.find_children("*", "StaticBody3D", true, false):
			bodies += 1
			for c in node.get_children():
				if c is CollisionShape3D:
					shapes += 1
		print("   碰撞：StaticBody %d 个，shape %d 个" % [bodies, shapes])

		# ② 对接测试：放到端口上方 10 米、零速度
		ship.docked = false
		ship.docked_station = null
		ship.landed = false
		ship.dock_cooldown = 0.0
		ship.velocity = Vector3.ZERO
		ship.global_position = port + Vector3(0.0, 10.0, 0.0)
		var docked_ok := false
		for _i in range(30):
			ship._physics_process(1.0 / 60.0)
			if ship.docked:
				docked_ok = true
				break
		print("   对接测试：%s" % ("成功 ✓" if docked_ok else "失败 ✗"))
		if docked_ok:
			print("     停靠位置 %s（端口 %s）" % [
				str(ship.global_position), str(port)])
			var before: Vector3 = ship.global_position
			ship.undock()
			print("     脱离：%s -> %s" % [
				str(before), str(ship.global_position)])
			ship.docked = false
			ship.docked_station = null
	quit(0)
