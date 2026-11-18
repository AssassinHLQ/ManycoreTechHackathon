extends CharacterBody3D

var game
var camera: Camera3D
var lamp: SpotLight3D
const MAX_FUEL := 200.0
var fuel := MAX_FUEL
var oxygen := 100.0
var focus := false
var scope_zoom := 1.0
const SCOPE_BASE_FOV := 35.0
const SCOPE_MAX_ZOOM := 8.0
const SCOPE_BLACK_HOLE_CLIP_NEAR := 30.0
const SCOPE_BLACK_HOLE_MIN_DISTANCE := 10000.0
var mouse_sensitivity := 0.0022
const WEB_LOOK_SCALE := 0.5
var bob_time := 0.0
var last_grounded := false
var blocked_time := 0.0
var blocked_hint_cooldown := 0.0
## 当前所处环境的「世界尺度」。星球表面 = planet.prop_scale（现在 5），
## 站内 / 阁楼这类手工空间 = 1.0。
##
## ⚠ 2026-11-11 用户选了 B 方案：建筑、洞穴、树石全部按 prop_scale ×5 放大，
##   而玩家一直是 8.5 m/s 的人类速度 —— 于是走进一栋 65 米高的塔要 30 秒，
##   walk_test 的「进出门」三条断言全部翻红（局部走了不到 1 米）。
##   所以人也要按同一比例变大：跑得更快、跳得更高、胶囊更大。
##   这样「相对建筑」的手感和放大前一模一样。
var body_scale := 1.0
var _body_collision: CollisionShape3D
var _body_capsule: CapsuleShape3D
var _body_scaled_once := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 9
	floor_snap_length = 0.55
	floor_max_angle = deg_to_rad(82.0)
	safe_margin = 0.025
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# 基准尺寸（body_scale = 1 时的人类尺度）。实际值在 _physics_process 里
	# 按所处环境的 body_scale 更新，见 _apply_body_scale()。
	capsule.radius = 0.34
	capsule.height = 1.65
	collision.shape = capsule
	collision.position.y = 0.82
	add_child(collision)
	_body_collision = collision
	_body_capsule = capsule

	camera = Camera3D.new()
	camera.position.y = 1.48
	camera.fov = 74.0
	camera.near = 0.07
	# ⚠ 2026-11-11 轨道 ×10：最远天体到相机约 20 万米，60000 会把远轨道裁掉。
	camera.far = 400000.0
	add_child(camera)
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0.18, -0.12, 0.0)
	lamp.spot_range = 38.0
	lamp.spot_angle = 48.0
	lamp.light_energy = 2.0
	lamp.light_color = Color("d8edff")
	lamp.visible = false
	camera.add_child(lamp)


func _unhandled_input(event: InputEvent) -> void:
	if game.state != "walk" or game.paused or game.map_open:
		focus = false
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Web 的鼠标位移会被乘以 devicePixelRatio；screen_relative 在 4.7 里与 relative 相同。
		var look_delta: Vector2 = event.relative
		if OS.has_feature("web"):
			look_delta = look_delta / maxf(1.0, DisplayServer.screen_get_scale()) * WEB_LOOK_SCALE
		apply_look(look_delta)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		focus = event.pressed
		if not focus:
			scope_zoom = 1.0
	elif event is InputEventMouseButton and event.pressed and focus:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scope_zoom = clampf(scope_zoom * 1.18, 1.0, SCOPE_MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scope_zoom = clampf(scope_zoom / 1.18, 1.0, SCOPE_MAX_ZOOM)
	elif event.is_action_pressed("lamp"):
		toggle_lamp()
	elif event.is_action_pressed("unstuck"):
		_escape_terrain()


func apply_look(relative: Vector2) -> void:
	if game.state != "walk" or game.paused or game.map_open:
		return
	relative = relative.limit_length(120.0)
	var sensitivity: float = mouse_sensitivity * _sensitivity_multiplier()
	rotate_object_local(Vector3.UP, -relative.x * sensitivity)
	camera.rotation.x = clampf(camera.rotation.x - relative.y * sensitivity, -1.48, 1.48)


func toggle_lamp() -> void:
	lamp.visible = not lamp.visible


func scope_magnification() -> float:
	return 74.0 / SCOPE_BASE_FOV * scope_zoom


func _target_is_in_camera_view(target: Vector3) -> bool:
	var viewport := camera.get_viewport()
	var view_size: Vector2i = viewport.size
	if view_size.y <= 0:
		return false
	var local: Vector3 = camera.global_transform.affine_inverse() * target
	var depth := -local.z
	if depth <= camera.near:
		return false
	var half_height := tan(deg_to_rad(camera.fov * 0.5))
	var half_width := half_height * float(view_size.x) / float(view_size.y)
	return absf(local.x) <= depth * half_width and absf(local.y) <= depth * half_height


func _update_scope_clip_distance() -> void:
	var near_distance := 0.07
	if focus and scope_zoom >= 4.0 and game.gargantua != null:
		var target: Vector3 = game.gargantua.global_position
		var target_distance := camera.global_position.distance_to(target)
		if target_distance >= SCOPE_BLACK_HOLE_MIN_DISTANCE and _target_is_in_camera_view(target):
			near_distance = SCOPE_BLACK_HOLE_CLIP_NEAR
	camera.near = near_distance


func _physics_process(delta: float) -> void:
	_update_scope_clip_distance()
	if game.state != "walk" or game.paused or game.supernova_active:
		_set_jetpack_audio(false)
		return
	if game.map_open or game.minigame_open or game.bag_open:
		_set_jetpack_audio(false)
		return
	var in_station: bool = game.in_station and game.station != null
	var planet = null
	var normal := Vector3.UP
	var altitude := 0.0
	var gravity_strength := 0.0
	if game.in_attic and game.attic != null:
		# 地面线：阁楼是固定房间，重力与朝向直接取房间自身；
		# 门后面那些小世界是平地，直接用世界坐标的上。
		normal = Vector3.UP if game.in_pocket() else game.attic.up_direction()
		gravity_strength = game.ATTIC_GRAVITY
	elif in_station:
		normal = game.station.up_direction()
		gravity_strength = game.station.artificial_gravity
	else:
		planet = game.nearest_planet(global_position)
		var offset: Vector3 = position if get_parent() == planet else global_position - planet.global_position
		normal = offset.normalized()
		if normal.length_squared() < 0.5:
			normal = global_transform.basis.y
		altitude = offset.length() - planet.radius
		gravity_strength = planet.gravity_strength
	_align_up(normal)
	up_direction = normal
	# 星球表面按星球尺度放大，室内（站内 / 阁楼）保持人类尺度。
	var wanted_scale := 1.0
	if not in_station and not game.in_attic and planet != null:
		wanted_scale = planet.prop_scale if planet.prop_scale > 0.0 else 1.0
	_apply_body_scale(wanted_scale)
	# 行星父节点已携带角色；再继承 StaticBody 的平台速度会在离开三角面时
	# 重复叠加公转位移。未挂在行星下的独立移动平台仍使用引擎默认跟随。
	platform_floor_layers = 0 if planet != null and get_parent() == planet else 0xffffffff

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish: Vector3 = global_transform.basis * Vector3(input.x, 0.0, input.y)
	wish = (wish - normal * wish.dot(normal)).normalized()
	# 速度按 body_scale 缩放：世界大 5 倍，人相对也要跑 5 倍快，
	# 才能维持「相对建筑」的原手感。
	var speed := 8.5 * body_scale
	if Input.is_action_pressed("thrust_down"):
		speed = 15.5 * body_scale
	if focus:
		speed = 4.0 * body_scale
	var vertical_speed := velocity.dot(normal)
	var horizontal := velocity - normal * vertical_speed
	horizontal = horizontal.move_toward(wish * speed,
		delta * (34.0 if is_on_floor() else 12.0) * body_scale)

	if is_on_floor():
		if vertical_speed < 0.0 or (planet != null and vertical_speed < 0.01):
			vertical_speed = -0.8
		if Input.is_action_just_pressed("jump"):
			# ⚠ 起跳也跟喷气保持一致：乘 sqrt(body_scale) 而不是 body_scale。
			#   旧版 9.5 × 5 = 47.5 m/s（170 km/h）—— 单按一下空格就是弹射。
			#   现在 9.5 × 2.24 ≈ 21 m/s，跳起高度约 4.6 米（1g 下），
			#   正好够翻过一架楼梯、跳上小平台，不会一按就上云。
			vertical_speed = 9.5 * sqrt(maxf(body_scale, 0.001))
		fuel = minf(MAX_FUEL, fuel + delta * 14.0)
	else:
		if in_station or game.in_attic:
			# 站内与阁楼都是室内：恒定重力，不做随高度衰减。
			vertical_speed -= gravity_strength * delta
		else:
			vertical_speed -= clampf(gravity_strength * (1.0 - altitude / (planet.radius * 0.55)), 1.0, gravity_strength) * delta

	var jetting := false
	if Input.is_action_pressed("jetpack") and fuel > 0.0 and not game.map_open:
		# ⚠ 2026-11-13 修「稍微按一下喷气就飞这么高」（用户原话）。
		#
		#   旧版把加速度和速度上限**都**乘了 body_scale（星球上 = 5）：
		#     加速度 46 × 5 = 230 m/s²（比地球重力还大 23 倍）
		#     上限   17 × 5 =  85 m/s（306 km/h）
		#   结果按住 0.37 秒就顶到上限，一按就窜天。
		#
		#   现在：
		#     · 加速度**不乘**（46 m/s²，约 5 倍地球重力，手感跟站内一致）
		#     · 上限乘 sqrt(body_scale) = ×2.24 → 38 m/s，跟 5 倍大的建筑尺度配得上
		#   按住 1 秒约飞 38 米，既跟得上地面移动速度（8.5 × 5 = 42.5），
		#   又不会一按就脱离视野。
		var jet_cap: float = 17.0 * sqrt(maxf(body_scale, 0.001))
		vertical_speed += 46.0 * delta
		vertical_speed = minf(vertical_speed, jet_cap)
		fuel = maxf(0.0, fuel - delta * (18.0 + gravity_strength * 0.22))
		jetting = true
	velocity = horizontal + normal * vertical_speed
	# 站内玩家已经由父节点携带。大世界坐标下 move_and_slide 的全局坐标往返
	# 会把毫米级舍入误差逐帧累积成侧向漂移；无水平移动且接地时保留局部 X/Z。
	var hold_station_position: bool = in_station and get_parent() == game.station \
		and horizontal.length_squared() < 0.000001 \
		and vertical_speed <= 0.0 and not jetting
	var was_grounded := is_on_floor()
	var hold_planet_position: bool = planet != null and get_parent() == planet \
		and horizontal.length_squared() < 0.000001 \
		and vertical_speed <= 0.0 and not jetting
	var local_before := position
	var before_move := global_position
	move_and_slide()
	# 无输入接地时沿用控制器算出的减速速度，避免碰撞把竖直分量投影成
	# 新的侧向/向上速度。正常松键减速继续生效，起跳和喷气不受影响。
	if planet != null and get_parent() == planet and is_on_floor() \
		and input.length_squared() < 0.000001 and not jetting \
		and vertical_speed <= 0.0 and not Input.is_action_just_pressed("jump"):
		velocity = horizontal
	if hold_station_position and (was_grounded or is_on_floor()):
		position.x = local_before.x
		position.z = local_before.z
	# 星球上的静止角色同样由父节点携带。只有前后都接地才保持局部站位，
	# 避免远轨道凹面碰撞网格的世界坐标舍入导致恢复推挤；离地和起跳照常求解。
	if hold_planet_position and was_grounded and is_on_floor():
		position = local_before
		velocity = Vector3.ZERO
	var moved_distance := global_position.distance_to(before_move)
	blocked_hint_cooldown = maxf(0.0, blocked_hint_cooldown - delta)
	if wish.length_squared() > 0.01 and moved_distance < 0.012:
		blocked_time += delta
	else:
		blocked_time = maxf(0.0, blocked_time - delta * 2.0)
	if blocked_time > 1.4 and blocked_hint_cooldown <= 0.0:
		game.hud.show_toast("移动受阻 · 按 R 脱离卡点", 2.2)
		blocked_hint_cooldown = 7.0
		blocked_time = 0.0

	# ── 氧气与喷气燃料的补给规则（用户 2026-11-11）──────────────────
	#
	# 用户原话：「人在飞机旁边不能回复氧气和喷气，必须进入飞机才回满」
	#
	# ⚠ 旧版是「距飞船 9 米内就 +18/s 回氧」—— 于是站在船边也能一直回氧。
	#   现在改成两档：
	#     · 站内 / 阁楼 / 篝火边：仍然回氧（这些是「安全屋」性质）
	#     · **飞船旁不再回氧**，只有真正上船（state == "ship"）才回满
	#       （上船那一刻由 main.gd 的 enter_ship 一次性灌满）
	var safe_zone: bool = in_station or game.in_attic \
			or global_position.distance_to(game.campfire.global_position) < 6.0
	if safe_zone:
		oxygen = minf(100.0, oxygen + delta * 18.0)
	else:
		oxygen = maxf(0.0, oxygen - delta * 0.22)
	if oxygen <= 0.0:
		game.die("宇航服氧气耗尽")
	elif global_position.length() < game.sun_radius + 1.0:
		game.begin_death("你坠入了恒星", 4.2)

	var target_fov := maxf(SCOPE_BASE_FOV / scope_zoom, 4.0) if focus else 74.0
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 9.0))
	var planar_speed := horizontal.length()
	if is_on_floor() and planar_speed > 0.5 * body_scale:
		bob_time += delta * planar_speed / maxf(body_scale, 0.001) * 1.25
	camera.position.y = (1.48 + sin(bob_time) * minf(planar_speed / (8.5 * body_scale), 1.0) * 0.035) * body_scale
	_set_jetpack_audio(jetting)


func _set_jetpack_audio(active: bool) -> void:
	if game != null and game.audio != null:
		game.audio.set_jetpack(active)


## 把胶囊与「贴地/台阶」相关的容差按 body_scale 重设。
## 只在数值真的变了的时候写一次，避免每帧改碰撞体（会让物理服务器反复重建）。
func _apply_body_scale(wanted: float) -> void:
	if is_equal_approx(wanted, body_scale) and _body_scaled_once:
		return
	body_scale = maxf(wanted, 0.01)
	_body_scaled_once = true
	if _body_capsule != null and _body_collision != null:
		_body_capsule.radius = 0.34 * body_scale
		_body_capsule.height = 1.65 * body_scale
		_body_collision.position.y = 0.82 * body_scale
	# 贴地吸附随角色大小变化；碰撞恢复余量保持基准值。
	# 放大 safe_margin 会让远轨道凹面地形提前恢复推挤，造成接地闪断和侧向跳动。
	floor_snap_length = 0.55 * body_scale
	safe_margin = 0.025


func _sensitivity_multiplier() -> float:
	if game != null and game.settings != null:
		return game.settings.sensitivity_multiplier()
	return 1.0


func _align_up(normal: Vector3) -> void:
	var transform := global_transform
	var current_up := transform.basis.y.normalized()
	if current_up.dot(normal) < 0.9999:
		var rotation_to_surface := Quaternion(current_up, normal)
		transform.basis = (Basis(rotation_to_surface) * transform.basis).orthonormalized()
		global_transform = transform


func _escape_terrain() -> void:
	if game.in_station and game.station != null:
		var spawn: Transform3D = game.station.interior_spawn_transform()
		global_transform = spawn
		velocity = Vector3.ZERO
		game.hud.show_toast("已回到归航站气闸", 2.0)
		return
	var planet = game.nearest_planet(global_position)
	var offset: Vector3 = global_position - planet.global_position
	var normal: Vector3 = offset.normalized() if offset.length_squared() > 0.01 else global_transform.basis.y.normalized()
	var altitude: float = offset.length() - planet.terrain_height(normal)

	if altitude < -2.0:
		var cave_root = planet.find_child("Cave_*", true, false)
		if cave_root != null and global_position.distance_to(cave_root.global_position) < 260.0:
			for height in [-12.0, -9.0, -15.0]:
				var cave_candidate: Vector3 = cave_root.global_transform * Vector3(0, height, 0)
				if game._safe_spawn_clear(cave_candidate, normal):
					global_position = cave_candidate
					velocity = Vector3.ZERO
					game.hud.show_toast("已回到洞室地面", 2.2)
					return
		global_position = game.find_safe_surface_position(planet, normal)
		velocity = normal * 0.5
		game.hud.show_toast("已从星体内部脱出 · 回到地表", 2.6)
		return

	var right: Vector3 = normal.cross(Vector3.FORWARD)
	if right.length_squared() < 0.01:
		right = normal.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward: Vector3 = normal.cross(right).normalized()
	for radius in [1.5, 3.0, 4.5, 6.0]:
		for step in range(8):
			var angle := TAU * float(step) / 8.0
			var candidate: Vector3 = global_position + (right * cos(angle) + forward * sin(angle)) * radius
			var candidate_normal: Vector3 = (candidate - planet.global_position).normalized()
			var candidate_altitude: float = candidate.distance_to(planet.global_position) - planet.terrain_height(candidate_normal)
			if candidate_altitude < 0.8:
				continue
			if game._safe_spawn_clear(candidate, candidate_normal):
				global_position = candidate
				velocity = Vector3.ZERO
				game.hud.show_toast("已避开卡点", 2.0)
				return

	global_position = game.find_safe_surface_position(planet, normal)
	velocity = normal * 0.5
	game.hud.show_toast("检测到地形卡死，已自动脱困 · R 可手动脱困", 2.5)
