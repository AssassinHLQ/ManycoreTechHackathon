extends SceneTree
# 探针：验证「松开鼠标后飞船立刻停，不反弹」。
# 用法：godot --headless --path . --script res://tests/probe_no_overshoot.gd
#
# 用户报的 bug 1：
#   「我往右滑鼠标, 然后鼠标拿开了没动, 结果飞船还在往右滑,
#     滑完突然又往反方向滑回来了」
# 这是角速度过冲 + 振荡。根因是旧代码 `angle/delta` 让角速度永远取上限，
# 角度很小时也满速转，必然冲过头再反向追。
#
# 用户报的 bug 2：
#   「我都没有按 ad 了, 飞船还在翻转很久才停止」
# 同样是角速度收敛太慢。
#
# 这个探针量：
#   1. 推一下鼠标后松开，飞船在多少帧内停住
#   2. 停住过程中**有没有反向**（振荡）
#   3. A/D 松开后多少帧内停住

var game
var failures := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS  ", msg)
	else:
		failures += 1
		print("FAIL  ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_overshoot.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(8):
		await physics_frame

	var ship = game.ship
	game.state = "ship"
	ship.landed = false
	ship.docked = false
	ship.autopilot = false
	ship.global_position = Vector3(80000, 0, 0)
	ship.velocity = Vector3.ZERO
	ship.intent_quat = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY

	# ── 1. 推一下鼠标然后松开，看飞船多久停住、有没有反向 ──
	print("\n=== 1. 松开鼠标后是否立刻停住（不反弹） ===")
	# 推鼠标一小段（模拟玩家划一下）
	for i in range(10):
		ship.apply_look(Vector2(25.0, 0.0))
	var intent_target: Quaternion = ship.intent_quat

	var yaw_history: Array = []
	for i in range(180):     # 3 秒
		ship.fuel = 100.0
		ship.global_position = Vector3(80000, 0, 0)
		ship._physics_process(1.0 / 60.0)
		yaw_history.append(ship.intent_quat.get_euler().y * 0.0 + _nose_yaw(ship))

	# 找停止帧：之后角度变化 < 0.05°
	var settled_frame := -1
	for i in range(2, yaw_history.size()):
		var still := true
		for j in range(i, yaw_history.size()):
			if absf(rad_to_deg(yaw_history[j] - yaw_history[i])) > 0.05:
				still = false
				break
		if still:
			settled_frame = i
			break
	print("   松开后 %d 帧（%.2f 秒）完全停住" % [settled_frame, settled_frame / 60.0])
	_check(settled_frame >= 0 and settled_frame < 45,
		"stops within 0.75s after releasing the mouse (frame %d)" % settled_frame)

	# 检查有没有反向：yaw 单调趋于目标，不应先冲过再回来
	var final_yaw: float = float(yaw_history[-1])
	var max_deviation := 0.0
	for y in yaw_history:
		var over := rad_to_deg(y - final_yaw)
		if absf(over) > absf(max_deviation):
			max_deviation = over
	# 过冲：中途角度超过最终值
	var start_yaw: float = float(yaw_history[0])
	var direction: float = signf(final_yaw - start_yaw)
	var overshoot := 0.0
	for y in yaw_history:
		var past: float = (y - final_yaw) * direction
		if past > overshoot:
			overshoot = past
	print("   过冲量 = %.3f°（应接近 0）" % rad_to_deg(overshoot))
	_check(rad_to_deg(overshoot) < 2.0,
		"no visible overshoot / bounce-back (%.3f deg)" % rad_to_deg(overshoot))

	# ── 2. A/D 松开后多久停 ──
	print("\n=== 2. 松开 A/D 后是否很快停止滚转 ===")
	ship.fuel = 100.0
	ship.intent_quat = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	Input.action_press("move_left")
	for i in range(60):
		ship.fuel = 100.0
		ship.global_position = Vector3(80000, 0, 0)
		ship._physics_process(1.0 / 60.0)
	Input.action_release("move_left")

	var up_history: Array = []
	for i in range(120):
		ship.fuel = 100.0
		ship.global_position = Vector3(80000, 0, 0)
		ship._physics_process(1.0 / 60.0)
		up_history.append(ship.global_transform.basis.y.normalized())

	var roll_settled := -1
	for i in range(2, up_history.size()):
		var still := true
		for j in range(i, up_history.size()):
			if rad_to_deg(up_history[j].angle_to(up_history[i])) > 0.05:
				still = false
				break
		if still:
			roll_settled = i
			break
	print("   松开 A/D 后 %d 帧（%.2f 秒）停止滚转" % [roll_settled, roll_settled / 60.0])
	_check(roll_settled >= 0 and roll_settled < 40,
		"roll settles quickly after releasing A/D (frame %d)" % roll_settled)

	# ── 3. 灵敏度与燃料精度 ──
	print("\n=== 3. 参数检查 ===")
	print("   AIM_SENSITIVITY = %.5f（应更低）" % ship.AIM_SENSITIVITY)
	_check(ship.AIM_SENSITIVITY < 0.0006, "mouse sensitivity is lower again (%.5f)" % ship.AIM_SENSITIVITY)

	# ── 4. 快速拖动（用户报的原始场景）──
	#
	# 用户：「我拖动快了还是给我往回拉」——
	# 上一版慢推没事、快拖就过冲，因为 _turn_velocity 是持久状态，
	# 快拖把它推到很大，目标停下后余速还要衰减。
	# 现在速度直接由角差算，结构上不可能过冲。这里专门验证快拖。
	print("\n=== 4. 快速拖动后是否过冲 ===")
	ship.fuel = 100.0
	ship.intent_quat = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	ship.velocity = Vector3.ZERO
	ship.global_position = Vector3(80000, 0, 0)

	# 模拟一次**快速大幅拖动**：一帧内推 300px（相当于甩手腕）
	ship.apply_look(Vector2(300.0, 0.0))
	var target_q: Quaternion = ship.intent_quat

	var yaw_seq: Array = []
	for i in range(150):
		ship.fuel = 100.0
		ship.global_position = Vector3(80000, 0, 0)
		ship._physics_process(1.0 / 60.0)
		yaw_seq.append(_nose_yaw(ship))

	var y_end: float = float(yaw_seq[-1])
	var y_start: float = float(yaw_seq[0])
	var dir_sign: float = signf(y_end - y_start)
	var over := 0.0
	for y in yaw_seq:
		var past: float = (float(y) - y_end) * dir_sign
		if past > over:
			over = past
	print("   快速拖动 300px：过冲 %.4f°" % rad_to_deg(over))
	_check(rad_to_deg(over) < 0.5, "fast drag causes no bounce-back (%.4f deg)" % rad_to_deg(over))

	# ── 5. √ 曲线：**模拟玩家连续推鼠标**，速度应先升后降 ──
	#
	# ⚠ 不能用「一次性给出 90 度目标」来测 —— 那样第一帧角差就有 90 度，
	#   直接满速，测不出「先慢后快」。
	#   真实操作是玩家**连续推**鼠标，角差随推动逐渐变大，速度才跟着上来。
	print("\n=== 5. √曲线：连续推鼠标时先慢后快 ===")
	ship.fuel = 100.0
	ship.intent_quat = Quaternion.IDENTITY
	ship._turn_velocity = Vector3.ZERO
	ship.global_transform.basis = Basis.IDENTITY
	ship.velocity = Vector3.ZERO
	ship.global_position = Vector3(80000, 0, 0)

	var per_frame: Array = []
	# ⚠ 用「两帧之间机头的夹角」而不是 atan2 差值 ——
	#   后者在 ±180 度处会跳变 360 度，产生假峰值（实测 359.88°/帧）。
	var prev_nose: Vector3 = -ship.global_transform.basis.z.normalized()
	for i in range(20):
		ship.apply_look(Vector2(15.0, 0.0))
		ship.fuel = 100.0
		ship.global_position = Vector3(80000, 0, 0)
		ship._physics_process(1.0 / 60.0)
		var now_nose: Vector3 = -ship.global_transform.basis.z.normalized()
		per_frame.append(rad_to_deg(prev_nose.angle_to(now_nose)))
		prev_nose = now_nose
	for i in range(40):
		ship.fuel = 100.0
		ship.global_position = Vector3(80000, 0, 0)
		ship._physics_process(1.0 / 60.0)
		var now_nose2: Vector3 = -ship.global_transform.basis.z.normalized()
		per_frame.append(rad_to_deg(prev_nose.angle_to(now_nose2)))
		prev_nose = now_nose2

	# 前 5 帧平均 vs 中间最快帧
	var early: float = 0.0
	for i in range(5):
		early += float(per_frame[i])
	early /= 5.0
	var peak := 0.0
	for v in per_frame:
		peak = maxf(peak, float(v))
	print("   前 5 帧平均 %.2f°/帧，峰值 %.2f°/帧" % [early, peak])
	_check(peak > early * 1.5,
		"turn ramps up (early %.2f vs peak %.2f deg/frame)" % [early, peak])

	# 末尾应该减速。⚠ 不能用「最后 8 帧」——那几帧飞船已经停住了（值接近 0），
	#   会把平均值拉低到没有意义。要取「到达前的减速段」：
	#   找到最后一帧仍有明显转动的位置，取它之前 8 帧。
	var last_moving := 0
	for i in range(per_frame.size()):
		if float(per_frame[i]) > 0.02:
			last_moving = i
	var late_start: int = maxi(0, last_moving - 7)
	var late: float = 0.0
	var n := 0
	for i in range(late_start, last_moving + 1):
		late += float(per_frame[i])
		n += 1
	if n > 0:
		late /= float(n)
	print("   减速段平均 %.2f°/帧（峰值 %.2f，应为峰值的 %.0f%%）" % [
		late, peak, 100.0 * late / maxf(peak, 0.001)])
	_check(late < peak * 0.85,
		"turn ramps down before arriving (%.2f vs peak %.2f)" % [late, peak])

	print("\nNO OVERSHOOT PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)


## 机头在世界 Y 平面上的朝向角（用于观察偏航变化）
func _nose_yaw(ship) -> float:
	var f: Vector3 = -ship.global_transform.basis.z.normalized()
	return atan2(f.x, f.z)
