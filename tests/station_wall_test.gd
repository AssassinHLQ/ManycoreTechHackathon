extends SceneTree

const FLOOR_TOP := -2.0
const CEILING_Y := 2.8

var failures := 0
var rays := 0
var root3d: Node3D
var space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	call_deferred("_run")


func _ray(from: Vector3, dir: Vector3, distance := 4.0) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * distance, 1)
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()


func _audit(origin: Vector3, direction: Vector3, label: String) -> void:
	rays += 1
	var from := root3d.global_transform * origin
	var dir := (root3d.global_transform.basis * direction).normalized()
	if not _ray(from, dir):
		failures += 1
		print("HOLE  ", label, "  local=", origin, "  dir=", direction)


func _audit_room(x: float, side: float, name: String) -> void:
	var zc := side * 7.05
	for sx: float in [-3.5, 0.0, 3.5]:
		_audit(Vector3(x + sx, -0.5, zc + side * 2.75), Vector3(0.0, 0.0, side), "%s window x%.1f" % [name, sx])
	for sz: float in [-2.2, 0.0, 2.2]:
		for edge: float in [-1.0, 1.0]:
			_audit(Vector3(x + edge * 4.25, -0.5, zc + side * sz), Vector3(edge, 0.0, 0.0), "%s side %s z%.1f" % [name, edge, sz])
	for sx: float in [-3.5, 0.0, 3.5]:
		_audit(Vector3(x + sx, FLOOR_TOP + 0.15, zc), Vector3.DOWN, "%s floor x%.1f" % [name, sx])
		_audit(Vector3(x + sx, CEILING_Y - 0.15, zc), Vector3.UP, "%s ceiling x%.1f" % [name, sx])


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_hole_probe.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	game.ship.dock_station(game.station)
	game.enter_station()
	for i in range(4):
		await physics_frame
	var station = game.station
	if not game.in_station:
		# enter_station() 需要 ship.docked；刚 start_game 就手动对接时它会被自动脱离覆盖掉。
		# 这条测试审计的是走廊几何，所以这里把状态钉死、把人放进走廊 A，
		# 好让走廊 A 的碰撞处于启用状态（看不见的走廊会按设计退出物理世界）。
		game.in_station = true
		game.state = "walk"
		if game.player.get_parent() != station:
			game.player.reparent(station, false)
		game.player.global_position = station.to_global(Vector3(60.0, -1.95, 0.0))
		game.player.velocity = Vector3.ZERO
		for i in range(3):
			await process_frame
	for i in range(1, station.corridor_roots.size()):
		var body: Node = station.corridor_roots[i].find_child("StationCollision", true, false)
		if body is StaticBody3D:
			body.collision_layer = 0
	root3d = station.corridor_roots[0]
	space = station.get_world_3d().direct_space_state
	var centers := [-84.0, -56.0, -28.0, 28.0, 56.0, 84.0]
	for x in centers:
		_audit_room(x, -1.0, "roomL%+.0f" % x)
		_audit_room(x, 1.0, "roomR%+.0f" % x)
	# Hall outer windows and side walls.
	for side: float in [-1.0, 1.0]:
		for sx: float in [-10.0, -5.0, 0.0, 5.0, 10.0]:
			_audit(Vector3(sx, -0.5, side * 9.8), Vector3(0.0, 0.0, side), "hall window x%.0f" % sx)
		for sz: float in [-7.0, -4.8, 4.8, 7.0]:
			_audit(Vector3(side * 12.5, -0.5, sz), Vector3(side, 0.0, 0.0), "hall side z%.1f" % sz)
		for sx: float in [-10.0, 0.0, 10.0]:
			_audit(Vector3(sx, FLOOR_TOP + 0.15, side * 8.0), Vector3.DOWN, "hall floor x%.0f" % sx)
	# Bridge outer viewport and side walls.
	for sz: float in [-5.0, -2.5, 0.0, 2.5, 5.0]:
		for sy: float in [-1.6, 0.6, 2.2]:
			_audit(Vector3(-119.6, sy, sz), Vector3(-1.0, 0.0, 0.0), "bridge viewport z%.1f y%.1f" % [sz, sy])
	for side: float in [-1.0, 1.0]:
		for sx: float in [-117.0, -112.0, -107.0]:
			for sy: float in [-1.6, 0.0, 3.5, 4.8]:
				_audit(Vector3(sx, sy, side * 6.6), Vector3(0.0, 0.0, side), "bridge side x%.0f y%.1f" % [sx, sy])
	for sx: float in [-118.0, -112.0, -106.0]:
		for sz: float in [-5.0, 0.0, 5.0]:
			_audit(Vector3(sx, FLOOR_TOP + 0.15, sz), Vector3.DOWN, "bridge floor x%.0f z%.0f" % [sx, sz])
			_audit(Vector3(sx, 5.0, sz), Vector3.UP, "bridge ceiling x%.0f z%.0f" % [sx, sz])
	# Bridge bulkhead at x=-104: side panels and header must be solid.
	for side: float in [-1.0, 1.0]:
		for sy: float in [-1.6, 0.0, 2.0, 4.5]:
			_audit(Vector3(-105.5, sy, side * 5.3), Vector3(1.0, 0.0, 0.0), "bridge bulkhead side y%.1f" % sy)
	for sz: float in [-2.5, 0.0, 2.5]:
		for sy: float in [3.3, 4.5]:
			_audit(Vector3(-105.5, sy, sz), Vector3(1.0, 0.0, 0.0), "bridge door header z%.1f y%.1f" % [sz, sy])
	print("STATION WALL TEST COMPLETE: ", rays, " rays, ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists("user://starward_hole_probe.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_hole_probe.json"))
	quit(0 if failures == 0 else 1)
