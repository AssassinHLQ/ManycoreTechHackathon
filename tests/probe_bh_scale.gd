extends SceneTree
# 验证黑洞引力在「星系 ×10」新尺度下的曲线是否合理。
#
# 关键判据：引力只应在**靠近时**才明显。
#   · 72000 米（引力范围边缘）应几乎为 0（≈ BH_ACCEL_FAR = 1.6）
#   · 中段应远低于推力 72 m/s²（否则巡航寸步难行）
#   · 内圈才升到几百
#
# 同时对照吸积盘的视觉外缘 48440 米 —— 盘面内部必须有明显引力。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _run() -> void:
	var test_save := "user://starward_bh_curve.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(5)
	game.start_game()
	await _frames(20)

	var ship = game.ship
	var bh: Vector3 = game.gargantua.global_position
	var range_far: float = ship.BH_PULL_RANGE
	var horizon: float = ship.BH_HORIZON

	print("\n吸积盘视觉外缘 ≈ 48440 米")
	print("引力范围 = %.0f 米  视界 = %.0f 米" % [range_far, horizon])
	print("\n距离(米)   closeness   引力(m/s²)   占推力72的比例")
	print("---------------------------------------------------")

	var dists := [72000.0, 60000.0, 50000.0, 48440.0, 40000.0, 30000.0,
		20000.0, 14000.0, 10000.0, 5000.0, 1200.0]
	var fails := 0
	for d in dists:
		# 放到黑洞正上方 d 米处，只读引力
		ship.global_position = bh + Vector3(0, d, 0)
		await _frames(2)
		var pull: Vector3 = ship._black_hole_pull(0.016)
		var acc: float = pull.length()
		var span: float = maxf(range_far - horizon, 1.0)
		var closeness: float = clampf((range_far - d) / span, 0.0, 1.0)
		var ratio: float = acc / 72.0
		print("%8.0f   %8.4f   %9.2f   %8.2fx" % [d, closeness, acc, ratio])

		# 断言：引力范围边缘必须几乎无感
		if absf(d - 72000.0) < 1.0:
			if acc > 5.0:
				fails += 1
				print("  !! FAIL 引力范围边缘应≈1.6，实际 %.2f" % acc)
		# 断言：盘面外侧（48440）应是「轻微但可感」
		if absf(d - 48440.0) < 1.0:
			if acc < 1.0 or acc > 200.0:
				fails += 1
				print("  !! FAIL 盘面外缘引力应 1~200，实际 %.2f" % acc)
		# 断言：中段（20000）不该压过推力 72
		if absf(d - 20000.0) < 1.0:
			if acc > 72.0:
				fails += 1
				print("  !! FAIL 2 万米处引力 %.2f 已压过普通推力 72" % acc)

	print("\n=== 结论 ===")
	if fails == 0:
		print("PASS  引力曲线在新尺度下合理")
	else:
		print("FAIL  %d 项不合理" % fails)

	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0 if fails == 0 else 1)
