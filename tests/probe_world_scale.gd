extends SceneTree
# 探针：量世界放大之后的实际几何，确认「距离×10、星球×3、太阳×10」真的落地了，
# 并且顺手检查几件容易被忽略的事：
#   · 最远天体到相机是否落在 camera.far 之内（否则星球会被裁掉）
#   · 黑洞是否还在行星轨道之外（不能变成路障）
#   · 自动驾驶飞到最远星球要多久、烧多少油
#   · 归航站环绕半径有没有跟上行星半径
#
#   godot --headless --path . --script res://tests/probe_world_scale.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_scale.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(6):
		await process_frame

	print("=== 尺度常量 ===")
	print("  ORBIT_SCALE        = %.1f" % game.ORBIT_SCALE)
	print("  PLANET_RADIUS_SCALE= %.1f" % game.PLANET_RADIUS_SCALE)
	print("  SUN_SCALE          = %.1f" % game.SUN_SCALE)
	print("  太阳半径           = %.0f 米" % game.sun_radius)

	print("")
	print("=== 十颗行星 ===")
	print("  名称      半径      轨道半径    垂直起伏   公转速度(m/s)")
	var max_reach := 0.0
	for p in game.planets:
		var h: float = float(p.orbit_height)
		# 公转速度量级：轨道半径 × 角速度
		var v: float = absf(float(p.orbit_speed)) * float(p.orbit_radius)
		print("  %-8s %8.0f  %10.0f  %10.0f  %10.1f" % [
			p.display_name, float(p.radius), float(p.orbit_radius), h, v])
		max_reach = maxf(max_reach, float(p.orbit_radius) + float(p.radius))

	print("")
	print("=== 相机裁剪面 ===")
	var far: float = game.ship.camera.far if game.ship != null else -1.0
	print("  ship.camera.far = %.0f" % far)
	print("  最远天体表面到原点的距离 = %.0f" % max_reach)
	print("  从最远天体看到对面天体所需约 %.0f 米（2 × 轨道半径）" % (2.0 * max_reach))
	var need: float = 2.0 * max_reach
	if far >= need:
		print("  ✓ far 足够（余量 %.0f 米）" % (far - need))
	else:
		print("  ✗ far 不够！还差 %.0f 米 —— 远轨道会被裁掉" % (need - far))

	print("")
	print("=== 黑洞位置 ===")
	var hole: Vector3 = game.gargantua.global_position
	var max_orbit := 0.0
	for p in game.planets:
		max_orbit = maxf(max_orbit, float(p.orbit_radius))
	print("  黑洞距原点 = %.0f 米" % hole.length())
	print("  最外层行星轨道 = %.0f 米" % max_orbit)
	if hole.length() > max_orbit:
		print("  ✓ 黑洞在行星轨道之外（%.2f 倍）" % (hole.length() / max_orbit))
	else:
		print("  ✗ 黑洞落进了行星轨道内！")

	print("")
	print("=== 自动驾驶：飞到最远星球 ===")
	var cruise: float = game.ship.AUTOPILOT_CRUISE
	var per_dv: float = game.ship.AUTOPILOT_FUEL_PER_DV
	var farthest := 0.0
	for p in game.planets:
		farthest = maxf(farthest, float(p.orbit_radius))
	print("  巡航上限 = %.0f m/s，油耗 = %.4f/（m/s）" % [cruise, per_dv])
	print("  最远单程约 %.0f 米 —— 至少 %.0f 秒（理想全速）" % [farthest, farthest / cruise])
	# 加速到巡航 + 减速回来的 Δv ≈ 2 × cruise
	print("  加速+减速的 Δv ≈ %.0f m/s → 约 %.1f 点推进剂（油箱 100）" % [
		2.0 * cruise, 2.0 * cruise * per_dv])

	print("")
	print("=== 归航站 ===")
	if game.station != null:
		print("  归航站距原点 = %.0f 米" % game.station.global_position.length())
		var nearest = null
		var nd := INF
		for p in game.planets:
			var d: float = game.station.global_position.distance_to(p.global_position)
			if d < nd:
				nd = d
				nearest = p
		if nearest != null:
			print("  最近行星 = %s，距离 %.0f 米（行星半径 %.0f）" % [
				nearest.display_name, nd, float(nearest.radius)])
			print("  环绕半径 = %.0f 米" % float(game.station.orbit_radius))

	quit(0)
