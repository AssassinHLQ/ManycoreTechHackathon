extends SceneTree
# 探针：量卡冈图雅引力的实际强度分布，找出「太强」在哪。
#
# 用户反馈：「黑洞太强了怎么办」。
# 本喵把各距离上的径向引力、切向阻力、推力余量都列出来，
# 看哪些数字明显失衡。
#
#   godot --headless --path . --script res://tests/probe_bh_strength.gd

var game
var ship


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_bhstrength.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(10):
		await process_frame
	ship = game.ship
	if ship == null or game.gargantua == null:
		print("没建出来")
		quit(1)
		return

	var hole: Vector3 = game.gargantua.global_position
	print("=== 卡冈图雅引力 / 阻力强度分布 ===")
	print("  推力 %d / 喷气 %d / 制动 %d（BH_FORCE_BRAKE_DECEL=%.0f）" % [
		ship.SHIP_THRUST, ship.SHIP_BOOST_THRUST, ship.SHIP_BRAKE_DECEL,
		ship.BH_FORCE_BRAKE_DECEL])
	print("  阻力：BH_DRAG_HALF=%.0f BH_DRAG_MAX=%.0f" % [
		ship.BH_DRAG_HALF, ship.BH_DRAG_MAX])
	print("  强制捕获圈 BH_FORCE_CAPTURE = %.0f" % ship.BH_FORCE_CAPTURE)
	print("")
	print("  距离    径向引力   阻力(切向)  推力余量   判定")
	for d in [7200.0, 6000.0, 5000.0, 4000.0, 3000.0, 2400.0, 2000.0,
			1500.0, 1200.0, 900.0, 600.0, 300.0, 200.0, 120.0]:
		ship.global_position = hole + Vector3(0.0, d, 0.0)
		ship.velocity = Vector3.ZERO
		ship.bh_orbit_age = 0.0
		ship.bh_captured = false
		ship._black_hole_pull(0.001)
		var radial: float = ship.bh_radial_accel
		# 阻力公式：a = MAX * v² / (v² + HALF²)，取 v = 推力 72（典型巡航）
		var v: float = ship.SHIP_THRUST
		var drag: float = ship.BH_DRAG_MAX * v * v / (v * v + ship.BH_DRAG_HALF * ship.BH_DRAG_HALF)
		var margin: float = ship.SHIP_THRUST - radial
		var verdict := "自由"
		if d <= ship.BH_FORCE_CAPTURE:
			verdict = "★强制捕获"
		elif margin <= 0.0:
			verdict = "推不动"
		elif margin < ship.SHIP_THRUST * 0.4:
			verdict = "吃力"
		elif margin < ship.SHIP_THRUST:
			verdict = "勉强"
		print("  %6.0f   %8.1f   %8.1f    %7.1f   %s" % [
			d, radial, drag, margin, verdict])

	print("")
	print("=== 强制捕获圈有多大 ===")
	var reach: float = ship.BH_FORCE_CAPTURE
	print("  捕获圈半径 %.0f 米 = %.1f 公里" % [reach, reach / 1000.0])
	print("  视界半径 %.0f 米 = %.2f 公里" % [ship.BH_HORIZON, ship.BH_HORIZON / 1000.0])
	print("  捕获圈是视界的 %.0f 倍" % (reach / ship.BH_HORIZON))
	print("  黑洞距母星（原点）%.0f 米" % hole.length())
	print("  站在原点距黑洞 %.0f 米 —— 在捕获圈外 %.0f 米" % [
		hole.length(), hole.length() - reach])
	print("  捕获圈是否覆盖了归航站？归航站在 (4300, 1180, -1500)")
	var station_pos := Vector3(4300.0, 1180.0, -1500.0)
	print("    归航站距黑洞 %.0f 米 -> %s" % [
		station_pos.distance_to(hole),
		"★在捕获圈内！" if station_pos.distance_to(hole) <= reach else "在圈外"])
	quit(0)
