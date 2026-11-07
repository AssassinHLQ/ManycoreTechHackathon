extends SceneTree
# 行囊（B）/ 金币 / 鱼类图鉴 / 成就 的检查。
# 用法：godot --headless --path . --script res://tests/progress_test.gd

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
	var save := "user://starward_progress_test.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_main_test.json"
	game.progress_path = "user://starward_progress_test.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	_check(game.progress != null, "进度服务已创建")
	_check(game.bag != null, "行囊面板已创建")
	if game.progress == null or game.bag == null:
		quit(1)
		return
	game.progress.save_path = save
	game.progress.reset()

	# --- 原作九种鱼 ---
	_check(game.progress.FISH_TABLE.size() == 9, "鱼谱共九种（原作 Di 表）")
	_check(game.progress.fish_name("mirror-koi") == "镜心鲤", "镜心鲤在谱上")
	_check(game.progress.fish_name("ice-crucian") == "冰纹鲫", "冰纹鲫在谱上")
	_check(game.progress.fish_value("mirror-koi") > game.progress.fish_value("ice-crucian"),
		"稀有鱼价值更高")
	# 鱼竿越好，稀有鱼权重越高（同一次抽样里权重表应当变化）
	var sample_ids := {}
	for i in range(200):
		sample_ids[game.progress.roll_fish()] = true
	_check(sample_ids.size() >= 4, "抽鱼会抽到多种鱼（%d 种）" % sample_ids.size())
	for id in sample_ids:
		_check(game.progress.FISH_TABLE.has(id), "抽到的鱼都在谱上：%s" % id)

	# --- 金币与图鉴 ---
	_check(game.progress.coins == 0, "初始金币为 0")
	var info: Dictionary = game.progress.add_fish("ice-crucian")
	_check(int(info["value"]) > 0, "钓上一尾鱼会给出价值")
	_check(bool(info["is_new"]), "第一次钓到记为图鉴新条目")
	_check(game.progress.coins == 0, "钓上来先只进鱼篓，不直接给金币")
	_check(game.progress.fish_count() == 1, "图鉴计数为 1")
	_check(game.progress.held_count() == 1, "鱼篓里有 1 尾")
	var again: Dictionary = game.progress.add_fish("ice-crucian")
	_check(not bool(again["is_new"]), "同种鱼第二次不算新条目")
	_check(int(again["count"]) == 2, "同种鱼计数累加")
	_check(game.progress.fish_count() == 2, "图鉴总数累加")
	_check(String(game.progress.add_fish("mirror-koi")["name"]) == "镜心鲤", "可以记录不同鱼种")
	_check(game.progress.dex_count() == 2, "图鉴鱼种数为 2")

	# --- 卖出渔获 ---
	var held_before: int = game.progress.held_count()
	_check(held_before == 3, "鱼篓里有 3 尾待卖")
	var sale: Dictionary = game.progress.sell_fish()
	_check(int(sale["count"]) == held_before, "一次卖出全部 %d 尾" % held_before)
	_check(game.progress.coins == int(sale["coins"]), "卖鱼换到金币")
	_check(game.progress.held_count() == 0, "卖完鱼篓清空")
	_check(game.progress.dex_count() == 2, "卖鱼不会丢图鉴")
	_check(game.progress.add_fish("ice-crucian")["count"] == 3, "累计钓获不受卖出影响")
	_check(int(game.progress.sell_fish()["count"]) == 1, "再钓再卖也能成交")

	# --- 鱼竿升级 ---
	_check(game.progress.rod == "bamboo", "初始是竹节鱼竿")
	game.progress.coins = 0
	_check(not game.progress.buy_rod("brass"), "金币不够买不了黄铜海竿")
	game.progress.coins = 200
	_check(game.progress.buy_rod("brass"), "金币够就能换黄铜海竿")
	_check(game.progress.coins == 80, "买竿扣掉 120 金")
	_check(not game.progress.buy_rod("bamboo"), "不能往回换成差竿")
	game.progress.coins = 400
	_check(game.progress.buy_rod("aurora"), "可以再升级到极光冰竿")
	_check(game.progress.rod_name() == "极光冰竿", "竿名正确")

	# --- 成就只解锁一次 ---
	_check(game.progress.unlock("first_fish"), "首次解锁成就返回 true")
	_check(not game.progress.unlock("first_fish"), "重复解锁返回 false")
	_check(game.progress.is_unlocked("first_fish"), "成就状态可查询")
	_check(game.progress.achievement_count() == 1, "成就计数正确")

	# --- 小游戏最好成绩 ---
	game.progress.record_game("chime", 40)
	var better: Dictionary = game.progress.record_game("chime", 90)
	_check(int(better["best"]) == 90 and bool(better["is_best"]), "小游戏成绩会刷新最好成绩")
	var worse: Dictionary = game.progress.record_game("chime", 30)
	_check(int(worse["best"]) == 90 and not bool(worse["is_best"]), "更低的成绩不会覆盖纪录")
	_check(game.progress.games_played() == 1, "已玩过的小游戏计数")

	# --- 存档与读档 ---
	game.progress.unlock("prism_heart")
	game.progress.unlock("keepsake_snow")
	game.progress.save()
	var coins_before: int = game.progress.coins
	var fish_before: int = game.progress.fish_count()
	var dex_before: int = game.progress.dex_count()
	var rod_before: String = game.progress.rod
	game.progress.reset()
	_check(game.progress.coins == 0 and game.progress.achievement_count() == 0, "reset 清空进度")
	game.progress.load_progress()
	_check(game.progress.coins == coins_before, "读档恢复金币")
	_check(game.progress.fish_count() == fish_before, "读档恢复图鉴")
	_check(game.progress.dex_count() == dex_before, "读档恢复图鉴鱼种数")
	_check(game.progress.rod == rod_before, "读档恢复鱼竿")
	_check(game.progress.is_unlocked("prism_heart"), "读档恢复成就")
	_check(int(game.progress.game_best.get("chime", 0)) == 90, "读档恢复小游戏纪录")

	# --- 读档后还原到世界 ---
	game.keepsakes.clear()
	game.has_prism_heart = false
	game._restore_progress()
	_check(game.keepsakes.has("snow"), "读档把纪念还原到阁楼")
	_check(game.attic.keepsake_nodes["snow"].visible, "旅行架上的纪念可见")
	_check(game.has_prism_heart, "读档还原棱镜之心")
	_check(game.attic.prism_heart.visible, "旅行架上的棱镜之心可见")

	# --- 行囊开合 ---
	game.toggle_bag()
	await process_frame
	_check(game.bag.open and game.bag_open, "B 键打开行囊")
	game.toggle_bag()
	await process_frame
	_check(not game.bag.open and not game.bag_open, "再按 B 收起行囊")

	# --- 真实交互：钓鱼进图鉴 + 解锁成就 ---
	game.enter_attic()
	await physics_frame
	game.enter_pocket("snow")
	await physics_frame
	game.progress.reset()
	var hole = game.attic_worlds.hole_anchor(0)
	game.player.global_position = (hole as Node3D).global_position
	await physics_frame
	game.start_fishing(0)
	game.fishing_timer = 0.0
	game._update_fishing(0.016)
	await physics_frame
	game.finish_fishing_catch()
	await physics_frame
	_check(game.progress.fish_count() == 1, "钓鱼会把鱼记进图鉴")
	_check(game.progress.held_count() == 1, "钓上来的鱼先进鱼篓")
	game.progress.sell_fish()
	_check(game.progress.coins > 0, "卖鱼后得到金币")
	_check(game.progress.is_unlocked("first_fish"), "首尾鱼解锁成就")
	game.leave_pocket()
	await physics_frame
	game.leave_attic()
	await physics_frame

	print("PROGRESS TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_main_test.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists("user://starward_progress_test.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_progress_test.json"))
	quit(0 if failures == 0 else 1)
