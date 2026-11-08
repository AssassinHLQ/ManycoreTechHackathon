extends SceneTree
# 一次性探针（只读）：垂直扫描枢纽周界，找「门平面之外、地板之上」的漏光口。
#   godot --path . --headless --script res://tests/probe_hub_gap.gd -- --vertical

var exclude_rids: Array[RID] = []


func _initialize() -> void:
	call_deferred("_run")


func _vert(space: PhysicsDirectSpaceState3D, station, label: String, from_l: Vector3, dist: float, dir_l := Vector3.UP) -> void:
	var q := PhysicsRayQueryParameters3D.create(station.to_global(from_l), station.to_global(from_l + dir_l * dist))
	q.collide_with_areas = false
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("%-46s → ★ 无阻挡（可穿出）" % label)
	else:
		var hp: Vector3 = station.to_local(hit["position"])
		print("%-46s → 命中 r=%.2f y=%.2f" % [label, Vector2(hp.x, hp.z).length(), hp.y])


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_gap_probe2.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	var station = game.station
	var space: PhysicsDirectSpaceState3D = station.get_world_3d().direct_space_state

	print("=== 垂直：从地面往上，角度 0..60° 之间每 5°，半径 27 / 28 / 29 / 29.5 ===")
	for deg in [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0]:
		var a := deg_to_rad(deg)
		var row := "%5.0f° " % deg
		for r: float in [27.0, 28.0, 29.0, 29.5]:
			var from := Vector3(cos(a) * r, -1.9, sin(a) * r)
			var q := PhysicsRayQueryParameters3D.create(station.to_global(from), station.to_global(from + Vector3.UP * 12.0))
			q.collision_mask = 1
			var hit: Dictionary = space.intersect_ray(q)
			row += "  r%.1f:%s" % [r, "★通" if hit.is_empty() else "%.1f" % (station.to_local(hit["position"]).y)]
		print(row)

	print("\n=== 扇区 0 门洞正前方：x 从 30 到 34，y 从 -1.9 向上 ===")
	for x: float in [30.2, 31.0, 32.0, 33.0, 34.0, 36.0]:
		var from := Vector3(x, -1.9, 0.0)
		var q := PhysicsRayQueryParameters3D.create(station.to_global(from), station.to_global(from + Vector3.UP * 14.0))
		q.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(q)
		print("x=%.1f → %s" % [x, "★通到外面" if hit.is_empty() else "命中 y=%.2f（天花板）" % station.to_local(hit["position"]).y])

	print("\n=== 门洞内侧正上方（门框后面）：x 29.6 / 30 / 30.4 ===")
	for x: float in [29.6, 30.0, 30.4]:
		for z: float in [-3.5, 0.0, 3.5]:
			var from := Vector3(x, -1.9, z)
			var q := PhysicsRayQueryParameters3D.create(station.to_global(from), station.to_global(from + Vector3.UP * 14.0))
			q.collision_mask = 1
			var hit: Dictionary = space.intersect_ray(q)
			print("x=%.1f z=%+.1f → %s" % [x, z, "★通到外面" if hit.is_empty() else "命中 y=%.2f" % station.to_local(hit["position"]).y])

	game.queue_free()
	await process_frame
	if FileAccess.file_exists("user://starward_gap_probe2.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_gap_probe2.json"))
	quit(0)
