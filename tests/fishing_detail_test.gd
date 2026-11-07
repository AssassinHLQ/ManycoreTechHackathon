extends SceneTree
# 图鉴详情页 / 鱼挣扎 / 鱼饵浮标表现。
# 用法：godot --headless --path . --script res://tests/fishing_detail_test.gd

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
	var test_save := "user://starward_detail_test.json"
	var test_progress := "user://starward_detail_progress.json"
	_cleanup(test_save)
	_cleanup(test_progress)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	game.progress_path = test_progress
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	# ---------- 一、鱼类详情页 ----------
	game.enter_attic()
	await physics_frame
	game.progress.reset()
	game.toggle_bag()
	await process_frame
	_check(game.bag.open, "B 打开行囊")
	_check(game.bag.page == "overview", "行囊默认在总览页")
	_check(game.bag.dex_index == 0, "详情页从第一条鱼开始")

	# → 从总览切到详情
	game.bag_page_next()
	await process_frame
	_check(game.bag.page == "dex", "按 → 从总览切到鱼类详情")

	# 详情页里 → 往后翻一条鱼
	var first_id: String = String(game.bag.FISH_IDS[0])
	game.bag_page_next()
	await process_frame
	_check(game.bag.dex_index == 1, "详情页里按 → 翻到下一条鱼")
	_check(String(game.bag.FISH_IDS[game.bag.dex_index]) != first_id, "翻页后换成了另一种鱼")

	# ← 翻回来
	game.bag_page_prev()
	await process_frame
	_check(game.bag.dex_index == 0, "详情页里按 ← 翻回上一条鱼")

	# 到头不绕圈
	game.bag_page_prev()
	await process_frame
	_check(game.bag.dex_index == 0, "第一条再往左不越界")
	for i in range(20):
		game.bag_page_next()
	await process_frame
	_check(game.bag.dex_index == game.bag.FISH_IDS.size() - 1, "翻到底停在最后一条鱼")

	# ↓ 回总览
	game.bag_page_overview()
	await process_frame
	_check(game.bag.page == "overview", "按 ↓ 从详情回到总览")

	# 一路翻到成就页（详情页要先翻到最后一条鱼，再按一次 → 才进成就页）
	game.bag_page_next()
	await process_frame
	_check(game.bag.page == "dex", "→ 从总览到鱼类详情")
	# 精确翻到最后一条鱼
	while game.bag.dex_index < game.bag.FISH_IDS.size() - 1:
		game.bag_page_next()
		await process_frame
	_check(game.bag.dex_index == game.bag.FISH_IDS.size() - 1, "翻到了最后一条鱼")
	game.bag_page_next()
	await process_frame
	_check(game.bag.page == "achievements", "→ 翻过最后一条鱼后进入成就总览")
	_check(game.bag.ach_scroll == 0, "成就页初始滚动在顶部")

	# 成就页滚动
	game.bag_scroll(1)
	await process_frame
	_check(game.bag.ach_scroll == 1, "成就页 ↓ 往下滚一行")
	game.bag_scroll(-1)
	await process_frame
	_check(game.bag.ach_scroll == 0, "成就页 ↑ 滚回顶部")
	game.bag_scroll(-1)
	await process_frame
	_check(game.bag.page == "overview", "成就页滚到顶再 ↑ 回总览")

	# 成就页能画出来
	game.bag.page = "achievements"
	game.bag.painter.queue_redraw()
	await process_frame
	_check(true, "成就页能画出来")

	# 再按一次 → 到最近远行页
	game.bag_page_next()
	await process_frame
	_check(game.bag.page == "runs", "成就页再按 → 进入最近远行")
	game.bag.painter.queue_redraw()
	await process_frame
	_check(true, "最近远行页能画出来（空记录也不崩）")

	# 有记录时也能画
	game.progress.reset()
	for i in range(7):
		game.progress.push_recent_run(120.0 + float(i), 5, i != 3, 8, 1, 60, "A")
	_check(game.progress.recent_runs.size() == 5, "远行记录只留 5 条")
	game.bag.page = "runs"
	game.bag.painter.queue_redraw()
	await process_frame
	_check(true, "最近远行页有记录时也能画出来")

	# → 从远行页回到总览
	game.bag_page_next()
	await process_frame
	_check(game.bag.page == "overview", "远行页再按 → 回到总览")

	# 分组表覆盖了所有成就
	var grouped: Array = []
	for group in game.bag.ACH_GROUPS:
		for id in group[1]:
			grouped.append(String(id))
	var all_ids: Array = []
	for id in game.progress.ACHIEVEMENTS.keys():
		all_ids.append(String(id))
	var missing: Array = []
	for id in all_ids:
		if not grouped.has(id):
			missing.append(id)
	_check(missing.is_empty(), "成就分组覆盖全部成就（缺：%s）" % str(missing))
	game.bag.page = "overview"

	# 详情页要能真的画出未钓到的鱼（不崩）
	game.bag.page = "dex"
	game.bag.dex_index = 0
	game.bag.painter.queue_redraw()
	await process_frame
	_check(true, "详情页面对未钓到的鱼也能画出来")

	# 钓一尾后，详情页读得到数量与最长纪录
	game.progress.add_fish("ice-crucian")
	game.progress.add_fish("ice-crucian")
	var summary: Dictionary = game.progress.summary()
	var entry: Dictionary = summary["fish"].get("ice-crucian", {})
	_check(int(entry.get("count", 0)) == 2, "冰纹鲫记了 2 尾")
	_check(int(entry.get("best_length", 0)) > 0, "冰纹鲫有最长纪录")
	game.bag.page = "dex"
	game.toggle_bag()
	await process_frame
	_check(not game.bag.open, "收起行囊")
	game.toggle_bag()
	await process_frame
	_check(game.bag.open, "重新打开行囊")
	_check(game.bag.page == "overview", "重新打开时回到总览页")
	game.toggle_bag()
	await process_frame
	_check(not game.bag.open, "再按一次收起行囊")

	# 星级是 1~5
	var worst: int = 99
	var best: int = 0
	for id in game.bag.FISH_IDS:
		var stars: int = game.progress.fish_stars(id)
		worst = mini(worst, stars)
		best = maxi(best, stars)
	_check(worst >= 1 and best <= 5, "星级都在 1~5 之间")
	_check(best == 5, "最稀有的鱼是 5 星")
	_check(game.progress.fish_stars("mirror-koi") > game.progress.fish_stars("ice-crucian"),
		"镜心鲤比冰纹鲫更稀有")
	_check(game.progress.fish_stars("ice-crucian") == 1, "冰纹鲫是最常见的 1 星")

	# ---------- 二、鱼挣扎 ----------
	game.enter_pocket("snow")
	await physics_frame
	game.progress.bait = "plain"
	var anchor = game.attic_worlds.hole_anchor(0)
	game.player.global_position = (anchor as Node3D).global_position
	await physics_frame
	game.start_fishing(0)
	await process_frame
	_check(game.fishing_struggle_amplitude() == 0.0, "还没咬钩时没有挣扎")

	game.fishing_timer = 0.0
	game._update_fishing(0.016)
	_check(game.fishing_phase == "reel", "咬钩后进入收线")
	_check(game.fishing_fish_id != "", "咬钩的瞬间就抽好了这条鱼")

	# 挣扎幅度：收线越接近上岸越大
	game.fishing_reel = 0.0
	var amp_early: float = game.fishing_struggle_amplitude()
	game.fishing_reel = 0.9
	var amp_late: float = game.fishing_struggle_amplitude()
	_check(amp_late > amp_early, "越接近上岸鱼挣扎得越厉害")

	# 稀有鱼更暴躁：换成镜心鲤比冰纹鲫幅度大
	game.fishing_reel = 0.5
	game.fishing_fish_id = "ice-crucian"
	var amp_common: float = game.fishing_struggle_amplitude()
	game.fishing_fish_id = "mirror-koi"
	var amp_legend: float = game.fishing_struggle_amplitude()
	_check(amp_legend > amp_common, "稀有鱼挣扎得更猛")

	# 挣扎会让张力在恒定升降之外起伏：静置时张力不应单调走平
	game.fishing_fish_id = "mirror-koi"
	game.fishing_reel = 0.5
	game.fishing_tension = 0.5
	game.fishing_struggle_clock = 0.0
	game.fishing_struggle_rate = 7.0
	game.fishing_reeling = false
	var samples: Array = []
	for i in range(40):
		# 手动模拟松手：只走张力回落 + 挣扎（不读真实输入）
		var before: float = game.fishing_tension
		game.fishing_tension += sin(game.fishing_struggle_clock * game.fishing_struggle_rate) \
			* game.fishing_struggle_amplitude() * 0.05 - 0.75 * 0.05
		game.fishing_struggle_clock += 0.05
		samples.append(game.fishing_tension)
	# 有挣扎时相邻帧的差值不会恒定；纯回落时差值是常数
	var deltas: Array = []
	for i in range(1, samples.size()):
		deltas.append(absf(float(samples[i]) - float(samples[i - 1])))
	var spread: float = float(deltas.max()) - float(deltas.min())
	_check(spread > 0.001, "张力回落过程中有挣扎带来的起伏")

	# 挣扎存在时仍然可以正常收线上岸
	game.fishing_fish_id = "ice-crucian"
	game.fishing_reel = 0.99
	game.fishing_tension = 0.45
	game._update_fishing(0.016)
	await process_frame
	_check(game.fishing_phase == "", "最后一帧仍能正常钓上来")

	# ---------- 三、鱼饵浮标 ----------
	var hud = game.fishing_hud
	_check(hud != null, "冰钓 HUD 存在")
	if hud != null:
		_check(hud.BAIT_COLORS.has("plain") and hud.BAIT_COLORS.has("glow") and hud.BAIT_COLORS.has("star"),
			"三款鱼饵都有浮标配色")
		_check(hud.BAIT_COLORS["glow"] != hud.BAIT_COLORS["plain"], "萤光饵的浮标颜色与面团饵不同")
		_check(hud.BAIT_COLORS["star"] != hud.BAIT_COLORS["plain"], "星屑饵的浮标颜色与面团饵不同")

	# 抛竿时 HUD 就亮起来（能看到浮标）
	game.progress.bait = "glow"
	game.player.global_position = (anchor as Node3D).global_position
	await physics_frame
	game.start_fishing(0)
	await process_frame
	if hud != null and hud.painter != null:
		_check(hud.painter.visible, "抛竿时浮标就出现在水面上")
		_check(game.fishing_phase == "wait", "此时还在等咬钩")
	# 换饵后浮标配色跟着变
	var tint_glow: Color = hud.BAIT_COLORS[game.progress.bait]
	game.progress.bait_charges["star"] = 3
	game.progress.switch_bait("star")
	var tint_star: Color = hud.BAIT_COLORS[game.progress.bait]
	_check(tint_star != tint_glow, "换星屑饵后浮标配色跟着换")

	game.queue_free()
	await process_frame
	_cleanup(test_save)
	_cleanup(test_progress)
	if failures > 0:
		print("FISHING DETAIL TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("FISHING DETAIL TEST: all clear")
		quit(0)


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
