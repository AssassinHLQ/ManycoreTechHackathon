extends SceneTree
# 批六收尾综合验证：生物 / 洞穴陈设 / 工坊模块 是否都进了游戏。
#
#   godot --headless --path . --script res://tests/probe_batch6_all.gd
#
# 只遍历各星球的 _prop_root 直接子节点与 Cave_* 节点，不递归 find_children。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _run() -> void:
	var save := "user://starward_b6all.json"
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
	await _frames(25)

	# ── 生物 ──
	print("=== 生物（含批六新增 7 种，共 12 种）===")
	var creat_kinds := {}
	var total_creatures := 0
	for p in game.planets:
		if p._prop_root == null:
			continue
		for i in range(p._prop_root.get_child_count()):
			var child: Node = p._prop_root.get_child(i)
			var nm := String(child.name)
			if not nm.contains("creature"):
				continue
			var pid := nm.replace("Prop_", "")
			creat_kinds[pid] = true
			var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
			total_creatures += mm.instance_count if mm != null else 0
	var kinds: Array = creat_kinds.keys()
	kinds.sort()
	print("  实际出现 %d 种，共 %d 只实例" % [kinds.size(), total_creatures])
	print("  %s" % ", ".join(kinds))

	# ── 植被（铺量层） ──
	print("")
	print("=== 植被（铺量层，批六新增 12 种）===")
	var plant_kinds := {}
	for p in game.planets:
		if p._prop_root == null:
			continue
		for i in range(p._prop_root.get_child_count()):
			var child: Node = p._prop_root.get_child(i)
			var nm := String(child.name)
			if not nm.contains("-lo") and not nm.contains("Prop_"):
				continue
			var pid := nm.replace("Prop_", "")
			for pid2 in ["fern-cluster", "vine-drape", "moss-mat", "spore-pod",
				"giant-fungus", "grass-plume", "reed-stand", "bulb-plant",
				"thorn-vine", "canopy-shrub", "lichen-rock", "seed-head"]:
				if pid == pid2:
					plant_kinds[pid2] = true
	var plant_list: Array = plant_kinds.keys()
	plant_list.sort()
	print("  实际出现 %d 种" % plant_list.size())
	print("  %s" % ", ".join(plant_list))

	# ── 洞穴陈设 ──
	print("")
	print("=== 洞穴陈设 ===")
	var cave_planets := 0
	var cave_total := 0
	for p in game.planets:
		if not p.cave_enabled:
			continue
		cave_planets += 1
		var cave: Node = null
		for c in p.get_children():
			if String(c.name).begins_with("Cave_"):
				cave = c
				break
		if cave == null:
			continue
		var n := 0
		for cc in cave.get_children():
			if String(cc.name).begins_with("CaveProp_"):
				n += 1
		cave_total += n
	print("  带洞穴星球 %d 颗，陈设合计 %d 件（每颗约 %d 件）" % [
		cave_planets, cave_total, cave_total / maxf(cave_planets, 1)])

	# ── 工坊模块 ──
	print("")
	print("=== 工坊模块 ===")
	var mod_kinds := {}
	for p in game.planets:
		if p._prop_root == null:
			continue
		for i in range(p._prop_root.get_child_count()):
			var child: Node = p._prop_root.get_child(i)
			var nm := String(child.name).replace("Prop_", "")
			if nm.begins_with("mod-"):
				mod_kinds[nm] = true
	var mod_list: Array = mod_kinds.keys()
	mod_list.sort()
	print("  实际出现 %d 种" % mod_list.size())
	print("  %s" % ", ".join(mod_list))

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
