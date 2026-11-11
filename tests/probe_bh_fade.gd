extends SceneTree
# 探针：测「不管你多大速度，到附近都会被快速拖慢」到底拖多快。
#
# 用户原话：「我 3200m 每秒，和 1000m 每秒，都是靠近，然后 3 秒左右失去速度
#             这正常吗？」
#
# 本探针在多个距离上，分别以 1000 / 3200 m/s 的**切向速度**入场，
# 逐帧跑真实的 _black_hole_pull，量出：
#   · 每秒实际掉多少速度
#   · 速度掉到 50% / 10% 需要几秒
#   · 淡出系数 disk_fade 在该距离上是多少
#
#   godot --headless --path . --script res://tests/probe_bh_fade.gd

var game
var ship


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_bhfade.json"
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
	print("=== 吸积盘阻力淡出实测（切向速度衰减）===")
	print("  BH_DISK_FROM=%.2f (约 %.0f 米) BH_DISK_TO=%.2f (约 %.0f 米)" % [
		ship.BH_DISK_FROM,
		ship.BH_PULL_RANGE - (ship.BH_PULL_RANGE - ship.BH_HORIZON) * ship.BH_DISK_FROM,
		ship.BH_DISK_TO,
		ship.BH_PULL_RANGE - (ship.BH_PULL_RANGE - ship.BH_HORIZON) * ship.BH_DISK_TO])
	print("  强制捕获圈 BH_FORCE_CAPTURE = %.0f" % ship.BH_FORCE_CAPTURE)
	print("")

	for d in [6000.0, 5000.0, 4000.0, 3000.0, 2000.0, 1500.0, 1000.0]:
		for v0 in [1000.0, 3200.0]:
			var r := _simulate(hole, d, v0)
			var line := "  距 %5.0f 米 · 初始 %6.0f m/s -> 1秒掉 %7.1f (%5.1f%%)" % [
				d, v0, r["d1"], r["p1"]]
			line += " | 降到50%%要 %5.2fs | 降到10%%要 %5.2fs | 判定 %s" % [
				r["t50"], r["t10"], r["verdict"]]
			print(line)

	print("")
	print("=== 抓帧：各距离的 disk_fade（0=不拖，1=满档）===")
	for d in [7000.0, 6000.0, 5000.0, 4500.0, 4000.0, 3000.0, 2000.0, 1500.0, 1200.0]:
		var closeness: float = clampf((ship.BH_PULL_RANGE - d) /
			(ship.BH_PULL_RANGE - ship.BH_HORIZON), 0.0, 1.0)
		var fade: float = smoothstep(ship.BH_DISK_FROM, ship.BH_DISK_TO, closeness)
		print("  %6.0f 米  closeness=%.3f  disk_fade=%.3f" % [d, closeness, fade])
	quit(0)


## 在距离 d 处以 v0 的切向速度跑 4 秒真实引力，逐帧记录速度。
##
## ⚠ 必须测**切向分量**，不能测总速度：
##   切向牵引（pull += tangent * strength * BH_TANGENT_RATIO）会**加速**切向速度，
##   那是「把飞船甩进轨道」用的，所以总速度在远场反而会上升 ——
##   拿总速度算「掉速」会把加速误判成拖慢。
func _simulate(hole: Vector3, d: float, v0: float) -> Dictionary:
	ship.global_position = hole + Vector3(0.0, d, 0.0)
	# 切向速度：沿 X 轴（垂直于半径方向）
	ship.velocity = Vector3(v0, 0.0, 0.0)
	ship.bh_orbit_age = 0.0
	ship.bh_captured = false
	var dt := 1.0 / 60.0
	var t50 := -1.0
	var t10 := -1.0
	var v_start: float = _tangential_speed(hole)
	var v_at_1s := v_start
	for i in range(240):
		var g: Vector3 = ship._black_hole_pull(dt)
		ship.velocity += g * dt
		var after: float = _tangential_speed(hole)
		var t: float = float(i + 1) * dt
		if t <= 1.0001:
			v_at_1s = after
		if t50 < 0.0 and after < v_start * 0.5:
			t50 = t
		if t10 < 0.0 and after < v_start * 0.1:
			t10 = t
	var d1: float = v_start - v_at_1s
	var verdict := "自由"
	if d <= ship.BH_FORCE_CAPTURE:
		verdict = "★强制捕获"
	elif d1 > 1.0:
		verdict = "被拖速"
	return {
		"d1": d1,
		"p1": (d1 / v0) * 100.0,
		"t50": t50,
		"t10": t10,
		"verdict": verdict,
	}


## 当前的切向速度大小（垂直于「飞船→黑洞」方向的分量）。
func _tangential_speed(hole: Vector3) -> float:
	var to_hole: Vector3 = hole - ship.global_position
	var d: float = to_hole.length()
	if d < 0.001:
		return 0.0
	var dir: Vector3 = to_hole / d
	return (ship.velocity - dir * ship.velocity.dot(dir)).length()
