extends SceneTree
# 地面线：四扇门与镜界回廊的可进入性检查。
# 用法：godot --headless --path . --script res://tests/pocket_world_test.gd

var game
var failures := 0

## 这五个世界从阁楼的门进出；镜牢（dungeon）从镜界进、回镜界，由 dungeon_test 覆盖
const WORLD_KEYS := ["snow", "cloud", "firefly", "alley", "mirror"]


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _run() -> void:
	var test_save := "user://starward_pocket_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	game.progress_path = "user://starward_pocket_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	_check(game.attic != null, "阁楼已建造")
	_check(game.attic_worlds != null, "口袋世界容器已建造")
	if game.attic_worlds == null:
		quit(1)
		return
	_check(game.attic_worlds.worlds.size() == 6, "六个世界（四扇门 + 镜界 + 镜牢）都存在")

	# 四扇门的定义齐全
	_check(game.attic.doors.size() == 4, "阁楼有四扇门")
	var door_keys: Array = []
	for entry in game.attic.doors:
		door_keys.append(entry["key"])
	for key in ["snow", "cloud", "firefly", "alley"]:
		_check(door_keys.has(key), "门定义包含 %s" % key)

	# 进入阁楼
	game.enter_attic()
	await physics_frame
	await physics_frame
	_check(game.in_attic and not game.in_pocket(), "已进入阁楼本体")

	# 站在门前应当能识别出对应的门
	for entry in game.attic.doors:
		var anchor: Node3D = entry["anchor"]
		game.player.global_position = anchor.global_position
		await physics_frame
		_check(game.near_attic_door() == entry["key"],
			"站在 %s 门前能被识别" % entry["key"])
	# 站在镜子前
	var mirror_anchor: Node3D = game.attic.anchors.get("AtticAnchor_Mirror")
	if mirror_anchor != null:
		game.player.global_position = mirror_anchor.global_position
		await physics_frame
		_check(game.near_attic_door() == "mirror", "站在镜面前能被识别为镜界入口")

	# 逐个进入并检查
	for key in WORLD_KEYS:
		var world: Node3D = game.attic_worlds.world_node(key)
		_check(world != null, "世界 %s 节点存在" % key)
		if world == null:
			continue
		game.enter_pocket(key)
		await physics_frame
		await physics_frame
		_check(game.in_pocket() and game.pocket_key == key, "进入 %s 后状态正确" % key)
		_check(game.player.get_parent() == world, "%s：玩家已挂到该世界下" % key)
		# 出生点应当落在场地范围内。
		# 场地内容挂在 content 下（带缩放与平移），所以范围要按 content 的实际变换算，
		# 不能再写死旧的 ±13.5。
		var local: Vector3 = world.to_local(game.player.global_position)
		var content = game.attic_worlds.worlds[key].get("content")
		var half := 13.0
		var center_z := 0.0
		if content != null:
			half = 13.0 * absf((content as Node3D).scale.x)
			center_z = (content as Node3D).position.z
		var in_x: bool = absf(local.x) < half + 0.5
		var in_z: bool = local.z > center_z - half - 0.5 and local.z < center_z + half + 0.5
		_check(in_x and in_z,
			"%s：出生点在场地内（x=%.2f z=%.2f，范围 x±%.1f z[%.1f, %.1f]）"
			% [key, local.x, local.z, half, center_z - half, center_z + half])
		# 该世界必须有碰撞体与回程门
		_check(world.find_child("WorldCollision", true, false) != null, "%s：有地面与边界碰撞" % key)
		_check(world.find_child("ReturnPortal", true, false) != null, "%s：有回程门" % key)
		var ret = game.attic_worlds.return_anchor(key)
		_check(ret != null, "%s：回程锚点可取" % key)

		# 走到回程门旁边
		game.player.global_position = (ret as Node3D).global_position
		await physics_frame
		_check(game.near_pocket_return(), "%s：站在回程门前能识别" % key)

		# 回阁楼
		game.leave_pocket()
		await physics_frame
		await physics_frame
		_check(not game.in_pocket() and game.in_attic, "%s：已回到阁楼" % key)
		_check(game.player.get_parent() == game.attic, "%s：玩家重新挂回阁楼" % key)
		var back_local: Vector3 = game.attic.to_local(game.player.global_position)
		_check(absf(back_local.x) < 4.0 and absf(back_local.z) < 3.5, "%s：落点在阁楼房间内" % key)

	# 四个世界的「小事」：三处装置全拨完 → 纪念上旅行架
	var keepsake_titles := {"snow": "冰镜极光", "cloud": "云舟船灯", "firefly": "树屋萤火", "alley": "雨巷钟铃"}
	for key in ["snow", "cloud", "firefly", "alley"]:
		game.enter_pocket(key)
		await physics_frame
		_check(game.attic.keepsake_nodes.has(key), "%s：旅行架有对应托座" % key)
		_check(not (game.attic.keepsake_nodes[key] as Node3D).visible,
			"%s：纪念初始不可见" % key)
		var activated := 0
		for i in range(3):
			var anchor = game.attic_worlds.device_anchor(key, i)
			_check(anchor != null, "%s：装置 %d 有锚点" % [key, i])
			if anchor == null:
				continue
			game.player.global_position = (anchor as Node3D).global_position
			await physics_frame
			_check(game.near_world_device() == i, "%s：站在装置 %d 旁能识别" % [key, i])
			activated += 1
		_check(activated == 3, "%s：三处装置全部可交互" % key)

		# 按原作的判定把三处做到完成：
		#   雪夜 —— 三面冰镜转到同一方向（每次转一档，循环即可对齐）
		#   雨巷 —— 三只铜阀都转到竖位（0 档）
		#   云海 / 萤火 —— 各按一次
		if key == "snow":
			for i in range(3):
				var guard := 0
				while int(game.attic_worlds.device_values[key][i]) != 0 and guard < 6:
					game.activate_world_device(i)
					await physics_frame
					guard += 1
			var values: Array = game.attic_worlds.device_values[key]
			_check(int(values[0]) == int(values[1]) and int(values[1]) == int(values[2]),
				"%s：三面冰镜已转到同一方向" % key)
		elif key == "alley":
			for i in range(3):
				var guard := 0
				while int(game.attic_worlds.device_values[key][i]) != 0 and guard < 6:
					game.activate_world_device(i)
					await physics_frame
					guard += 1
			var values2: Array = game.attic_worlds.device_values[key]
			_check(int(values2[0]) == 0 and int(values2[1]) == 0 and int(values2[2]) == 0,
				"%s：三只铜阀都已对准竖位" % key)
		else:
			for i in range(3):
				game.activate_world_device(i)
				await physics_frame
		for i in range(3):
			_check(game.attic_worlds.device_done(key, i), "%s：装置 %d 已完成" % [key, i])
		_check(game.attic_worlds.devices_all_done(key), "%s：小事三处齐了" % key)
		_check(game.keepsakes.has(key), "%s：纪念「%s」已入袋" % [key, keepsake_titles[key]])
		_check((game.attic.keepsake_nodes[key] as Node3D).visible,
			"%s：旅行架上的纪念已出现" % key)
		game.leave_pocket()
		await physics_frame

	# 冰钓：三处冰洞，每钓一尾亮一盏冰灯
	game.enter_pocket("snow")
	await physics_frame
	_check(game.attic_worlds.fishing_holes.size() == 3, "雪夜有三处冰洞")
	_check(game.attic_worlds.caught_count() == 0, "冰钓初始为 0 尾")
	for i in range(3):
		var hole_anchor = game.attic_worlds.hole_anchor(i)
		_check(hole_anchor != null, "冰洞 %d 有锚点" % i)
		if hole_anchor == null:
			continue
		game.player.global_position = (hole_anchor as Node3D).global_position
		await physics_frame
		_check(game.near_fishing_hole() == i, "站在冰洞 %d 旁能下竿" % i)
		game.start_fishing(i)
		await physics_frame
		_check(game.fishing_hole == i, "冰洞 %d：已抛竿" % i)
		# 让浮标沉下去，再收杆
		game.fishing_timer = 0.0
		game._update_fishing(0.016)
		await physics_frame
		_check(game.fishing_phase == "reel", "冰洞 %d：浮标沉了，进入收线阶段" % i)
		game.finish_fishing_catch()
		await physics_frame
		_check(game.attic_worlds.hole_caught(i), "冰洞 %d：已钓上一尾" % i)
		_check(game.attic_worlds.caught_count() == i + 1, "冰灯亮到 %d 盏" % (i + 1))
	_check(game.fishing_caught == 3, "三盏冰灯全亮")
	game.leave_pocket()
	await physics_frame

	# 镜界的棱镜之心
	_check(not game.attic.prism_heart.visible, "旅行架上的棱镜之心初始不可见")
	game.enter_pocket("mirror")
	await physics_frame
	var heart_anchor = game.attic_worlds.heart_anchor("mirror")
	_check(heart_anchor != null, "镜界有棱镜之心锚点")
	if heart_anchor != null:
		game.player.global_position = (heart_anchor as Node3D).global_position
		await physics_frame
		_check(game.near_prism_heart(), "站在棱镜之心旁能识别")
		game.take_prism_heart()
		await physics_frame
		_check(game.has_prism_heart, "棱镜之心已取到")
		_check(game.attic.prism_heart.visible, "旅行架上的棱镜之心已出现")
		var heart = game.attic_worlds.heart_node("mirror")
		_check(heart != null and not (heart as Node3D).visible, "镜界里的原件已消失")

	# 离开阁楼回到飞船
	game.leave_pocket()
	await physics_frame
	game.leave_attic()
	await physics_frame
	_check(not game.in_attic, "可以离开阁楼回太阳系")

	print("POCKET WORLD TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	if FileAccess.file_exists("user://starward_pocket_progress.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_pocket_progress.json"))
	quit(0 if failures == 0 else 1)
