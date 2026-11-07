extends SceneTree
# 冰钓收线：张力窗口 + 收线进度 + 鱼竿 / 鱼饵的影响。
# 用法：godot --headless --path . --script res://tests/fishing_reel_test.gd

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
	var test_save := "user://starward_reel_test.json"
	var test_progress := "user://starward_reel_progress.json"
	_cleanup(test_save)
	_cleanup(test_progress)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	game.progress_path = test_progress
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	# 进阁楼 → 雪世界，站到第一处冰洞旁
	game.enter_attic()
	await physics_frame
	game.enter_pocket("snow")
	await physics_frame
	game.progress.reset()
	var hole_anchor = game.attic_worlds.hole_anchor(0)
	_check(hole_anchor != null, "雪夜有冰洞锚点")
	game.player.global_position = (hole_anchor as Node3D).global_position
	await physics_frame
	var hole: int = game.near_fishing_hole()
	_check(hole == 0, "站在冰洞旁能识别出可下竿的洞")

	# 抛竿 → 等咬钩
	game.start_fishing(hole)
	_check(game.fishing_phase == "wait", "抛竿后进入等咬钩阶段")
	_check(game.fishing_hole == hole, "记下了正在钓的洞")
	_check(absf(game.fishing_tension - 0.3) < 0.001, "初始张力是 0.3")
	_check(game.fishing_reel == 0.0, "初始收线进度为 0")
	_check(game.progress.bait_charge("plain") == -1, "默认面团饵不占库存")

	# 咬钩 → 收线阶段
	game.fishing_timer = 0.0
	game._update_fishing(0.016)
	_check(game.fishing_phase == "reel", "浮标沉下后转入收线阶段")
	if game.fishing_hud != null:
		_check(game.fishing_hud.painter != null, "冰钓 HUD 已建好画笔")
		_check(game.fishing_hud.painter.visible, "收线时张力条 HUD 可见")
	else:
		_check(false, "冰钓 HUD 已创建")

	# 窗口内收线：进度上升
	game.fishing_tension = 0.45
	game.fishing_reel = 0.0
	game.fishing_reeling = false
	game._update_fishing(0.05)
	_check(game.fishing_reel > 0.0, "张力在窗口内时收线进度上升")

	# 窗口外（太低）不前进
	game.fishing_tension = 0.05
	game.fishing_reel = 0.0
	game._update_fishing(0.05)
	_check(game.fishing_reel == 0.0, "张力离开窗口时收线不前进")

	# 张力冲出去：断线
	game.fishing_tension = 1.15
	game._update_fishing(0.05)
	_check(game.fishing_phase == "", "张力冲出去后鱼跑了")
	_check(game.fishing_hole == -1, "断线后清空洞序号")
	if game.fishing_hud != null and game.fishing_hud.painter != null:
		_check(not game.fishing_hud.painter.visible, "断线后张力条 HUD 收起")

	# 鱼竿变强：窗口更宽、收线更快
	var wide_before: float = game.progress.rod_tension_window()
	var speed_before: float = game.progress.rod_reel_speed()
	game.progress.coins = 9999
	_check(game.progress.buy_rod("brass"), "能升级到黄铜海竿")
	var wide_after: float = game.progress.rod_tension_window()
	var speed_after: float = game.progress.rod_reel_speed()
	_check(wide_after > wide_before, "黄铜海竿的张力窗口更宽")
	_check(speed_after > speed_before, "黄铜海竿收线更快")

	# 鱼饵：买萤光饵并换上，咬钩更快
	_check(bool(game.progress.buy_bait("glow")["ok"]), "能买一份萤光饵")
	game.progress.switch_bait("glow")
	_check(game.progress.bait == "glow", "切换到了萤光饵")
	_check(game.progress.bait_bite_scale() < 1.0, "萤光饵让咬钩更快")
	var count_before: int = game.progress.bait_charge("glow")
	_check(count_before > 0, "萤光饵有库存")

	# 钓上一条鱼会吃掉一份鱼饵
	game.player.global_position = (hole_anchor as Node3D).global_position
	await physics_frame
	game.start_fishing(0)
	game.fishing_phase = "reel"
	game.finish_fishing_catch()
	await physics_frame
	_check(game.progress.bait_charge("glow") == count_before - 1, "钓上鱼消耗一份鱼饵")
	_check(game.progress.fish_count() == 1, "钓上的鱼记进了图鉴")

	# 星屑饵才钓得到传说鱼
	game.progress.bait_charges["star"] = 20
	game.progress.switch_bait("star")
	_check(game.progress.bait == "star", "切换到了星屑饵")
	var seen_legend := false
	var seen_normal := false
	for i in range(300):
		var id: String = game.progress.roll_fish()
		if game.progress.LEGEND_FISH.has(id):
			seen_legend = true
		else:
			seen_normal = true
	_check(seen_legend, "星屑饵能钓到传说鱼")
	_check(seen_normal, "星屑饵也不是条条传说")

	# 面团饵钓不到传说鱼
	game.progress.switch_bait("plain")
	var plain_legend := false
	for i in range(300):
		var id2: String = game.progress.roll_fish()
		if game.progress.LEGEND_FISH.has(id2):
			plain_legend = true
	_check(not plain_legend, "面团饵钓不到传说鱼")

	game.queue_free()
	await process_frame
	_cleanup(test_save)
	_cleanup(test_progress)
	if failures > 0:
		print("FISHING REEL TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("FISHING REEL TEST: all clear")
		quit(0)


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
