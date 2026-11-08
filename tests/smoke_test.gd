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


func _run() -> void:
	var test_save := "user://starward_smoke_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = test_save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	var old_logs: Dictionary = game.discovered.duplicate(true)
	var old_loops: int = game.loop_count
	game.discovered.clear()
	game.loop_count = 1
	_check(game.planets.size() == 10, "ten explorable bodies created (five major + five secondary)")
	_check(game.anomalies.size() == 16, "ten planetary signals plus six hidden echoes")
	_check(game.state == "menu", "main menu is initial state")
	_check(game.home.radius >= 400.0, "planets use the ten-times scale")
	_check(game.planets.back().orbit_radius >= 4000.0, "orbits are expanded to the new scale")
	var gravities := {}
	for planet in game.planets:
		gravities[planet.gravity_strength] = true
	_check(gravities.size() >= 4, "planets have distinct gravity strengths")
	_check(game.home.find_child("Architecture_Qinglan", true, false) != null, "home receives its observatory scene")
	_check(game.home.find_child("Architecture_Qinglan", true, false).find_child("BuildingCollision", true, false) != null, "landmark architecture has physical collision")
	_check(game.home.find_child("Cave_Qinglan", true, false) != null, "home hides an underground cave")
	_check(game.planets[1].find_child("Cave_Zheya", true, false) != null, "ember hides a lava cave")
	_check(game.planets[3].find_child("Cave_Xuanjing", true, false) != null, "shard hides a crystal cave")
	_check(game.planets[2].find_child("Cave_Cangbo", true, false) == null, "tide has no cave")
	_check(game.home.find_child("CaveCollision", true, false).get_child_count() > 40, "cave shell, ramp and chamber all collide")
	_check(game.home.find_child("InteriorAnomalyAnchor", true, false) != null, "observatory interior is enterable")
	_check(game.planets[2].find_child("InteriorAnomalyAnchor", true, false) != null, "tide station interior is enterable")
	_check(game.quantum != null and game.quantum.positions.size() >= 5, "quantum shard has multiple resting places")
	_check(game.sun_detail != null and game.sun_detail.get_child_count() >= 8, "sun builds a near-field prominence LOD")
	_check(game.comet.find_child("IonTail", true, false) != null and game.comet.find_child("DustTailMesh", true, false) != null, "comet keeps one ion tail and one dust tail")
	var cave = game.home.find_child("Cave_Qinglan", true, false)
	var ray_from: Vector3 = game.home.global_position + game.home.surface_position(game.home.cave_direction, 14.0)
	var ray_to: Vector3 = game.home.global_position + game.home.surface_position(game.home.cave_direction, -22.0)
	var ray_query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
	var ray_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray_query)
	_check(not ray_hit.is_empty(), "cave mouth is open through the terrain shell")
	if not ray_hit.is_empty():
		var cave_local: Vector3 = cave.global_transform.affine_inverse() * ray_hit.position
		_check(cave_local.y < -10.0, "the open mouth drops all the way to the cave floor")
	var door_from: Vector3 = cave.global_transform * Vector3(0, 1.6, 14.0)
	var door_to: Vector3 = cave.global_transform * Vector3(0, 1.6, 7.0)
	var door_query := PhysicsRayQueryParameters3D.create(door_from, door_to, 1)
	_check(game.get_world_3d().direct_space_state.intersect_ray(door_query).is_empty(), "cave doorway is walkable")
	var ramp_angle := PI * 0.5 - 0.30 + 0.15
	var ramp_from: Vector3 = cave.global_transform * Vector3(cos(ramp_angle) * 8.4, 2.5, sin(ramp_angle) * 8.4)
	var ramp_to: Vector3 = cave.global_transform * Vector3(cos(ramp_angle) * 8.4, -3.0, sin(ramp_angle) * 8.4)
	var ramp_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ramp_from, ramp_to, 1))
	_check(not ramp_hit.is_empty(), "spiral ramp starts under the doorway")
	if not ramp_hit.is_empty():
		var ramp_local: Vector3 = cave.global_transform.affine_inverse() * ramp_hit.position
		_check(ramp_local.y > -1.6, "the ramp is level with the surface at its top")
	var platform_probes := [
		[game.home, Vector3(3.2, 6.0, 3.2), 1.755, "observatory platform"],
		[game.planets[1], Vector3(6.0, 6.0, 0.0), 2.35, "ember platform"],
		[game.planets[3], Vector3(5.0, 14.0, 0.0), 10.4, "shard temple tiers"],
		[game.planets[4], Vector3(0.0, 5.0, 8.0), 1.75, "eye gate platform"],
		[game.planets[2], Vector3(8.5, 15.0, 0.0), 11.5, "tide deck"]
	]
	for probe in platform_probes:
		var planet = probe[0]
		var arch: Node3D = planet.find_child("Architecture_*", true, false)
		var from: Vector3 = arch.global_transform * probe[1]
		var to: Vector3 = arch.global_transform * (probe[1] - Vector3(0, 10.0, 0))
		var probe_query := PhysicsRayQueryParameters3D.create(from, to, 1)
		var probe_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(probe_query)
		if probe_hit.is_empty():
			_check(false, probe[3] + " has a collider")
		else:
			var local: Vector3 = arch.global_transform.affine_inverse() * probe_hit.position
			_check(absf(local.y - probe[2]) < 0.4, probe[3] + " collision matches its visible top")
	var dome_arch: Node3D = game.home.find_child("Architecture_Qinglan", true, false)
	var dome_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(dome_arch.global_transform * Vector3(0, 21, 0), dome_arch.global_transform * Vector3(0, 10, 0), 1))
	_check(not dome_hit.is_empty() and (dome_arch.global_transform.affine_inverse() * dome_hit.position).y > 12.5, "windmill cap blocks flight")
	_check(game.home.find_children("*", "StaticBody3D", true, false).size() > 30, "near-site trees and buildings create static colliders")
	var scene_count := 0
	for planet in game.planets:
		if planet.find_child("Architecture_*", true, false) != null:
			scene_count += 1
	_check(scene_count == 10, "all ten bodies receive signature architecture")
	# 次天体地标逐一点名，防止只加定义忘了接地标。
	for pair in [["baiyao", "Architecture_Baiyao"], ["pansha", "Architecture_Pansha"],
			["taiyuan", "Architecture_Taiyuan"], ["liuwu", "Architecture_Liuwu"],
			["jianmo", "Architecture_Jianmo"]]:
		var body = null
		for planet in game.planets:
			if planet.planet_id == pair[0]:
				body = planet
				break
		_check(body != null and body.find_child(pair[1], true, false) != null,
			"secondary body %s has its own landmark" % pair[0])
		_check(body != null and body.find_child("BuildingCollision", true, false) != null,
			"secondary body %s landmark is solid" % pair[0])
	_check(game.sun_radius >= 250.0, "sun is rebuilt at the new scale")
	_check(game.sky_material != null, "sky shader material is built together with the environment")
	_check(game.get("starfield_root") == null, "the 2600-quad billboard starfield is gone; stars render inside the sky shader")
	game.apply_sky("space")
	_check(is_equal_approx(float(game.sky_material.get_shader_parameter("star_density")), 1.0), "the space preset pushes its star density to the sky shader")
	game.apply_sky_detail(3)
	_check(int(game.sky_material.get_shader_parameter("sky_detail")) == 3, "the sky detail tier reaches the sky shader")
	game.apply_sky_detail(2)
	game.apply_sky("cloud")
	_check(float(game.sky_material.get_shader_parameter("sun_strength")) > 0.5, "the cloud dawn gets a sun disc in the sky")
	_check(Vector3(game.sky_material.get_shader_parameter("sun_direction")).length() > 0.99, "the sky sun direction comes from the key light as a unit vector")
	game.apply_sky("space")
	_check(float(game.sky_material.get_shader_parameter("sun_strength")) == 0.0, "open space has no sun disc; its sun is the central star mesh")

	# ── 卡冈图雅：外部导入的黑洞模型 ──────────────────────────────────
	# 它不走程序化几何那条路，所以单独钉三条：接进来了、放得足够远、发光被加亮过。
	_check(game.gargantua != null, "Gargantua is built into the world")
	if game.gargantua != null:
		_check(game.gargantua.global_position.length() > 9000.0,
			"Gargantua sits outside the ten planets' orbits (2640~9200)")
		var model_meshes := 0
		for node in game.gargantua.find_children("*", "MeshInstance3D", true, false):
			model_meshes += 1
		_check(model_meshes >= 2, "Gargantua keeps the black hole body and its accretion disk")
		_check(game.gargantua_glow_materials.size() >= 3,
			"the accretion disk glow materials are found and boosted")
		for material in game.gargantua_glow_materials:
			if material.emission_energy_multiplier <= 1.0:
				_check(false, "every boosted glow material actually got a higher emission energy")
				break
		_check(not game.gargantua.find_child("GargantuaLabel", true, false) is Label3D,
			"Gargantua has no name plate floating over the disk")
	# CC BY 4.0 要求署名必须出现在**游戏里**（导出后的 exe/网页并不带仓库文档）
	_check(load("res://assets/models/LICENSE_MANIFEST.json") != null or
		FileAccess.file_exists("res://assets/models/LICENSE_MANIFEST.json"),
		"the external-asset licence manifest ships with the game")
	var manifest := FileAccess.get_file_as_string("res://assets/models/LICENSE_MANIFEST.json")
	_check(manifest.contains("black-hole") and manifest.contains("Nestaeric"),
		"the manifest records the black hole's author for attribution")

	# ── 每个世界自己的云 ────────────────────────────────────────────
	# 上一版六个世界共用同一套 fbm，只换颜色与密度，「换个世界」其实只是同一片云
	# 换了个色调。这里逐世界读回真正推给 GPU 的参数，要求两两都不同 ——
	# 哪个世界漏了字段、或者复制粘贴时忘了改，都会立刻在这里现形。
	var signatures := {}
	var duplicated := []
	var worlds := ["space", "attic", "snow", "cloud", "firefly", "alley", "mirror", "dungeon"]
	for key in worlds:
		game.apply_sky(key)
		var sig := "%s|%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [
			str(game.sky_material.get_shader_parameter("nebula_axis")),
			str(game.sky_material.get_shader_parameter("nebula_seed")),
			float(game.sky_material.get_shader_parameter("nebula_band")),
			float(game.sky_material.get_shader_parameter("nebula_scale")),
			float(game.sky_material.get_shader_parameter("nebula_warp")),
			float(game.sky_material.get_shader_parameter("nebula_threshold")),
			float(game.sky_material.get_shader_parameter("nebula_structure")),
			float(game.sky_material.get_shader_parameter("nebula_blend")),
		]
		if signatures.has(sig):
			duplicated.append("%s 撞了 %s" % [key, signatures[sig]])
		signatures[sig] = key
	_check(duplicated.is_empty(), "every world pushes its own nebula noise basis, so no two worlds share one cloud shape%s" % (
		"" if duplicated.is_empty() else "（撞车：%s）" % ", ".join(duplicated)))

	# 白天的高空云：覆盖全天（不带子）、替换天空（不是加色）、没有银河结构
	game.apply_sky("cloud")
	_check(float(game.sky_material.get_shader_parameter("nebula_band")) <= 1.01,
		"the cloud sea drops the galactic band so its high clouds cover the whole sky")
	_check(float(game.sky_material.get_shader_parameter("nebula_blend")) > 0.5,
		"daytime clouds replace the sky instead of adding on top of it")
	_check(float(game.sky_material.get_shader_parameter("nebula_structure")) <= 0.01,
		"the cloud sea keeps no galaxy-only structures (dust lane / core / teal blob)")
	# 星空那边的星云反过来：加色、带银河结构
	game.apply_sky("space")
	_check(float(game.sky_material.get_shader_parameter("nebula_blend")) <= 0.01,
		"the space nebula stays additive")
	_check(float(game.sky_material.get_shader_parameter("nebula_structure")) > 0.99,
		"space keeps the galaxy-only structures")

	# 天色渐变的方向：天顶要暗/冷，地平线要亮/暖。
	# 着色器里这块曾经把方向写反（horizon_color 画到了天顶，zenith_color 埋到地平线以下），
	# 「上蓝下金的黎明」于是渲染成一整片金色 —— 数据面在这里再钉一次。
	var inverted := []
	for key in worlds:
		game.apply_sky(key)
		var zen: Vector3 = game.sky_material.get_shader_parameter("zenith_color")
		var hor: Vector3 = game.sky_material.get_shader_parameter("horizon_color")
		var zen_lum: float = zen.x * 0.299 + zen.y * 0.587 + zen.z * 0.114
		var hor_lum: float = hor.x * 0.299 + hor.y * 0.587 + hor.z * 0.114
		if zen_lum >= hor_lum:
			inverted.append(key)
	_check(inverted.is_empty(), "every world keeps its zenith darker than its horizon%s" % (
		"" if inverted.is_empty() else "（写反：%s）" % ", ".join(inverted)))
	_check(float(game.sky_material.get_shader_parameter("gradient_power")) > 0.0,
		"the gradient power reaches the sky shader")

	game.start_game()
	for i in range(8):
		await physics_frame
	_check(game.state == "walk", "start enters on-foot mode")
	_check(game.player.camera.current, "player camera active")
	game.player.camera.current = true
	game._update_sky_pixel_angle()
	_check(float(game.sky_material.get_shader_parameter("pixel_angle")) > 0.0, "the sky shader receives the live pixel angle, so star discs stay anti-aliased")
	var ship_distance: float = game.player.global_position.distance_to(game.ship.global_position)
	_check(ship_distance < 9.0 and ship_distance > 2.0, "player wakes beside the parked ship")
	_check(game._safe_spawn_clear(game.player.global_position, (game.player.global_position - game.home.global_position).normalized()), "spawn point is collision-free")
	var spawn_forward: Vector3 = -game.player.camera.global_transform.basis.z
	var village_world: Vector3 = game.home.global_position + game.home.surface_position(Vector3(-0.06, 1.0, -0.04).normalized(), 0.0)
	_check(spawn_forward.dot((village_world - game.player.global_position).normalized()) > 0.35, "spawn faces the observatory")
	var buried_planet = game.planets[1]
	var buried_normal: Vector3 = -buried_planet.cave_direction.normalized()
	var buried_height: float = buried_planet.terrain_height(buried_normal) - 40.0
	game.player.global_position = buried_planet.global_position + buried_normal * buried_height
	game.player.velocity = Vector3.ZERO
	game.player._escape_terrain()
	var escaped_normal: Vector3 = (game.player.global_position - buried_planet.global_position).normalized()
	var escaped_altitude: float = game.player.global_position.distance_to(buried_planet.global_position) - buried_planet.terrain_height(escaped_normal)
	_check(escaped_altitude > 0.5, "R throws a buried player back above the surface")
	_check(game._safe_spawn_clear(game.player.global_position, escaped_normal), "R escape point has no collision")
	_check(is_equal_approx(game.LOOP_DURATION, 1020.0), "the time loop runs for seventeen minutes")
	_check(game.roast != null, "marshmallow roasting rig is attached to the player camera")
	game.player.global_position = game.campfire.global_position + game.campfire.global_transform.basis.y * 2.0
	game.player.velocity = Vector3.ZERO
	game._interact()
	_check(game.roast.active, "E at the campfire starts roasting")
	game.roast.progress = 0.70
	game.player.oxygen = 10.0
	game.player.fuel = 10.0
	game.roast.finish()
	_check(not game.roast.active and game.player.oxygen >= 99.0 and game.player.fuel >= 99.0, "a golden marshmallow refills oxygen and fuel")
	game.discover("qinglan")
	_check(game.discovered.has("qinglan"), "scanning writes persistent knowledge")
	_check(game._migrate_legacy_knowledge_key("ember_cave") == "zheya_cave" and game._migrate_legacy_knowledge_key("eye") == "xuanyuan" and game._migrate_legacy_knowledge_key("qinglan") == "qinglan", "old save keys migrate to the new planet ids")
	_check(game.missing_clues().size() == 3, "eye begins with three missing coordinates")
	game.discovered["zheya"] = true
	game.discovered["cangbo"] = true
	game.discovered["xuanjing"] = true
	_check(game.missing_clues().is_empty(), "three prism coordinates unlock eye")
	game.toggle_map()
	_check(game.map_open, "star map opens")
	game.toggle_map()
	game.toggle_journal()
	_check(game.journal_open and game.paused, "journal pauses exploration")
	game.toggle_journal()
	_check(not game.journal_open and not game.paused, "journal closes cleanly")
	game.state = "ship"
	game.ship.camera.current = true
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	game.ship._unhandled_input(wheel)
	_check(game.ship.zoom > 1.0, "mouse wheel zooms the ship camera")
	game.ship._physics_process(0.2)
	_check(game.ship.camera.fov < 72.0, "ship zoom narrows the camera field of view")
	for i in range(40):
		game.ship._unhandled_input(wheel)
	_check(is_equal_approx(game.ship.zoom, 16.0), "ship zoom caps at 16x")
	game.ship._physics_process(1.0)
	_check(game.ship.camera.fov < 6.0, "16x zoom is a real telephoto view")
	game.state = "walk"
	game.player.focus = true
	for i in range(40):
		game.player._unhandled_input(wheel)
	_check(is_equal_approx(game.player.scope_zoom, 8.0), "signal scope wheel zoom caps at 8x")
	_check(game.player.scope_magnification() >= 16.0, "signal scope reaches 16x magnification")
	game.player._physics_process(0.5)
	_check(game.player.camera.fov < 6.0, "signal scope narrows the camera field of view")
	game.player.focus = false
	game.player.scope_zoom = 1.0
	game.state = "ship"
	game.ship.zoom = 1.0
	game.ship.camera.fov = 72.0
	game.ship.takeoff()
	_check(not game.ship.landed and game.ship.velocity.length() > 0.0, "ship takes off with outward velocity")
	game.ship.velocity = Vector3.ZERO
	Input.action_press("jump")
	game.ship._physics_process(0.2)
	_check(game.ship.velocity.dot(game.ship.global_transform.basis.y.normalized()) > 1.0, "Space applies upward thrust")
	Input.action_release("jump")
	var descend_key := InputEventKey.new()
	descend_key.physical_keycode = KEY_C
	_check(InputMap.action_has_event("thrust_down", descend_key), "C is an alternate descend key")
	game.ship.global_position = game.home.global_position + game.home.surface_position(Vector3.UP, 20.0)
	game.ship.velocity = Vector3.ZERO
	game.ship.try_land()
	_check(game.ship.landed and game.ship.landed_planet == game.home, "ship auto-lands near a landmark at 20m altitude")
	game.exit_ship()
	var exit_normal: Vector3 = (game.player.global_position - game.home.global_position).normalized()
	_check(game.state == "walk" and game.player.visible, "player exits landed ship")
	_check(game._safe_spawn_clear(game.player.global_position, exit_normal), "ship exit chooses a collision-free position")
	game.discover("xuanyuan")
	_check(game.state == "end", "eye signal completes narrative arc")
	game.continue_after_end()
	_check(game.state in ["walk", "ship"], "free exploration continues after ending")
	# ── 开发者模式：F3 连按 5 次开启，开启后 F4 直达宇宙线结局 ──────────
	game.dev_mode = false
	game.dev_overlay_visible = true
	game._dev_taps = 0
	var dev_tap := InputEventKey.new()
	dev_tap.physical_keycode = KEY_F3
	dev_tap.pressed = true
	for _tap in range(4):
		game._unhandled_input(dev_tap)
	_check(not game.dev_mode, "developer mode stays closed after four F3 taps")
	game._unhandled_input(dev_tap)
	_check(game.dev_mode, "five consecutive F3 taps open developer mode")
	_check(game.hud.dev_panel != null, "developer mode ships a performance panel")
	game.hud._process(0.016)
	_check(game.hud.dev_panel.visible, "the performance panel appears once developer mode is on")
	_check(game.hud.dev_label.text.find("FPS") >= 0 and game.hud.dev_label.text.find("显存") >= 0, "the panel reports frame rate and video memory")
	game.dev_overlay_visible = false
	game.hud._process(0.016)
	_check(not game.hud.dev_panel.visible, "F3 hides the panel again")
	game.dev_overlay_visible = true
	game.dev_mode = false
	game._dev_taps = 0
	game._unhandled_input(dev_tap)
	game._dev_tap_last_ms -= 5000
	game._unhandled_input(dev_tap)
	_check(not game.dev_mode and game._dev_taps == 1, "a long pause restarts the F3 tap count")
	var dev_ending := InputEventKey.new()
	dev_ending.physical_keycode = KEY_F4
	dev_ending.pressed = true
	game._unhandled_input(dev_ending)
	_check(game.state != "end", "F4 does nothing while developer mode is closed")
	game.dev_mode = true
	game.dev_overlay_visible = true
	game.state = "walk"
	game.paused = false
	game._unhandled_input(dev_ending)
	_check(game.state == "end" and game.end_text != "", "F4 jumps straight to the universe ending")
	game.continue_after_end()
	var dev_unlock := InputEventKey.new()
	dev_unlock.physical_keycode = KEY_F5
	dev_unlock.pressed = true
	game._unhandled_input(dev_unlock)
	_check(game.discovered.size() == game.anomalies.size(), "F5 unlocks every signal record")
	game.player.oxygen = 4.0
	game.player.fuel = 3.0
	game.ship.fuel = 2.0
	game.ship.hull = 5.0
	var dev_refill := InputEventKey.new()
	dev_refill.physical_keycode = KEY_F6
	dev_refill.pressed = true
	game._unhandled_input(dev_refill)
	_check(game.player.oxygen == 100.0 and game.ship.fuel == 100.0 and game.ship.hull == 100.0, "F6 refills suit and ship")
	var dev_nova := InputEventKey.new()
	dev_nova.physical_keycode = KEY_F7
	dev_nova.pressed = true
	game.state = "walk"
	game._unhandled_input(dev_nova)
	_check(game.state == "supernova", "F7 skips the countdown and fires the supernova")
	game._update_supernova(3.7)
	_check(game.state == "walk", "the supernova still returns to the campfire loop")
	game.dev_mode = false
	game.dev_overlay_visible = true
	game._dev_taps = 0
	game.hud._process(0.016)
	_check(not game.hud.dev_panel.visible, "closing developer mode hides the panel")
	var expected_loops: int = game.loop_count + 1
	game.reset_loop("test")
	_check(game.loop_count == expected_loops and game.state == "walk", "loop reset preserves knowledge and restores player")
	game._trigger_supernova()
	_check(game.state == "supernova", "supernova sequence starts")
	game._update_supernova(3.7)
	_check(game.state == "walk" and not game.supernova_active, "supernova returns player to campfire loop")
	game.begin_death("test burn", 1.0)
	_check(game.state == "dying", "death enters an explicit consciousness-loss sequence")
	game.death_timer = game.death_duration + 0.1
	game._process(0.0)
	_check(game.state == "walk", "death waits for the sequence before the campfire loop")
	game.state = "ship"
	game.paused = false
	game.map_open = false
	game.ship.landed = false
	game.ship.landed_planet = null
	game.ship.autopilot = false
	game.ship.global_position = Vector3(20000.0, 0.0, 0.0)
	game.ship.velocity = Vector3.ZERO
	game.ship.hull = 100.0
	game.ship.fuel = 50.0
	game.ship.fuel_empty_time = 0.0
	game.ship._physics_process(0.1)
	_check(game.state == "ship", "deep space no longer kills the ship")

	# ── 卡冈图雅的引力 ────────────────────────────────────────────────
	# 钉四点：范围外完全自由、越近越大、内圈推力顶不住、压到视界就死。
	var bh_ship = game.ship
	var hole: Vector3 = game.gargantua.global_position
	bh_ship.global_position = hole + Vector3(0.0, 0.0, bh_ship.BH_PULL_RANGE + 1500.0)
	bh_ship.velocity = Vector3.ZERO
	_check(bh_ship._black_hole_pull(0.016) == Vector3.ZERO,
		"outside the pull range the black hole does not touch the ship")
	var far_pull: float = bh_ship._black_hole_pull(0.016).length()
	bh_ship.global_position = hole + Vector3(0.0, 0.0, 1800.0)
	bh_ship.velocity = Vector3.ZERO
	var near_pull: float = bh_ship._black_hole_pull(0.016).length()
	_check(near_pull > far_pull * 8.0,
		"the black hole pulls harder the closer the ship gets")
	_check(near_pull > 150.0,
		"up close the pull beats even the boost thruster (150)")
	# 耗油：引力场外不吃额外油耗，越靠近倍率越高（同样一次点火更烧钱）。
	bh_ship.global_position = hole + Vector3(0.0, 0.0, bh_ship.BH_PULL_RANGE + 1500.0)
	bh_ship.velocity = Vector3.ZERO
	bh_ship._black_hole_pull(0.016)
	_check(is_equal_approx(bh_ship.bh_fuel_multiplier, 1.0),
		"outside the pull range thrust costs no extra propellant")
	bh_ship.global_position = hole + Vector3(0.0, 0.0, 2400.0)
	bh_ship.velocity = Vector3.ZERO
	bh_ship._black_hole_pull(0.016)
	var mid_fuel: float = bh_ship.bh_fuel_multiplier
	bh_ship.global_position = hole + Vector3(0.0, 0.0, 300.0)
	bh_ship.velocity = Vector3.ZERO
	bh_ship._black_hole_pull(0.016)
	var deep_fuel: float = bh_ship.bh_fuel_multiplier
	_check(mid_fuel > 1.4 and deep_fuel > mid_fuel * 1.4,
		"thrusting near the black hole burns noticeably more propellant")
	bh_ship.global_position = hole + Vector3(0.0, 0.0, bh_ship.BH_HORIZON - 1.0)
	bh_ship.velocity = Vector3.ZERO
	var captured: bool = bh_ship._apply_black_hole_capture(0.016)
	_check(captured and game.state == "dying",
		"crossing the horizon swallows the ship and starts the death sequence")
	# 这几条测完必须把飞船挪回引力场外、并把状态清干净，否则后面的燃料测试
	# 会在黑洞旁边跑，被牵引力拖着，读出来的数就不对了。
	bh_ship.global_position = hole + Vector3(0.0, 0.0, bh_ship.BH_PULL_RANGE + 1500.0)
	bh_ship.velocity = Vector3.ZERO
	bh_ship.bh_warn_level = 0
	bh_ship.bh_orbit_age = 0.0
	bh_ship.bh_distance = INF
	bh_ship.bh_fuel_multiplier = 1.0
	game.death_timer = 0.0
	game.state = "ship"
	game.ship.velocity = Vector3(100.0, 0.0, 0.0)
	game.ship.fuel = 50.0
	Input.action_press("brake")
	game.ship._physics_process(0.1)
	Input.action_release("brake")
	_check(game.ship.fuel < 49.95 and game.ship.velocity.length() < 100.0, "manual brake burns propellant")
	game.ship.velocity = Vector3.ZERO
	game.ship.target = game.planets[0]
	game.ship.autopilot = true
	game.ship.fuel = 0.0
	game.ship._physics_process(0.1)
	_check(not game.ship.autopilot, "autopilot stops when the tank is empty")
	game.ship.fuel = 0.0
	game.ship.fuel_empty_time = 89.5
	game.ship._physics_process(1.0)
	_check(game.state == "dying" and game.death_reason.find("推进剂") >= 0, "fuel exhaustion ends the expedition")
	game.discovered = old_logs
	game.loop_count = old_loops
	game._save_knowledge()
	print("SMOKE TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	quit(0 if failures == 0 else 1)
