extends SceneTree
# 一次性探针：量化「六扇门旁边能跳出去」的缺口，和「走廊里挡路的物件」。
#   godot --path . --headless --script res://tests/probe_hub_gap.gd
#
# 只读：不改动场景，只沿径向打射线、并扫描墙体附近的碰撞体形状。

const HUB_RADIUS := 30.0


func _initialize() -> void:
	call_deferred("_run")


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collision_mask = 1
	if not exclude.is_empty():
		q.exclude = exclude
	return space.intersect_ray(q)


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_gap_probe.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	var station = game.station
	var space: PhysicsDirectSpaceState3D = station.get_world_3d().direct_space_state

	print("=== 1. 扇区 0 与扇区 1 之间（门中心角 0° 与 60°）的径向射线 ===")
	print("%8s %6s %6s   %s" % ["角度", "y", "半径", "结果"])
	for deg in [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0]:
		var a := deg_to_rad(deg)
		for y in [-1.5, 0.0, 1.5, 3.0, 4.5, 6.0]:
			var from := Vector3(cos(a) * 26.0, y, sin(a) * 26.0)
			var to := Vector3(cos(a) * 34.0, y, sin(a) * 34.0)
			var hit := _ray(space, station.to_global(from), station.to_global(to))
			var result := "★通到外面"
			if not hit.is_empty():
				var hp: Vector3 = station.to_local(hit["position"])
				result = "命中 r=%.2f" % Vector2(hp.x, hp.z).length()
			print("%8.1f %6.1f %6s   %s" % [deg, y, "26→34", result])

	print("\n=== 2. 半径 26~33 内的碰撞盒（按到门平面附近筛选）===")
	print("%8s %8s %8s %8s   %s" % ["x", "y", "z", "r", "尺寸"])
	var body: Node = station.hub_root.find_child("HubCollision", true, false)
	var rows: Array = []
	if body != null:
		for node in body.get_children():
			if not (node is CollisionShape3D):
				continue
			var shape: Shape3D = (node as CollisionShape3D).shape
			if not (shape is BoxShape3D):
				continue
			var size: Vector3 = (shape as BoxShape3D).size
			var local: Vector3 = station.to_local((node as CollisionShape3D).global_position)
			var r := Vector2(local.x, local.z).length()
			if r < 25.0 or r > 35.0:
				continue
			rows.append({"p": local, "r": r, "s": size})
	rows.sort_custom(func(a, b): return a["r"] < b["r"])
	for d in rows:
		print("%8.2f %8.2f %8.2f %8.2f   %s" % [d["p"].x, d["p"].y, d["p"].z, d["r"], str(d["s"])])

	game.queue_free()
	await process_frame
	if FileAccess.file_exists("user://starward_gap_probe.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_gap_probe.json"))
	quit(0)
