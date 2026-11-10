extends SceneTree
# 探针：验证黑洞机制的两条——
#   1. **引力**（径向加速度）只跟距离有关，**与速度无关**  ← 物理正确
#   2. **吸积盘阻力**随速度增大，低段 ∝ v²，高段饱和     ← 用户要的「越快拽得越狠」
#
# 用户原话：「我觉得现实黑洞应该是，你速度越快，他吸引你的加速度越快」
# 作为引力这不成立（牛顿 a=GM/r²、史瓦西 d²r/dτ²=−M/r² 都只看距离），
# 但作为穿过吸积盘的动力学摩擦（F ∝ ρv²）完全成立，
# 所以把「越快越狠」做在阻力上。
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


## 把飞船放到「距黑洞 d、切向速度为 v」的状态
func _place(ship, d: float, v: float) -> void:
	var hole: Vector3 = game.gargantua.global_position
	ship.global_position = hole + Vector3(d, 0, 0)
	# 切向 = 垂直于半径（这里半径沿 X，所以切向取 Z）
	ship.velocity = Vector3(0, 0, -v)
	ship.turn_budget = Quaternion.IDENTITY
	ship.fuel = 100.0


## 返回「这一帧被阻力砍掉的切向速度」
func _drag_loss(ship, d: float, v: float) -> float:
	_place(ship, d, v)
	var before: Vector3 = ship.velocity - (ship.global_position - game.gargantua.global_position).normalized() \
		* ship.velocity.dot((ship.global_position - game.gargantua.global_position).normalized())
	ship._black_hole_pull(1.0 / 60.0)
	var dir: Vector3 = (ship.global_position - game.gargantua.global_position).normalized()
	var after: Vector3 = ship.velocity - dir * ship.velocity.dot(dir)
	return (before.length() - after.length()) * 60.0     # 换算成 m/s²


## 返回径向引力加速度（与速度无关的那个量）
func _radial_accel(ship, d: float, v: float) -> float:
	_place(ship, d, v)
	ship.bh_pull_strength = 0.0
	ship._black_hole_pull(1.0 / 60.0)
	return ship.bh_radial_accel


func _run() -> void:
	var save := "user://starward_bhdrag.json"
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
	if game.gargantua == null:
		print("FAIL  场景里没有黑洞")
		quit(1)
		return

	# ── 1. 引力与速度无关 ──
	print("\n=== 1. 径向引力只跟距离有关（与速度无关） ===")
	var d := 1500.0
	var a_slow := _radial_accel(ship, d, 1.0)
	var a_mid := _radial_accel(ship, d, 2000.0)
	var a_fast := _radial_accel(ship, d, 16000.0)
	print("   距离 %.0f：v=1 -> %.3f ；v=2000 -> %.3f ；v=16000 -> %.3f" % [
		d, a_slow, a_mid, a_fast])
	_check(absf(a_slow - a_mid) < 0.001 and absf(a_mid - a_fast) < 0.001,
		"radial gravity is identical at any speed (physics-correct)")

	# ── 2. 阻力随速度单调增大 ──
	print("\n=== 2. 吸积盘阻力随速度增大 ===")
	var speeds := [200.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
	var losses: Array = []
	for v in speeds:
		var l := _drag_loss(ship, 130.0, v)
		losses.append(l)
		print("   切向 %6.0f m/s -> 阻力减速 %8.1f m/s²" % [v, l])

	var monotonic := true
	for i in range(1, losses.size()):
		if float(losses[i]) <= float(losses[i - 1]):
			monotonic = false
	_check(monotonic, "drag grows monotonically with speed")

	# ── 3. 低段近似 ∝ v² ──
	# v 从 200 到 400（翻倍）时，阻力应约变为 4 倍（还没到饱和区）
	print("\n=== 3. 低速段近似 ∝ v² ===")
	var l1 := _drag_loss(ship, 130.0, 300.0)
	var l2 := _drag_loss(ship, 130.0, 600.0)
	var ratio := l2 / maxf(l1, 0.0001)
	print("   300 -> 600 m/s（速度 x2）：阻力 %.1f -> %.1f（倍数 %.2f，理想 4）" % [l1, l2, ratio])
	_check(ratio > 3.0 and ratio < 4.6, "drag scales roughly as v^2 at low speed (x%.2f)" % ratio)

	# ── 4. 高速段饱和（不会一帧骤停） ──
	print("\n=== 4. 高速段饱和 ===")
	var l_hi := _drag_loss(ship, 130.0, 16000.0)
	print("   16000 m/s 时阻力 %.1f m/s²（上限 BH_DRAG_MAX = %.0f）" % [l_hi, ship.BH_DRAG_MAX])
	_check(l_hi <= ship.BH_DRAG_MAX * 1.05, "drag is capped at BH_DRAG_MAX")
	# 一帧最多砍掉多少：不应超过该帧速度本身（否则会瞬停）
	var per_frame := l_hi / 60.0
	print("   一帧最多砍掉 %.1f m/s（初速 16000，占比 %.1f%%）" % [
		per_frame, 100.0 * per_frame / 16000.0])
	_check(per_frame < 16000.0 * 0.5, "one frame cannot zero out the speed (no teleport-stop)")

	# ── 5. 越快绝对值掉得越多 ──
	print("\n=== 5. 「越快拽得越狠」 ===")
	var slow := _drag_loss(ship, 130.0, 500.0)
	var fast := _drag_loss(ship, 130.0, 5000.0)
	print("   500 m/s 被砍 %.0f m/s² ；5000 m/s 被砍 %.0f m/s²（%.1f 倍）" % [
		slow, fast, fast / maxf(slow, 0.001)])
	_check(fast > slow * 3.0, "a much faster ship is pulled much harder")

	print("\nBH DRAG PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
