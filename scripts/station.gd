extends Node3D

var game
var display_name := "归航站"
var radius := 270.0
var artificial_gravity := 14.0
var active_corridor := -1

const SPINE_LENGTH := 300.0
const RING_RADIUS := 280.0
const RING_HALF_WIDTH := 10.0
const RING_HALF_HEIGHT := 8.0
const ARM_START := 30.0
const ARM_END := 255.0
const ARM_HALF_WIDTH := 12.0
const ARM_HALF_HEIGHT := 8.0
const POD_HALF_LENGTH := 22.0
const POD_HALF_WIDTH := 17.0
const POD_HALF_HEIGHT := 12.0
const STATION_ORBIT_SPEED := 0.004
const HUB_RADIUS := 30.0
const CORRIDOR_COUNT := 6
const CORRIDOR_HALF_LENGTH := 105.0
const CORRIDOR_HALF_WIDTH := 3.6
const ROOM_DEPTH := 6.9
const ROOM_HALF_WIDTH := 5.0
const FLOOR_TOP := -2.0
const CEILING_Y := 2.8
const HALL_CEILING_Y := 5.6
const WALL_HEIGHT := 4.8
const ROOM_CENTERS := [-84.0, -56.0, -28.0, 28.0, 56.0, 84.0]
const ROOM_NAMES_LEFT := ["医疗舱", "食堂", "档案室", "实验舱", "储藏舱", "休憩厅"]
const ROOM_NAMES_RIGHT := ["温室", "居住舱", "通信室", "维修间", "图书室", "观景廊"]
const ROOM_KINDS_LEFT := ["med", "canteen", "archive", "lab", "storage", "lounge"]
const ROOM_KINDS_RIGHT := ["green", "dorm", "comms", "repair", "library", "observation"]
const CORRIDOR_NAMES := ["医疗环", "科研环", "居住环", "工业环", "后勤环", "观景环"]
const DOOR_HALF_WIDTH := 1.8
const DOOR_TRAVEL_TIME := 0.55
const DOOR_TRIGGER_RANGE := 9.0
const DOOR_HOLD_RANGE := 12.0
const DOOR_SAFETY_RANGE := 4.2
# 静态网格合并：把成百上千个装饰盒子烘焙成少量多材质网格。关掉即回到逐盒子建节点的旧行为。
const MERGE_STATIC_MESHES := true
# 分块边长要小于灯间距，保证每块只用得上附近几盏灯（配合 project.godot 里的每对象灯上限 16）。
const MERGE_CHUNK := 24.0
# 站外只有 3 盏灯，分块主要是权衡"视锥剔除粒度"与"绘制批次"：块越大，材质共享越多、批次越少。
const EXTERIOR_MERGE_CHUNK := 60.0
# 同一时刻只有一条走廊会渲染，其余五条的站内碰撞没有理由常驻物理世界（1,464 → 244 个形状）。
# 安全性：走廊从半径 30 开始，而"按朝向选走廊"只在半径 ≤26 内生效；半径 26~34 这段玩家踩的是
# 枢纽地板（半径 34、常驻启用），所以关掉看不见的走廊不会让人掉下去。关掉即回到旧行为。
const ACTIVE_CORRIDOR_COLLISION_ONLY := true

var ring_root: Node3D
var interior_root: Node3D
var hub_root: Node3D
var hub_body: StaticBody3D
var exterior_body: StaticBody3D
var orbit_planet: Node3D
var orbit_phase := 0.0
var orbit_radius := 2600.0
var orbit_ready := false
var corridor_roots: Array[Node3D] = []
var corridor_shapes: Array = []
var corridor_collision_state: Array[bool] = []
var door_panels: Array[Node3D] = []
var door_open: Array[float] = []
var door_state: Array[int] = []
var merge_reports: Dictionary = {}
# 会被代码改动的材质（信标闪烁）。合并时它们必须当分块的代表材质，否则合完就不闪了。
var merge_live_materials: Array = []
var end_pods: Array[Node3D] = []
var station_body: StaticBody3D
var hologram: Node3D
var hub_hologram: Node3D
var _font: Font
var _time := 0.0
var _beacon_material: StandardMaterial3D
var _mat_hull: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_trim: StandardMaterial3D
var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_screen: StandardMaterial3D
var _mat_lift: StandardMaterial3D
var _mat_warm: StandardMaterial3D
var _mat_teal: StandardMaterial3D
var _mat_glow: StandardMaterial3D
var _mat_glass: StandardMaterial3D
var _mat_window: StandardMaterial3D
var _mat_green: StandardMaterial3D
var _mat_blue: StandardMaterial3D
var _mat_orange: StandardMaterial3D
var _mat_white: StandardMaterial3D


func _ready() -> void:
	_font = load("res://assets/ui_font.ttf")
	_build_materials()
	merge_live_materials = [_beacon_material]
	_build_exterior()
	_build_interior()
	_arrange_corridors()
	_build_hub()
	_merge_exterior_meshes()


func _merge_exterior_meshes() -> void:
	# 站外（六条外臂、主塔、端舱、检修车、设施）才是玩家飞到站点附近时真正在画的东西：
	# 1,400 多个独立网格节点在网页版上就是 1,400 多次绘制，所以同样按分块合并。
	# 端舱要按站内/站外切换可见性、会闪的信标材质必须留原实例，两者都在合并之外。
	var skip: Array = []
	if hub_root != null:
		skip.append(hub_root)
	if ring_root != null:
		skip.append(ring_root)
	if station_body != null:
		skip.append(station_body)
	if exterior_body != null:
		skip.append(exterior_body)
	for corridor in corridor_roots:
		var container := corridor.get_parent()
		if container != null and not skip.has(container):
			skip.append(container)
	for pod in end_pods:
		skip.append(pod)
	_merge_static_meshes(self, skip, "ExteriorMerged", EXTERIOR_MERGE_CHUNK)
	# 外环的细节跟着 ring_root 一起转，合并进它自己即可保持转动。
	if ring_root != null:
		var ring_skip: Array = []
		for pod in end_pods:
			ring_skip.append(pod)
		_merge_static_meshes(ring_root, ring_skip, "RingMerged", EXTERIOR_MERGE_CHUNK)


func _process(delta: float) -> void:
	_time += delta
	if not orbit_ready:
		_setup_orbit()
	_update_orbit()
	if game != null and game.ship != null and game.ship.docked and game.ship.docked_station == self:
		game.ship.global_position = dock_ship_position()
		game.ship.look_at(dock_look_target(), dock_up_direction())
	if ring_root != null:
		ring_root.rotate_y(delta * 0.03)
	if hologram != null:
		hologram.rotate_y(delta * 0.55)
	if hub_hologram != null:
		hub_hologram.rotate_y(delta * 0.32)
	if _beacon_material != null:
		_beacon_material.emission_energy_multiplier = 1.6 + sin(_time * 2.6) * 1.1
	if hub_root != null:
		var in_station: bool = game != null and game.in_station
		hub_root.visible = in_station
		for pod in end_pods:
			pod.visible = not in_station
		var idx := -1
		if in_station and game.player != null:
			var local := to_local(game.player.global_position)
			var aim := local
			if Vector2(local.x, local.z).length() <= 26.0:
				aim = to_local(game.player.global_position - game.player.global_transform.basis.z) - local
			var angle := atan2(aim.z, aim.x)
			var slot := roundi(angle / (TAU / 6.0))
			idx = posmod(slot, 6)
		active_corridor = idx
		for i in range(corridor_roots.size()):
			corridor_roots[i].visible = in_station and i == idx
		if ACTIVE_CORRIDOR_COLLISION_ONLY:
			for i in range(corridor_shapes.size()):
				var wanted: bool = in_station and i == idx
				if i < corridor_collision_state.size() and corridor_collision_state[i] == wanted:
					continue
				if i < corridor_collision_state.size():
					corridor_collision_state[i] = wanted
				for shape in corridor_shapes[i]:
					shape.disabled = not wanted
		_update_doors(delta, in_station, idx)


func door_openness(index: int) -> float:
	if index < 0 or index >= door_open.size():
		return 0.0
	return door_open[index]


func _update_doors(delta: float, in_station: bool, idx: int) -> void:
	if door_open.is_empty():
		return
	var player_local := Vector3.ZERO
	var has_player: bool = in_station and game != null and game.player != null
	if has_player:
		player_local = to_local(game.player.global_position)
	for i in range(door_open.size()):
		var target := 0.0
		if has_player:
			# 门中心就是门框节点的枢纽局部坐标，用它判断玩家有没有走到门口。
			var door_frame := door_panels[i].get_parent() as Node3D
			var distance := player_local.distance_to(door_frame.position)
			# 已经动起来的门用更远的保持距离，避免玩家在触发半径上来回走时门反复开合。
			var reach: float = DOOR_HOLD_RANGE if door_open[i] > 0.02 else DOOR_TRIGGER_RANGE
			# 站在门洞里时不许关门，免得门扇夹住玩家。
			if distance <= DOOR_SAFETY_RANGE or (i == idx and distance <= reach):
				target = 1.0
		# 开合指令翻转的那一帧放一次放气门音效，音源贴在门框上。
		var want_open := 1 if target > 0.5 else 0
		if want_open != door_state[i]:
			door_state[i] = want_open
			if has_player and game.audio != null:
				var frame := door_panels[i].get_parent() as Node3D
				game.audio.play_door(frame.global_position, want_open == 1)
		var previous := door_open[i]
		door_open[i] = move_toward(previous, target, delta / DOOR_TRAVEL_TIME)
		if is_equal_approx(previous, door_open[i]):
			continue
		# 两扇门从中缝向两侧滑出，碰撞体挂在门扇上所以会跟着一起走。
		for child in door_panels[i].get_children():
			var leaf := child as Node3D
			var side := float(leaf.get_meta("door_side", -1.0))
			leaf.position.z = side * DOOR_HALF_WIDTH * (1.0 + 2.0 * door_open[i])


func _setup_orbit() -> void:
	if game == null or game.planets.is_empty():
		return
	var best: Node3D = null
	var best_distance := INF
	var best_position := Vector3.ZERO
	for planet in game.planets:
		var planet_node: Node3D = planet
		var planet_position := _planet_orbit_position(planet_node)
		var distance: float = global_position.distance_squared_to(planet_position) - float(planet_node.radius) * float(planet_node.radius)
		if distance < best_distance:
			best_distance = distance
			best = planet_node
			best_position = planet_position
	if best == null:
		return
	orbit_planet = best
	var radial := best_position.normalized()
	var orbit_u := Vector3.UP.cross(radial)
	if orbit_u.length_squared() < 0.01:
		orbit_u = Vector3.RIGHT.cross(radial)
	orbit_u = orbit_u.normalized()
	var orbit_v := radial.cross(orbit_u).normalized()
	var offset := global_position - best_position
	var projected := offset - radial * offset.dot(radial)
	if projected.length_squared() < 1.0:
		projected = orbit_u
	orbit_phase = atan2(projected.dot(orbit_v), projected.dot(orbit_u))
	# ⚠ 2026-11-11 行星半径 ×3、轨道 ×10 之后，环绕半径不能再写死 2200：
	#   那会让归航站贴着放大后的行星表面（1200 米半径的星球只剩 1000 米余量）。
	#   偏移量与下限都按「行星半径放大倍数」同步放宽。
	orbit_radius = maxf(float(best.radius) + 2200.0 * 3.0, 2600.0 * 3.0)
	orbit_ready = true


func _planet_orbit_position(planet: Node3D) -> Vector3:
	var angle: float = float(planet.orbit_phase) + float(planet.orbit_speed) * float(game.elapsed)
	return Vector3(cos(angle) * float(planet.orbit_radius),
		float(planet.orbit_height) + sin(angle * 1.7) * 500.0,
		sin(angle) * float(planet.orbit_radius))


func _update_orbit() -> void:
	if not orbit_ready or orbit_planet == null or game == null:
		return
	var center := _planet_orbit_position(orbit_planet)
	var radial := center.normalized()
	var orbit_u := Vector3.UP.cross(radial)
	if orbit_u.length_squared() < 0.01:
		orbit_u = Vector3.RIGHT.cross(radial)
	orbit_u = orbit_u.normalized()
	var orbit_v := radial.cross(orbit_u).normalized()
	var angle := orbit_phase + float(game.elapsed) * STATION_ORBIT_SPEED
	global_position = center + (orbit_u * cos(angle) + orbit_v * sin(angle)) * orbit_radius


func _build_materials() -> void:
	_mat_hull = _mat(Color("48565c"), 0.62, 0.46)
	_mat_dark = _mat(Color("1d272c"), 0.72, 0.38)
	_mat_trim = _mat(Color("9b9a8c"), 0.5, 0.34)
	_mat_floor = _mat(Color("3a4246"), 0.38, 0.42)
	_mat_wall = _mat(Color("6d7774"), 0.28, 0.55)
	_mat_wall.emission_enabled = true
	_mat_wall.emission = Color("2a221a")
	_mat_wall.emission_energy_multiplier = 0.22
	_mat_screen = _mat(Color("12262c"), 0.48, 0.24)
	_mat_screen.emission_enabled = true
	_mat_screen.emission = Color("0d333b")
	_mat_screen.emission_energy_multiplier = 0.55
	_mat_lift = _mat(Color("929c95"), 0.42, 0.38)
	_mat_lift.emission_enabled = true
	_mat_lift.emission = Color("7b847d")
	_mat_lift.emission_energy_multiplier = 0.8
	_mat_warm = _mat(Color("e8c58b"), 0.1, 0.6)
	_mat_teal = _mat(Color("5cb7b4"), 0.2, 0.5)
	_mat_glow = _mat(Color("ffe2b0"), 0.0, 0.4)
	_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_glow.emission_enabled = true
	_mat_glow.emission = Color("ffe2b0")
	_mat_glow.emission_energy_multiplier = 1.6
	_mat_glass = _mat(Color("1d3944"), 0.55, 0.18)
	_mat_window = StandardMaterial3D.new()
	_mat_window.albedo_color = Color(0.46, 0.76, 0.86, 0.08)
	_mat_window.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_window.metallic = 0.2
	_mat_window.roughness = 0.06
	_mat_window.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_green = _mat(Color("4d8c62"), 0.1, 0.6)
	_mat_blue = _mat(Color("3f6f9a"), 0.45, 0.45)
	_mat_orange = _mat(Color("b96c3e"), 0.2, 0.55)
	_mat_white = _mat(Color("d7d5c4"), 0.12, 0.6)


func _mat(color: Color, metallic := 0.4, roughness := 0.5) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _glow_mat(color: Color, energy := 2.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot := Vector3.ZERO, collider := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	if collider and station_body != null:
		_add_collider(size, pos, rot)
	return instance


func _cylinder(parent: Node3D, radius_top: float, radius_bottom: float, height: float, pos: Vector3, material: Material, segments := 16, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_top
	mesh.bottom_radius = radius_bottom
	mesh.height = height
	mesh.radial_segments = segments
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _sphere(parent: Node3D, radius: float, pos: Vector3, material: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 18
	mesh.rings = 9
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.scale = scale
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material, rot := Vector3.ZERO, ring_segments := 24, rings := 96) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = rings
	mesh.ring_segments = ring_segments
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _add_collider(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = pos
	collision.rotation = rot
	station_body.add_child(collision)


func _light(pos: Vector3, color: Color, energy: float, range_m: float, parent: Node3D = null) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	(parent if parent != null else self).add_child(light)


func _label(text: String, pos: Vector3, font_size: int, pixel_size: float, rot_y: float, color: Color, parent: Node3D = null) -> Label3D:
	var label := Label3D.new()
	label.text = text
	if _font != null:
		label.font = _font
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = Color(0.02, 0.03, 0.035, 0.9)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos
	label.rotation.y = rot_y
	label.no_depth_test = false
	label.shaded = false
	label.double_sided = true
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(label)
	return label


func _build_exterior() -> void:
	exterior_body = StaticBody3D.new()
	exterior_body.name = "ExteriorCollision"
	exterior_body.collision_layer = 4
	exterior_body.collision_mask = 0
	add_child(exterior_body)
	_add_exterior_sphere_collider(34.0, Vector3.ZERO)
	# 中央枢纽与上方对接口
	_sphere(self, 34.0, Vector3.ZERO, _mat_hull)
	_torus(self, 34.0, 36.0, Vector3.ZERO, _mat_trim, Vector3.ZERO, 8, 48)
	for i in range(18):
		var hub_angle := TAU * float(i) / 18.0
		_box(self, Vector3(1.0, 2.2, 0.5), Vector3(cos(hub_angle) * 34.2, 0.0, sin(hub_angle) * 34.2), _mat_glow, Vector3(0.0, -hub_angle, 0.0))
	_beacon_material = _glow_mat(Color("ff8a55"), 2.4)
	# 贯通式中央主轴：下段能源核心，上段指挥塔，对接口升到塔顶
	_cylinder(self, 7.0, 8.0, 48.0, Vector3(0.0, -58.0, 0.0), _mat_dark, 20)
	for y: float in [-78.0, -70.0, -62.0, -54.0, -46.0, -38.0]:
		_torus(self, 9.5, 11.0, Vector3(0.0, y, 0.0), _mat_trim, Vector3.ZERO, 8, 40)
	for i in range(4):
		var conduit_angle := TAU * float(i) / 4.0 + PI * 0.25
		_box(self, Vector3(0.18, 42.0, 0.3), Vector3(cos(conduit_angle) * 9.2, -58.0, sin(conduit_angle) * 9.2),
			_mat_glow, Vector3(0.0, -conduit_angle, 0.0))
	var core_material := _glow_mat(Color("63eaff"), 3.2)
	_sphere(self, 12.0, Vector3(0.0, -58.0, 0.0), core_material)
	_sphere(self, 13.5, Vector3(0.0, -58.0, 0.0), _mat_window)
	for i in range(6):
		var cage_angle := TAU * float(i) / 6.0
		_box(self, Vector3(0.7, 30.0, 0.7), Vector3(cos(cage_angle) * 16.0, -58.0, sin(cage_angle) * 16.0),
			_mat_trim, Vector3(0.0, -cage_angle, 0.0))
		_box(self, Vector3(0.12, 28.0, 0.12), Vector3(cos(cage_angle) * 16.15, -58.0, sin(cage_angle) * 16.15),
			_mat_glow, Vector3(0.0, -cage_angle, 0.0))
		_sphere(self, 0.22, Vector3(cos(cage_angle) * 16.0, -73.0, sin(cage_angle) * 16.0), _beacon_material)
	for i in range(4):
		var strut_angle := TAU * float(i) / 4.0 + PI * 0.25
		_box(self, Vector3(15.5, 0.35, 0.35), Vector3(cos(strut_angle) * 8.0, -58.0, sin(strut_angle) * 8.0),
			_mat_trim, Vector3(0.0, -strut_angle, 0.0))
	_torus(self, 15.2, 16.0, Vector3(0.0, -58.0, 0.0), _mat_glow, Vector3.ZERO, 8, 48)
	_torus(self, 17.0, 18.0, Vector3(0.0, -58.0, 0.0), _mat_orange, Vector3.ZERO, 8, 48)
	_torus(self, 15.5, 18.0, Vector3(0.0, -73.0, 0.0), _mat_trim, Vector3.ZERO, 8, 48)
	_torus(self, 15.5, 18.0, Vector3(0.0, -43.0, 0.0), _mat_trim, Vector3.ZERO, 8, 48)
	_cylinder(self, 10.0, 14.0, 10.0, Vector3(0.0, -87.0, 0.0), _mat_hull, 20)
	_sphere(self, 6.0, Vector3(0.0, -94.0, 0.0), _mat_trim)
	_box(self, Vector3(14.0, 2.4, 0.5), Vector3(0.0, -52.0, 18.6), _mat_dark)
	_label("能源中枢", Vector3(0.0, -51.4, 18.9), 50, 0.0125, 0.0, Color("8fe7e3"))
	_light(Vector3(0.0, -58.0, 0.0), Color("58d8d0"), 3.0, 120.0)

	# 下段长轴与末端传感器阵列
	_cylinder(self, 4.5, 5.0, 128.0, Vector3(0.0, -158.0, 0.0), _mat_dark, 16)
	for lower_index in range(4):
		var lower_angle := TAU * float(lower_index) / 4.0 + PI * 0.25
		_box(self, Vector3(0.36, 128.0, 0.36), Vector3(cos(lower_angle) * 8.0, -158.0, sin(lower_angle) * 8.0),
			_mat_trim, Vector3(0.0, -lower_angle, 0.0))
	for lower_y: float in [-110.0, -130.0, -150.0, -170.0, -190.0, -210.0]:
		_torus(self, 8.0, 9.5, Vector3(0.0, lower_y, 0.0), _mat_trim, Vector3.ZERO, 8, 36)
	for lower_index in range(3):
		var lower_conduit_angle := TAU * float(lower_index) / 3.0
		_box(self, Vector3(0.14, 126.0, 0.26), Vector3(cos(lower_conduit_angle) * 5.2, -158.0, sin(lower_conduit_angle) * 5.2),
			_mat_glow, Vector3(0.0, -lower_conduit_angle, 0.0))
	for lower_beacon_y: float in [-120.0, -160.0, -200.0]:
		for lower_beacon_index in range(3):
			var lower_beacon_angle := TAU * float(lower_beacon_index) / 3.0
			_sphere(self, 0.16, Vector3(cos(lower_beacon_angle) * 9.8, lower_beacon_y, sin(lower_beacon_angle) * 9.8), _beacon_material)
	for radiator_index in range(4):
		var radiator_angle := TAU * float(radiator_index) / 4.0 + PI * 0.25
		_box(self, Vector3(0.2, 18.0, 9.0), Vector3(cos(radiator_angle) * 11.5, -140.0, sin(radiator_angle) * 11.5),
			_mat_dark, Vector3(0.0, -radiator_angle, 0.0))
		_add_exterior_box_collider(Vector3(0.2, 18.0, 9.0), Vector3(cos(radiator_angle) * 11.5, -140.0, sin(radiator_angle) * 11.5), Vector3(0.0, -radiator_angle, 0.0))
		_box(self, Vector3(0.1, 16.0, 0.18), Vector3(cos(radiator_angle) * 16.0, -140.0, sin(radiator_angle) * 16.0),
			_mat_trim, Vector3(0.0, -radiator_angle, 0.0))
	_cylinder(self, 12.0, 12.0, 6.0, Vector3(0.0, -224.0, 0.0), _mat_trim, 24)
	_torus(self, 11.0, 12.5, Vector3(0.0, -227.0, 0.0), _mat_trim, Vector3.ZERO, 8, 40)
	_sphere(self, 5.0, Vector3(0.0, -230.0, 0.0), _mat_screen)
	_add_exterior_sphere_collider(11.0, Vector3(0.0, -230.0, 0.0))

	_cylinder(self, 16.0, 24.0, 10.0, Vector3(0.0, 37.0, 0.0), _mat_hull, 28)
	for i in range(12):
		var shoulder_rib := TAU * float(i) / 12.0
		_box(self, Vector3(0.35, 9.0, 0.9), Vector3(cos(shoulder_rib) * 20.4, 37.0, sin(shoulder_rib) * 20.4),
			_mat_dark, Vector3(0.0, -shoulder_rib, 0.0))
		_box(self, Vector3(0.12, 7.0, 0.12), Vector3(cos(shoulder_rib) * 20.7, 37.0, sin(shoulder_rib) * 20.7),
			_mat_glow, Vector3(0.0, -shoulder_rib, 0.0))
	_torus(self, 16.0, 18.0, Vector3(0.0, 42.0, 0.0), _mat_trim, Vector3.ZERO, 10, 48)
	_cylinder(self, 17.0, 17.0, 8.0, Vector3(0.0, 48.0, 0.0), _mat_hull, 32)
	for i in range(24):
		var window_angle := TAU * float(i) / 24.0
		_box(self, Vector3(1.0, 2.2, 0.18), Vector3(cos(window_angle) * 17.08, 48.0, sin(window_angle) * 17.08),
			_mat_warm if i % 3 != 0 else _mat_teal, Vector3(0.0, -window_angle, 0.0))
	for i in range(8):
		var rib_angle := TAU * float(i) / 8.0
		_box(self, Vector3(0.22, 8.0, 0.3), Vector3(cos(rib_angle) * 17.25, 48.0, sin(rib_angle) * 17.25),
			_mat_trim, Vector3(0.0, -rib_angle, 0.0))
	_torus(self, 17.0, 18.4, Vector3(0.0, 52.0, 0.0), _mat_trim, Vector3.ZERO, 10, 48)
	_cylinder(self, 12.0, 15.0, 14.0, Vector3(0.0, 60.0, 0.0), _mat_trim, 24)
	for i in range(6):
		var fin_angle := TAU * float(i) / 6.0
		_box(self, Vector3(0.7, 18.0, 2.4), Vector3(cos(fin_angle) * 16.0, 60.0, sin(fin_angle) * 16.0),
			_mat_hull, Vector3(0.0, -fin_angle, 0.0))
		_box(self, Vector3(0.12, 16.0, 0.12), Vector3(cos(fin_angle) * 16.2, 60.0, sin(fin_angle) * 16.2),
			_mat_glow, Vector3(0.0, -fin_angle, 0.0))
	for i in range(12):
		var seam_angle := TAU * float(i) / 12.0
		_box(self, Vector3(0.55, 1.6, 0.14), Vector3(cos(seam_angle) * 14.3, 60.0, sin(seam_angle) * 14.3),
			_mat_teal if i % 3 == 0 else _mat_dark, Vector3(0.0, -seam_angle, 0.0))
	_torus(self, 13.0, 14.2, Vector3(0.0, 66.0, 0.0), _mat_teal, Vector3.ZERO, 8, 48)
	_cylinder(self, 9.0, 12.0, 8.0, Vector3(0.0, 72.0, 0.0), _mat_hull, 20)
	for i in range(16):
		var cupola_angle := TAU * float(i) / 16.0
		_box(self, Vector3(0.9, 1.8, 0.16), Vector3(cos(cupola_angle) * 12.08, 72.0, sin(cupola_angle) * 12.08),
			_mat_glow, Vector3(0.0, -cupola_angle, 0.0))
	_torus(self, 12.0, 13.3, Vector3(0.0, 76.0, 0.0), _mat_trim, Vector3.ZERO, 8, 40)
	_cylinder(self, 11.0, 12.0, 10.0, Vector3(0.0, 81.0, 0.0), _mat_dark, 24)
	for i in range(8):
		var mast_angle := TAU * float(i) / 8.0 + PI * 0.25
		_box(self, Vector3(0.16, 52.0, 0.16), Vector3(cos(mast_angle) * 18.3, 59.0, sin(mast_angle) * 18.3),
			_mat_dark, Vector3(0.0, -mast_angle, 0.0))
		_sphere(self, 0.22, Vector3(cos(mast_angle) * 18.3, 85.0, sin(mast_angle) * 18.3), _beacon_material)
	_box(self, Vector3(12.0, 2.4, 0.5), Vector3(0.0, 55.0, 18.4), _mat_dark)
	_label("指挥塔", Vector3(0.0, 55.5, 18.7), 48, 0.013, 0.0, Color("f0e0bd"))
	_light(Vector3(0.0, 60.0, 0.0), Color("ffc18a"), 1.6, 70.0)

	# 90 米节点：长轴桁架的起点
	_cylinder(self, 14.0, 14.0, 4.0, Vector3(0.0, 90.0, 0.0), _mat_dark, 32)
	_torus(self, 10.4, 11.0, Vector3(0.0, 91.9, 0.0), _mat_glow, Vector3.ZERO, 8, 48)
	_torus(self, 7.4, 7.8, Vector3(0.0, 92.1, 0.0), _mat_teal, Vector3.ZERO, 8, 48)
	_torus(self, 3.0, 3.3, Vector3(0.0, 92.1, 0.0), _mat_glow, Vector3.ZERO, 8, 40)
	_box(self, Vector3(1.0, 0.08, 12.0), Vector3(0.0, 92.15, 0.0), _mat_trim)
	_box(self, Vector3(12.0, 0.08, 1.0), Vector3(0.0, 92.15, 0.0), _mat_trim)

	# 170 米长轴：纵梁、环箍、导线与检修车
	_cylinder(self, 8.0, 8.0, 150.0, Vector3(0.0, 167.0, 0.0), _mat_dark, 20)
	for spar_index in range(6):
		var spar_angle := TAU * float(spar_index) / 6.0
		_box(self, Vector3(0.55, 150.0, 0.55), Vector3(cos(spar_angle) * 13.0, 167.0, sin(spar_angle) * 13.0),
			_mat_trim, Vector3(0.0, -spar_angle, 0.0))
	for spar_y: float in [100.0, 120.0, 140.0, 160.0, 180.0, 200.0, 220.0, 240.0]:
		_torus(self, 12.8, 14.4, Vector3(0.0, spar_y, 0.0), _mat_trim, Vector3.ZERO, 8, 40)
	for spar_index in range(4):
		var spar_conduit_angle := TAU * float(spar_index) / 4.0 + PI * 0.25
		_box(self, Vector3(0.18, 148.0, 0.34), Vector3(cos(spar_conduit_angle) * 8.7, 167.0, sin(spar_conduit_angle) * 8.7),
			_mat_glow, Vector3(0.0, -spar_conduit_angle, 0.0))
	for spar_module_y: float in [120.0, 150.0, 180.0, 210.0]:
		_cylinder(self, 10.5, 10.5, 12.0, Vector3(0.0, spar_module_y, 0.0), _mat_hull, 24)
		_torus(self, 10.5, 11.6, Vector3(0.0, spar_module_y - 6.0, 0.0), _mat_trim, Vector3.ZERO, 8, 40)
		_torus(self, 10.5, 11.6, Vector3(0.0, spar_module_y + 6.0, 0.0), _mat_trim, Vector3.ZERO, 8, 40)
		for spar_window_index in range(10):
			var spar_window_angle := TAU * float(spar_window_index) / 10.0
			_box(self, Vector3(0.8, 1.4, 0.14), Vector3(cos(spar_window_angle) * 10.56, spar_module_y, sin(spar_window_angle) * 10.56),
				_mat_warm if spar_window_index % 3 != 0 else _mat_teal, Vector3(0.0, -spar_window_angle, 0.0))
	for beacon_y: float in [110.0, 150.0, 190.0, 230.0]:
		for beacon_index in range(4):
			var spar_beacon_angle := TAU * float(beacon_index) / 4.0 + PI * 0.25
			_sphere(self, 0.18, Vector3(cos(spar_beacon_angle) * 14.6, beacon_y, sin(spar_beacon_angle) * 14.6), _beacon_material)
	_box(self, Vector3(2.2, 2.0, 1.6), Vector3(14.8, 170.0, 0.0), _mat_dark)
	_box(self, Vector3(1.4, 0.5, 0.08), Vector3(14.8, 170.4, 0.84), _mat_glow)

	# 顶部对接塔与磁力口
	_cylinder(self, 14.0, 14.0, 8.0, Vector3(0.0, 246.0, 0.0), _mat_hull, 28)
	_torus(self, 14.0, 15.6, Vector3(0.0, 250.0, 0.0), _mat_trim, Vector3.ZERO, 10, 48)
	_cylinder(self, 9.0, 10.5, 8.0, Vector3(0.0, 254.0, 0.0), _mat_dark, 24)
	for top_index in range(16):
		var top_angle := TAU * float(top_index) / 16.0
		_box(self, Vector3(0.8, 1.8, 0.16), Vector3(cos(top_angle) * 9.9, 254.0, sin(top_angle) * 9.9),
			_mat_warm if top_index % 4 != 0 else _mat_teal, Vector3(0.0, -top_angle, 0.0))
	_torus(self, 10.0, 11.2, Vector3(0.0, 258.0, 0.0), _mat_trim, Vector3.ZERO, 8, 40)
	_cylinder(self, 12.0, 12.0, 4.0, Vector3(0.0, 260.0, 0.0), _mat_dark, 32)
	_torus(self, 9.5, 10.2, Vector3(0.0, 261.8, 0.0), _mat_glow, Vector3.ZERO, 8, 48)
	_torus(self, 6.8, 7.2, Vector3(0.0, 262.0, 0.0), _mat_teal, Vector3.ZERO, 8, 48)
	_torus(self, 3.0, 3.3, Vector3(0.0, 262.0, 0.0), _mat_glow, Vector3.ZERO, 8, 40)
	_box(self, Vector3(1.0, 0.08, 11.0), Vector3(0.0, 262.05, 0.0), _mat_trim)
	_box(self, Vector3(11.0, 0.08, 1.0), Vector3(0.0, 262.05, 0.0), _mat_trim)
	for top_clamp_index in range(4):
		var top_clamp_angle := TAU * float(top_clamp_index) / 4.0 + PI * 0.25
		var top_clamp := Node3D.new()
		top_clamp.position = Vector3(0.0, 262.15, 0.0)
		top_clamp.rotation.y = -top_clamp_angle
		add_child(top_clamp)
		_box(top_clamp, Vector3(7.0, 0.5, 1.1), Vector3(10.2, 0.0, 0.0), _mat_trim)
		_box(top_clamp, Vector3(3.0, 0.06, 0.5), Vector3(10.2, 0.29, 0.0), _mat_dark)
		_box(top_clamp, Vector3(0.4, 0.72, 1.5), Vector3(13.7, 0.0, 0.0), _mat_orange)
		_add_exterior_box_collider(Vector3(7.0, 0.5, 1.1), top_clamp.position + top_clamp.basis * Vector3(10.2, 0.0, 0.0), top_clamp.rotation)
	for top_pylon_index in range(4):
		var top_pylon_angle := TAU * float(top_pylon_index) / 4.0 + PI * 0.25
		var top_pylon := Node3D.new()
		top_pylon.position = Vector3(cos(top_pylon_angle) * 20.0, 264.5, sin(top_pylon_angle) * 20.0)
		add_child(top_pylon)
		_add_exterior_box_collider(Vector3(1.1, 7.0, 1.1), top_pylon.position)
		_box(top_pylon, Vector3(1.1, 7.0, 1.1), Vector3.ZERO, _mat_trim)
		for side: float in [-1.0, 1.0]:
			_box(top_pylon, Vector3(0.16, 5.4, 0.16), Vector3(side * 0.57, 0.6, 0.0), _mat_glow)
		_cylinder(top_pylon, 0.1, 0.1, 3.0, Vector3(0.0, 3.4, 0.0), _mat_trim, 6)
		_sphere(top_pylon, 0.75, Vector3(0.0, 3.85, 0.0), _beacon_material)
	_box(self, Vector3(8.0, 2.2, 0.4), Vector3(0.0, 255.0, 13.5), _mat_dark)
	_label("对接塔", Vector3(0.0, 255.5, 13.8), 42, 0.012, 0.0, Color("ffe4b4"))
	_light(Vector3(0.0, 254.0, 0.0), Color("ffc18a"), 1.8, 100.0)

	# 六条可进入的栖息臂，对应内部六条放射走廊；静止，外环独立旋转
	for i in range(CORRIDOR_COUNT):
		_build_exterior_arm(TAU * float(i) / float(CORRIDOR_COUNT))

	# 枢纽侧面标牌
	_box(self, Vector3(30.0, 12.0, 0.8), Vector3(0.0, 8.0, 33.2), _mat_dark)
	_label(display_name, Vector3(0.0, 9.8, 33.7), 180, 0.04, 0.0, Color("ffe4b4"))

	# 连续方截面外环：整圈一体，缓慢旋转
	_build_continuous_ring()

	# 停靠的小型穿梭机
	_build_shuttle(Vector3(55.0, -12.0, 34.0), 0.3)
	_build_shuttle(Vector3(130.0, -14.0, -34.0), -0.4)
	_build_shuttle(Vector3(0.0, 24.0, -55.0), 2.2)


func _make_open_tube_mesh(length: float, half_height: float, half_width: float) -> ArrayMesh:
	# 只有朝外四个面的方管：没有端盖，也没有朝内的面。
	# 这样它从站内看永远是被背面剔除的，不会挡住门洞、也不会挡住舷窗里的星空。
	var half_length := length * 0.5
	var c000 := Vector3(-half_length, -half_height, -half_width)
	var c001 := Vector3(-half_length, -half_height, half_width)
	var c010 := Vector3(-half_length, half_height, -half_width)
	var c011 := Vector3(-half_length, half_height, half_width)
	var c100 := Vector3(half_length, -half_height, -half_width)
	var c101 := Vector3(half_length, -half_height, half_width)
	var c110 := Vector3(half_length, half_height, -half_width)
	var c111 := Vector3(half_length, half_height, half_width)
	var faces := [
		[c000, c100, c101, c001, Vector3(0.0, -1.0, 0.0)],
		[c110, c010, c011, c111, Vector3(0.0, 1.0, 0.0)],
		[c100, c000, c010, c110, Vector3(0.0, 0.0, -1.0)],
		[c001, c101, c111, c011, Vector3(0.0, 0.0, 1.0)],
	]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for face in faces:
		var normal: Vector3 = face[4]
		# 同 _detail_face：Godot 正面绕序为顺时针，用 0,2,1 / 0,3,2 发顶点正面才朝外。
		for index in [0, 2, 1, 0, 3, 2]:
			vertices.append(face[index])
			normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_exterior_arm(angle: float) -> void:
	var root := Node3D.new()
	root.rotation.y = -angle
	add_child(root)
	var arm_body := StaticBody3D.new()
	arm_body.name = "ArmCollision"
	arm_body.collision_layer = 4
	arm_body.collision_mask = 0
	root.add_child(arm_body)
	var hull_size := Vector3(ARM_END - ARM_START, ARM_HALF_HEIGHT * 2.0 + 1.0, ARM_HALF_WIDTH * 2.0 + 1.0)
	var hull_center := Vector3((ARM_START + ARM_END) * 0.5, 0.0, 0.0)
	var hull_shape := BoxShape3D.new()
	hull_shape.size = hull_size
	_add_static_shape(arm_body, hull_shape, hull_center)
	var pod_shape := BoxShape3D.new()
	pod_shape.size = Vector3(POD_HALF_LENGTH * 2.0 + 4.0, POD_HALF_HEIGHT * 2.0 + 4.0, POD_HALF_WIDTH * 2.0 + 4.0)
	_add_static_shape(arm_body, pod_shape, Vector3(ARM_END, 0.0, 0.0))
	for side: float in [-1.0, 1.0]:
		var beam_shape := BoxShape3D.new()
		beam_shape.size = Vector3(74.0, 1.8, 1.8)
		_add_static_shape(arm_body, beam_shape, Vector3(80.0, 0.0, side * 28.0))

	# 方截面主臂：与内部走廊、舱室和中央大厅同构。
	# 这里必须是"无端盖的开口方管"，不能是实心长方体：实心体的端面正好落在半径 30 的门平面上，
	# 从枢纽看每扇门后面都是一堵灰绿色的墙（而且它的碰撞只在 layer 4，玩家会直接穿过去）。
	# 管只有朝外的四个面：站外看外壳照旧完整，站内/舷窗看它永远是背面被剔除，所以还能看到真实星空。
	var hull := MeshInstance3D.new()
	hull.name = "ArmHull"
	hull.mesh = _make_open_tube_mesh(ARM_END - ARM_START, ARM_HALF_HEIGHT, ARM_HALF_WIDTH)
	hull.material_override = _mat_hull
	hull.position = hull_center
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hull)
	for x in range(42, 256, 18):
		var frame_x := float(x)
		_box(root, Vector3(0.7, 0.5, ARM_HALF_WIDTH * 2.0 + 0.8), Vector3(frame_x, ARM_HALF_HEIGHT + 0.2, 0.0), _mat_trim)
		_box(root, Vector3(0.7, 0.5, ARM_HALF_WIDTH * 2.0 + 0.8), Vector3(frame_x, -ARM_HALF_HEIGHT - 0.2, 0.0), _mat_trim)
		_box(root, Vector3(0.7, ARM_HALF_HEIGHT * 2.0 + 0.8, 0.5), Vector3(frame_x, 0.0, ARM_HALF_WIDTH + 0.2), _mat_trim)
		_box(root, Vector3(0.7, ARM_HALF_HEIGHT * 2.0 + 0.8, 0.5), Vector3(frame_x, 0.0, -ARM_HALF_WIDTH - 0.2), _mat_trim)
	for side: float in [-1.0, 1.0]:
		_box(root, Vector3(ARM_END - ARM_START - 3.0, 0.2, 0.6), Vector3(hull_center.x, ARM_HALF_HEIGHT + 0.02, side * 8.0), _mat_glow)
		_box(root, Vector3(ARM_END - ARM_START - 3.0, 0.6, 0.2), Vector3(hull_center.x, side * 3.0, ARM_HALF_WIDTH + 0.02), _mat_glow)
		_box(root, Vector3(ARM_END - ARM_START - 3.0, 0.6, 0.2), Vector3(hull_center.x, side * 3.0, -ARM_HALF_WIDTH - 0.02), _mat_glow)
	for side: float in [-1.0, 1.0]:
		for x in range(48, 250, 24):
			_box(root, Vector3(2.2, 1.15, 0.12), Vector3(float(x), 1.55, side * (ARM_HALF_WIDTH + 0.07)),
				_mat_warm if int(x / 24) % 3 != 0 else _mat_teal)
			_box(root, Vector3(1.5, 0.8, 0.12), Vector3(float(x), -0.75, side * (ARM_HALF_WIDTH + 0.07)),
				_mat_teal if int(x / 24) % 4 != 0 else _mat_warm)
	# 方形气闸门
	for side: float in [-1.0, 1.0]:
		var hatches := [110.0, 210.0] if side > 0.0 else [70.0, 170.0]
		for hatch_x in hatches:
			var hx := float(hatch_x)
			_box(root, Vector3(3.6, 3.0, 0.2), Vector3(hx, 0.0, side * (ARM_HALF_WIDTH + 0.11)), _mat_dark)
			_box(root, Vector3(4.0, 0.2, 0.3), Vector3(hx, 1.55, side * (ARM_HALF_WIDTH + 0.2)), _mat_trim)
			_box(root, Vector3(4.0, 0.2, 0.3), Vector3(hx, -1.55, side * (ARM_HALF_WIDTH + 0.2)), _mat_trim)
			for edge: float in [-1.0, 1.0]:
				_box(root, Vector3(0.2, 3.2, 0.3), Vector3(hx + edge * 1.85, 0.0, side * (ARM_HALF_WIDTH + 0.2)), _mat_trim)
			_box(root, Vector3(0.9, 0.12, 0.16), Vector3(hx, -1.2, side * (ARM_HALF_WIDTH + 0.26)), _mat_orange)
	for i in range(4):
		var rcs_y := 1.0 if i % 2 == 0 else -1.0
		var rcs_z := 1.0 if i < 2 else -1.0
		_box(root, Vector3(0.9, 0.9, 0.9), Vector3(238.0, rcs_y * (ARM_HALF_HEIGHT - 0.5), rcs_z * (ARM_HALF_WIDTH - 0.5)), _mat_dark)
		_box(root, Vector3(0.45, 0.45, 0.45), Vector3(238.0, rcs_y * (ARM_HALF_HEIGHT - 0.5), rcs_z * (ARM_HALF_WIDTH + 0.1)), _mat_glow)
	for x in range(55, 250, 35):
		_box(root, Vector3(1.6, 0.8, 8.0), Vector3(float(x), ARM_HALF_HEIGHT + 0.4, 0.0), _mat_trim)

	# 方盒末端指挥舱与方形环梁
	var pod := _box(root, Vector3(POD_HALF_LENGTH * 2.0, POD_HALF_HEIGHT * 2.0, POD_HALF_WIDTH * 2.0), Vector3(ARM_END, 0.0, 0.0), _mat_hull)
	pod.name = "StationEndPod"
	end_pods.append(pod)
	for edge: float in [-1.0, 1.0]:
		_box(root, Vector3(1.6, 2.0, POD_HALF_WIDTH * 2.0 + 2.0), Vector3(ARM_END + edge * (POD_HALF_LENGTH + 0.1), POD_HALF_HEIGHT + 0.2, 0.0), _mat_trim)
		_box(root, Vector3(1.6, 2.0, POD_HALF_WIDTH * 2.0 + 2.0), Vector3(ARM_END + edge * (POD_HALF_LENGTH + 0.1), -POD_HALF_HEIGHT - 0.2, 0.0), _mat_trim)
		_box(root, Vector3(1.6, POD_HALF_HEIGHT * 2.0 + 2.0, 2.0), Vector3(ARM_END + edge * (POD_HALF_LENGTH + 0.1), 0.0, POD_HALF_WIDTH + 0.2), _mat_trim)
		_box(root, Vector3(1.6, POD_HALF_HEIGHT * 2.0 + 2.0, 2.0), Vector3(ARM_END + edge * (POD_HALF_LENGTH + 0.1), 0.0, -POD_HALF_WIDTH - 0.2), _mat_trim)
	for side: float in [-1.0, 1.0]:
		_box(root, Vector3(2.4, 2.4, POD_HALF_WIDTH * 2.0 + 4.4), Vector3(ARM_END, side * (POD_HALF_HEIGHT + 1.0), 0.0), _mat_trim)
		_box(root, Vector3(2.4, POD_HALF_HEIGHT * 2.0 + 4.4, 2.4), Vector3(ARM_END, 0.0, side * (POD_HALF_WIDTH + 1.0)), _mat_trim)
		_box(root, Vector3(2.4, 0.14, POD_HALF_WIDTH * 2.0 + 4.6), Vector3(ARM_END, side * (POD_HALF_HEIGHT + 2.25), 0.0), _mat_glow)
	for side: float in [-1.0, 1.0]:
		for dx: float in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			for dy: float in [-4.0, 4.0]:
				_box(root, Vector3(2.2, 1.4, 0.12), Vector3(ARM_END + dx, dy, side * (POD_HALF_WIDTH + 0.07)),
					_mat_warm if int((dx + 12.0) / 6.0) % 2 == 0 else _mat_teal)
	_box(root, Vector3(POD_HALF_LENGTH * 2.0 - 4.0, 0.18, 0.6), Vector3(ARM_END, POD_HALF_HEIGHT + 0.05, 0.0), _mat_glow)

	# 两根方截面外挂桁架
	for side: float in [-1.0, 1.0]:
		_box(root, Vector3(74.0, 1.8, 1.8), Vector3(80.0, 0.0, side * 28.0), _mat_trim)
		_box(root, Vector3(72.0, 0.12, 0.5), Vector3(80.0, 0.98, side * 28.0), _mat_glow)


func _build_continuous_ring() -> void:
	ring_root = Node3D.new()
	ring_root.name = "RotatingRing"
	add_child(ring_root)
	var ring_mesh := _make_ring_mesh(96, RING_RADIUS, RING_HALF_WIDTH, RING_HALF_HEIGHT, 0.0)
	var ring_instance := MeshInstance3D.new()
	ring_instance.name = "ContinuousRing"
	ring_instance.mesh = ring_mesh
	var hull_material := _mat(Color("46555c"), 0.62, 0.46)
	hull_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_instance.material_override = hull_material
	ring_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_root.add_child(ring_instance)
	_add_static_shape(exterior_body, ring_mesh.create_trimesh_shape(), Vector3.ZERO)
	for band_y: float in [-RING_HALF_HEIGHT - 0.12, RING_HALF_HEIGHT + 0.12]:
		var band := MeshInstance3D.new()
		band.mesh = _make_ring_mesh(96, RING_RADIUS, RING_HALF_WIDTH - 0.3, 0.1, band_y)
		var band_material := _glow_mat(Color("4aa9a4"), 0.8)
		band_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		band.material_override = band_material
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring_root.add_child(band)
	var outer_band := MeshInstance3D.new()
	outer_band.mesh = _make_ring_mesh(96, RING_RADIUS + RING_HALF_WIDTH, 0.18, 0.12, 0.0)
	var outer_material := _glow_mat(Color("4aa9a4"), 0.65)
	outer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	outer_band.material_override = outer_material
	outer_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_root.add_child(outer_band)
	var inner_band := MeshInstance3D.new()
	inner_band.mesh = _make_ring_mesh(96, RING_RADIUS - RING_HALF_WIDTH, 0.18, 0.12, 0.0)
	var inner_material := _glow_mat(Color("4aa9a4"), 0.55)
	inner_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	inner_band.material_override = inner_material
	inner_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_root.add_child(inner_band)
	for i in range(36):
		var angle := TAU * float(i) / 36.0
		var rib := Node3D.new()
		rib.position = Vector3(cos(angle) * (RING_RADIUS + RING_HALF_WIDTH + 0.12), 0.0, sin(angle) * (RING_RADIUS + RING_HALF_WIDTH + 0.12))
		rib.rotation.y = -angle
		ring_root.add_child(rib)
		_box(rib, Vector3(0.55, RING_HALF_HEIGHT * 2.0 + 0.4, 0.55), Vector3.ZERO, _mat_trim)
	for i in range(40):
		var angle := TAU * float(i) / 40.0
		for y: float in [-2.6, 2.6]:
			_box(ring_root, Vector3(3.0, 1.5, 0.14),
				Vector3(cos(angle) * (RING_RADIUS + RING_HALF_WIDTH + 0.06), y, sin(angle) * (RING_RADIUS + RING_HALF_WIDTH + 0.06)),
				_mat_warm if i % 4 != 0 else _mat_teal, Vector3(0.0, -angle + PI * 0.5, 0.0))
	for i in range(32):
		var angle := TAU * float(i) / 32.0
		for y: float in [-4.2, 0.0, 4.2]:
			_box(ring_root, Vector3(3.4, 1.6, 0.14),
				Vector3(cos(angle) * (RING_RADIUS - RING_HALF_WIDTH - 0.06), y, sin(angle) * (RING_RADIUS - RING_HALF_WIDTH - 0.06)),
				_mat_warm if i % 5 == 0 else _mat_teal, Vector3(0.0, -angle + PI * 0.5, 0.0))


func _make_ring_mesh(segments: int, radius: float, half_width: float, half_height: float, y_offset: float) -> ArrayMesh:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var indices: Array[int] = []
	var outer_radius := radius + half_width
	var inner_radius := radius - half_width
	var bottom := y_offset - half_height
	var top := y_offset + half_height
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var radial := (d0 + d1).normalized()
		_add_ring_quad(vertices, normals, indices,
			Vector3(d0.x * outer_radius, bottom, d0.z * outer_radius),
			Vector3(d1.x * outer_radius, bottom, d1.z * outer_radius),
			Vector3(d1.x * outer_radius, top, d1.z * outer_radius),
			Vector3(d0.x * outer_radius, top, d0.z * outer_radius), radial)
		_add_ring_quad(vertices, normals, indices,
			Vector3(d1.x * inner_radius, bottom, d1.z * inner_radius),
			Vector3(d0.x * inner_radius, bottom, d0.z * inner_radius),
			Vector3(d0.x * inner_radius, top, d0.z * inner_radius),
			Vector3(d1.x * inner_radius, top, d1.z * inner_radius), -radial)
		_add_ring_quad(vertices, normals, indices,
			Vector3(d0.x * outer_radius, top, d0.z * outer_radius),
			Vector3(d1.x * outer_radius, top, d1.z * outer_radius),
			Vector3(d1.x * inner_radius, top, d1.z * inner_radius),
			Vector3(d0.x * inner_radius, top, d0.z * inner_radius), Vector3.UP)
		_add_ring_quad(vertices, normals, indices,
			Vector3(d0.x * inner_radius, bottom, d0.z * inner_radius),
			Vector3(d1.x * inner_radius, bottom, d1.z * inner_radius),
			Vector3(d1.x * outer_radius, bottom, d1.z * outer_radius),
			Vector3(d0.x * outer_radius, bottom, d0.z * outer_radius), Vector3.DOWN)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_ring_quad(vertices: Array, normals: Array, indices: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var base := vertices.size()
	for point in [a, b, c, d]:
		vertices.append(point)
		normals.append(normal)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)


func _build_shuttle(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var shuttle_body := StaticBody3D.new()
	shuttle_body.collision_layer = 4
	shuttle_body.collision_mask = 0
	root.add_child(shuttle_body)
	var shuttle_shape := BoxShape3D.new()
	shuttle_shape.size = Vector3(9.0, 3.0, 13.0)
	_add_static_shape(shuttle_body, shuttle_shape, Vector3.ZERO)
	_box(root, Vector3(4.0, 2.0, 13.0), Vector3.ZERO, _mat_white)
	_box(root, Vector3(2.2, 1.0, 3.0), Vector3(0.0, 1.3, -4.0), _mat_glass)
	_box(root, Vector3(9.0, 0.4, 3.0), Vector3(0.0, -0.6, 1.0), _mat_trim)
	for side: float in [-1.0, 1.0]:
		_cylinder(root, 1.0, 1.2, 2.5, Vector3(side * 2.5, -0.2, 4.5), _mat_dark, 10, Vector3(PI * 0.5, 0.0, 0.0))
		_sphere(root, 0.5, Vector3(side * 2.5, -0.2, 5.9), _glow_mat(Color("67dceb"), 2.0))
	_box(root, Vector3(0.2, 0.2, 6.0), Vector3(0.0, 1.2, 1.0), _mat_trim)


func _build_corridor_detail() -> void:
	var intervals := [
		Vector2(-105.0, -85.6), Vector2(-82.4, -57.6), Vector2(-54.4, -29.6),
		Vector2(-26.4, -13.0), Vector2(13.0, 26.4), Vector2(29.6, 54.4),
		Vector2(57.6, 82.4), Vector2(85.6, 105.0)
	]
	for side: float in [-1.0, 1.0]:
		for interval in intervals:
			var length: float = interval.y - interval.x
			var center: float = (interval.x + interval.y) * 0.5
			_box(self, Vector3(length - 1.2, 2.2, 0.06), Vector3(center, 0.2, side * 3.43), _mat_dark)
			_box(self, Vector3(length - 2.2, 1.7, 0.03), Vector3(center, 0.2, side * 3.385), _mat_wall)
			_box(self, Vector3(length - 2.6, 0.05, 0.02), Vector3(center, 0.95, side * 3.365), _mat_trim)
			_box(self, Vector3(length - 2.6, 0.05, 0.02), Vector3(center, -0.55, side * 3.365), _mat_trim)
			for edge: float in [-1.0, 1.0]:
				_box(self, Vector3(0.12, 2.3, 0.16), Vector3(center + edge * (length * 0.5 - 0.55), 0.2, side * 3.4), _mat_trim)
				_sphere(self, 0.05, Vector3(center + edge * (length * 0.5 - 0.65), 1.3, side * 3.38), _mat_trim)
				_sphere(self, 0.05, Vector3(center + edge * (length * 0.5 - 0.65), -0.9, side * 3.38), _mat_trim)
			for k in range(3):
				_box(self, Vector3(0.8, 0.045, 0.025), Vector3(center - 0.5 + float(k) * 0.5, 0.35, side * 3.36), _mat_trim)
			_cylinder(self, 0.07, 0.07, length - 1.4, Vector3(center, 1.85, side * 3.3), _mat_trim, 8, Vector3(0.0, 0.0, PI * 0.5))
			_cylinder(self, 0.05, 0.05, length - 1.4, Vector3(center, -1.35, side * 3.3), _mat_dark, 6, Vector3(0.0, 0.0, PI * 0.5))
			_cylinder(self, 0.035, 0.035, length - 1.0, Vector3(center, 0.72, side * 3.24), _mat_trim, 6, Vector3(0.0, 0.0, PI * 0.5))
			_box(self, Vector3(0.65, 0.05, 0.1), Vector3(center, 2.32, side * 3.39), _mat_glow)
	for side: float in [-1.0, 1.0]:
		_cylinder(self, 0.09, 0.09, 204.0, Vector3(0.0, 2.52, side * 2.7), _mat_trim, 8, Vector3(0.0, 0.0, PI * 0.5))
		_box(self, Vector3(204.0, 0.1, 0.34), Vector3(0.0, 2.42, side * 2.52), _mat_dark)
		for x in range(-100, 101, 8):
			_box(self, Vector3(0.22, 0.05, 0.46), Vector3(float(x), 2.36, side * 2.52), _mat_trim)
	for x in range(-102, 103, 6):
		_box(self, Vector3(0.16, 0.16, 7.0), Vector3(float(x), 2.68, 0.0), _mat_dark)
	for x in range(-100, 101, 4):
		_box(self, Vector3(0.025, 0.02, 6.9), Vector3(float(x), FLOOR_TOP + 0.015, 0.0), _mat_dark)
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(204.0, 0.035, 0.32), Vector3(0.0, FLOOR_TOP + 0.02, side * 3.12), _mat_dark)
		for x in range(-100, 101, 2):
			_box(self, Vector3(0.07, 0.025, 0.28), Vector3(float(x), FLOOR_TOP + 0.03, side * 3.12), _mat_trim)
	for x in ROOM_CENTERS:
		for side: float in [-1.0, 1.0]:
			for edge: float in [-1.0, 1.0]:
				_cylinder(self, 0.08, 0.08, 0.9, Vector3(x + edge * 2.0, -1.15, side * 3.34), _mat_trim, 8)
				_box(self, Vector3(0.14, 0.14, 0.42), Vector3(x + edge * 2.0, -0.62, side * 3.34), _mat_dark)
				_box(self, Vector3(0.12, 0.1, 0.04), Vector3(x + edge * 2.0, 2.0, side * 3.34), _mat_glow)
			for k in range(4):
				_box(self, Vector3(0.55, 0.02, 0.16), Vector3(x - 2.0 + float(k) * 1.35, FLOOR_TOP + 0.03, side * 3.14), _mat_orange)


func _arrange_corridors() -> void:
	if interior_root == null:
		return
	var template := interior_root
	var old_parent := template.get_parent()
	if old_parent != null:
		old_parent.remove_child(template)
	for i in range(CORRIDOR_COUNT):
		var angle := TAU * float(i) / float(CORRIDOR_COUNT)
		var container := Node3D.new()
		container.name = "CorridorContainer%d" % i
		container.position = Vector3(cos(angle) * HUB_RADIUS, 0.0, sin(angle) * HUB_RADIUS)
		container.rotation.y = -angle
		add_child(container)
		var root: Node3D
		if i == 0:
			root = template
		else:
			root = template.duplicate()
		container.add_child(root)
		root.name = "Corridor%d" % i
		root.visible = false
		corridor_roots.append(root)
		# 记下这条走廊的站内碰撞形状，好在切走廊时把看不见的五条从物理世界里摘掉。
		var shapes: Array = []
		var collision_body := root.find_child("StationCollision", true, false)
		if collision_body != null:
			for node in collision_body.get_children():
				if node is CollisionShape3D:
					shapes.append(node)
		corridor_shapes.append(shapes)
		corridor_collision_state.append(true)


func _add_hub_box_collider(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = pos
	collider.rotation = rot
	hub_body.add_child(collider)


func _add_hub_cylinder_collider(radius: float, height: float, pos: Vector3) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = pos
	hub_body.add_child(collider)


func _add_static_shape(body: PhysicsBody3D, shape: Shape3D, pos: Vector3, rot := Vector3.ZERO) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = pos
	collider.rotation = rot
	body.add_child(collider)


func _add_exterior_sphere_collider(radius: float, pos: Vector3) -> void:
	var shape := SphereShape3D.new()
	shape.radius = radius
	_add_static_shape(exterior_body, shape, pos)


func _add_exterior_cylinder_collider(radius: float, height: float, pos: Vector3, rot := Vector3.ZERO) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_add_static_shape(exterior_body, shape, pos, rot)


func _add_exterior_box_collider(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_add_static_shape(exterior_body, shape, pos, rot)


func _build_hub_wall_detail(wall: Node3D) -> void:
	_box(wall, Vector3(0.16, 6.8, 19.2), Vector3(-0.27, 3.2, 0.0), _mat_dark)
	for y: float in [1.25, 6.55]:
		_box(wall, Vector3(0.22, 0.14, 19.6), Vector3(-0.36, y, 0.0), _mat_trim)
	for z: float in [-9.4, -4.5, 4.5, 9.4]:
		_box(wall, Vector3(0.2, 6.2, 0.22), Vector3(-0.37, 3.1, z), _mat_trim)
	_build_hub_screen(wall, Vector3(-0.4, 4.05, 0.0), Vector2(7.0, 3.8), true)
	for z: float in [-6.9, 6.9]:
		_build_hub_screen(wall, Vector3(-0.4, 4.05, z), Vector2(3.0, 2.4), false)
	for side: float in [-1.0, 1.0]:
		for k in range(5):
			_box(wall, Vector3(0.08, 0.05, 2.4), Vector3(-0.4, 1.42 + float(k) * 0.14, side * 7.6), _mat_trim)
		_box(wall, Vector3(0.08, 0.05, 0.05), Vector3(-0.4, 2.15, side * 8.55), _mat_glow)
		_box(wall, Vector3(0.12, 0.95, 1.35), Vector3(-0.39, 0.55, side * 2.9), _mat_trim)
		_box(wall, Vector3(0.06, 0.08, 0.9), Vector3(-0.46, 0.75, side * 2.9), _mat_teal)
	# 长凳与角落植栽
	_box(wall, Vector3(0.78, 0.14, 3.4), Vector3(-0.68, -1.52, 0.0), _mat_teal)
	_box(wall, Vector3(0.12, 0.95, 3.4), Vector3(-0.34, -1.05, 0.0), _mat_teal)
	for z: float in [-1.4, 1.4]:
		_box(wall, Vector3(0.55, 0.42, 0.14), Vector3(-0.88, -1.76, z), _mat_dark)
	_add_hub_box_collider(Vector3(0.78, 0.14, 3.4), wall.transform * Vector3(-0.68, -1.52, 0.0), wall.rotation)
	for z: float in [-9.0, 9.0]:
		_cylinder(wall, 0.46, 0.52, 0.7, Vector3(-0.95, -1.64, z), _mat_dark, 12)
		_sphere(wall, 0.56, Vector3(-0.95, -1.02, z), _mat_green, Vector3(1.0, 1.15, 1.0))
		_add_hub_box_collider(Vector3(1.0, 1.7, 1.0), wall.transform * Vector3(-0.95, -1.2, z), wall.rotation)


func _build_hub_screen(wall: Node3D, center: Vector3, size: Vector2, main: bool) -> void:
	var width := size.x
	var height := size.y
	_box(wall, Vector3(0.08, height + 0.26, width + 0.26), center, _mat_trim)
	_box(wall, Vector3(0.05, height, width), center + Vector3(-0.07, 0.0, 0.0), _mat_screen)
	for edge: float in [-1.0, 1.0]:
		_box(wall, Vector3(0.05, 0.045, width), center + Vector3(-0.1, edge * (height * 0.5 - 0.03), 0.0), _mat_teal)
		_box(wall, Vector3(0.05, height, 0.045), center + Vector3(-0.1, 0.0, edge * (width * 0.5 - 0.03)), _mat_teal)
	if main:
		_build_hub_schematic(wall, center + Vector3(-0.12, -0.1, 0.0), 1.1)
		for k in range(CORRIDOR_COUNT):
			var side := -1.0 if k < 3 else 1.0
			var row := k % 3
			_label("%s  %s" % [String.chr(65 + k), CORRIDOR_NAMES[k]],
				center + Vector3(-0.16, 1.02 - float(row) * 0.6, side * 2.55),
				28, 0.0065, -PI * 0.5, Color("8fc9c7"), wall)
		_label("环区态势", center + Vector3(-0.16, height * 0.5 - 0.4, 0.0),
			36, 0.0085, -PI * 0.5, Color("ffe4b4"), wall)
	else:
		for k in range(4):
			var bar_len := 0.72 + 0.22 * float(k)
			_box(wall, Vector3(0.05, 0.06, bar_len), center + Vector3(-0.14, 0.62 - float(k) * 0.42, -width * 0.5 + 0.4 + bar_len * 0.5),
				_mat_glow if k % 2 == 0 else _mat_teal)
		_box(wall, Vector3(0.05, 0.62, 0.06), center + Vector3(-0.14, 0.25, width * 0.32), _mat_orange)


func _build_hub_schematic(wall: Node3D, center: Vector3, radius: float) -> void:
	var points: Array[Vector2] = []
	for i in range(CORRIDOR_COUNT):
		var angle := TAU * float(i) / float(CORRIDOR_COUNT) - PI * 0.5
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	for i in range(CORRIDOR_COUNT):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % CORRIDOR_COUNT]
		_hub_segment(wall, center, a, b, _mat_teal, 0.035)
		_hub_segment(wall, center, Vector2.ZERO, a * 0.72, _mat_trim, 0.025)
		_box(wall, Vector3(0.05, 0.09, 0.09), center + Vector3(0.0, a.y, a.x), _mat_glow)
	_sphere(wall, 0.15, center, _mat_glow)


func _hub_segment(wall: Node3D, center: Vector3, a: Vector2, b: Vector2, material: Material, thickness: float) -> void:
	var direction := b - a
	var mid := (a + b) * 0.5
	_box(wall, Vector3(0.05, thickness, direction.length()),
		center + Vector3(0.0, mid.y, mid.x), material, Vector3(atan2(-direction.y, direction.x), 0.0, 0.0))


func _build_hub() -> void:
	hub_root = Node3D.new()
	hub_root.name = "StationHub"
	add_child(hub_root)
	hub_root.visible = false
	hub_body = StaticBody3D.new()
	hub_body.name = "HubCollision"
	hub_body.collision_layer = 1
	hub_body.collision_mask = 0
	hub_root.add_child(hub_body)
	_cylinder(hub_root, 34.0, 34.0, 0.4, Vector3(0.0, FLOOR_TOP - 0.2, 0.0), _mat_floor, 48)
	_add_hub_cylinder_collider(34.0, 0.4, Vector3(0.0, FLOOR_TOP - 0.2, 0.0))
	_cylinder(hub_root, 34.0, 34.0, 0.3, Vector3(0.0, 8.15, 0.0), _mat_wall, 48)
	_add_hub_cylinder_collider(34.0, 0.3, Vector3(0.0, 8.15, 0.0))
	_torus(hub_root, 8.0, 8.2, Vector3(0.0, FLOOR_TOP + 0.03, 0.0), _mat_teal, Vector3.ZERO, 8, 48)
	_torus(hub_root, 20.0, 20.18, Vector3(0.0, FLOOR_TOP + 0.03, 0.0), _mat_teal, Vector3.ZERO, 8, 64)
	for i in range(12):
		var seam := TAU * float(i) / 12.0
		_box(hub_root, Vector3(26.0, 0.02, 0.05), Vector3(cos(seam) * 15.0, FLOOR_TOP + 0.045, sin(seam) * 15.0), _mat_dark, Vector3(0.0, -seam, 0.0))
	# ── 中央立柱（2026-11-10 精简）────────────────────────────────
	# 原先这里是一整圈「升降梯」装饰：4 米圆柱外壳 + 8 根竖条 + 4 个凹槽 +
	# 4 道环 + 4 扇 lift_door 假门（有门缝、橙色警示条、小灯球）+ 18 块警示
	# 地砖 + 两块「中央升降梯」标牌 + 灯杆 + 顶灯球。
	#
	# 问题：那些假门长得太像能开的门，玩家反复去撞、以为卡 bug；
	# 而且它们贴在半径 4 米的实心柱面上，本来就只是为了「看着像升降梯」。
	# 既然进不去，就不该摆出要请你进去的样子 —— 全部删掉，只留一根光柱。
	_cylinder(hub_root, 3.2, 3.2, 10.0, Vector3(0.0, 3.0, 0.0), _mat_hull, 24)
	_add_hub_cylinder_collider(3.2, 10.0, Vector3(0.0, 3.0, 0.0))
	# 柱脚一圈收边 + 一道细环，让这根柱子有「结构件」的收口，不至于秃得太难看
	_cylinder(hub_root, 3.5, 3.5, 0.3, Vector3(0.0, FLOOR_TOP + 0.05, 0.0), _mat_trim, 32)
	_torus(hub_root, 3.22, 3.34, Vector3(0.0, 2.4, 0.0), _mat_trim, Vector3.ZERO, 8, 48)
	_torus(hub_root, 3.24, 3.5, Vector3(0.0, 7.35, 0.0), _mat_trim, Vector3.ZERO, 8, 48)
	_cylinder(hub_root, 2.4, 2.8, 1.0, Vector3(0.0, FLOOR_TOP + 0.5, -10.0), _mat_dark, 20)
	_cylinder(hub_root, 2.5, 2.5, 0.1, Vector3(0.0, FLOOR_TOP + 1.02, -10.0), _mat_glass, 32)
	_torus(hub_root, 2.0, 2.4, Vector3(0.0, FLOOR_TOP + 1.2, -10.0), _mat_teal, Vector3.ZERO, 8, 32)
	_cylinder(hub_root, 0.16, 0.16, 1.2, Vector3(0.0, FLOOR_TOP + 1.13, -10.0), _mat_glow, 8)
	hub_hologram = Node3D.new()
	hub_hologram.position = Vector3(0.0, 0.45, -10.0)
	hub_hologram.scale = Vector3.ONE * 0.9
	hub_hologram.rotation.x = 0.26
	hub_root.add_child(hub_hologram)
	_torus(hub_hologram, 1.9, 2.05, Vector3.ZERO, _mat_teal, Vector3.ZERO, 8, 48)
	_torus(hub_hologram, 1.45, 1.52, Vector3(0.0, 0.35, 0.0), _mat_glow, Vector3(PI * 0.28, 0.0, PI * 0.18), 8, 40)
	for i in range(CORRIDOR_COUNT):
		var holo_angle := TAU * float(i) / float(CORRIDOR_COUNT)
		_box(hub_hologram, Vector3(1.75, 0.06, 0.08), Vector3(cos(holo_angle) * 0.95, 0.0, sin(holo_angle) * 0.95),
			_mat_glow, Vector3(0.0, -holo_angle, 0.0))
		_sphere(hub_hologram, 0.2, Vector3(cos(holo_angle) * 1.95, 0.0, sin(holo_angle) * 1.95), _mat_glow)
		_cylinder(hub_hologram, 0.02, 0.02, 0.72, Vector3(cos(holo_angle) * 1.95, 0.42, sin(holo_angle) * 1.95), _mat_teal, 6)
	_sphere(hub_hologram, 0.3, Vector3.ZERO, _mat_teal)
	_label("中央枢纽", Vector3(0.0, 4.8, -10.0), 48, 0.012, 0.0, Color("d9b879"), hub_root)
	_cylinder(hub_root, 6.0, 6.4, 0.12, Vector3(0.0, FLOOR_TOP + 0.06, 12.0), _mat_floor, 40)
	_torus(hub_root, 5.8, 6.1, Vector3(0.0, FLOOR_TOP + 0.13, 12.0), _mat_teal, Vector3.ZERO, 8, 48)
	for i in range(14):
		var pad_angle := TAU * float(i) / 14.0
		_box(hub_root, Vector3(0.55, 0.018, 0.3), Vector3(cos(pad_angle) * 6.05, FLOOR_TOP + 0.16, 12.0 + sin(pad_angle) * 6.05),
			_mat_orange if i % 2 == 0 else _mat_dark, Vector3(0.0, -pad_angle, 0.0))
	_box(hub_root, Vector3(3.2, 1.0, 1.1), Vector3(0.0, FLOOR_TOP + 0.55, 12.0), _mat_dark)
	_add_hub_box_collider(Vector3(3.2, 1.0, 1.1), Vector3(0.0, FLOOR_TOP + 0.55, 12.0))
	_box(hub_root, Vector3(2.2, 0.5, 0.06), Vector3(0.0, FLOOR_TOP + 0.85, 12.56), _mat_glow)
	_box(hub_root, Vector3(2.2, 0.5, 0.06), Vector3(0.0, FLOOR_TOP + 0.85, 11.44), _mat_glow)
	_box(hub_root, Vector3(0.6, 0.14, 0.05), Vector3(-1.0, FLOOR_TOP + 0.85, 11.44), _mat_teal)
	_box(hub_root, Vector3(0.6, 0.14, 0.05), Vector3(1.0, FLOOR_TOP + 0.85, 11.44), _mat_orange)
	_torus(hub_root, 1.2, 1.6, Vector3(0.0, FLOOR_TOP + 0.04, 12.0), _mat_glow, Vector3.ZERO, 8, 32)
	for side: float in [-1.0, 1.0]:
		_box(hub_root, Vector3(0.42, 3.6, 0.42), Vector3(side * 3.6, -0.2, 13.4), _mat_trim)
		_add_hub_box_collider(Vector3(0.42, 3.6, 0.42), Vector3(side * 3.6, -0.2, 13.4))
		_box(hub_root, Vector3(0.08, 2.6, 0.08), Vector3(side * 3.6, -0.1, 13.16), _mat_glow)
		_box(hub_root, Vector3(0.5, 0.3, 0.08), Vector3(side * 3.6, 1.3, 13.16), _mat_dark)
		_sphere(hub_root, 0.1, Vector3(side * 3.6, 1.3, 13.09), _mat_teal)
	_box(hub_root, Vector3(5.4, 1.1, 0.16), Vector3(0.0, 2.35, 14.0), _mat_dark)
	for side: float in [-1.0, 1.0]:
		_box(hub_root, Vector3(0.22, 4.9, 0.22), Vector3(side * 2.9, 0.45, 14.0), _mat_trim)
		_box(hub_root, Vector3(0.08, 2.6, 0.08), Vector3(side * 2.9, 0.85, 13.86), _mat_teal)
		_add_hub_box_collider(Vector3(0.22, 4.9, 0.22), Vector3(side * 2.9, 0.45, 14.0))
	_label("气闸", Vector3(0.0, 2.35, 13.9), 48, 0.011, PI, Color("f0e0bd"), hub_root)
	_label("归航站", Vector3(0.0, 2.35, 14.1), 40, 0.0095, 0.0, Color("d9b879"), hub_root)
	for i in range(CORRIDOR_COUNT):
		var lane_angle := TAU * float(i) / float(CORRIDOR_COUNT)
		for offset: float in [-0.32, 0.32]:
			_box(hub_root, Vector3(20.0, 0.02, 0.09),
				Vector3(cos(lane_angle) * 16.5 - sin(lane_angle) * offset, FLOOR_TOP + 0.05, sin(lane_angle) * 16.5 + cos(lane_angle) * offset),
				_mat_teal, Vector3(0.0, -lane_angle, 0.0))
	for i in range(CORRIDOR_COUNT):
		var angle := TAU * float(i) / float(CORRIDOR_COUNT)
		var door := Node3D.new()
		door.name = "HubDoor%d" % i
		door.position = Vector3(cos(angle) * HUB_RADIUS, 0.0, sin(angle) * HUB_RADIUS)
		door.rotation.y = -angle
		hub_root.add_child(door)
		for side: float in [-1.0, 1.0]:
			_box(door, Vector3(0.35, 4.8, 0.4), Vector3(0.0, 0.4, side * 3.7), _mat_trim)
			_add_hub_box_collider(Vector3(0.35, 4.8, 0.4), door.transform * Vector3(0.0, 0.4, side * 3.7), door.rotation)
			_cylinder(door, 0.1, 0.1, 3.0, Vector3(-0.2, 0.0, side * 3.45), _mat_trim, 8)
			_box(door, Vector3(0.18, 0.12, 0.12), Vector3(-0.2, 1.7, side * 3.45), _mat_glow)
		_box(door, Vector3(0.35, 0.3, 7.8), Vector3(0.0, 2.9, 0.0), _mat_trim)
		var leaf := Node3D.new()
		leaf.name = "DoorLeaves"
		door.add_child(leaf)
		# 放气门分成左右两扇，开门时从中缝滑向两侧的门框，碰撞随门扇一起移动。
		for side: float in [-1.0, 1.0]:
			var half := Node3D.new()
			half.name = "DoorLeaf%s" % ("L" if side < 0.0 else "R")
			half.set_meta("door_side", side)
			half.position = Vector3(0.0, 0.0, side * DOOR_HALF_WIDTH)
			leaf.add_child(half)
			var panel := _box(half, Vector3(0.18, 4.8, DOOR_HALF_WIDTH * 2.0), Vector3(0.0, 0.4, 0.0), _mat_dark)
			panel.name = "DoorPanel"
			_box(half, Vector3(0.12, 0.1, 2.6), Vector3(-0.16, 0.9, 0.0), _mat_glow)
			_box(half, Vector3(0.12, 0.1, 2.6), Vector3(-0.16, -0.6, 0.0), _mat_teal)
			# 门号画在左门扇上，关门时正好落在门洞正中，开门时跟着门扇一起滑走。
			if side < 0.0:
				_label(String.chr(65 + i), Vector3(-0.12, 0.15, DOOR_HALF_WIDTH), 100, 0.012, -PI * 0.5, Color("4f8f8b"), half)
			var panel_body := StaticBody3D.new()
			panel_body.name = "HubDoorCollision%d%s" % [i, "L" if side < 0.0 else "R"]
			panel_body.collision_layer = 1
			panel_body.collision_mask = 0
			half.add_child(panel_body)
			var panel_shape := BoxShape3D.new()
			panel_shape.size = Vector3(0.28, 4.8, DOOR_HALF_WIDTH * 2.0)
			_add_static_shape(panel_body, panel_shape, Vector3(0.0, 0.4, 0.0))
		door_panels.append(leaf)
		door_open.append(0.0)
		door_state.append(0)
		_box(door, Vector3(0.2, 0.12, 6.2), Vector3(-0.14, -1.72, 0.0), _mat_orange)
		for k in range(8):
			_box(door, Vector3(1.4, 0.02, 0.42), Vector3(-0.95, FLOOR_TOP + 0.04, -3.15 + float(k) * 0.9),
				_mat_orange if k % 2 == 0 else _mat_dark)
		_box(door, Vector3(0.4, 5.2, 7.8), Vector3(0.0, 5.4, 0.0), _mat_wall)
		_add_hub_box_collider(Vector3(0.4, 5.2, 7.8), door.transform * Vector3(0.0, 5.4, 0.0), door.rotation)
		_box(door, Vector3(0.1, 1.0, 5.4), Vector3(-0.28, 3.6, 0.0), _mat_dark)
		_label("%s  %s" % [String.chr(65 + i), CORRIDOR_NAMES[i]], Vector3(-0.36, 3.62, 0.0), 44, 0.011, -PI * 0.5, Color("ffe4b4"), door)
		for side: float in [-1.0, 1.0]:
			_sphere(door, 0.07, Vector3(-0.2, 2.62, side * 3.35), _mat_trim)
			_sphere(door, 0.07, Vector3(-0.2, -1.88, side * 3.35), _mat_trim)
		_box(door, Vector3(26.0, 0.2, 0.3), Vector3(15.0, 7.7, 0.0), _mat_dark)
		_box(door, Vector3(24.0, 0.025, 0.08), Vector3(15.0, FLOOR_TOP + 0.04, 0.0), _mat_glow)
		_light(Vector3(cos(angle) * 25.5, 2.6, sin(angle) * 25.5), Color("ffd8ac"), 1.0, 12.0, hub_root)
		# 注：门两侧原先在这里补过一小段侧墙，但间隔墙改到门洞同一半径、
		# 并按「弧长 - 门洞宽」精确填满之后，缝隙已经不存在了 ——
		# 侧墙反而会压到门洞上，所以去掉。
		var mid_angle := angle + TAU / 12.0
		var wall := Node3D.new()
		wall.position = Vector3(cos(mid_angle) * HUB_RADIUS, 0.0, sin(mid_angle) * HUB_RADIUS)
		wall.rotation.y = -mid_angle
		hub_root.add_child(wall)
		# 间隔墙改到**门洞所在的同一个半径**（HUB_RADIUS），并且按 30° 角距算出
		# 正好填满两门之间的弧长。
		#
		# 原来这道墙在半径 28.5、宽 21 米：一是比门洞靠里 1.5 米，留下一条能斜穿
		# 出去的径向缝；二是半径 28.5 处每扇门占弧长 29.85 米，21 米的墙两侧各漏
		# 4.42 米。两者相加，玩家从枢纽里能直接看到站外虚空（实测截图确认）。
		#
		# 现在墙贴在门洞半径上，宽度取「弧长 - 门洞宽 + 一点重叠」，与门框咬合。
		var arc_span: float = TAU * HUB_RADIUS / float(CORRIDOR_COUNT)
		var wall_span: float = arc_span - DOOR_HALF_WIDTH * 2.0
		_box(wall, Vector3(0.5, 10.0, wall_span), Vector3(0.0, 3.0, 0.0), _mat_wall)
		_add_hub_box_collider(Vector3(0.5, 10.0, wall_span), wall.transform * Vector3(0.0, 3.0, 0.0), wall.rotation)
		_build_hub_wall_detail(wall)
		_light(Vector3(cos(mid_angle) * 20.0, 6.3, sin(mid_angle) * 20.0), Color("ffd8ac"), 1.3, 18.0, hub_root)
	for i in range(12):
		var beam_angle := TAU * float(i) / 12.0
		_box(hub_root, Vector3(23.6, 0.24, 0.26), Vector3(cos(beam_angle) * 16.0, 7.92, sin(beam_angle) * 16.0),
			_mat_trim, Vector3(0.0, -beam_angle, 0.0))
		_sphere(hub_root, 0.09, Vector3(cos(beam_angle) * 5.25, 7.72, sin(beam_angle) * 5.25), _mat_glow)
	for radius in [10.0, 18.0, 26.0]:
		_torus(hub_root, radius - 0.3, radius + 0.3, Vector3(0.0, 7.55, 0.0), _mat_trim, Vector3.ZERO, 8, 64)
	_light(Vector3(0.0, 7.0, 0.0), Color("ffd8ac"), 1.8, 26.0, hub_root)
	# 枢纽的静态网格也合并；全息沙盘会旋转、六扇门的活动门扇会滑动，都必须排除。
	var hub_skip: Array = []
	if hub_hologram != null:
		hub_skip.append(hub_hologram)
	for leaf in door_panels:
		hub_skip.append(leaf)
	_merge_static_meshes(hub_root, hub_skip, "HubMerged")
	_build_hub_detail()
	# 外塔和能源核心的碰撞挂在 hub_body 上，飞船靠近时不会穿模。
	_add_hub_cylinder_collider(22.0, 64.0, Vector3(0.0, 60.0, 0.0))
	_add_hub_cylinder_collider(11.5, 152.0, Vector3(0.0, 167.0, 0.0))
	_add_hub_cylinder_collider(15.0, 20.0, Vector3(0.0, 251.0, 0.0))
	_add_hub_cylinder_collider(18.5, 58.0, Vector3(0.0, -58.0, 0.0))
	_add_hub_cylinder_collider(10.5, 134.0, Vector3(0.0, -157.0, 0.0))


# 枢纽补充细节：所有盒子合并成一张 8 材质网格，只占 1 个节点、8 次绘制。
func _build_hub_detail() -> void:
	var buckets := [
		[_mat_trim, SurfaceTool.new(), 0],
		[_mat_dark, SurfaceTool.new(), 0],
		[_mat_teal, SurfaceTool.new(), 0],
		[_mat_glow, SurfaceTool.new(), 0],
		[_mat_orange, SurfaceTool.new(), 0],
		[_mat_floor, SurfaceTool.new(), 0],
		[_mat_lift, SurfaceTool.new(), 0],
		[_mat_wall, SurfaceTool.new(), 0],
	]
	for bucket in buckets:
		var tool: SurfaceTool = bucket[1]
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_hub_detail_floor(buckets)
	_hub_detail_ceiling(buckets)
	_hub_detail_walls(buckets)
	_hub_detail_lift(buckets)
	_hub_detail_doors(buckets)
	var mesh := ArrayMesh.new()
	for bucket in buckets:
		if int(bucket[2]) <= 0:
			continue
		var tool: SurfaceTool = bucket[1]
		tool.set_material(bucket[0])
		tool.commit(mesh)
	if mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "HubDetail"
	node.mesh = mesh
	hub_root.add_child(node)


func _hub_detail_floor(buckets: Array) -> void:
	var trim: Array = buckets[0]
	var dark: Array = buckets[1]
	for radius: float in [11.0, 17.0, 23.0, 29.0]:
		var segments := 24
		var chord := 2.0 * radius * sin(PI / float(segments))
		for k in range(segments):
			var a := TAU * float(k) / float(segments)
			_detail_box(dark, Vector3(0.055, 0.02, chord * 0.94), _hub_detail_frame(a, radius, FLOOR_TOP + 0.012, 0.0, 0.0), -a)
	for i in range(CORRIDOR_COUNT):
		var a := TAU * float(i) / float(CORRIDOR_COUNT) + TAU / 12.0
		_detail_box(dark, Vector3(1.0, 0.05, 1.0), _hub_detail_frame(a, 26.0, FLOOR_TOP + 0.028, 0.0, 0.0), -a)
		for k in range(5):
			_detail_box(trim, Vector3(0.09, 0.02, 0.86),
				_hub_detail_frame(a, 26.0, FLOOR_TOP + 0.062, 0.0, float(k - 2) * 0.19), -a)
	for k in range(12):
		var a := TAU * float(k) / 12.0
		_detail_box(trim, Vector3(0.1, 0.03, 0.1), _hub_detail_frame(a, 5.2, FLOOR_TOP + 0.02, 0.0, 0.0), -a)


func _hub_detail_ceiling(buckets: Array) -> void:
	var trim: Array = buckets[0]
	var dark: Array = buckets[1]
	var teal: Array = buckets[2]
	var glow: Array = buckets[3]
	var orange: Array = buckets[4]
	# 六条放射电缆桥架
	for i in range(CORRIDOR_COUNT):
		var a := TAU * float(i) / float(CORRIDOR_COUNT) + TAU / 12.0
		_detail_box(dark, Vector3(21.0, 0.06, 0.52), _hub_detail_frame(a, 16.0, 7.74, 0.0, 0.0), -a)
		for side: float in [-1.0, 1.0]:
			_detail_box(trim, Vector3(21.0, 0.16, 0.06), _hub_detail_frame(a, 16.0, 7.8, 0.0, side * 0.26), -a)
		_detail_box(teal, Vector3(19.6, 0.07, 0.16), _hub_detail_frame(a, 16.0, 7.7, 0.0, 0.12), -a)
		_detail_box(orange, Vector3(19.6, 0.07, 0.12), _hub_detail_frame(a, 16.0, 7.7, 0.0, -0.12), -a)
		for k in range(5):
			_detail_box(trim, Vector3(0.14, 0.22, 0.66), _hub_detail_frame(a, 6.0 + float(k) * 5.0, 7.78, 0.0, 0.0), -a)
	# 环向管束
	var ring_segments := 18
	var ring_chord := 2.0 * 21.0 * sin(PI / float(ring_segments))
	for k in range(ring_segments):
		var a := TAU * float(k) / float(ring_segments) + TAU / float(ring_segments * 2)
		_detail_box(trim, Vector3(0.14, 0.14, ring_chord * 0.9), _hub_detail_frame(a, 21.0, 7.42, 0.0, 0.0), -a)
		_detail_box(dark, Vector3(0.2, 0.08, 0.24), _hub_detail_frame(a, 21.0, 7.34, 0.0, 0.0), -a)
	# 灯具外壳（对应既有灯光位置）与吊杆
	for i in range(CORRIDOR_COUNT):
		var a := TAU * float(i) / float(CORRIDOR_COUNT)
		_detail_box(trim, Vector3(0.9, 0.3, 1.7), _hub_detail_frame(a, 25.5, 2.75, -0.1, 0.0), -a)
		_detail_box(glow, Vector3(0.66, 0.06, 1.4), _hub_detail_frame(a, 25.5, 2.56, -0.1, 0.0), -a)
		_detail_box(dark, Vector3(0.11, 5.1, 0.11), _hub_detail_frame(a, 25.5, 5.45, -0.1, 0.0), -a)
		var m := a + TAU / 12.0
		_detail_box(trim, Vector3(1.0, 0.26, 1.6), _hub_detail_frame(m, 20.0, 6.5, 0.0, 0.0), -m)
		_detail_box(glow, Vector3(0.76, 0.05, 1.3), _hub_detail_frame(m, 20.0, 6.34, 0.0, 0.0), -m)
		_detail_box(dark, Vector3(0.11, 1.5, 0.11), _hub_detail_frame(m, 20.0, 7.35, 0.0, 0.0), -m)


func _hub_detail_walls(buckets: Array) -> void:
	var trim: Array = buckets[0]
	var dark: Array = buckets[1]
	var teal: Array = buckets[2]
	for i in range(CORRIDOR_COUNT):
		var a := TAU * float(i) / float(CORRIDOR_COUNT) + TAU / 12.0
		var wall_r := 28.5
		# 踢脚与压条
		_detail_box(dark, Vector3(0.16, 0.36, 20.6), _hub_detail_frame(a, wall_r, FLOOR_TOP + 0.18, -0.31, 0.0), -a)
		_detail_box(trim, Vector3(0.08, 0.07, 20.6), _hub_detail_frame(a, wall_r, FLOOR_TOP + 0.39, -0.38, 0.0), -a)
		# 竖肋
		for k in range(7):
			var z := -9.0 + float(k) * 3.0
			_detail_box(trim, Vector3(0.16, 9.6, 0.16), _hub_detail_frame(a, wall_r, 3.0, -0.33, z), -a)
			_detail_box(dark, Vector3(0.06, 9.0, 0.06), _hub_detail_frame(a, wall_r, 3.0, -0.42, z), -a)
		# 环向分带
		for y: float in [-1.1, 0.9, 4.4, 6.4]:
			_detail_box(trim, Vector3(0.1, 0.11, 20.4), _hub_detail_frame(a, wall_r, y, -0.37, 0.0), -a)
		for k in range(9):
			_detail_box(dark, Vector3(0.07, 0.07, 0.07),
				_hub_detail_frame(a, wall_r, FLOOR_TOP + 0.44, -0.44, -8.0 + float(k) * 2.0), -a)
		# 检修格栅与接线箱
		for side: float in [-1.0, 1.0]:
			var z := side * 6.6
			_detail_box(dark, Vector3(0.12, 0.8, 1.5), _hub_detail_frame(a, wall_r, -0.5, -0.32, z), -a)
			for k in range(4):
				_detail_box(trim, Vector3(0.06, 0.07, 1.34), _hub_detail_frame(a, wall_r, -0.79 + float(k) * 0.2, -0.38, z), -a)
			_detail_box(trim, Vector3(0.2, 0.55, 0.8), _hub_detail_frame(a, wall_r, 0.6, -0.35, side * 4.0), -a)
			_detail_box(teal, Vector3(0.06, 0.18, 0.56), _hub_detail_frame(a, wall_r, 0.72, -0.46, side * 4.0), -a)
		# 扶手与立柱
		_detail_box(trim, Vector3(0.12, 0.11, 18.4), _hub_detail_frame(a, wall_r, -0.9, -0.42, 0.0), -a)
		for k in range(5):
			_detail_box(trim, Vector3(0.1, 1.05, 0.1), _hub_detail_frame(a, wall_r, -1.45, -0.36, -7.0 + float(k) * 3.5), -a)
		# 贴墙管束与卡箍
		for side: float in [-1.0, 1.0]:
			_detail_box(dark, Vector3(0.1, 0.1, 20.4), _hub_detail_frame(a, wall_r, 7.0 + side * 0.34, -0.36, 0.0), -a)
		for k in range(5):
			_detail_box(trim, Vector3(0.15, 0.34, 0.12), _hub_detail_frame(a, wall_r, 7.0, -0.4, -8.0 + float(k) * 4.0), -a)


func _hub_detail_lift(buckets: Array) -> void:
	var trim: Array = buckets[0]
	var dark: Array = buckets[1]
	var glow: Array = buckets[3]
	var lift: Array = buckets[6]
	for k in range(12):
		var a := TAU * float(k) / 12.0 + TAU / 24.0
		_detail_box(lift, Vector3(0.14, 0.5, 2.05), _hub_detail_frame(a, 4.15, FLOOR_TOP + 0.3, 0.0, 0.0), -a)
	for k in range(4):
		var a := TAU * float(k) / 4.0
		_detail_box(dark, Vector3(0.24, 0.95, 0.46), _hub_detail_frame(a, 4.2, -0.3, 0.0, 0.0), -a)
		_detail_box(glow, Vector3(0.06, 0.2, 0.3), _hub_detail_frame(a, 4.36, -0.05, 0.0, 0.0), -a)
		_detail_box(trim, Vector3(0.09, 0.09, 0.09), _hub_detail_frame(a, 4.34, -0.62, 0.0, 0.16), -a)
	_detail_box(trim, Vector3(0.24, 0.24, 0.24), Vector3(0.0, 7.32, 0.0), 0.0)


func _hub_detail_doors(buckets: Array) -> void:
	var trim: Array = buckets[0]
	var dark: Array = buckets[1]
	var glow: Array = buckets[3]
	var orange: Array = buckets[4]
	for i in range(CORRIDOR_COUNT):
		var a := TAU * float(i) / float(CORRIDOR_COUNT)
		for side: float in [-1.0, 1.0]:
			# 门柱面板、液压软管、状态灯都贴在门洞边缘，不占通行宽度
			_detail_box(trim, Vector3(0.1, 4.7, 0.46), _hub_detail_frame(a, HUB_RADIUS, 0.4, -0.28, side * 3.7), -a)
			_detail_box(dark, Vector3(0.06, 3.4, 0.2), _hub_detail_frame(a, HUB_RADIUS, 0.2, -0.35, side * 3.7), -a)
			_detail_box(glow, Vector3(0.05, 0.16, 0.12), _hub_detail_frame(a, HUB_RADIUS, 1.9, -0.4, side * 3.7), -a)
			_detail_box(dark, Vector3(0.12, 4.4, 0.12), _hub_detail_frame(a, HUB_RADIUS, 0.3, -0.3, side * 3.42), -a)
			_detail_box(orange, Vector3(0.16, 0.2, 0.16), _hub_detail_frame(a, HUB_RADIUS, 2.5, -0.34, side * 3.42), -a)
			_detail_box(dark, Vector3(0.14, 0.34, 0.14), _hub_detail_frame(a, HUB_RADIUS, -1.7, -0.3, side * 3.42), -a)
		_detail_box(dark, Vector3(0.2, 0.22, 5.2), _hub_detail_frame(a, HUB_RADIUS, 3.02, -0.16, 0.0), -a)
		_detail_box(glow, Vector3(0.06, 0.08, 4.6), _hub_detail_frame(a, HUB_RADIUS, 3.1, -0.26, 0.0), -a)


func _detail_box(bucket: Array, size: Vector3, pos: Vector3, rot_y := 0.0) -> void:
	# 生成一个带逐面法线的长方体；绕 Y 的旋转不改变绕序，所以法线只需同样旋转。
	bucket[2] = int(bucket[2]) + 36
	var tool: SurfaceTool = bucket[1]
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c := cos(rot_y)
	var s := sin(rot_y)
	var x_axis := Vector3(c, 0.0, -s)
	var z_axis := Vector3(s, 0.0, c)
	var xp := x_axis * hx
	var yp := Vector3(0.0, hy, 0.0)
	var zp := z_axis * hz
	var c000 := pos - xp - yp - zp
	var c001 := pos - xp - yp + zp
	var c010 := pos - xp + yp - zp
	var c011 := pos - xp + yp + zp
	var c100 := pos + xp - yp - zp
	var c101 := pos + xp - yp + zp
	var c110 := pos + xp + yp - zp
	var c111 := pos + xp + yp + zp
	_detail_face(tool, c100, c110, c111, c101, x_axis)
	_detail_face(tool, c001, c011, c010, c000, -x_axis)
	_detail_face(tool, c110, c010, c011, c111, Vector3.UP)
	_detail_face(tool, c000, c100, c101, c001, Vector3.DOWN)
	_detail_face(tool, c001, c101, c111, c011, z_axis)
	_detail_face(tool, c100, c000, c010, c110, -z_axis)


func _detail_face(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	# Godot 的正面约定是"顶点顺时针看过去的那一侧"，也就是 cross(b-a, c-a) 指向内侧。
	# 因此按 a,c,b / a,d,c 发顶点，正面才朝外（法线也用同一个朝外方向）。
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.set_normal(normal)
	tool.add_vertex(c)
	tool.set_normal(normal)
	tool.add_vertex(b)
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.set_normal(normal)
	tool.add_vertex(d)
	tool.set_normal(normal)
	tool.add_vertex(c)


func _hub_detail_frame(angle: float, radius: float, y: float, local_x: float, local_z: float) -> Vector3:
	# 与门/环墙同一套局部坐标：+x 朝外、+z 沿切向，rotation.y = -angle
	var c := cos(angle)
	var s := sin(angle)
	var radial := radius + local_x
	return Vector3(c * radial - s * local_z, y, s * radial + c * local_z)


func _material_signature(material: Material) -> String:
	# 属性完全相同的材质（例如每处 _glow_mat 都新建一个实例）归到同一个桶，合并后仍是同一观感。
	if material == null:
		return "null"
	if material is StandardMaterial3D:
		var m: StandardMaterial3D = material
		return "std|" + m.albedo_color.to_html() + "|" + str(m.metallic) + "|" + str(m.roughness) + "|" + str(m.emission_enabled) + "|" + m.emission.to_html() + "|" + str(m.emission_energy_multiplier) + "|" + str(m.shading_mode) + "|" + str(m.transparency) + "|" + str(m.cull_mode)
	return "other|" + str(material.get_instance_id())


func _merge_static_meshes(root: Node3D, skip: Array, merged_name: String, chunk := MERGE_CHUNK) -> int:
	# 把 root 下所有静态 MeshInstance3D 按"材质签名 + 空间分块"烘焙成若干张多材质网格，返回被合并掉的节点数。
	# 必须分块：兼容渲染器每个对象只取 max_lights_per_object 盏灯（默认 8），
	# 整条 213 米走廊合成一个对象时，只有 8 盏灯能生效且都离门口很远，门厅就会发黑。
	# 碰撞体挂在 station_body / hub_body 上，与网格节点无关，所以合并不会动碰撞。
	if not MERGE_STATIC_MESHES:
		return 0
	var buckets := {}
	var victims: Array[Node] = []
	var root_inverse := root.global_transform.affine_inverse()
	var source_triangles := 0
	var expected_triangles := 0
	var stack: Array[Node] = []
	for child in root.get_children():
		stack.append(child)
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if skip.has(node):
			continue
		if node is MeshInstance3D:
			var instance: MeshInstance3D = node
			var mesh: Mesh = instance.mesh
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var xform := root_inverse * instance.global_transform
			# 非均匀缩放：append_from 会直接拿基向量变换法线（不取逆转置），法线会偏约 7°。
			# 这类节点很少（走廊 0 个、枢纽只有盆栽），留在树上当独立节点，换来法线精确。
			var node_scale := xform.basis.get_scale()
			if absf(node_scale.x - node_scale.y) > 0.0001 or absf(node_scale.y - node_scale.z) > 0.0001:
				continue
			var local_aabb: AABB = xform * mesh.get_aabb()
			var fits_chunk := local_aabb.size.x <= chunk and local_aabb.size.y <= chunk and local_aabb.size.z <= chunk
			# 长方体可以任意切；细长圆柱只能沿自身轴切。圆环、圆盘这类切不动的大件保持独立节点，
			# 和合并之前完全一样（它们本来就是一个对象），也不会打断按名字查找它们的断言。
			var splittable := mesh is BoxMesh or (mesh is CylinderMesh and local_aabb.size.x <= chunk and local_aabb.size.z <= chunk)
			if not fits_chunk and not splittable:
				continue
			for s in range(mesh.get_surface_count()):
				var material: Material = instance.material_override
				if material == null:
					material = mesh.surface_get_material(s)
				source_triangles += _surface_triangles(mesh, s)
				var key_base := _material_signature(material)
				if fits_chunk:
					expected_triangles += _surface_triangles(mesh, s)
					_merge_bucket(buckets, key_base, material, _merge_chunk_key(local_aabb.get_center(), chunk)).append_from(mesh, s, xform)
				else:
					expected_triangles += _append_mesh_chunked(buckets, key_base, material, mesh, s, xform, local_aabb, chunk)
			victims.append(instance)
		else:
			for child in node.get_children():
				stack.append(child)
	if victims.is_empty():
		return 0
	var by_chunk := {}
	for key in buckets:
		var bucket: Array = buckets[key]
		var chunk_key: String = bucket[2]
		if not by_chunk.has(chunk_key):
			by_chunk[chunk_key] = []
		by_chunk[chunk_key].append(key)
	var merged_triangles := 0
	var surface_total := 0
	var chunk_index := 0
	for chunk_key in by_chunk:
		var out := ArrayMesh.new()
		for key in by_chunk[chunk_key]:
			var bucket: Array = buckets[key]
			var tool: SurfaceTool = bucket[1]
			tool.set_material(bucket[0])
			tool.commit(out)
		if out.get_surface_count() == 0:
			continue
		surface_total += out.get_surface_count()
		for s in range(out.get_surface_count()):
			merged_triangles += _surface_triangles(out, s)
		var merged_node := MeshInstance3D.new()
		merged_node.name = "%s_%d" % [merged_name, chunk_index]
		merged_node.mesh = out
		merged_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(merged_node)
		chunk_index += 1
	for victim in victims:
		victim.free()
	merge_reports[merged_name] = {
		"nodes": victims.size(),
		"chunks": chunk_index,
		"surfaces": surface_total,
		"source_triangles": source_triangles,
		"expected_triangles": expected_triangles,
		"merged_triangles": merged_triangles,
	}
	return victims.size()


func _merge_chunk_key(position: Vector3, chunk: float) -> String:
	return "%d,%d,%d" % [floori(position.x / chunk), floori(position.y / chunk), floori(position.z / chunk)]


func _merge_bucket(buckets: Dictionary, key_base: String, material: Material, chunk_key: String) -> SurfaceTool:
	var full := key_base + "|" + chunk_key
	if not buckets.has(full):
		var fresh := SurfaceTool.new()
		fresh.begin(Mesh.PRIMITIVE_TRIANGLES)
		buckets[full] = [material, fresh, chunk_key]
	else:
		var existing: Array = buckets[full]
		# 会被代码改动的材质（信标闪烁）必须当这一块的代表，否则合并后就不闪了。
		if merge_live_materials.has(material):
			existing[0] = material
	return buckets[full][1]


func _append_mesh_chunked(buckets: Dictionary, key_base: String, material: Material, mesh: Mesh, surface: int, xform: Transform3D, local_aabb: AABB, chunk: float) -> int:
	# 比一个分块还大的几何必须切开：210 米的走廊地板原本就是一个对象，若整体只进一个分块，
	# 它就只能吃到一组（默认 8 盏）远离门口的灯，门厅会发黑。
	# 返回这些碎片合计应有的三角形数（切段会多出隐藏在块内的接缝面，属于预期内）。
	var size := local_aabb.size
	var steps_y := maxi(1, ceili(size.y / chunk))
	var expected := 0
	if mesh is BoxMesh:
		var box: BoxMesh = mesh
		var box_size := box.size
		var corner := box.get_aabb().position
		var steps_x := maxi(1, ceili(box_size.x / chunk))
		var steps_z := maxi(1, ceili(box_size.z / chunk))
		for ix in range(steps_x):
			for iy in range(steps_y):
				for iz in range(steps_z):
					var piece := BoxMesh.new()
					piece.size = Vector3(box_size.x / float(steps_x), box_size.y / float(steps_y), box_size.z / float(steps_z))
					var offset := corner + Vector3(
						box_size.x * (float(ix) + 0.5) / float(steps_x),
						box_size.y * (float(iy) + 0.5) / float(steps_y),
						box_size.z * (float(iz) + 0.5) / float(steps_z))
					var piece_xform := xform * Transform3D(Basis(), offset)
					expected += _surface_triangles(piece, 0)
					_merge_bucket(buckets, key_base, material, _merge_chunk_key(piece_xform.origin, chunk)).append_from(piece, 0, piece_xform)
		return expected
	if mesh is CylinderMesh:
		var cylinder: CylinderMesh = mesh
		var low := cylinder.get_aabb().position.y
		for iy in range(steps_y):
			var piece := CylinderMesh.new()
			piece.top_radius = cylinder.top_radius
			piece.bottom_radius = cylinder.bottom_radius
			piece.height = cylinder.height / float(steps_y)
			piece.radial_segments = cylinder.radial_segments
			var offset := Vector3(0.0, low + cylinder.height * (float(iy) + 0.5) / float(steps_y), 0.0)
			var piece_xform := xform * Transform3D(Basis(), offset)
			expected += _surface_triangles(piece, 0)
			_merge_bucket(buckets, key_base, material, _merge_chunk_key(piece_xform.origin, chunk)).append_from(piece, 0, piece_xform)
		return expected
	expected += _surface_triangles(mesh, surface)
	_merge_bucket(buckets, key_base, material, _merge_chunk_key(local_aabb.get_center(), chunk)).append_from(mesh, surface, xform)
	return expected


func _surface_triangles(mesh: Mesh, surface: int) -> int:
	# Mesh 基类没有 surface_get_array_index_len（那是 ArrayMesh 的），所以统一走 surface_get_arrays。
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return 0
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices is PackedInt32Array:
		var index_count: int = (indices as PackedInt32Array).size()
		if index_count > 0:
			return index_count / 3
	var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
	if vertices is PackedVector3Array:
		return (vertices as PackedVector3Array).size() / 3
	return 0


func _build_interior() -> void:
	interior_root = Node3D.new()
	interior_root.name = "StationInterior"
	add_child(interior_root)
	var interior_start := get_child_count()
	station_body = StaticBody3D.new()
	station_body.name = "StationCollision"
	station_body.collision_layer = 1
	station_body.collision_mask = 0
	add_child(station_body)

	_box(self, Vector3(CORRIDOR_HALF_LENGTH * 2.0, 0.4, CORRIDOR_HALF_WIDTH * 2.0), Vector3(0.0, FLOOR_TOP - 0.2, 0.0), _mat_floor, Vector3.ZERO, true)
	_box(self, Vector3(CORRIDOR_HALF_LENGTH * 2.0, 0.3, CORRIDOR_HALF_WIDTH * 2.0), Vector3(0.0, CEILING_Y + 0.15, 0.0), _mat_wall, Vector3.ZERO, true)
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(CORRIDOR_HALF_LENGTH * 2.0, 0.035, 0.08), Vector3(0.0, FLOOR_TOP + 0.02, side * 2.95), _mat_glow)
		_box(self, Vector3(CORRIDOR_HALF_LENGTH * 2.0, 0.04, 0.06), Vector3(0.0, FLOOR_TOP + 0.025, 0.0), _mat_teal)
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(CORRIDOR_HALF_LENGTH * 2.0, 0.05, 0.1), Vector3(0.0, 2.2, side * (CORRIDOR_HALF_WIDTH - 0.06)), _mat_glow)
	for x in range(-100, 101, 20):
		for side: float in [-1.0, 1.0]:
			_box(self, Vector3(0.2, 4.6, 0.28), Vector3(float(x), 0.3, side * (CORRIDOR_HALF_WIDTH - 0.16)), _mat_dark)
		_box(self, Vector3(0.2, 0.22, 7.1), Vector3(float(x), CEILING_Y - 0.18, 0.0), _mat_dark)
		_box(self, Vector3(1.2, 0.08, 0.45), Vector3(float(x), CEILING_Y - 0.08, 0.0), _mat_glow)
		_light(Vector3(float(x), CEILING_Y - 0.5, 0.0), Color("ffd7a0"), 1.25, 27.0)

	_build_corridor_walls()
	_build_airlock()
	_build_hall()
	_build_bridge()
	for i in range(ROOM_CENTERS.size()):
		_build_room(ROOM_CENTERS[i], -1.0, ROOM_NAMES_LEFT[i], ROOM_KINDS_LEFT[i])
		_build_room(ROOM_CENTERS[i], 1.0, ROOM_NAMES_RIGHT[i], ROOM_KINDS_RIGHT[i])
	_build_end_fittings()
	_build_corridor_detail()
	var interior_nodes := get_children().slice(interior_start)
	for child in interior_nodes:
		child.reparent(interior_root, true)
	interior_root.position = Vector3(105.0, 0.0, 0.0)
	interior_root.rotation.y = PI
	# 约 1,500 个静态网格节点在这里合并成一张多材质网格；走廊要复制 6 份，收益也 ×6。
	# 中央大厅的全息沙盘会被 _process 旋转，必须排除在合并之外。
	var corridor_skip: Array = []
	if hologram != null:
		corridor_skip.append(hologram)
	_merge_static_meshes(interior_root, corridor_skip, "CorridorMerged")
	interior_root.visible = false


func _build_corridor_walls() -> void:
	var intervals := [
		Vector2(-105.0, -85.6), Vector2(-82.4, -57.6), Vector2(-54.4, -29.6),
		Vector2(-26.4, -13.0), Vector2(13.0, 26.4), Vector2(29.6, 54.4),
		Vector2(57.6, 82.4), Vector2(85.6, 105.0)
	]
	for side: float in [-1.0, 1.0]:
		for interval in intervals:
			var length: float = interval.y - interval.x
			var center: float = (interval.x + interval.y) * 0.5
			_box(self, Vector3(length, WALL_HEIGHT, 0.26), Vector3(center, 0.4, side * CORRIDOR_HALF_WIDTH), _mat_wall, Vector3.ZERO, true)
			_box(self, Vector3(length, 0.16, 0.32), Vector3(center, 2.5, side * CORRIDOR_HALF_WIDTH), _mat_trim)
			_box(self, Vector3(length, 0.08, 0.34), Vector3(center, FLOOR_TOP + 2.7, side * CORRIDOR_HALF_WIDTH), _mat_glow)
		for x in ROOM_CENTERS:
			_box(self, Vector3(3.2, 1.8, 0.3), Vector3(x, 1.9, side * CORRIDOR_HALF_WIDTH), _mat_wall, Vector3.ZERO, true)
			for edge: float in [-1.0, 1.0]:
				_box(self, Vector3(0.22, 3.0, 0.36), Vector3(x + edge * 1.7, -0.5, side * CORRIDOR_HALF_WIDTH), _mat_trim)
			_box(self, Vector3(3.4, 0.09, 0.5), Vector3(x, FLOOR_TOP + 0.04, side * CORRIDOR_HALF_WIDTH), _mat_warm)


func _build_room(x: float, side: float, room_name: String, kind: String) -> void:
	var z_center := side * (CORRIDOR_HALF_WIDTH + ROOM_DEPTH * 0.5)
	_box(self, Vector3(ROOM_HALF_WIDTH * 2.0, 0.4, ROOM_DEPTH), Vector3(x, FLOOR_TOP - 0.2, z_center), _mat_floor, Vector3.ZERO, true)
	_box(self, Vector3(ROOM_HALF_WIDTH * 2.0 + 0.2, 0.3, ROOM_DEPTH), Vector3(x, CEILING_Y + 0.15, z_center), _mat_wall, Vector3.ZERO, true)
	_build_room_window(x, side, 8.4 if kind == "observation" else 6.4, 2.6 if kind == "observation" else 2.1)
	for edge: float in [-1.0, 1.0]:
		_box(self, Vector3(0.28, WALL_HEIGHT, ROOM_DEPTH), Vector3(x + edge * (ROOM_HALF_WIDTH + 0.1), 0.4, z_center), _mat_wall, Vector3.ZERO, true)
	_box(self, Vector3(6.8, 0.08, 1.1), Vector3(x, CEILING_Y - 0.06, z_center), _mat_glow)
	_light(Vector3(x, CEILING_Y - 0.55, z_center), Color("ffd9aa"), 1.9, 17.0)
	_label(room_name, Vector3(x, 1.86, side * (CORRIDOR_HALF_WIDTH - 0.3)), 64, 0.011, PI if side > 0.0 else 0.0, Color("f0e0bd"))
	_box(self, Vector3(0.9, 0.16, 3.0), Vector3(x, FLOOR_TOP + 0.03, z_center), _mat_teal)
	_furnish(kind, x, side, z_center)


func _build_room_window(x: float, side: float, width: float, height: float) -> void:
	var z_wall := side * (CORRIDOR_HALF_WIDTH + ROOM_DEPTH)
	var wall_width := ROOM_HALF_WIDTH * 2.0 + 0.2
	var side_width := (wall_width - width) * 0.5
	var center_y := 0.35
	var bottom_h := center_y - height * 0.5 - FLOOR_TOP
	var top_h := CEILING_Y - (center_y + height * 0.5)
	_box(self, Vector3(wall_width, bottom_h, 0.3), Vector3(x, FLOOR_TOP + bottom_h * 0.5, z_wall), _mat_wall, Vector3.ZERO, true)
	_box(self, Vector3(wall_width, top_h, 0.3), Vector3(x, CEILING_Y - top_h * 0.5, z_wall), _mat_wall, Vector3.ZERO, true)
	for edge: float in [-1.0, 1.0]:
		_box(self, Vector3(side_width, height, 0.3), Vector3(x + edge * (width * 0.5 + side_width * 0.5), center_y, z_wall), _mat_wall, Vector3.ZERO, true)
	_box(self, Vector3(width, height, 0.05), Vector3(x, center_y, z_wall), _mat_window)
	_add_collider(Vector3(width, height, 0.3), Vector3(x, center_y, z_wall))
	var inner_z := z_wall - side * 0.18
	_box(self, Vector3(width + 0.3, 0.13, 0.26), Vector3(x, center_y - height * 0.5, inner_z), _mat_trim)
	_box(self, Vector3(width + 0.3, 0.13, 0.26), Vector3(x, center_y + height * 0.5, inner_z), _mat_trim)
	for edge: float in [-1.0, 1.0]:
		_box(self, Vector3(0.13, height, 0.26), Vector3(x + edge * width * 0.5, center_y, inner_z), _mat_trim)
	_box(self, Vector3(width + 0.6, 0.14, 0.6), Vector3(x, center_y - height * 0.5 - 0.07, z_wall - side * 0.32), _mat_trim)
	_box(self, Vector3(width, 0.05, 0.14), Vector3(x, center_y + height * 0.5 + 0.11, inner_z), _mat_glow)


func _furnish(kind: String, x: float, side: float, z_center: float) -> void:
	match kind:
		"med":
			for offset: float in [-2.5, 2.5]:
				_box(self, Vector3(2.4, 0.42, 1.0), Vector3(x + offset, FLOOR_TOP + 0.55, z_center + side * 1.4), _mat_white, Vector3.ZERO, true)
				_box(self, Vector3(0.8, 0.18, 0.5), Vector3(x + offset, FLOOR_TOP + 0.86, z_center + side * 1.8), _mat_teal)
				_box(self, Vector3(2.4, 1.1, 0.16), Vector3(x + offset, FLOOR_TOP + 0.9, z_center + side * 0.85), _mat_trim)
			_box(self, Vector3(3.2, 1.7, 0.6), Vector3(x - 3.2, FLOOR_TOP + 0.85, z_center - side * 2.2), _mat_dark, Vector3.ZERO, true)
			_box(self, Vector3(1.1, 0.7, 0.1), Vector3(x - 3.2, FLOOR_TOP + 1.2, z_center - side * 2.52), _mat_glow)
		"green":
			for offset: float in [-2.8, 0.0, 2.8]:
				_box(self, Vector3(2.2, 0.55, 1.3), Vector3(x + offset, FLOOR_TOP + 0.28, z_center + side * 1.2), _mat_dark, Vector3.ZERO, true)
				_sphere(self, 0.75, Vector3(x + offset, FLOOR_TOP + 1.25, z_center + side * 1.2), _mat_green, Vector3(1.2, 1.4, 1.1))
				_add_collider(Vector3(1.7, 2.0, 1.6), Vector3(x + offset, FLOOR_TOP + 1.25, z_center + side * 1.2))
				_cylinder(self, 0.08, 0.08, 1.2, Vector3(x + offset, CEILING_Y - 0.5, z_center + side * 1.2), _mat_warm)
			_box(self, Vector3(4.0, 0.09, 0.3), Vector3(x, CEILING_Y - 0.12, z_center), _mat_glow)
		"canteen":
			_box(self, Vector3(6.5, 1.0, 0.9), Vector3(x, FLOOR_TOP + 0.5, z_center - side * 2.1), _mat_trim, Vector3.ZERO, true)
			for offset: float in [-2.1, 2.1]:
				_box(self, Vector3(1.6, 0.1, 1.6), Vector3(x + offset, FLOOR_TOP + 0.82, z_center + side * 0.9), _mat_warm, Vector3.ZERO, true)
				for chair: float in [-0.7, 0.7]:
					_box(self, Vector3(0.45, 0.45, 0.45), Vector3(x + offset + chair, FLOOR_TOP + 0.22, z_center + side * 0.0), _mat_dark, Vector3.ZERO, true)
			_box(self, Vector3(2.4, 1.8, 0.1), Vector3(x + 3.0, FLOOR_TOP + 1.4, z_center - side * 2.55), _mat_glass)
		"dorm":
			for offset: float in [-2.6, 2.6]:
				for level: float in [0.45, 1.35]:
					_box(self, Vector3(2.2, 0.32, 1.0), Vector3(x + offset, FLOOR_TOP + level, z_center + side * 1.5), _mat_white, Vector3.ZERO, true)
					_box(self, Vector3(0.7, 0.16, 0.45), Vector3(x + offset, FLOOR_TOP + level + 0.24, z_center + side * 1.9), _mat_teal)
			_box(self, Vector3(1.4, 2.2, 0.6), Vector3(x - 3.8, FLOOR_TOP + 1.1, z_center - side * 2.2), _mat_dark, Vector3.ZERO, true)
			_box(self, Vector3(1.4, 0.7, 0.1), Vector3(x + 3.8, FLOOR_TOP + 1.3, z_center - side * 2.5), _mat_glass)
		"archive":
			for offset: float in [-2.6, 0.0, 2.6]:
				_box(self, Vector3(2.0, 2.3, 0.55), Vector3(x + offset, FLOOR_TOP + 1.15, z_center - side * 2.2), _mat_dark, Vector3.ZERO, true)
				for row in range(3):
					for col in range(3):
						_box(self, Vector3(0.42, 0.36, 0.42), Vector3(x + offset - 0.55 + col * 0.55, FLOOR_TOP + 0.5 + row * 0.62, z_center - side * 1.9), _mat_orange if (row + col) % 2 == 0 else _mat_teal)
			_box(self, Vector3(2.4, 0.1, 1.2), Vector3(x, FLOOR_TOP + 0.9, z_center + side * 1.0), _mat_warm, Vector3.ZERO, true)
		"comms":
			for offset: float in [-2.0, 2.0]:
				_box(self, Vector3(2.2, 0.9, 0.7), Vector3(x + offset, FLOOR_TOP + 0.6, z_center - side * 1.8), _mat_dark, Vector3.ZERO, true)
				_box(self, Vector3(1.5, 0.65, 0.08), Vector3(x + offset, FLOOR_TOP + 1.0, z_center - side * 2.16), _mat_glass)
			_box(self, Vector3(0.7, 2.8, 0.7), Vector3(x + 3.6, FLOOR_TOP + 1.4, z_center + side * 2.0), _mat_trim, Vector3.ZERO, true)
			_cylinder(self, 0.08, 0.12, 2.4, Vector3(x + 3.6, FLOOR_TOP + 3.2, z_center + side * 2.0), _mat_trim)
		"lab":
			for offset: float in [-2.4, 2.4]:
				_box(self, Vector3(2.6, 0.12, 1.2), Vector3(x + offset, FLOOR_TOP + 0.98, z_center + side * 0.6), _mat_white, Vector3.ZERO, true)
				_cylinder(self, 0.35, 0.35, 1.1, Vector3(x + offset, FLOOR_TOP + 1.62, z_center + side * 0.6), _mat_glass)
				_sphere(self, 0.36, Vector3(x + offset, FLOOR_TOP + 2.0, z_center + side * 0.6), _mat_teal)
			_box(self, Vector3(3.4, 1.8, 0.5), Vector3(x, FLOOR_TOP + 0.9, z_center - side * 2.4), _mat_dark, Vector3.ZERO, true)
			_box(self, Vector3(2.2, 0.8, 0.08), Vector3(x, FLOOR_TOP + 1.2, z_center - side * 2.68), _mat_glow)
		"repair":
			_box(self, Vector3(5.5, 1.0, 0.9), Vector3(x, FLOOR_TOP + 0.5, z_center - side * 1.8), _mat_trim, Vector3.ZERO, true)
			for i in range(3):
				_box(self, Vector3(0.6, 0.6, 0.5), Vector3(x - 1.8 + i * 1.8, FLOOR_TOP + 1.15, z_center - side * 2.4), _mat_orange)
			_box(self, Vector3(1.6, 0.9, 1.6), Vector3(x + 3.4, FLOOR_TOP + 0.45, z_center + side * 1.8), _mat_dark, Vector3.ZERO, true)
			_cylinder(self, 0.25, 0.25, 4.4, Vector3(x - 3.9, FLOOR_TOP + 2.2, z_center + side * 2.2), _mat_trim)
			_add_collider(Vector3(0.6, 4.4, 0.6), Vector3(x - 3.9, FLOOR_TOP + 2.2, z_center + side * 2.2))
		"storage":
			for i in range(6):
				var cx := x - 2.8 + float(i % 3) * 2.8
				var cz := z_center - side * 1.1 + (float(i / 3)) * side * 1.7
				_box(self, Vector3(1.5, 1.1, 1.5), Vector3(cx, FLOOR_TOP + 0.55, cz), _mat_orange if i % 2 == 0 else _mat_dark, Vector3.ZERO, true)
			_cylinder(self, 0.5, 0.5, 1.3, Vector3(x + 3.6, FLOOR_TOP + 0.65, z_center - side * 2.2), _mat_blue)
			_add_collider(Vector3(1.0, 1.3, 1.0), Vector3(x + 3.6, FLOOR_TOP + 0.65, z_center - side * 2.2))
		"library":
			for offset: float in [-3.2, 0.0, 3.2]:
				_box(self, Vector3(2.2, 2.4, 0.55), Vector3(x + offset, FLOOR_TOP + 1.2, z_center - side * 2.2), _mat_dark, Vector3.ZERO, true)
				for row in range(3):
					for col in range(4):
						_box(self, Vector3(0.28, 0.4, 0.32), Vector3(x + offset - 0.65 + col * 0.42, FLOOR_TOP + 0.45 + row * 0.65, z_center - side * 1.9), _mat_warm if (row + col) % 2 == 0 else _mat_teal)
			_box(self, Vector3(2.6, 0.1, 1.4), Vector3(x, FLOOR_TOP + 0.82, z_center + side * 1.1), _mat_warm, Vector3.ZERO, true)
			_box(self, Vector3(0.6, 0.6, 0.6), Vector3(x, FLOOR_TOP + 0.3, z_center + side * 1.1), _mat_dark, Vector3.ZERO, true)
		"lounge":
			_box(self, Vector3(2.6, 0.6, 0.9), Vector3(x - 2.4, FLOOR_TOP + 0.3, z_center + side * 1.4), _mat_teal, Vector3.ZERO, true)
			_box(self, Vector3(2.6, 0.6, 0.9), Vector3(x + 2.4, FLOOR_TOP + 0.3, z_center + side * 1.4), _mat_teal, Vector3.ZERO, true)
			_box(self, Vector3(2.0, 0.1, 1.1), Vector3(x, FLOOR_TOP + 0.52, z_center), _mat_warm, Vector3.ZERO, true)
			_sphere(self, 0.7, Vector3(x - 3.4, FLOOR_TOP + 0.8, z_center - side * 2.1), _mat_green)
			_add_collider(Vector3(1.4, 1.7, 1.4), Vector3(x - 3.4, FLOOR_TOP + 0.8, z_center - side * 2.1))
			_box(self, Vector3(1.1, 2.1, 0.8), Vector3(x + 3.5, FLOOR_TOP + 1.05, z_center - side * 2.2), _mat_dark, Vector3.ZERO, true)
			_box(self, Vector3(0.7, 0.9, 0.08), Vector3(x + 3.5, FLOOR_TOP + 1.4, z_center - side * 2.62), _mat_glow)
		"observation":
			_build_console(Vector3(x + 3.4, FLOOR_TOP, z_center - side * 0.6), 0.0, 2.0)
			_build_telescope(Vector3(x - 3.8, FLOOR_TOP, z_center + side * 1.7), 0.0)
			_box(self, Vector3(4.2, 0.42, 0.8), Vector3(x, FLOOR_TOP + 0.21, z_center + side * 2.9), _mat_dark, Vector3.ZERO, true)
			_box(self, Vector3(4.4, 0.1, 0.9), Vector3(x, FLOOR_TOP + 0.47, z_center + side * 2.9), _mat_warm)
			_box(self, Vector3(4.0, 0.32, 0.12), Vector3(x, FLOOR_TOP + 0.3, z_center + side * 2.48), _mat_trim)
			_build_planter(Vector3(x - 4.4, FLOOR_TOP, z_center + side * 2.8), 0.5)
			_build_planter(Vector3(x + 4.4, FLOOR_TOP, z_center + side * 2.8), 0.5)
			for z: float in [4.8, 6.4, 8.0, 9.6]:
				_box(self, Vector3(9.8, 0.14, 0.18), Vector3(x, CEILING_Y - 0.16, z), _mat_trim)
			_box(self, Vector3(0.12, 0.06, 6.6), Vector3(x, CEILING_Y - 0.12, z_center), _mat_glow)
			for offset: float in [-2.6, 2.6]:
				_box(self, Vector3(0.05, 0.02, 4.8), Vector3(x + offset, FLOOR_TOP + 0.03, z_center + side * 0.8), _mat_teal)
			_box(self, Vector3(5.0, 0.02, 0.06), Vector3(x, FLOOR_TOP + 0.035, z_center + side * 2.5), _mat_orange)
			_box(self, Vector3(8.8, 0.12, 0.5), Vector3(x, -0.88, z_center + side * 3.25), _mat_trim)
			_label("观景廊", Vector3(x, 2.35, z_center + side * 3.2), 30, 0.008, PI if side > 0.0 else 0.0, Color("8fc9c7"))


func _build_seat(pos: Vector3, yaw: float, width := 1.6) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	_box(root, Vector3(width * 0.86, 0.42, 0.55), Vector3(0.0, 0.21, 0.0), _mat_dark)
	_box(root, Vector3(width, 0.14, 0.72), Vector3(0.0, 0.49, 0.0), _mat_warm)
	_box(root, Vector3(width * 0.8, 0.45, 0.1), Vector3(0.0, 0.82, -0.35), _mat_warm)
	for side: float in [-1.0, 1.0]:
		_box(root, Vector3(0.1, 0.75, 0.16), Vector3(side * width * 0.42, 0.82, -0.35), _mat_trim)
		_box(root, Vector3(0.12, 0.18, 0.58), Vector3(side * (width * 0.5 - 0.08), 0.66, 0.0), _mat_trim)
	_box(root, Vector3(width * 0.9, 0.06, 0.15), Vector3(0.0, 1.06, -0.35), _mat_trim)
	_box(root, Vector3(width * 0.6, 0.04, 0.05), Vector3(0.0, 0.62, -0.41), _mat_teal)
	_add_collider(Vector3(width, 0.75, 0.85), root.transform * Vector3(0.0, 0.35, 0.0), Vector3(0.0, yaw, 0.0))


func _build_planter(pos: Vector3, radius: float) -> void:
	_cylinder(self, radius, radius * 1.08, 0.7, pos + Vector3(0.0, 0.35, 0.0), _mat_dark, 12)
	_torus(self, radius * 0.9, radius * 1.02, pos + Vector3(0.0, 0.68, 0.0), _mat_trim, Vector3.ZERO, 6, 20)
	_sphere(self, radius * 0.95, pos + Vector3(0.0, 1.1, 0.0), _mat_green, Vector3(1.0, 1.2, 1.0))
	_add_collider(Vector3(radius * 2.0, 0.7, radius * 2.0), pos + Vector3(0.0, 0.35, 0.0))


func _build_console(pos: Vector3, yaw: float, width := 1.8) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	_box(root, Vector3(width, 0.9, 0.8), Vector3(0.0, 0.45, 0.0), _mat_dark)
	_box(root, Vector3(width * 0.92, 0.08, 0.7), Vector3(0.0, 0.93, 0.0), _mat_trim)
	_box(root, Vector3(width * 0.8, 0.55, 0.06), Vector3(0.0, 1.25, 0.28), _mat_screen)
	_box(root, Vector3(width * 0.7, 0.045, 0.08), Vector3(0.0, 1.38, 0.21), _mat_glow)
	for k in range(5):
		_box(root, Vector3(0.06, 0.06, 0.04), Vector3(-width * 0.3 + float(k) * width * 0.15, 1.02, -0.22),
			_mat_glow if k % 2 == 0 else _mat_teal)
	_add_collider(Vector3(width, 1.0, 0.9), root.transform * Vector3(0.0, 0.5, 0.0), Vector3(0.0, yaw, 0.0))


func _build_telescope(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	_cylinder(root, 0.72, 0.9, 0.55, Vector3(0.0, 0.28, 0.0), _mat_trim, 14)
	_torus(root, 0.7, 0.82, Vector3(0.0, 0.55, 0.0), _mat_dark, Vector3.ZERO, 6, 20)
	for i in range(3):
		var angle := TAU * float(i) / 3.0 + PI / 6.0
		_cylinder(root, 0.07, 0.07, 1.1, Vector3(cos(angle) * 0.52, 0.25, sin(angle) * 0.52), _mat_dark, 6)
	for side: float in [-1.0, 1.0]:
		_box(root, Vector3(0.16, 1.1, 0.22), Vector3(side * 0.52, 1.15, 0.0), _mat_trim)
	var tube := Node3D.new()
	tube.position = Vector3(0.0, 1.5, 0.0)
	tube.rotation.x = 0.95
	root.add_child(tube)
	_cylinder(tube, 0.22, 0.28, 2.3, Vector3.ZERO, _mat_trim, 18)
	_torus(tube, 0.28, 0.36, Vector3(0.0, 1.13, 0.0), _mat_dark, Vector3.ZERO, 8, 30)
	_torus(tube, 0.26, 0.3, Vector3(0.0, -0.4, 0.0), _mat_teal, Vector3.ZERO, 8, 30)
	_cylinder(tube, 0.08, 0.12, 0.4, Vector3(0.0, -1.3, 0.0), _mat_dark, 8)
	_sphere(tube, 0.1, Vector3(0.0, 1.15, 0.0), _mat_glass)
	_cylinder(tube, 0.05, 0.05, 0.8, Vector3(0.4, 0.3, 0.1), _mat_dark, 6)
	_add_collider(Vector3(1.5, 2.2, 1.5), root.transform * Vector3(0.0, 1.0, 0.0), Vector3(0.0, yaw, 0.0))


func _build_hall() -> void:
	_box(self, Vector3(26.0, 0.4, 21.0), Vector3(0.0, FLOOR_TOP - 0.2, 0.0), _mat_floor, Vector3.ZERO, true)
	_box(self, Vector3(26.0, 0.3, 21.0), Vector3(0.0, HALL_CEILING_Y + 0.15, 0.0), _mat_wall, Vector3.ZERO, true)
	for side: float in [-1.0, 1.0]:
		_build_hall_window(side)
		for x_side: float in [-1.0, 1.0]:
			_box(self, Vector3(0.3, HALL_CEILING_Y - FLOOR_TOP + 0.6, 6.9), Vector3(13.0 * x_side, HALL_CEILING_Y * 0.5 + FLOOR_TOP * 0.5 + 0.15, side * 7.0), _mat_wall, Vector3.ZERO, true)
		_box(self, Vector3(0.3, HALL_CEILING_Y - CEILING_Y, 7.2), Vector3(13.0 * side, (HALL_CEILING_Y + CEILING_Y) * 0.5, 0.0), _mat_wall, Vector3.ZERO, true)
		_box(self, Vector3(25.6, 0.08, 0.35), Vector3(0.0, HALL_CEILING_Y - 0.08, side * 6.5), _mat_glow)
		_box(self, Vector3(4.4, 0.08, 0.5), Vector3(0.0, HALL_CEILING_Y - 0.08, 0.0), _mat_glow)
		_light(Vector3(0.0, 4.2, side * 5.0), Color("ffd8ac"), 1.5, 22.0)
	_box(self, Vector3(16.0, 0.1, 0.1), Vector3(0.0, HALL_CEILING_Y - 0.2, 0.0), _mat_trim)
	_cylinder(self, 2.6, 3.0, 1.0, Vector3(0.0, FLOOR_TOP + 0.5, 0.0), _mat_dark, 24)
	_add_collider(Vector3(5.2, 1.0, 5.2), Vector3(0.0, FLOOR_TOP + 0.5, 0.0))
	_torus(self, 2.9, 3.04, Vector3(0.0, FLOOR_TOP + 1.01, 0.0), _mat_teal, Vector3.ZERO, 6, 48)
	for i in range(8):
		var hazard_angle := TAU * float(i) / 8.0
		_box(self, Vector3(0.45, 0.04, 0.12), Vector3(cos(hazard_angle) * 3.08, FLOOR_TOP + 0.94, sin(hazard_angle) * 3.08),
			_mat_orange, Vector3(0.0, -hazard_angle, 0.0))
	_cylinder(self, 0.3, 0.3, 2.0, Vector3(0.0, FLOOR_TOP + 1.9, 0.0), _mat_trim, 8)
	hologram = Node3D.new()
	hologram.position = Vector3(0.0, FLOOR_TOP + 3.8, 0.0)
	hologram.scale = Vector3.ONE * 0.55
	add_child(hologram)
	_torus(hologram, 2.2, 2.7, Vector3.ZERO, _mat_teal, Vector3(PI * 0.5, 0.0, 0.0), 8, 32)
	_torus(hologram, 3.2, 3.7, Vector3.ZERO, _mat_glow, Vector3(PI * 0.5, 0.0, 0.0), 8, 32)
	_torus(hologram, 1.15, 1.3, Vector3.ZERO, _mat_trim, Vector3(PI * 0.5, 0.0, 0.0), 6, 24)
	for i in range(6):
		var spoke_angle := TAU * float(i) / 6.0
		_box(hologram, Vector3(1.9, 0.07, 0.1), Vector3(cos(spoke_angle) * 1.05, 0.0, sin(spoke_angle) * 1.05),
			_mat_teal, Vector3(0.0, -spoke_angle, 0.0))
		_box(hologram, Vector3(0.24, 0.12, 0.24), Vector3(cos(spoke_angle) * 2.2, 0.0, sin(spoke_angle) * 2.2),
			_mat_glow, Vector3(0.0, -spoke_angle, 0.0))
	_box(hologram, Vector3(1.2, 0.2, 0.2), Vector3.ZERO, _mat_glow)
	_box(hologram, Vector3(0.3, 0.7, 0.3), Vector3.ZERO, _mat_glow)
	for side: float in [-1.0, 1.0]:
		for offset: float in [-2.1, 0.0, 2.1]:
			_build_seat(Vector3(offset, FLOOR_TOP, side * 7.8), 0.0 if side < 0.0 else PI, 1.9)
		for x_offset: float in [-11.2, 11.2]:
			_build_planter(Vector3(x_offset, FLOOR_TOP, side * 8.8), 0.62)
		for x_offset: float in [-12.7, -9.4, 9.4, 12.7]:
			_box(self, Vector3(0.35, 7.2, 0.3), Vector3(x_offset, 1.5, side * 10.3), _mat_trim)
		_box(self, Vector3(25.0, 0.05, 0.14), Vector3(0.0, HALL_CEILING_Y - 0.25, side * 9.8), _mat_glow)
	for x_offset: float in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		_box(self, Vector3(0.24, 0.2, 20.6), Vector3(x_offset, HALL_CEILING_Y - 0.18, 0.0), _mat_trim)
	_torus(self, 3.5, 3.66, Vector3(0.0, FLOOR_TOP + 0.03, 0.0), _mat_teal, Vector3.ZERO, 8, 48)
	_torus(self, 7.2, 7.35, Vector3(0.0, FLOOR_TOP + 0.03, 0.0), _mat_trim, Vector3.ZERO, 8, 64)
	for i in range(8):
		var inlay_angle := TAU * float(i) / 8.0
		_box(self, Vector3(3.4, 0.02, 0.06), Vector3(cos(inlay_angle) * 5.35, FLOOR_TOP + 0.035, sin(inlay_angle) * 5.35),
			_mat_orange, Vector3(0.0, -inlay_angle, 0.0))


func _build_hall_window(side: float) -> void:
	var z_wall := side * 10.5
	var width := 18.0
	var height := 3.2
	var center_y := 0.55
	var wall_width := 26.0
	var side_width := (wall_width - width) * 0.5
	var bottom_h := center_y - height * 0.5 - FLOOR_TOP
	var top_h := HALL_CEILING_Y - (center_y + height * 0.5)
	_box(self, Vector3(wall_width, bottom_h, 0.3), Vector3(0.0, FLOOR_TOP + bottom_h * 0.5, z_wall), _mat_wall, Vector3.ZERO, true)
	_box(self, Vector3(wall_width, top_h, 0.3), Vector3(0.0, HALL_CEILING_Y - top_h * 0.5, z_wall), _mat_wall, Vector3.ZERO, true)
	for edge: float in [-1.0, 1.0]:
		_box(self, Vector3(side_width, height, 0.3), Vector3(edge * (width * 0.5 + side_width * 0.5), center_y, z_wall), _mat_wall, Vector3.ZERO, true)
	_box(self, Vector3(width, height, 0.05), Vector3(0.0, center_y, z_wall), _mat_window)
	_add_collider(Vector3(width, height, 0.3), Vector3(0.0, center_y, z_wall))
	var inner_z := z_wall - side * 0.18
	_box(self, Vector3(width + 0.4, 0.16, 0.3), Vector3(0.0, center_y - height * 0.5, inner_z), _mat_trim)
	_box(self, Vector3(width + 0.4, 0.16, 0.3), Vector3(0.0, center_y + height * 0.5, inner_z), _mat_trim)
	for edge: float in [-1.0, 1.0]:
		_box(self, Vector3(0.16, height, 0.3), Vector3(edge * width * 0.5, center_y, inner_z), _mat_trim)
	for i in range(1, 6):
		var column_x := -width * 0.5 + width * float(i) / 6.0
		_box(self, Vector3(0.12, height, 0.22), Vector3(column_x, center_y, inner_z), _mat_trim)
	_box(self, Vector3(width + 0.8, 0.18, 0.7), Vector3(0.0, center_y - height * 0.5 - 0.08, z_wall - side * 0.35), _mat_trim)
	_box(self, Vector3(width, 0.06, 0.16), Vector3(0.0, center_y + height * 0.5 + 0.13, inner_z), _mat_glow)


func _build_bridge() -> void:
	_box(self, Vector3(16.0, 0.4, 14.0), Vector3(-112.0, FLOOR_TOP - 0.2, 0.0), _mat_floor, Vector3.ZERO, true)
	_box(self, Vector3(16.0, 0.3, 14.0), Vector3(-112.0, 5.2, 0.0), _mat_wall, Vector3.ZERO, true)
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(16.0, 7.2, 0.3), Vector3(-112.0, 1.5, side * 7.0), _mat_wall, Vector3.ZERO, true)
		_box(self, Vector3(0.3, 7.2, 3.4), Vector3(-104.0, 1.5, side * 5.3), _mat_wall, Vector3.ZERO, true)
	_box(self, Vector3(0.3, 2.3, 7.2), Vector3(-104.0, 3.95, 0.0), _mat_wall, Vector3.ZERO, true)
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(0.5, 4.8, 0.22), Vector3(-103.8, 0.4, side * 3.6), _mat_trim)
	_box(self, Vector3(0.5, 0.22, 7.42), Vector3(-103.8, 2.9, 0.0), _mat_trim)
	_label("舰桥", Vector3(-103.62, 3.65, 0.0), 56, 0.011, PI * 0.5, Color("f0e0bd"))
	_build_bridge_viewport()
	for offset: float in [-3.4, 3.4]:
		_box(self, Vector3(2.4, 0.85, 0.8), Vector3(-115.0, FLOOR_TOP + 0.55, offset), _mat_dark, Vector3.ZERO, true)
		_box(self, Vector3(0.08, 0.55, 1.8), Vector3(-114.28, FLOOR_TOP + 1.25, offset), _mat_screen)
		_box(self, Vector3(0.04, 0.05, 1.5), Vector3(-114.22, FLOOR_TOP + 1.42, offset), _mat_glow)
		for k in range(4):
			_box(self, Vector3(0.06, 0.04, 0.07), Vector3(-114.1, FLOOR_TOP + 1.02, offset - 0.9 + float(k) * 0.6),
				_mat_glow if k % 2 == 0 else _mat_teal)
		_build_seat(Vector3(-112.6, FLOOR_TOP, offset), -PI * 0.5, 1.5)
	_box(self, Vector3(2.2, 0.04, 2.2), Vector3(-109.2, FLOOR_TOP + 0.02, 4.6), _mat_floor)
	_build_seat(Vector3(-109.2, FLOOR_TOP + 0.04, 4.6), -PI * 0.5, 1.6)
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(3.2, 1.0, 0.06), Vector3(-112.0, 1.8, side * 6.86), _mat_screen)
		_box(self, Vector3(2.8, 0.04, 0.08), Vector3(-112.0, 2.2, side * 6.80), _mat_glow)
		_box(self, Vector3(0.18, 4.8, 0.25), Vector3(-118.0, 1.4, side * 6.85), _mat_trim)
		_box(self, Vector3(0.18, 4.8, 0.25), Vector3(-106.0, 1.4, side * 6.85), _mat_trim)
		_box(self, Vector3(14.0, 0.02, 0.06), Vector3(-112.0, FLOOR_TOP + 0.035, side * 5.2), _mat_orange)
	for x: float in [-118.0, -114.0, -110.0, -106.0]:
		_box(self, Vector3(0.2, 0.18, 13.6), Vector3(x, 5.0, 0.0), _mat_trim)
	_box(self, Vector3(14.0, 0.02, 0.08), Vector3(-112.0, FLOOR_TOP + 0.035, 0.0), _mat_teal)
	_box(self, Vector3(14.0, 0.06, 0.12), Vector3(-112.0, 4.9, 0.0), _mat_glow)
	_label("舰桥", Vector3(-119.55, 2.75, 0.0), 34, 0.009, PI * 0.5, Color("d9b879"))
	_light(Vector3(-112.0, 4.4, 0.0), Color("9fd7ff"), 1.1, 16.0)


func _build_bridge_viewport() -> void:
	var x_wall := -120.0
	var width := 11.0
	var height := 3.6
	var center_y := 0.6
	var wall_width := 14.0
	var side_width := (wall_width - width) * 0.5
	var bottom_h := center_y - height * 0.5 - FLOOR_TOP
	var top_h := 5.2 - (center_y + height * 0.5)
	_box(self, Vector3(0.3, bottom_h, wall_width), Vector3(x_wall, FLOOR_TOP + bottom_h * 0.5, 0.0), _mat_wall, Vector3.ZERO, true)
	_box(self, Vector3(0.3, top_h, wall_width), Vector3(x_wall, 5.2 - top_h * 0.5, 0.0), _mat_wall, Vector3.ZERO, true)
	for edge: float in [-1.0, 1.0]:
		_box(self, Vector3(0.3, height, side_width), Vector3(x_wall, center_y, edge * (width * 0.5 + side_width * 0.5)), _mat_wall, Vector3.ZERO, true)
	_box(self, Vector3(0.05, height, width), Vector3(x_wall, center_y, 0.0), _mat_window)
	_add_collider(Vector3(0.3, height, width), Vector3(x_wall, center_y, 0.0))
	_box(self, Vector3(0.26, 0.16, width + 0.4), Vector3(x_wall + 0.18, center_y - height * 0.5, 0.0), _mat_trim)
	_box(self, Vector3(0.26, 0.16, width + 0.4), Vector3(x_wall + 0.18, center_y + height * 0.5, 0.0), _mat_trim)
	for edge: float in [-1.0, 0.0, 1.0]:
		_box(self, Vector3(0.26, height, 0.14), Vector3(x_wall + 0.18, center_y, edge * width * 0.5), _mat_trim)
	_box(self, Vector3(0.6, 0.18, width + 0.7), Vector3(x_wall + 0.4, center_y - height * 0.5 - 0.08, 0.0), _mat_trim)
	_box(self, Vector3(0.22, 0.06, width), Vector3(x_wall + 0.18, center_y + height * 0.5 + 0.13, 0.0), _mat_glow)


func _build_airlock() -> void:
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(0.4, WALL_HEIGHT, 0.4), Vector3(101.0, 0.4, side * 3.4), _mat_trim)
		_box(self, Vector3(0.4, 0.4, 0.4), Vector3(101.0, 2.6, side * 3.4), _mat_dark)
	_box(self, Vector3(0.4, 0.4, 7.2), Vector3(101.0, 2.6, 0.0), _mat_trim)
	_box(self, Vector3(0.3, 0.06, 7.0), Vector3(101.0, FLOOR_TOP + 0.04, 0.0), _mat_glow)
	_light(Vector3(102.5, 1.8, 0.0), Color("a8ffd7"), 0.7, 7.0)


func _build_end_fittings() -> void:
	for x: float in [-102.0, 102.0]:
		for side: float in [-1.0, 1.0]:
			_box(self, Vector3(0.12, 2.6, 1.6), Vector3(x, 0.6, side * 2.8), _mat_teal, Vector3.ZERO, true)
	_label("中央大厅", Vector3(13.25, 3.3, 0.0), 42, 0.010, PI * 0.5, Color("d9b879"))
	_label("中央大厅", Vector3(-13.25, 3.3, 0.0), 42, 0.010, -PI * 0.5, Color("d9b879"))


func docking_point() -> Vector3:
	return to_global(Vector3(0.0, 260.0, 0.0))


func dock_ship_position() -> Vector3:
	return to_global(Vector3(0.0, 266.0, 0.0))


func dock_look_target() -> Vector3:
	return to_global(Vector3.ZERO)


func dock_up_direction() -> Vector3:
	return global_transform.basis.z.normalized()


func up_direction() -> Vector3:
	return global_transform.basis.y.normalized()


func airlock_position() -> Vector3:
	return to_global(Vector3(0.0, FLOOR_TOP + 0.03, 12.0))


func interior_spawn_transform() -> Transform3D:
	var up := up_direction()
	var forward := global_transform.basis.x.normalized()
	return Transform3D(Basis.looking_at(forward, up), to_global(Vector3(0.0, FLOOR_TOP + 0.02, 6.0)))


func is_interior_position(position: Vector3) -> bool:
	var local := to_local(position)
	var planar := Vector2(local.x, local.z).length()
	return planar < 265.0 and local.y > FLOOR_TOP - 2.0 and local.y < HALL_CEILING_Y + 3.0
