extends SceneTree
# 探针：只测「强制捕获圈内的切向刹车」到底按不按初速度区分。
#
# 为什么要单独测这个：完整轨迹测试里，飞船一进 BH_FORCE_CAPTURE 就被
# 立刻拉满径向速度冲向视界，1~2 秒就死了，根本来不及观察「刹停耗时」。
# 这里把飞船钉在捕获圈的固定位置（不移动），只跑刹车公式，
# 纯粹看「不同初速下，切向速度降到 10% 要多久」。
#
#   godot --headless --path . --script res://tests/probe_bh_brake_only.gd

var game
var ship


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_brakeonly.json"
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

	print("=== 强制捕获圈内的刹车：钉住位置，只看切向衰减 ===")
	print("  减速度常量 BH_FORCE_BRAKE_DECEL = %.0f m/s²" % ship.BH_FORCE_BRAKE_DECEL)
	print("")
	print("  初速(m/s)   理论耗时   实测耗时   剩 10%% 时的切向速度")
	var dt := 1.0 / 600.0
	var results: Array = []
	for speed in [400.0, 800.0, 1000.0, 1600.0, 2400.0, 3200.0]:
		var tangential: float = speed          # 起始切向速度
		var elapsed := 0.0
		var hit10 := -1.0
		var remain_at_10 := 0.0
		for i in range(int(60.0 / dt)):
			# 复刻 _apply_black_hole_capture 里的刹车逻辑（位置不动）
			var cut: float = minf(tangential, ship.BH_FORCE_BRAKE_DECEL * dt)
			tangential -= cut
			elapsed += dt
			if hit10 < 0.0 and tangential <= speed * 0.10:
				hit10 = elapsed
				remain_at_10 = tangential
				break
			if tangential <= 0.01:
				if hit10 < 0.0:
					hit10 = elapsed
					remain_at_10 = tangential
				break
		var theory: float = (speed * 0.90) / ship.BH_FORCE_BRAKE_DECEL
		print("  %8.0f    %6.2f 秒   %6.2f 秒    %6.0f" % [
			speed, theory, hit10 if hit10 >= 0 else -1.0, remain_at_10])
		results.append([speed, hit10])

	print("")
	print("=== 结论 ===")
	if results.size() >= 2:
		print("  400 m/s  : %.2f 秒" % float(results[0][1]))
		print("  3200 m/s : %.2f 秒" % float(results[-1][1]))
		var ratio: float = float(results[-1][1]) / maxf(0.001, float(results[0][1]))
		print("  最慢/最快 = %.2f 倍（旧版按比例砍 ≈ 1.0；固定减速度应 ≈ 8.0）" % ratio)
	quit(0)
