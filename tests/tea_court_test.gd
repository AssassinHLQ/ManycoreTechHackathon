extends SceneTree
# 阁楼茶席三步 + 雨巷听雨院（三盏听雨灯 → 檐下坐一会儿）检查。
# 用法：godot --headless --path . --script res://tests/tea_court_test.gd

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


func _run() -> void:
	var save := "user://starward_tea_court_test.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_tea_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.enter_attic()
	await physics_frame

	# ---- 茶席三步 ----
	_check(game.attic.tea_step == 0, "茶席初始未开始")
	var kettle: Node3D = game.attic.tea_anchor()
	_check(kettle != null, "茶桌上有茶壶锚点")
	if kettle != null:
		game.player.global_position = kettle.global_position
		await physics_frame
		# 走 _interact 的真实路径
		game._interact()
		await physics_frame
		_check(game.attic.tea_step == 1, "第一步：烧水")
		game._interact()
		await physics_frame
		_check(game.attic.tea_step == 2, "第二步：投茶")
		_check(game.attic.tea_steam != null and game.attic.tea_steam.visible, "投茶后壶口有蒸汽")
		game._interact()
		await physics_frame
		_check(game.attic.tea_step == 3, "第三步：出汤")
		_check(game.attic.tea_cups.size() == 2, "桌上有两只杯子")
		# 再按一次不应继续加步
		game._interact()
		await physics_frame
		_check(game.attic.tea_step == 3, "泡好后不再推进")

	# ---- 听雨院 ----
	game.enter_pocket("alley")
	await physics_frame
	_check(game.attic_worlds.court_lamps.size() == 3, "听雨院有三盏听雨灯")
	_check(not game.attic_worlds.court_all_lit(), "初始三盏都没亮")
	_check(not game.attic_worlds.court_rested, "初始没有坐过")

	# 没点灯时不能坐
	var bench = game.attic_worlds.court_bench_anchor()
	_check(bench != null, "檐下有长凳锚点")
	if bench != null:
		game.player.global_position = (bench as Node3D).global_position
		await physics_frame
		_check(game.near_court_bench(), "站在长凳旁能识别")
		game._interact()
		await physics_frame
		_check(not game.attic_worlds.court_rested, "三盏灯没亮时坐不下（檐下还暗着）")

	# 逐盏点灯
	for i in range(3):
		var lamp = game.attic_worlds.court_lamp_anchor(i)
		_check(lamp != null, "听雨灯 %d 有锚点" % i)
		if lamp == null:
			continue
		game.player.global_position = (lamp as Node3D).global_position
		await physics_frame
		_check(game.near_court_lamp() == i, "站在听雨灯 %d 旁能识别" % i)
		game._interact()
		await physics_frame
		_check(game.attic_worlds.court_lamp_lit(i), "听雨灯 %d 已点亮" % i)
		_check(game.attic_worlds.court_lit_count() == i + 1, "已点亮 %d / 3" % (i + 1))
	_check(game.attic_worlds.court_all_lit(), "三盏听雨灯全亮")

	# 现在可以坐下
	if bench != null:
		game.player.global_position = (bench as Node3D).global_position
		await physics_frame
		game._interact()
		await physics_frame
		_check(game.attic_worlds.court_rested, "三盏全亮后可以在檐下坐一会儿")
		# 第二次不再重复触发
		game._interact()
		await physics_frame
		_check(game.attic_worlds.court_rested, "坐过之后状态保持")

	game.leave_pocket()
	await physics_frame
	game.leave_attic()
	await physics_frame
	print("TEA COURT TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	if FileAccess.file_exists("user://starward_tea_progress.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_tea_progress.json"))
	quit(0 if failures == 0 else 1)
