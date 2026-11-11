extends SceneTree
# 列出机身所有 mesh 的 Z/X/Y 范围，找出超出 ship_model_* 的那个。
# 排除尾焰（engine_plumes）。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _run() -> void:
	var save_path := "user://starward_zr2.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(25)

	var ship = game.ship
	print("ship_model: span=%.2f height=%.2f length=%.2f" % [
		ship.ship_model_span, ship.ship_model_height, ship.ship_model_length])
	print("")
	print("%-30s %8s %8s %8s %8s" % ["mesh", "minZ", "maxZ", "minY", "maxY"])

	var rows: Array = []
	for node in ship.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var tag := "[PLUME]" if ship.engine_plumes.has(mi) else ""
		var xf: Transform3D = ship.global_transform.affine_inverse() * mi.global_transform
		var ab: AABB = xf * mi.get_aabb()
		rows.append([mi.name + tag, ab.position.z, ab.position.z + ab.size.z,
			ab.position.y, ab.position.y + ab.size.y])

	rows.sort_custom(func(a, b): return absf(a[2]) > absf(b[2]))
	for r in rows:
		print("%-30s %8.2f %8.2f %8.2f %8.2f" % [
			str(r[0]).substr(0, 28), r[1], r[2], r[3], r[4]])

	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
