extends SceneTree
# 探针：量卡冈图雅引力的实际数字表。
#
# 回答两个问题：
#   1) HUD 那个「引力场 · 卡冈图雅 N%」里的 N 到底代表什么；
#   2) 在各个距离上，推力（72）/ 喷气（150）/ 制动（260）到底能不能逃出去。
#
#   godot --headless --path . --script res://tests/probe_bh_gravity.gd

var game
var ship


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_bh_gravity.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	ship = game.ship
	if ship == null or game.gargantua == null:
		print("飞船或卡冈图雅没建出来")
		quit(1)
		return

	var hole: Vector3 = game.gargantua.global_position
	print("=== 卡冈图雅引力场实际数字 ===")
	print("  视界 BH_HORIZON      = %.0f" % ship.BH_HORIZON)
	print("  牵引范围 BH_PULL_RANGE = %.0f" % ship.BH_PULL_RANGE)
	print("  远端加速度 FAR        = %.2f" % ship.BH_ACCEL_FAR)
	print("  近端加速度 NEAR       = %.2f" % ship.BH_ACCEL_NEAR)
	print("  逃逸层 BOOST          = %.2f（从 closeness %.2f 起生效）" % [
		ship.BH_ESCAPE_BOOST, ship.BH_ESCAPE_FROM])
	print("")
	print("  距离    closeness  引力加速度  逃逸层  推力余量  推力72 喷气150  制动260")
	for d in [7200.0, 6000.0, 5000.0, 4000.0, 3500.0, 3000.0, 2400.0, 2000.0, 1500.0,
			1000.0, 600.0, 300.0, 200.0, 150.0, 120.0]:
		ship.global_position = hole + Vector3(0.0, d, 0.0)
		ship.velocity = Vector3.ZERO
		ship.bh_orbit_age = 0.0
		ship._black_hole_pull(0.016)
		var radial: float = ship.bh_radial_accel
		var margin: int = int(round((72.0 - radial) / 72.0 * 100.0))
		print("  %6.0f   %8.3f   %9.2f   %6.2f   %7d%%    %s    %s    %s" % [
			d, ship.bh_pull_strength, radial,
			radial / maxf(0.001, lerpf(1.6, 420.0, pow(ship.bh_pull_strength, 2.2))),
			margin,
			"赢" if radial < 72.0 else "输",
			"赢" if radial < 150.0 else "输",
			"赢" if radial < 260.0 else "输"])

	print("")
	print("=== 报警档位随距离的变化（推力余量驱动） ===")
	for d in [7200.0, 5000.0, 4300.0, 4000.0, 3500.0, 3000.0, 2400.0, 1500.0, 500.0]:
		ship.global_position = hole + Vector3(0.0, d, 0.0)
		ship.velocity = Vector3.ZERO
		ship.bh_orbit_age = 0.0
		ship._black_hole_pull(0.016)
		var radial: float = ship.bh_radial_accel
		var margin: float = 72.0 - radial
		var lvl := 0
		if margin <= 0.0:
			lvl = 3
		elif margin <= 150.0 * 0.35:
			lvl = 2
		elif radial > 1.6 * 2.0:
			lvl = 1
		print("  距离 %6.0f  引力 %7.2f  余量 %7.1f  ->  档位 %d" % [d, radial, margin, lvl])

	print("")
	print("=== 死亡过场时长 ===")
	print("  视界判定 begin_death(..., 1.6) -> 过场 1.6 秒")
	quit(0)
