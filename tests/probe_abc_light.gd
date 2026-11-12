extends SceneTree
# A/B/C 轻量验证（不遍历节点树，避免上一版卡在 find_children）。
#
#   godot --headless --path . --script res://tests/probe_abc_light.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _run() -> void:
	var save := "user://starward_abclight.json"
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
	await _frames(30)

	print("=== 道具容器与剔除（C）===")
	var shown := 0
	var hidden := 0
	var total_nodes := 0
	for p in game.planets:
		if p._prop_root == null:
			continue
		total_nodes += p._prop_root.get_child_count()
		if p._prop_root.visible:
			shown += 1
		else:
			hidden += 1
	print("  道具容器节点总数 %d（20 球合计）" % total_nodes)
	print("  可见星球 %d / 隐藏星球 %d" % [shown, hidden])
	print("  %s" % ("✓ 远处星球已整组隐藏" if hidden >= 15 else "✗ 剔除没生效"))

	print("")
	print("=== 构图组与交互提示（A/B）===")
	var home = game.home
	print("  %s 的构图组数量 = %d" % [home.planet_id, home.PATTERN_PROPS.get(home.kind, []).size()])
	print("  交互点数量 = %d（含互动种子）" % home.interactive_spots.size())
	var idx := -1
	for i in range(home.interactive_spots.size()):
		var sp: Dictionary = home.interactive_spots[i]
		if String(sp["kind"]) == "crystal" and not bool(sp["used"]):
			idx = i
			break
	if idx < 0:
		print("  ⚠ 无晶簇点，跳过 B")
	else:
		var sp2: Dictionary = home.interactive_spots[idx]
		var dir: Vector3 = sp2["dir"]
		var pos: Vector3 = home.global_position + home.surface_position(dir, 1.5)
		game.player.reparent(home, false)
		game.player.global_transform = Transform3D(
			Basis(Quaternion(Vector3.UP, dir)), pos)
		await _frames(20)
		var hint: String = game.get_prompt()
		print("  贴近晶簇时提示 = 「%s」" % hint)
		print("  %s" % ("✓ 提示含 E 与采集" if hint.contains("E") and hint.contains("采集")
			else "✗ 提示不对"))

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
