extends SceneTree
# 验证生物是否真的进了星球（轻量：只遍历 _prop_root 的直接子节点，不递归 find_children）。
#
#   godot --headless --path . --script res://tests/probe_creatures.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _run() -> void:
	var save := "user://starward_creat.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(20)
	for i in range(1500):
		await process_frame
		if game.planets.size() >= 20:
			break
	await _frames(20)

	print("=== 外星生物分布 ===")
	var total := 0
	var planets_with := 0
	for p in game.planets:
		if p._prop_root == null:
			continue
		var found: Array[String] = []
		var n: int = p._prop_root.get_child_count()
		for i in range(n):
			var child: Node = p._prop_root.get_child(i)
			var nm := String(child.name)
			if not nm.contains("creature"):
				continue
			var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
			var cnt: int = mm.instance_count if mm != null else 0
			total += cnt
			found.append("%s x%d" % [nm.replace("Prop_", ""), cnt])
		if not found.is_empty():
			planets_with += 1
			print("  %-10s %s" % [p.planet_id, ", ".join(found)])
	print("")
	print("  有生物的星球 %d / 20，生物实例合计 %d" % [planets_with, total])
	print("  %s" % ("✓ 生物已分布到星球上" if planets_with >= 15 else "✗ 分布不足"))

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
