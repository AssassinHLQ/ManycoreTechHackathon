extends SceneTree
# 探针：量行星地表粗糙度，验证「地形起伏正比于 radius」这个假设。
#
# 为什么要测：world_scale 改动后 walk_test 有 3 项「每帧位移 < 1.5」失败，
# 说明玩家在地表走动时被瞬移。本喵怀疑是 `_raw_terrain_height` 里
# `radius * amplitude` 让起伏随行星半径线性放大，行星 ×3 后地面也 ×3 粗糙。
#
#   godot --headless --path . --script res://tests/probe_terrain_roughness.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_terrain.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(4):
		await process_frame

	print("=== 各行星地表起伏（沿同一方位角扫 200 个采样点）===")
	print("  行星      半径      起伏峰峰值   占半径%%   相邻步最大落差")
	for p in game.planets:
		var prev: float = 0.0
		var lo := INF
		var hi := -INF
		var max_step := 0.0
		# 从基准方向出发，沿一个切向小步长走一圈
		var base: Vector3 = p.site_direction if p.site_direction.length() > 0.1 else Vector3.UP
		var axis: Vector3 = base.cross(Vector3.RIGHT).normalized()
		if axis.length_squared() < 0.01:
			axis = base.cross(Vector3.FORWARD).normalized()
		var n := 200
		for i in range(n + 1):
			var ang: float = float(i) / float(n) * 0.25   # 扫约 14 度
			var dir: Vector3 = (base * cos(ang) + axis * sin(ang)).normalized()
			var h: float = p.terrain_height(dir)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			if i > 0:
				max_step = maxf(max_step, absf(h - prev))
			prev = h
		var r: float = float(p.radius)
		print("  %-8s %7.0f  %10.2f  %8.2f  %12.3f" % [
			p.display_name, r, hi - lo, (hi - lo) / r * 100.0, max_step])

	print("")
	print("=== 结论 ===")
	print("  「相邻步最大落差」应与玩家每帧位移上限 1.5 米比较：")
	print("  若地形本身一步就差很多米，玩家贴地时就必然被判成瞬移。")

	quit(0)
