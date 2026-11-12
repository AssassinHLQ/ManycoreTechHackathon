extends SceneTree
# 验证 A/B/C：采集次数与冷却、遗迹图鉴进度、信标奖励。
#
#   godot --headless --path . --script res://tests/probe_planet_interact.gd
#
# A 次语义（旧探针已过时）：
#   · 晶簇 3 次充能，每采一次 charges -1，采空后不再生效
#   · 采空后进冷却（90 秒），冷却结束自动长回来
# B：遗迹每扫一个 relic_progress() 的 done +1，扫满给奖励
# C：信标点亮给一次补给

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
	var counts := {"crystal": 0, "cargo": 0, "vent": 0, "relic": 0, "beacon": 0}
	for sp in p.interactive_spots:
		var k := String(sp["kind"])
		counts[k] = int(counts.get(k, 0)) + 1
	print("=== %s 可交互点 ===" % p.planet_id)
	print("  晶簇 %d 货舱 %d 喷口 %d 遗迹 %d 信标 %d （合计 %d）" % [
		counts["crystal"], counts["cargo"], counts["vent"], counts["relic"],
		counts["beacon"], p.interactive_spots.size()])
	print("")

	# ── A：晶簇 3 次充能，逐次递减，采空后失效 ──
	var ci := _find_spot(p, "crystal")
	if ci < 0:
		print("  ⚠ 无晶簇点，跳过 A 测试")
	else:
		await _stand_at(p, ci)
		game.player.fuel = 0.0
		print("  A 晶簇（应 3 次充能）：")
		for round_i in range(4):
			var before_f: float = game.player.fuel
			var before_c: int = int((p.interactive_spots[ci] as Dictionary)["charges"])
			game._interact()
			var after_f: float = game.player.fuel
			var after_c: int = int((p.interactive_spots[ci] as Dictionary)["charges"])
			print("    第 %d 次：燃料 %.0f → %.0f   次数 %d → %d" % [
				round_i + 1, before_f, after_f, before_c, after_c])
		var spent: bool = int((p.interactive_spots[ci] as Dictionary)["charges"]) == 0
		print("    采空后 charges=0  %s" % ("✓" if spent else "✗"))

	# ── A2：冷却再生（把 ready_at 提前，模拟 90 秒过去）──
	if ci >= 0:
		(p.interactive_spots[ci] as Dictionary)["ready_at"] = 0.0
		await _frames(4)
		var regen: int = int((p.interactive_spots[ci] as Dictionary)["charges"])
		print("  A2 冷却到期后自动再生：charges=%d  %s" % [
			regen, "✓" if regen > 0 else "✗"])

	# ── B：遗迹图鉴进度 ──
	var ri := _find_spot(p, "relic")
	if ri < 0:
		print("  ⚠ 无遗迹点，跳过 B 测试")
	else:
		var prog0: Array = p.relic_progress()
		await _stand_at(p, ri)
		game._interact()
		var prog1: Array = p.relic_progress()
		print("  B 遗迹扫描：进度 %d/%d → %d/%d  %s" % [
			int(prog0[0]), int(prog0[1]), int(prog1[0]), int(prog1[1]),
			"✓" if int(prog1[0]) > int(prog0[0]) else "✗"])

	# ── C：信标点亮 ──
	var bi := _find_spot(p, "beacon")
	if bi < 0:
		print("  ⚠ 无信标点，跳过 C 测试")
	else:
		await _stand_at(p, bi)
		game.player.fuel = 10.0
		game.player.oxygen = 10.0
		game._interact()
		print("  C 信标点亮：燃料 → %.0f  氧气 → %.0f  %s" % [
			game.player.fuel, game.player.oxygen,
			"✓" if game.player.fuel > 10.0 else "✗"])

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
