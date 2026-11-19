extends SceneTree
# 验证洞穴陈设是否摆进了洞穴内室。
#
#   godot --headless --path . --script res://tests/probe_cave_props.gd
#
# 检查：带洞穴的星球里，Cave_* 节点下有多少 CaveProp_* 件，
#      以及它们的 y 是否落在 floor_y(-13) ~ ceiling_y(-5.6) 之间（别飘到半空或陷进地板）。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _run() -> void:
	var save := "user://starward_caveprops.json"
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

	print("=== 洞穴陈设 ===")
	var cave_planets := 0
	var total := 0
	for p in game.planets:
		if not p.cave_enabled:
			continue
		cave_planets += 1
		# 找 Cave_<Kind> 节点（递归，因为它是 _prop_parent 的产物）
		var cave: Node = null
		for child in p.get_children():
			if String(child.name).begins_with("Cave_"):
				cave = child
				break
		if cave == null:
			print("  %-10s \u26a0 \u627e\u4e0d\u5230 Cave_ \u8282\u70b9" % p.planet_id)
			continue
		var names := {}
		var bad_y := 0
		var n := 0
		for c in cave.get_children():
			var nm := String(c.name)
			if not nm.begins_with("CaveProp_"):
				continue
			n += 1
			names[nm.replace("CaveProp_", "")] = true
			var y: float = (c as Node3D).position.y
			# 内室地板 -13、天花 -5.6，留 1.5 米容差（石柱会顶到天花）
			if y > -4.0 or y < -14.5:
				bad_y += 1
		total += n
		var keys: Array = names.keys()
		print("  %-10s %2d \u4ef6  y\u8d8a\u754c %d  %s" % [
			p.planet_id, n, bad_y, ", ".join(keys.slice(0, 5))])
	print("")
	print("  带洞穴星球 %d 颗，陈设合计 %d 件" % [cave_planets, total])
	print("  %s" % ("✓ 洞穴陈设已就位" if total >= cave_planets * 5 else "✗ 数量不足"))

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
