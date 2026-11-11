extends SceneTree
# 测试：下船后玩家不抖。
#
# 用户反馈「飞船停了，下船还会抖」。实测根因是玩家被放在离地 1.4 m，
# 重力下坠 + floor_snap 吸附导致前 8 帧上下振荡最大 0.24 m。
# 修法：exit_ship 走 find_safe_surface_position(..., 0.3) 贴地放置。
#
# 这个测试直接调 exit_ship()，然后逐帧量「玩家相对行星」的位移。
# 断言：静置后连续帧位移必须 < 0.02 m（正常应该是 0）。

var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		failures += 1
		push_error("FAIL  " + msg)
		print("FAIL  ", msg)


func _run() -> void:
	var test_save := "user://starward_exit_shake.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(25)

	# 直接把飞船放到地表并标记已着陆（不走 try_land，避开渐进着陆流程）
	game.state = "ship"
	game.player.visible = false
	game.ship.camera.current = true
	var planet = game.nearest_planet(game.ship.global_position)
	var dir: Vector3 = (game.ship.global_position - planet.global_position).normalized()
	game.ship.global_position = planet.global_position + planet.surface_position(dir, 2.3)
	game.ship.velocity = Vector3.ZERO
	game.ship.landed = true
	game.ship.landed_planet = planet
	if game.ship.get_parent() != planet:
		game.ship.reparent(planet, true)
	await _frames(15)

	# 下船
	game.exit_ship()
	await _frames(3)
	_check(game.state == "walk" and game.player.visible, "player exits to walk state")

	# 量抖动：玩家相对行星的逐帧位移
	var prev: Vector3 = game.player.global_transform.origin - planet.global_transform.origin
	var first_frames: Array[float] = []
	var later_frames: Array[float] = []
	for i in range(40):
		await process_frame
		var cur: Vector3 = game.player.global_transform.origin - planet.global_transform.origin
		var d: float = (cur - prev).length()
		if i < 10:
			first_frames.append(d)
		elif i >= 25:
			later_frames.append(d)
		prev = cur

	var first_max := 0.0
	for d in first_frames:
		first_max = maxf(first_max, d)
	var later_max := 0.0
	for d in later_frames:
		later_max = maxf(later_max, d)

	print("\n下船后前 10 帧最大位移: %.4f m" % first_max)
	print("静置后（第 25 帧起）最大位移: %.4f m" % later_max)

	# 以前 1.4 m 时前 10 帧会抖到 0.15~0.24；现在应接近 0
	_check(first_max < 0.05,
		"下船瞬间不抖（前 10 帧最大位移 %.4f < 0.05）" % first_max)
	_check(later_max < 0.005,
		"静置后完全静止（最大位移 %.4f < 0.005）" % later_max)

	# 顺带确认玩家确实站在地表附近（不是被塞进地里、也不是悬在半空）
	var exit_normal: Vector3 = (game.player.global_position - planet.global_position).normalized()
	var alt: float = game.player.global_position.distance_to(planet.global_position) \
			- planet.terrain_height(exit_normal)
	print("下船落点离地高度: %.2f m" % alt)
	_check(alt > -0.5 and alt < 2.0, "下船落点在地表附近（%.2f m）" % alt)

	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("\nEXIT SHAKE TEST COMPLETE: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
