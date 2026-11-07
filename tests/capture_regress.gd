extends SceneTree
# 视觉回归：把关键界面逐屏截图，存到 res://captures/regress_*.png
# 用法（窗口模式，需要真实渲染，不能 headless）：
#   godot --position -20000,-20000 --path . --script res://tests/capture_regress.gd

var game
var shots := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


## 冻结场景里的粒子。雪花/萤火/雨丝是随时间演化的，
## 不冻住的话每次截图都略有不同，基线比对会一直在阈值边缘抖。
func _freeze_particles(node: Node) -> void:
	if node is CPUParticles3D:
		var p := node as CPUParticles3D
		# 固定种子 + 重启：把它们压回同一个初始状态，再停住推进
		p.use_fixed_seed = true
		p.seed = 20261106
		p.speed_scale = 1.0
		p.restart()
		p.speed_scale = 0.0
	for child in node.get_children():
		_freeze_particles(child)


func _capture(name: String) -> void:
	_freeze_particles(root)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://captures/regress_%s.png" % name
	var err := image.save_png(path)
	if err == OK:
		shots += 1
	print("CAPTURE ", path, " -> ", error_string(err))


func _run() -> void:
	var save := "user://starward_regress.json"
	var prog := "user://starward_regress_progress.json"
	for p in [save, prog]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = prog
	root.add_child(game)
	await game.await_world_ready()
	await _frames(24)
	# 截图脚本自己驱动一切；玩家脚本每帧会抢相机朝向，会引入帧时长相关的抖动
	if game.player != null:
		game.player.set_process(false)
		game.player.set_physics_process(false)
	await _frames(4)

	# 塞一份「玩到后期」的进度，让各界面都有内容。
	# 先固定随机种子：add_fish() 会给每条鱼随机抽长度，
	# 不固定的话每次截图的「最长 Ncm」都不同，连纯 UI 面板都会有差异。
	seed(20261106)
	game.progress.reset()
	for id in ["ice-crucian", "snow-lamp", "bell-carp", "star-scale", "moon-perch",
			"aurora-trout", "cloud-ray", "galaxy-eel", "mirror-koi"]:
		game.progress.add_fish(id)
	game.progress.add_fish("ice-crucian")
	game.progress.coins = 640
	game.progress.buy_rod("brass")
	for id in ["first_fish", "three_fish", "keepsake_snow", "keepsake_cloud",
			"keepsake_forest", "keepsake_alley", "keepsake_all", "tea_full",
			"court_rest", "listening-court", "prism_heart", "dex-all", "wind_organ"]:
		game.progress.unlock(id)
	game.progress.bait_charges["glow"] = 4
	game.progress.bait_charges["star"] = 2
	game.progress.game_best = {"chime": 62, "firefly": 118, "rain": 143}
	game.progress.dungeon = {"runs": 3, "clears": 2, "best_rank": "S",
		"best_seconds": 271.0, "total_boons": 5, "flawless": true}
	game.progress.wind_heard = [true, true, true]
	game.progress.wind_solved = true
	game.progress.mirror_coins_total = 216
	game.progress.recent_runs = [
		{"seconds": 271.0, "rooms": 6, "cleared": true, "kills": 14, "hits": 0, "coins": 96, "rank": "S", "at": "2026-11-06 04:31:00"},
		{"seconds": 344.0, "rooms": 6, "cleared": true, "kills": 11, "hits": 2, "coins": 72, "rank": "A", "at": "2026-11-06 03:12:00"},
		{"seconds": 158.0, "rooms": 3, "cleared": false, "kills": 5, "hits": 4, "coins": 36, "rank": "B", "at": "2026-11-06 02:40:00"},
		{"seconds": 402.0, "rooms": 6, "cleared": true, "kills": 9, "hits": 1, "coins": 72, "rank": "A", "at": "2026-11-05 23:18:00"},
		{"seconds": 96.0, "rooms": 2, "cleared": false, "kills": 2, "hits": 5, "coins": 24, "rank": "C", "at": "2026-11-05 22:05:00"},
	]
	game.keepsakes = {"snow": true, "cloud": true, "firefly": true, "alley": true}
	game.has_prism_heart = true
	# 雪夜炉火默认第 2 档（添过一根柴）
	if game.attic_worlds != null:
		game.attic_worlds.hearth_level = 1
		game.attic_worlds._apply_hearth()

	# --- 1 主菜单 ---
	# 菜单镜头按 visual_time 绕行，帧间会动 —— 先让主循环停下来再拍
	await _frames(10)
	game.set_process(false)
	await _frames(2)
	await _capture("01_menu")
	game.set_process(true)

	# --- 2 阁楼 ---
	game.enter_attic()
	await _frames(24)
	await _capture("02_attic")

	# --- 2b 新手引导（旅人初记）---
	game.progress.guide_done = false
	game.replay_guide()
	await _frames(10)
	# 淡入进度随 delta 衰减，钉成 0 才是「完全显形」的稳定状态
	if game.guide_card != null:
		game.guide_card.fresh = 0.0
	await _capture("02b_guide_step1")
	game.guide_card.advance(1)
	await _frames(6)
	if game.guide_card != null:
		game.guide_card.fresh = 0.0
	await _capture("02c_guide_step2")
	game.guide_card.skip()
	await _frames(6)

	# --- 2c 镜牢结算画面（S 评级）---
	game.run_summary.show_summary({
		"cleared": true, "failed": false, "rank": "S", "rank_name": "无瑕",
		"rank_note": "无伤且 7 分钟内通关", "time_text": "04:31",
		"hits": 0, "kills": 14, "coins": 96, "rooms": 6, "boons": 3, "depth": 6,
		"best_rank": "S", "best_seconds": 271.0, "is_best": true, "has_best": true,
	})
	await _frames(10)
	await _capture("02d_run_summary")
	game.run_summary.close()
	await _frames(4)

	# --- 2e 窗台燕子（雨巷完成后出现在窗台）---
	game.keepsakes["alley"] = true
	game.attic.show_swallow()
	await _frames(6)
	if game.attic.swallow_node != null:
		# 取景太依赖相机节点的挂法，这里干脆把燕子挪到镜头正前方再拍。
		# 只影响这张截图，游戏里的位置不变。
		var cam_xform: Transform3D = game.player.camera.global_transform
		var ahead: Vector3 = -cam_xform.basis.z
		game.attic.swallow_node.global_position = cam_xform.origin + ahead * 2.0 + Vector3(0, -0.15, 0)
		game.attic.swallow_node.rotation.y = PI
	await _frames(8)
	await _capture("02e_attic_swallow")
	await _frames(2)

	# --- 2f 自动演示（跑到中段拍两张）---
	game.start_demo()
	if game.attic_worlds != null:
		game.attic_worlds.freeze_airship_at(0.6)
	await _frames(6)
	# 演示层每帧会自己推进 clock，截图前先停住，否则镜头位置会飘
	game.demo.clock = 6.4
	game.demo.tick(0.0)
	game.demo.clock_paused = true
	await _frames(8)
	await _capture("02f_demo_start")
	game.demo.clock = 34.0
	game.demo.tick(0.0)
	await _frames(14)
	await _capture("02g_demo_cloud")
	game.demo.clock_paused = false
	game.stop_demo()
	await _frames(6)

	# --- 3 旅行小册 ---
	game.toggle_travel_journal()
	await _frames(10)
	await _capture("03_travel_journal")
	game.toggle_travel_journal()
	await _frames(6)

	# --- 4 旅人手册（七节逐屏）---
	game.toggle_handbook()
	await _frames(10)
	for i in range(7):
		game.handbook.section = i
		game.handbook.painter.queue_redraw()
		await _frames(6)
		await _capture("04_handbook_%d" % (i + 1))
	game.toggle_handbook()
	await _frames(6)

	# --- 5 行囊四页 ---
	game.toggle_bag()
	await _frames(10)
	await _capture("05_bag_overview")
	game.bag_page_next()
	await _frames(6)
	await _capture("06_bag_dex")
	while game.bag.dex_index < game.bag.FISH_IDS.size() - 1:
		game.bag_page_next()
		await _frames(2)
	game.bag_page_next()
	await _frames(6)
	await _capture("07_bag_achievements")
	game.bag_page_next()
	await _frames(6)
	await _capture("07b_bag_runs")
	game.toggle_bag()
	await _frames(6)

	# --- 6 四个世界各一张 ---
	var world_names := {"cloud": "08_world_cloud", "firefly": "09_world_firefly",
		"alley": "10_world_alley", "snow": "11_world_snow"}
	for key in ["cloud", "firefly", "alley", "snow"]:
		game.enter_pocket(key)
		# 飞艇会巡游，冻结到固定位置，否则每次截图都不一样
		if game.attic_worlds != null:
			game.attic_worlds.freeze_airship_at(0.6)
		await _frames(22)
		await _capture(String(world_names[key]))
		# 云海：站在栈桥内侧朝云舟与浮标看，拍一张
		if key == "cloud" and game.attic_worlds.boat_node != null:
			game.attic_worlds.boat_active = false
			game.boat_seated = false
			game.attic_worlds.light_buoy(0)
			game.attic_worlds.light_buoy(2)
			var cloud_w = game.attic_worlds.world_node("cloud")
			if cloud_w != null:
				var eye: Vector3 = (cloud_w as Node3D).to_global(Vector3(4.6, 1.95, -2.2))
				var boat_w: Vector3 = (cloud_w as Node3D).to_global(
					Vector3(game.attic_worlds.boat_pos.x, 0.6, game.attic_worlds.boat_pos.y))
				game.player.global_position = eye
				game.player.look_at(boat_w, Vector3.UP)
			await _frames(14)
			await _capture("08b_cloud_boat")
			# 云桥放下 + 望远镜
			game.attic_worlds.bridge_target = 1.0
			game.attic_worlds.bridge_t = 1.0
			game.attic_worlds.update_bridge(0.0)
			await _frames(6)
			if cloud_w != null:
				var winch_anchor = game.attic_worlds.prop_anchor("cloud_winch")
				if winch_anchor != null:
					var wa: Node3D = winch_anchor
					game.player.global_position = wa.global_position + Vector3(0, 1.9, 3.4)
					game.player.look_at(wa.global_position + Vector3(0, 0.9, -2.0), Vector3.UP)
			await _frames(10)
			await _capture("08c_cloud_bridge")
			await _frames(2)
		# 雪夜：走到炉火旁拍一张（炉火三档里最亮的那档）
		if key == "snow" and game.attic_worlds != null:
			game.attic_worlds.hearth_level = 2
			game.attic_worlds._apply_hearth()
			var hearth_anchor = game.attic_worlds.prop_anchor("hearth_snow")
			if hearth_anchor != null:
				var ha: Node3D = hearth_anchor
				game.player.global_position = ha.global_position + Vector3(0.0, 1.5, 3.2)
				game.player.look_at(ha.global_position + Vector3(0, 0.9, 0), Vector3.UP)
				await _frames(12)
				await _capture("11b_snow_hearth")
		# 走进一块木牌旁，看提示
		var sign_id := "sign_%s" % key
		var anchor = game.attic_worlds.prop_anchor(sign_id)
		if anchor != null:
			game.player.global_position = (anchor as Node3D).global_position + Vector3(0, 0, 1.6)
			await _frames(10)
			await _capture(String(world_names[key]) + "_sign")
		game.leave_pocket()
		await _frames(8)

	# --- 7 冰钓收线 HUD ---
	game.enter_pocket("snow")
	await _frames(16)
	var hole = game.attic_worlds.hole_anchor(0)
	if hole != null:
		game.player.global_position = (hole as Node3D).global_position
		await _frames(6)
		game.progress.bait_charges["star"] = 2
		game.progress.switch_bait("star")
		game.start_fishing(0)
		await _frames(6)
		await _capture("12_fishing_wait")
		game.fishing_timer = 0.0
		game._update_fishing(0.016)
		game.fishing_tension = 0.45
		game.fishing_reel = 0.42
		# 涟漪相位在 HUD 的 _process 里推进，光赋值没用 —— 先停掉它再摆相位
		game.fishing_hud.set_process(false)
		game.fishing_hud.ripple = 1.25
		await _frames(8)
		await _capture("13_fishing_reel")
		game.fishing_hud.set_process(true)
		game._end_fishing("测试收尾", false)
		await _frames(4)
	game.leave_pocket()
	await _frames(8)

	# --- 8 卡冈图雅（外部导入的黑洞模型，见 assets/models/black-hole）---
	# 它离得很远（距太阳约 16000），普通机位拍不到，所以单独架一台相机拍一张。
	if game.gargantua != null:
		game.state = "capture"
		game.hud.visible = false
		var bh_cam := Camera3D.new()
		bh_cam.near = 1.0
		bh_cam.far = 200000.0
		bh_cam.fov = 55.0
		game.add_child(bh_cam)
		bh_cam.current = true
		var bh_center: Vector3 = game.gargantua.global_position
		bh_cam.global_position = bh_center + Vector3(-3000.0, 2200.0, 3200.0)
		bh_cam.look_at(bh_center, Vector3.UP)
		await _frames(12)
		await _capture("14_gargantua")
		bh_cam.queue_free()
		game.hud.visible = true

	print("REGRESS CAPTURE DONE: %d shots" % shots)
	quit(0)
