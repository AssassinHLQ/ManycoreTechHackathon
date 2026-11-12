extends SceneTree
# 验证星球互动物品：E 键采集/拆解/扫描是否生效。
#
#   godot --headless --path . --script res://tests/probe_planet_interact.gd
#
# 对每类交互找一个实例，把玩家放到跟前，调用 game._interact()，
# 检查资源变化 + 该交互点是否被标记已用。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _find_spot(p, kind: String) -> int:
	for i in range(p.interactive_spots.size()):
		var sp: Dictionary = p.interactive_spots[i]
		if String(sp["kind"]) == kind and not bool(sp["used"]):
			return i
	return -1


func _stand_at(p, index: int) -> void:
	var sp: Dictionary = p.interactive_spots[index]
	var dir: Vector3 = sp["dir"]
	# 站在交互物正前方一点点（地面高度 + 物体半高）
	var pos: Vector3 = p.global_position + p.surface_position(dir, 1.5)
	game.player.reparent(p, false)
	game.player.global_transform = Transform3D(
		Basis(Quaternion(Vector3.UP, dir)), pos)
	game.player.velocity = Vector3.ZERO
	await _frames(20)


func _run() -> void:
	var save := "user://starward_interact.json"
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
	await _frames(10)

	var p = game.home
	print("=== %s 的可交互点 ===" % p.planet_id)
	var counts := {"crystal": 0, "cargo": 0, "vent": 0, "relic": 0}
	for sp in p.interactive_spots:
		var k := String(sp["kind"])
		counts[k] = int(counts.get(k, 0)) + 1
	print("  晶簇 %d  货舱 %d  喷口 %d  遗迹 %d  （合计 %d）" % [
		counts["crystal"], counts["cargo"], counts["vent"], counts["relic"],
		p.interactive_spots.size()])
	print("")

	# ① 晶簇：燃料 50 → 应 +35
	var ci := _find_spot(p, "crystal")
	if ci < 0:
		print("  \u26a0 没有晶簇点，跳过采集测试")
	else:
		await _stand_at(p, ci)
		game.player.fuel = 50.0
		var before: float = game.player.fuel
		game._interact()
		print("  晶簇采集：燃料 %.0f → %.0f  已标记=%s  %s" % [
			before, game.player.fuel,
			str(bool((p.interactive_spots[ci] as Dictionary)["used"])),
			"\u2713" if game.player.fuel > before else "\u2717"])

	# ② 货舱：氧气 50 → 应 +30
	var ki := _find_spot(p, "cargo")
	if ki < 0:
		print("  \u26a0 没有货舱点，跳过拆解测试")
	else:
		await _stand_at(p, ki)
		game.player.oxygen = 50.0
		var ob: float = game.player.oxygen
		game._interact()
		print("  货舱拆解：氧气 %.0f → %.0f  %s" % [
			ob, game.player.oxygen,
			"\u2713" if game.player.oxygen > ob else "\u2717"])

	# ③ 遗迹：应写进 relic_seen
	var ri := _find_spot(p, "relic")
	if ri < 0:
		print("  \u26a0 没有遗迹点，跳过扫描测试")
	else:
		await _stand_at(p, ri)
		var seen_before: int = game.relic_seen.size()
		game._interact()
		print("  遗迹扫描：记录 %d → %d  %s" % [
			seen_before, game.relic_seen.size(),
			"\u2713" if game.relic_seen.size() > seen_before else "\u2717"])

	# ④ 同一处再按一次 E：不应该重复生效
	if ci >= 0:
		await _stand_at(p, ci)
		var f2: float = game.player.fuel
		game._interact()
		print("  重复采集：燃料 %.0f → %.0f  %s" % [
			f2, game.player.fuel,
			"\u2713（没有再涨）" if is_equal_approx(f2, game.player.fuel) else "\u2717 重复生效了"])

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
