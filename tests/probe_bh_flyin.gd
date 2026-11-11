extends SceneTree
# 探针：模拟玩家真实的「朝黑洞冲进去」，看速度到底怎么掉。
#
# 用户原话：「我 3200m 每秒，和 1000m 每秒，都是靠近，然后 3 秒左右失去速度」。
#
# 之前 probe_bh_fade.gd 测「切向绕行」时量到切向速度反而上升 —— 那是几何效应
# （径向下落被切向牵引转成了切向），不是阻力。这个探针改成玩家真实操作：
# **关掉推力，直线朝黑洞冲**，逐帧记录距离和速度。
#
#   godot --headless --path . --script res://tests/probe_bh_flyin.gd

var game
var ship


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_bhflyin.json"
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
	print("=== 朝黑洞直线冲（无推力）速度衰减实测 ===")
	print("  BH_FORCE_CAPTURE=%.0f  BH_DISK_FROM=%.2f BH_DISK_TO=%.2f" % [
		ship.BH_FORCE_CAPTURE, ship.BH_DISK_FROM, ship.BH_DISK_TO])
	print("")

	for v0 in [1000.0, 3200.0]:
		print("--- 初始速度 %.0f m/s（直线朝黑洞）---" % v0)
		_run_case(hole, v0)

	print("")
	print("=== 对照：切向绕行（不进捕获圈）应保持速度 ===")
	_run_tangential(hole, 3200.0)
	print("")
	print("=== 用户原场景：远处朝黑洞靠近，速度会不会莫名掉 ===")
	_run_user_scene(hole)
	quit(0)


## 直线朝黑洞冲：看速度掉到 50% / 10% 各要几秒。
func _run_case(hole: Vector3, v0: float) -> void:
	ship.global_position = hole + Vector3(0.0, 6000.0, 0.0)
	ship.velocity = Vector3(0.0, -v0, 0.0)   # 正对着冲
	ship.bh_orbit_age = 0.0
	ship.bh_captured = false
	var dt := 1.0 / 60.0
	var t50 := -1.0
	var t10 := -1.0
	var t_captured := -1.0
	var t_horizon := -1.0
	print("    秒    距离      总速度    径向速度   状态")
	for i in range(600):
		var g: Vector3 = ship._black_hole_pull(dt)
		ship.velocity += g * dt
		ship.global_position += ship.velocity * dt
		var d: float = ship.global_position.distance_to(hole)
		var spd: float = ship.velocity.length()
		var radial: float = ship.velocity.dot((hole - ship.global_position).normalized())
		var t: float = float(i + 1) * dt
		if t50 < 0.0 and spd < v0 * 0.5:
			t50 = t
		if t10 < 0.0 and spd < v0 * 0.1:
			t10 = t
		if t_captured < 0.0 and d <= ship.BH_FORCE_CAPTURE:
			t_captured = t
		if t_horizon < 0.0 and d <= ship.BH_HORIZON:
			t_horizon = t
		if i % 60 == 0 or (i % 6 == 0 and t < 3.0):
			var state := "自由"
			if t_captured >= 0.0:
				state = "★捕获"
			if t_horizon >= 0.0:
				state = "★越过视界"
			print("   %5.2f %8.1f %9.1f %9.1f   %s" % [t, d, spd, radial, state])
			if t_horizon >= 0.0:
				break
		# ── 关键：真实游戏里这一步还会跑「强制捕获刹车」──
		# 用户说的「3 秒失去速度」就是这里来的（BH_FORCE_BRAKE_DECEL 固定减速度）。
		# 探针必须复用真实判定，否则测的是影子实现。
		ship._apply_black_hole_capture(dt)
	print("    => 速度降到 50%%: %s | 降到 10%%: %s | 进入捕获圈: %s | 越过视界: %s" % [
		_fmt(t50), _fmt(t10), _fmt(t_captured), _fmt(t_horizon)])
	print("")


## 切向绕行：初始速度垂直于半径，不该被直线吃掉。
func _run_tangential(hole: Vector3, v0: float) -> void:
	ship.global_position = hole + Vector3(0.0, 4000.0, 0.0)
	ship.velocity = Vector3(v0, 0.0, 0.0)
	ship.bh_orbit_age = 0.0
	ship.bh_captured = false
	var dt := 1.0 / 60.0
	var v0_len: float = v0
	for i in range(180):
		var g: Vector3 = ship._black_hole_pull(dt)
		ship.velocity += g * dt
		ship.global_position += ship.velocity * dt
	var d: float = ship.global_position.distance_to(hole)
	print("  4000 米切向 3200 m/s 绕 3 秒后：速度 %.1f（%.1f%%）、距离 %.0f" % [
		ship.velocity.length(),
		ship.velocity.length() / v0_len * 100.0, d])


func _fmt(t: float) -> String:
	if t < 0.0:
		return "没到"
	return "%.2fs" % t


## 用户原场景：「3200 m/s 和 1000 m/s 都是靠近，然后 3 秒左右失去速度」。
## 这里模拟：玩家从 5000 米外以初速朝黑洞**斜着**飞（既有向心也有切向分量，
## 像真人一边靠近一边想绕），量切向速度的衰减曲线。
func _run_user_scene(hole: Vector3) -> void:
	for v0 in [1000.0, 3200.0]:
		ship.global_position = hole + Vector3(0.0, 5000.0, 0.0)
		# 斜向：60% 朝里 + 100% 切向
		var inward := Vector3(0.0, -1.0, 0.0)
		var tangent := Vector3(1.0, 0.0, 0.0)
		ship.velocity = (inward * 0.6 + tangent * 1.0).normalized() * v0
		ship.bh_orbit_age = 0.0
		ship.bh_captured = false
		var dt := 1.0 / 60.0
		var t_start: float = _tangential_speed(hole)
		print("  --- 斜向靠近 · 初速 %.0f m/s（切向起始 %.0f）---" % [v0, t_start])
		for i in range(180):
			var g: Vector3 = ship._black_hole_pull(dt)
			ship.velocity += g * dt
			ship.global_position += ship.velocity * dt
			ship._apply_black_hole_capture(dt)
			var t: float = float(i + 1) * dt
			if i % 30 == 0:
				var d: float = ship.global_position.distance_to(hole)
				print("    %4.1fs  距离 %7.0f  切向 %7.0f (%.0f%%)" % [
					t, d, _tangential_speed(hole),
					_tangential_speed(hole) / maxf(t_start, 1.0) * 100.0])
		print("")


## 当前的切向速度大小（垂直于「飞船→黑洞」方向的分量）。
func _tangential_speed(hole: Vector3) -> float:
	var to_hole: Vector3 = hole - ship.global_position
	var d: float = to_hole.length()
	if d < 0.001:
		return 0.0
	var dir: Vector3 = to_hole / d
	return (ship.velocity - dir * ship.velocity.dot(dir)).length()
