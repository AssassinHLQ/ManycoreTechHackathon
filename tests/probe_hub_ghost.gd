extends SceneTree
# 一次性探针（只读）：扫描枢纽周界外「门与门之间」的幽灵区，找可从枢纽掉出去的漏口。
#   godot --path . --headless --script res://tests/probe_hub_ghost.gd

const HUB_RADIUS := 30.0


func _initialize() -> void:
	call_deferred("_run")


func _has_floor(space: PhysicsDirectSpaceState3D, station: Node3D, p: Vector3) -> String:
	var from: Vector3 = station.to_global(Vector3(p.x, -1.5, p.z))
	var q := PhysicsRayQueryParameters3D.create(from, station.to_global(Vector3(p.x, -6.0, p.z)))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return "★无地板"
	var hp: Vector3 = station.to_local(hit["position"])
	return "地板 y=%.2f" % hp.y


func _has_wall_out(space: PhysicsDirectSpaceState3D, station: Node3D, p: Vector3, deg: float) -> String:
	var a := deg_to_rad(deg)
	var from: Vector3 = station.to_global(p)
	var q := PhysicsRayQueryParameters3D.create(from, station.to_global(p + Vector3(cos(a), 0.0, sin(a)) * 6.0))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return "★6m 内无墙"
	return "墙 r=%.2f" % Vector2(station.to_local(hit["position"]).x, station.to_local(hit["position"]).z).length()


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_ghost_probe.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	var station = game.station
	var space: PhysicsDirectSpaceState3D = station.get_world_3d().direct_space_state

	print("=== A. 扇区 1 门洞中线（角度 60°）：往外每 0.5m 的 y 高度能否站住 ===")
	print("%7s %-14s %-14s" % ["x", "脚下", "外侧墙"])
	for x: float in [30.5, 31.5, 32.5, 33.0, 33.4, 34.0, 35.0, 36.0, 38.0, 42.0, 46.0]:
		var a := deg_to_rad(60.0)
		var p := Vector3(cos(a) * x, -1.2, sin(a) * x)
		print("%7.1f %-14s %-14s" % [x, _has_floor(space, station, p), _has_wall_out(space, station, p, 60.0)])

	print("\n=== B. 门与门之间（角度 30°）：r 从 20 到 50 ===")
	print("%7s %-14s %-14s" % ["r", "脚下", "外侧墙"])
	for r: float in [20.0, 24.0, 26.0, 27.5, 28.0, 29.0, 30.0, 31.0, 32.0, 33.0, 33.8, 34.0, 35.0, 38.0, 42.0, 46.0, 50.0]:
		var a := deg_to_rad(30.0)
		var p := Vector3(cos(a) * r, -1.2, sin(a) * r)
		print("%7.1f %-14s %-14s" % [r, _has_floor(space, station, p), _has_wall_out(space, station, p, 30.0)])

	print("\n=== C. 门洞正前方能否走（r 30~34, 角度 60°）===")
	for r: float in [29.5, 30.5, 31.5, 32.5, 33.5, 34.5]:
		var a := deg_to_rad(60.0)
		var p := Vector3(cos(a) * r, -1.2, sin(a) * r)
		var q := PhysicsRayQueryParameters3D.create(
			station.to_global(Vector3(p.x, -1.2, p.z)),
			station.to_global(Vector3(p.x, -6.0, p.z)))
		q.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(q)
		print("r=%.1f 脚下 %s" % [r, "★无地板（会掉出去）" if hit.is_empty() else "y=%.2f" % station.to_local(hit["position"]).y])

	game.queue_free()
	await process_frame
	if FileAccess.file_exists("user://starward_ghost_probe.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_ghost_probe.json"))
	quit(0)
