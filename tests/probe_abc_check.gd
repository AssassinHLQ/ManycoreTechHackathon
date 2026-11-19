extends SceneTree
# A/B/C 的 headless 结构性验证（不开窗口）。
#
#   godot --headless --path . --script res://tests/probe_abc_check.gd
#
# A：构图模式装饰组是否生效（检查每球是否有 PATTERN_PROPS 对应的道具，且位置成组）
# B：靠近交互物时 get_prompt() 是否给出「E ...」提示
# C：远处星球的道具容器是否被整组 hidden（预期：玩家所在 1 颗可见，其余 19 颗隐藏）

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _prop_count(p) -> int:
	var n := 0
	for node in p.find_children("Prop_*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if mm != null:
			n += mm.instance_count
	return n


func _run() -> void:
	var save := "user://starward_abc.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(20)
	for i in range(1200):
		await process_frame
		if game.planets.size() >= 20:
			break
	await _frames(20)

	# ── A：构图组 ──
	print("=== A 构图模式装饰组 ===")
	var home = game.home
	var pat: Array = home.PATTERN_PROPS.get(home.kind, [])
	print("  %s 配置了 %d 组构图：" % [home.planet_id, pat.size()])
	for e in pat:
		var n := 0
		for node in home.find_children("Prop_%s" % String(e[0]), true, false):
			var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
			if mm != null:
				n += mm.instance_count
		print("    %-18s 目标 %d 个，实际 %d 个  %s" % [
			String(e[0]), int(e[1]), n,
			"✓" if n >= int(e[1]) else "（含其他来源）"])

	# ── C：远处星球道具是否整组隐藏 ──
	print("")
	print("=== C 远处星球道具整组隐藏 ===")
	var hidden := 0
	var shown := 0
	for p in game.planets:
		if p._prop_root == null:
			continue
		if p._prop_root.visible:
			shown += 1
		else:
			hidden += 1
	print("  可见星球 %d 个，隐藏 %d 个（共 %d）" % [shown, hidden, game.planets.size()])
	print("  说明：玩家在母星附近，预期可见 1 个（母星），其余隐藏  %s" % (
		"✓" if hidden >= 15 and shown >= 1 else "✗ 异常"))

	# ── B：靠近交互物的 HUD 提示 ──
	print("")
	print("=== B 靠近交互物的提示 ===")
	var p = home
	var found := -1
	for i in range(p.interactive_spots.size()):
		if String((p.interactive_spots[i] as Dictionary)["kind"]) == "crystal" \
				and not bool((p.interactive_spots[i] as Dictionary)["used"]):
			found = i
			break
	if found < 0:
		print("  ⚠ 没有晶簇点，跳过")
	else:
		var sp: Dictionary = p.interactive_spots[found]
		var dir: Vector3 = sp["dir"]
		var pos: Vector3 = p.global_position + p.surface_position(dir, 1.5)
		game.player.reparent(p, false)
		game.player.global_transform = Transform3D(
			Basis(Quaternion(Vector3.UP, dir)), pos)
		await _frames(20)
		var hint: String = game.get_prompt()
		print("  回到晶簇旁 get_prompt() = 「%s」" % hint)
		print("  %s" % ("✓ 提示里含 E 与采集" if hint.contains("E") and hint.contains("采集")
			else "✗ 提示不对"))
		# 走远之后提示应恢复成通用键位
		var away: Vector3 = p.global_position + p.surface_position(
			dir.rotated(dir.cross(Vector3.UP).normalized(), 0.05), 1.5)
		game.player.global_position = away
		await _frames(6)
		print("  走远后 get_prompt() = 「%s」" % game.get_prompt())

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
