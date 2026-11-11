## 测试：自动航行逼近行星的剖面 + 落点判定。
##
## 用户反馈「自动驾驶太差了，一直加速直接撞上星球却毫发无伤」，这条测试钉住三件事：
##   1. 自动航行的下降剖面是**动力学可行**的（任何高度都能在撞地前把速度收住）；
##   2. 着陆那一刻的**法向接近速度**低于落点判定的 14 m/s，船体不掉血；
##   3. 豁免已经删掉 —— 真的撞快了会掉血、会解体。
##
## 另外钉住落点判定的参照系：行星在以 10～39 m/s 公转，判定必须用
## 「相对地面、沿法线的接近速度」，不能用自己的绝对速度。
##
## 结果同时写进 user:// 文件（控制台被 UV 警告刷屏）。
extends SceneTree

var game
var lines: Array[String] = []
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _log(s: String) -> void:
	print(s)
	lines.append(s)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)
		print("FAIL  ", message)


func _flush(name: String) -> void:
	var f := FileAccess.open("user://" + name, FileAccess.WRITE)
	if f == null:
		return
	for l in lines:
		f.store_line(l)
	f.close()


func _setup_ship() -> void:
	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	game.ship.reparent(game, true)
	game.ship.landed = false
	game.ship.docked = false
	game.ship.hull = 100.0
	game.ship.fuel = 100.0
	game.ship.impact_cooldown = 0.0


## 机头摆正：有初速就顺着初速，没有就指向行星。
##
## 手动模式下飞船会把速度矢量慢慢转到机头方向（`VELOCITY_ALIGN_RATE`），
## 机头不顺着初速的话初速会被转走，飞船从行星旁边擦过去（探针里踩过这个坑）。
func _aim_ship(planet, direction: Vector3, velocity_in: Vector3) -> void:
	var to_planet: Vector3 = (planet.global_position - game.ship.global_position).normalized()
	var nose: Vector3 = velocity_in.normalized() if velocity_in.length() > 1.0 else to_planet
	var safe_up: Vector3 = Vector3.UP if absf(nose.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	game.ship.global_transform = Transform3D(
		Basis.looking_at(nose, safe_up), game.ship.global_position)


## 通用场景：把船放在行星的 direction 方向、height 米高，给初速度，跑到有结果为止。
## 返回 {landed, hull, closing, frames}。
func _scenario(label: String, planet, direction: Vector3, height: float,
		start_velocity: Vector3, use_autopilot: bool, frames: int = 4000) -> Dictionary:
	_setup_ship()
	var dir: Vector3 = direction.normalized()
	game.ship.target = planet
	game.ship.global_position = planet.global_position + dir * (planet.terrain_height(dir) + height)
	game.ship.velocity = start_velocity
	game.ship.autopilot = use_autopilot
	_aim_ship(planet, dir, start_velocity)
	await physics_frame

	_log("")
	_log("=== %s  %s ===" % [planet.display_name, label])
	_log("      高 %.0f 米  初速 %.0f m/s  自动驾驶 %s" % [
		height, start_velocity.length(), use_autopilot])
	_log("frame  altTerr     speed   close    relSpd   want    hull  flag")
	var last_report := -999
	var prev_closing := 0.0
	var touchdown_closing := -1.0
	var frame_no := 0
	for i in range(frames):
		await physics_frame
		frame_no = i
		var off: Vector3 = game.ship.global_position - planet.global_position
		var n := off.normalized()
		var alt_terrain: float = off.length() - planet.terrain_height(n)
		var speed: float = game.ship.velocity.length()
		var rel: Vector3 = game.ship.velocity - planet.orbital_velocity()
		var closing: float = maxf(0.0, -rel.dot(n))
		var want: float = game.ship._autopilot_desired_speed(alt_terrain, Vector3.ZERO)
		var flag := ""
		if not game.ship.autopilot:
			flag += "AUTOPILOT_OFF "
		if game.ship.landed:
			flag += "LANDED "
			if touchdown_closing < 0.0:
				touchdown_closing = prev_closing
		if game.state == "dying":
			flag += "DYING "
		if alt_terrain < 300.0 or i - last_report >= 25 or flag != "":
			last_report = i
			_log("%5d %9.1f %9.1f %7.1f %8.1f %7.1f %6.1f  %s" % [
				i, alt_terrain, speed, closing, rel.length(), want, game.ship.hull, flag])
		prev_closing = closing
		if game.ship.landed or game.state == "dying":
			break
	return {
		"landed": game.ship.landed,
		"hull": game.ship.hull,
		"closing": touchdown_closing,
		"frames": frame_no,
	}


## 单帧撞击判定：贴地 2 米、给定速度、只跑一帧、看结果。
##
## ⚠ 期望值要补上**一帧引力**：`_physics_process` 先 `velocity += gravity * delta`
##   再做落点判定，所以实际接近速度比输入大 `gravity/60`。少了这一项时
##   40 m/s 的用例会差 0.14 点船体，看起来像 bug 其实不是。
func _instant_impact(label: String, planet, velocity_in: Vector3, expect_land: bool) -> void:
	_setup_ship()
	var dir: Vector3 = Vector3.UP
	game.ship.target = planet
	game.ship.global_position = planet.global_position + planet.surface_position(dir, 2.0)
	game.ship.velocity = velocity_in
	_aim_ship(planet, dir, velocity_in)
	var rel: Vector3 = velocity_in - planet.orbital_velocity()
	var closing: float = maxf(0.0, -rel.dot(dir))
	# 地表 2 米处引力几乎就是满值。
	var gravity_now: float = planet.gravity_strength
	var effective: float = closing + gravity_now / 60.0
	await physics_frame
	var hull_after: float = game.ship.hull
	var landed: bool = game.ship.landed
	var expected_hull: float = 100.0 if expect_land else maxf(0.0, 100.0 - effective * 0.42)
	_log("")
	_log("=== %s ===" % label)
	_log("  输入 |v| = %.1f  地面 |v| = %.1f  相对 |v| = %.1f" % [
		velocity_in.length(), planet.orbital_velocity().length(), rel.length()])
	_log("  法向接近速度 %.2f m/s（含一帧引力后 %.2f，门槛 14）" % [closing, effective])
	_log("  结果：%s  船体 %.1f%%（期望 %.1f%%）" % [
		"着陆" if landed else "撞击", hull_after, expected_hull])
	_check(landed == expect_land, "%s：%s" % [
		label, "应当着陆" if expect_land else "应当撞击"])
	_check(absf(hull_after - expected_hull) < 0.5, "%s：船体 %.1f%% ≈ %.1f%%" % [
		label, hull_after, expected_hull])


func _run() -> void:
	var test_save := "user://starward_probe_autoland.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(10):
		await physics_frame

	_log("sun_radius=%s  planets=%d" % [game.sun_radius, game.planets.size()])
	for p in game.planets:
		_log("  %-10s radius=%7.1f orbit=%8.1f 公转速度=%6.1f m/s" % [
			p.display_name, p.radius, p.orbit_radius, p.orbital_velocity().length()])

	var qinglan = game.planets[0]   # 青岚星 400 米 / 公转 6.6
	var jianmo = game.planets[9]    # 缄默星 150 米 / 公转 38.6（最快）

	# ── 1. 全部行星：正上方 1200 米静置起步，必须安全着陆 ──
	for p in game.planets:
		var r: Dictionary = await _scenario("正上方 1200 米 静置起步", p, Vector3.UP,
			1200.0, Vector3.ZERO, true)
		_check(r.landed, "%s：自动驾驶着陆成功" % p.display_name)
		_check(r.hull >= 99.99, "%s：着陆不掉血（船体 %.1f）" % [p.display_name, r.hull])
		_check(r.closing >= 0.0 and r.closing < 14.0,
			"%s：接地接近速度 %.2f < 14" % [p.display_name, r.closing])

	# ── 2. 斜掠进场 ──
	for p in game.planets:
		var r: Dictionary = await _scenario("斜掠 侧 900 米", p,
			Vector3.UP + Vector3.RIGHT * 0.75, 1200.0, Vector3.ZERO, true)
		_check(r.landed and r.hull >= 99.99,
			"%s：斜掠进场安全着陆（船体 %.1f，接近 %.2f）" % [p.display_name, r.hull, r.closing])

	# ── 3. 带着高速冲向行星：只要刹车距离够，剖面必须能刹住 ──
	#
	#   800 m/s 要 800²/(2·230) ≈ 1391 米才能停住，所以给 1600 米。
	var r3a: Dictionary = await _scenario("正上方 1600 米 · 800 m/s 冲进来", qinglan,
		Vector3.UP, 1600.0, Vector3.DOWN * 800.0, true)
	_check(r3a.landed and r3a.hull >= 99.99, "1600 米 / 800 m/s：刹得住并安全着陆（船体 %.1f）" % r3a.hull)
	var r3b: Dictionary = await _scenario("正上方 900 米 · 600 m/s 冲进来", jianmo,
		Vector3.UP, 900.0, Vector3.DOWN * 600.0, true)
	_check(r3b.landed and r3b.hull >= 99.99, "900 米 / 600 m/s：刹得住并安全着陆（船体 %.1f）" % r3b.hull)

	# ── 4. 物理上救不回来：300 米高、800 m/s 向内。
	#
	#   需要的刹车距离是 1391 米，只有 300 米 —— 任何控制器都救不了。
	#   ⚠ 这一条是「豁免已删掉」的核心断言：旧版有 `or autopilot`，
	#   同样的情况会被判成完美着陆、船体 100%。
	var r4: Dictionary = await _scenario("物理上救不回来：300 米 · 800 m/s", qinglan,
		Vector3.UP, 300.0, Vector3.DOWN * 800.0, true)
	_check(not r4.landed and r4.hull <= 0.01,
		"救不回来时必须真的撞毁（船体 %.1f，不是「毫发无伤」）" % r4.hull)

	# ── 5. 落点判定：单帧、确定性 ──
	var qinglan_vel: Vector3 = qinglan.orbital_velocity()
	var jianmo_vel: Vector3 = jianmo.orbital_velocity()
	await _instant_impact("青岚星 · 纯径向 40 m/s 砸下", qinglan, Vector3.DOWN * 40.0, false)
	await _instant_impact("青岚星 · 纯径向 10 m/s 轻放", qinglan, Vector3.DOWN * 10.0, true)
	await _instant_impact("青岚星 · 纯径向 200 m/s 硬砸", qinglan, Vector3.DOWN * 200.0, false)
	await _instant_impact("青岚星 · 跟地面同步 + 径向 20 m/s",
		qinglan, qinglan_vel + Vector3.DOWN * 20.0, false)

	# ── 6. 参照系：地面在动，判定必须只看「相对地面」 ──
	#
	#   ⚠ 关键回归断言：缄默星公转 38.6 m/s。旧版用飞船的**绝对速度**判撞击，
	#   于是「与地面同步飞行」的飞船 —— 相对地面完全静止 —— 会被判成 38.6 m/s
	#   撞击。自动航行现在会主动匹配地面速度，所以不修这条，
	#   自动驾驶落在缄默星上每落一次炸一次。
	await _instant_impact("缄默星 · 与地面同步（绝对 39 m/s）", jianmo, jianmo_vel, true)
	await _instant_impact("缄默星 · 绝对静止（地面以 39 m/s 掠走）", jianmo, Vector3.ZERO, true)
	await _instant_impact("青岚星 · 切向擦碰 30 m/s（不算撞地）",
		qinglan, qinglan_vel.normalized() * 30.0, true)

	_flush("probe_autopilot_landing.txt")
	game.state = "walk"
	game.discovered = {}
	game._save_knowledge()
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("PROBE AUTOPILOT LANDING COMPLETE: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
