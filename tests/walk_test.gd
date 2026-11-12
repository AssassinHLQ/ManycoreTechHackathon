extends SceneTree

var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


## 用「行星局部坐标」度量位移。
##
## ⚠ 2026-11-12：旧版用 global_position，会把**行星公转**算进去。
##   行星位置由 game.elapsed 驱动，建场卡顿时 elapsed 跳变，
##   行星沿轨道瞬移 → 作为它子节点的玩家 global_position 也跟着跳 3 米。
##   实测：失败时玩家在行星局部坐标里完全不动，只有全局坐标在跳。
##   改成局部坐标后，量的就是「相对地面的移动」，判据一分不放宽。
func _walk(action: String, frames: int) -> Array:
	var previous: Vector3 = game.player.position
	var max_step := 0.0
	var total := 0.0
	Input.action_press(action)
	for i in range(frames):
		await physics_frame
		var step: float = previous.distance_to(game.player.position)
		max_step = maxf(max_step, step)
		total += step
		previous = game.player.position
	Input.action_release(action)
	return [max_step, total]


func _place(arch: Node3D, local: Vector3) -> void:
	if game.player.get_parent() != arch.get_parent():
		game.player.reparent(arch.get_parent(), false)
	game.player.global_transform = Transform3D(arch.global_transform.basis.orthonormalized(), arch.global_transform * local)
	game.player.velocity = Vector3.ZERO


func _run() -> void:
	var test_save := "user://starward_walk_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(20):
		await physics_frame
	# ⚠ 2026-11-12：必须等后台行星补建完成再开始。
	#   建造期间主线程会卡顿，某一帧 physics delta 变大，
	#   玩家一帧走 3 米多（阈值 1.5）—— 测试会误判成「卡住」。
	#   实测见 tests/probe_tide_stairs.gd：每次大跳都紧跟着一行 [Lux3D] 建造日志。
	# 轮询行星数量到 20（比 world_build_remaining 可靠：那个标志在第二段建造
	# 开始之前是 false，守卫会提前放行，随后建造卡顿就落进下面的行走窗口）。
	var build_guard := 0
	while game.planets.size() < 20 and build_guard < 3600:
		await process_frame
		build_guard += 1
	for i in range(20):
		await physics_frame
	var arch: Node3D = game.home.find_child("Architecture_Qinglan", true, false)

	_place(arch, Vector3(8.0, 1.9, 0.0))
	# 2026-11-11 物理插值开启后，从 0.29 米高处落地要约 15 帧才稳定；
	# 原来等 10 帧是踩线过的（实测第 10 帧 is_on_floor 仍为 false）。
	for i in range(30):
		await physics_frame
	_check(game.player.is_on_floor(), "player stands on the observatory platform")
	var wall_run: Array = await _walk("move_left", 180)
	var wall_local: Vector3 = arch.global_transform.affine_inverse() * game.player.global_position
	_check(wall_run[0] < 1.5, "pushing into a wall does not teleport the player")
	_check(wall_local.x > 6.0, "the platform wall stops the player outside the tower")

	_place(arch, Vector3(0.5, 1.78, 3.0))
	for i in range(30):
		await physics_frame
	var exit_run: Array = await _walk("move_back", 180)
	var exit_local: Vector3 = arch.global_transform.affine_inverse() * game.player.global_position
	_check(exit_run[0] < 1.5, "walking out of the observatory is continuous")
	_check(exit_local.z > 6.0, "the player leaves through the front doorway")

	_place(arch, Vector3(0.5, 1.9, 8.0))
	for i in range(30):
		await physics_frame
	var enter_run: Array = await _walk("move_forward", 150)
	var enter_local: Vector3 = arch.global_transform.affine_inverse() * game.player.global_position
	_check(enter_run[0] < 1.5, "walking into the observatory is continuous")
	_check(enter_local.z < 5.0, "the player enters through the front doorway")

	var tide_arch: Node3D = game.planets[2].find_child("Architecture_Cangbo", true, false)
	if game.player.get_parent() != game.planets[2]:
		game.player.reparent(game.planets[2], false)
	game.player.global_transform = Transform3D(tide_arch.global_transform.basis.orthonormalized(), tide_arch.global_transform * Vector3(-1.5, 11.7, 6.4))
	game.player.velocity = Vector3.ZERO
	for i in range(12):
		await physics_frame
	var tide_run: Array = await _walk("move_forward", 150)
	var tide_local: Vector3 = tide_arch.global_transform.affine_inverse() * game.player.global_position
	_check(tide_run[0] < 1.5, "tide station stairs are climbable")
	_check(tide_local.z < 3.6, "the player enters the tide station")

	_place(arch, Vector3(8.0, 1.9, 0.0))
	for i in range(30):
		await physics_frame
	var surface_run: Array = await _walk("move_forward", 120)
	_check(surface_run[0] < 1.5, "surface walking never snaps")
	_check(surface_run[1] > 5.0, "surface walking covers ground")

	var cave: Node3D = game.home.find_child("Cave_Qinglan", true, false)
	# ⚠ 2026-11-11：星球放大后这一段会随机有 1~2 个点失败，但单独诊断
	#   （probe_cave_ramp_diag.gd）四个点全过、误差仅 0.21~0.30 米。
	#   说明坡道本身没问题，是**前面几步留下的物理状态**让玩家在 45 帧内
	#   还没落稳。所以这里只加「稳定时间」，不改容差、不放宽判据。
	for sample in [24, 64, 104, 144]:
		var t := float(sample) / 160.0
		var angle := PI * 0.5 - 0.30 + 0.36 * 40.0 * t
		var expected_y := lerpf(-0.2, -12.85, t)
		game.player.reparent(game.home, false)
		game.player.velocity = Vector3.ZERO
		game.player.global_position = cave.global_transform * Vector3(cos(angle) * 8.4, expected_y + 1.2, sin(angle) * 8.4)
		# 先空跑几帧让物理服务器把新位置同步进碰撞检测
		for i in range(10):
			await physics_frame
		game.player.velocity = Vector3.ZERO
		game.player.global_position = cave.global_transform * Vector3(cos(angle) * 8.4, expected_y + 1.2, sin(angle) * 8.4)
		for i in range(140):
			await physics_frame
		var local: Vector3 = cave.global_transform.affine_inverse() * game.player.global_position
		_check(game.player.is_on_floor() and absf(local.y - expected_y) < 0.9, "spiral ramp supports the player at sample %d" % sample)

	game.discovered = {}
	game._save_knowledge()
	print("WALK TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0 if failures == 0 else 1)
