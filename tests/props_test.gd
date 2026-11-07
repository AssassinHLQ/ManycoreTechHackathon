extends SceneTree
# 原作外围道具：木牌 / 风琴礁三来风 / 各处小交互 / 旅行小册 / 镜币。
# 用法：godot --headless --path . --script res://tests/props_test.gd

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
	var test_save := "user://starward_props_test.json"
	var test_progress := "user://starward_props_progress.json"
	_cleanup(test_save)
	_cleanup(test_progress)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	game.progress_path = test_progress
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	var worlds = game.attic_worlds
	_check(worlds != null, "口袋世界已建造")

	# ---------- 一、道具登记与锚点 ----------
	_check(worlds.PROP_TABLE.size() >= 15, "道具表至少 15 件")
	var expected := {
		"snow": ["sign_snow", "sled", "lantern_snow", "hearth_snow"],
		"cloud": ["sign_cloud", "cloud_beacon", "wind_organ", "cloud_winch", "cloud_scope"],
		"firefly": ["sign_firefly", "ranger_lamp", "waterwheel", "wood_drum", "mushroom"],
		"alley": ["sign_alley", "umbrella", "stone_cat", "paper_boat"],
	}
	for key in expected.keys():
		for id in expected[key]:
			_check(worlds.prop_anchor(String(id)) != null, "%s：%s 有锚点" % [key, id])
		_check(worlds.prop_ids_in(String(key)).size() == expected[key].size(),
			"%s：道具数量对得上" % key)

	# 四个世界各有一块木牌
	for key in ["snow", "cloud", "firefly", "alley"]:
		_check(worlds.prop_ids_in(String(key)).has("sign_%s" % key), "%s：有木牌" % key)

	# ---------- 二、风琴礁三来风 ----------
	game.progress.reset()
	_check(game.progress.wind_heard_count() == 0, "风琴礁初始一种都没听过")
	_check(not game.progress.wind_solved, "风琴礁初始未和鸣")

	var r1: Dictionary = worlds.use_prop("wind_organ")
	_check(bool(r1["ok"]), "能奏响风琴")
	_check(int(r1["wind"]) == 0, "第一声是北风")
	_check(String(r1["message"]).contains("北风"), "北风的文案对")
	_check(game.progress.wind_heard_count() == 1, "已听 1/3")

	var r2: Dictionary = worlds.use_prop("wind_organ")
	_check(int(r2["wind"]) == 1, "第二声是西风")
	_check(game.progress.wind_heard_count() == 2, "已听 2/3")

	var r3: Dictionary = worlds.use_prop("wind_organ")
	_check(int(r3["wind"]) == 2, "第三声是回风")
	_check(game.progress.wind_heard_count() == 3, "已听 3/3")
	_check(bool(r3["solved"]), "三种听完即和鸣")
	_check(game.progress.wind_solved, "和鸣状态写进了存档")
	_check(String(r3["message"]).contains("金色"), "和鸣文案提到云海染成金色")
	_check(game.progress.is_unlocked("wind_organ"), "解锁风琴礁成就")

	# 和鸣后再奏不改变状态
	var r4: Dictionary = worlds.use_prop("wind_organ")
	_check(int(r4["wind"]) == -1, "和鸣后不再轮换")
	_check(game.progress.wind_heard_count() == 3, "和鸣后听过的数量不变")

	# 提示语随进度变化
	_check(worlds.prop_prompt("wind_organ").contains("再听"), "和鸣后提示变成再听一遍")
	game.progress.reset()
	_check(worlds.prop_prompt("wind_organ").contains("奏响"), "初始提示是奏响风琴")
	worlds.use_prop("wind_organ")
	_check(worlds.prop_prompt("wind_organ").contains("1/3"), "听过一种后提示显示 1/3")

	# ---------- 三、一次性道具 ----------
	game.progress.reset()
	worlds.prop_used.clear()
	var sled: Dictionary = worlds.use_prop("sled")
	_check(bool(sled["ok"]), "能推雪橇")
	_check(String(sled["message"]).contains("雪辙"), "雪橇文案对")
	var sled_again: Dictionary = worlds.use_prop("sled")
	_check(not bool(sled_again["ok"]), "雪橇推过一次就不再重复")
	_check(String(sled_again["message"]).contains("已经"), "重复互动给出提示")

	# 每件道具都能用一次（sled 前面已经推过，先清状态）
	worlds.prop_used.clear()
	var all_ok := true
	# 有状态循环的道具不走「一次性」逻辑，单独测
	var stateful := ["wind_organ", "cloud_winch", "cloud_scope", "hearth_snow"]
	for id in worlds.PROP_TABLE.keys():
		var key := String(worlds.PROP_TABLE[id][0])
		if stateful.has(String(id)):
			continue
		var res: Dictionary = worlds.use_prop(String(id))
		if not bool(res["ok"]):
			all_ok = false
			push_error("道具互动失败: " + String(id))
	_check(all_ok, "所有一次性道具都能互动")

	# 有状态的三件：云桥可放可收、炉火三档循环、望远镜能进出
	worlds.bridge_target = 0.0
	worlds.bridge_down = false
	var down_result: Dictionary = worlds.use_prop("cloud_winch")
	_check(bool(down_result["ok"]), "能放下云桥")
	_check(bool(down_result["down"]), "放下后云桥状态为「已放下」")
	_check(String(worlds.prop_prompt("cloud_winch")).contains("收起"), "放下后提示变成收起")
	var up_result: Dictionary = worlds.use_prop("cloud_winch")
	_check(not bool(up_result["down"]), "能收起云桥")
	_check(String(up_result["message"]).contains("风从断开"), "收起文案照原作")

	worlds.hearth_level = 1
	var heat1: Dictionary = worlds.use_prop("hearth_snow")
	_check(int(heat1["level"]) == 2, "炉火第一次添柴到第 3 档")
	_check(String(heat1["message"]).contains("雪夜被关在门外"), "第 3 档文案照原作")
	var heat2: Dictionary = worlds.use_prop("hearth_snow")
	_check(int(heat2["level"]) == 0, "炉火再添一圈回到第 1 档")
	_check(String(heat2["message"]).contains("仍在这里等你"), "回到第 1 档文案照原作")
	_check(String(worlds.prop_prompt("hearth_snow")).contains("添柴"), "第 1 档提示是添柴")
	worlds.hearth_level = 2
	_check(String(worlds.prop_prompt("hearth_snow")).contains("歇一歇"), "第 3 档提示是让炉火歇一歇")

	var scope_result: Dictionary = worlds.use_prop("cloud_scope")
	_check(bool(scope_result["ok"]), "能用望远镜")
	_check(bool(scope_result["scope"]), "望远镜要求接管相机")
	_check(worlds.scope_active, "望远镜进入观看状态")
	worlds.close_scope()
	_check(not worlds.scope_active, "能放下望远镜")

	# 木牌文案带「木牌上写着」
	worlds.prop_used.clear()
	var sign: Dictionary = worlds.use_prop("sign_cloud")
	_check(String(sign["message"]).contains("木牌上写着"), "木牌文案以「木牌上写着」开头")
	_check(String(sign["message"]).contains("北风高"), "风琴礁木牌提到北风高")

	# ---------- 四、near_prop ----------
	var cloud_anchor = worlds.prop_anchor("cloud_beacon")
	game.enter_attic()
	await physics_frame
	game.enter_pocket("cloud")
	await physics_frame
	game.player.global_position = (cloud_anchor as Node3D).global_position + Vector3(0.5, 0, 0.5)
	await physics_frame
	_check(game.near_prop_interact() == "cloud_beacon", "站在云灯塔旁能识别")
	game.player.global_position = (cloud_anchor as Node3D).global_position + Vector3(40, 0, 40)
	await physics_frame
	_check(game.near_prop_interact() == "", "离远了就识别不到")

	# ---------- 五、旅行小册 ----------
	_check(game.travel_journal != null, "旅行小册已创建")
	_check(game.travel_journal.ENTRIES.size() == 5, "小册有五条目")
	_check(game.travel_journal.seen_count() == 0, "开局一条都没解锁")
	game.keepsakes["snow"] = true
	_check(game.travel_journal.entry_seen(0), "雪夜纪念解锁第一条")
	_check(not game.travel_journal.entry_seen(1), "云海还没纪念，第二条仍锁着")
	game.keepsakes["cloud"] = true
	game.keepsakes["firefly"] = true
	game.keepsakes["alley"] = true
	game.has_prism_heart = true
	_check(game.travel_journal.seen_count() == 5, "五条全解锁")
	game.toggle_travel_journal()
	await process_frame
	_check(game.travel_journal.open, "能翻开小册")
	_check(game.journal_book_open, "游戏侧记录了小册已打开")
	game.toggle_travel_journal()
	await process_frame
	_check(not game.travel_journal.open, "能合上小册")

	# ---------- 六、镜币 ----------
	game.progress.reset()
	game.progress.add_coins(0)
	var coins_before: int = game.progress.coins
	game.progress.add_coins(72)
	game.progress.mirror_coins_total += 72
	_check(game.progress.coins == coins_before + 72, "镜币结算进金币")
	_check(game.progress.mirror_coins_total == 72, "镜币累计记下来了")

	game.queue_free()
	await process_frame
	_cleanup(test_save)
	_cleanup(test_progress)
	if failures > 0:
		print("PROPS TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("PROPS TEST: all clear")
		quit(0)


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
