extends CharacterBody3D

var game
var camera: Camera3D
var lamp: SpotLight3D
var fuel := 100.0
var oxygen := 100.0
var focus := false
var scope_zoom := 1.0
const SCOPE_BASE_FOV := 35.0
const SCOPE_MAX_ZOOM := 8.0
var mouse_sensitivity := 0.0022
const WEB_LOOK_SCALE := 0.5
var bob_time := 0.0
var last_grounded := false
var blocked_time := 0.0
var blocked_hint_cooldown := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.55
	floor_max_angle = deg_to_rad(82.0)
	safe_margin = 0.025
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.65
	collision.shape = capsule
	collision.position.y = 0.82
	add_child(collision)

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


func _physics_process(delta: float) -> void:
	if game.state != "walk" or game.paused or game.supernova_active:
		return
	if game.map_open or game.minigame_open or game.bag_open:
		game.audio.set_jetpack(false)
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
		var offset: Vector3 = global_position - planet.global_position
		normal = offset.normalized()
		if normal.length_squared() < 0.5:
			normal = global_transform.basis.y
		altitude = offset.length() - planet.radius
		gravity_strength = planet.gravity_strength
	_align_up(normal)
	up_direction = normal

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish: Vector3 = global_transform.basis * Vector3(input.x, 0.0, input.y)
	wish = (wish - normal * wish.dot(normal)).normalized()
	var speed := 8.5
	if Input.is_action_pressed("thrust_down"):
		speed = 15.5
	if focus:
		speed = 4.0
	var vertical_speed := velocity.dot(normal)
	var horizontal := velocity - normal * vertical_speed
	horizontal = horizontal.move_toward(wish * speed, delta * (34.0 if is_on_floor() else 12.0))

	if is_on_floor():
		if vertical_speed < 0.0:
			vertical_speed = -0.8
		if Input.is_action_just_pressed("jump"):
			vertical_speed = 9.5
		fuel = minf(100.0, fuel + delta * 14.0)
	else:
		if in_station or game.in_attic:
			# 站内与阁楼都是室内：恒定重力，不做随高度衰减。
			vertical_speed -= gravity_strength * delta
		else:
			vertical_speed -= clampf(gravity_strength * (1.0 - altitude / (planet.radius * 0.55)), 1.0, gravity_strength) * delta

	var jetting := false
	if Input.is_action_pressed("jetpack") and fuel > 0.0 and not game.map_open:
		vertical_speed += 46.0 * delta
		vertical_speed = minf(vertical_speed, 17.0)
		fuel = maxf(0.0, fuel - delta * (18.0 + gravity_strength * 0.22))
		jetting = true
	velocity = horizontal + normal * vertical_speed
	var before_move := global_position
	move_and_slide()
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

	if in_station or global_position.distance_to(game.ship.global_position) < 9.0 or global_position.distance_to(game.campfire.global_position) < 6.0:
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
	if is_on_floor() and planar_speed > 0.5:
		bob_time += delta * planar_speed * 1.25
	camera.position.y = 1.48 + sin(bob_time) * minf(planar_speed / 8.5, 1.0) * 0.035
	game.audio.set_jetpack(jetting)


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
