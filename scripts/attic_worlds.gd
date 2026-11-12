extends Node3D

## 地面线：阁楼四扇门后面的「口袋世界」。
##
## 四扇门各通向一小块独立场景（雪夜 / 云海 / 萤火 / 雨巷），镜界回廊通向一间镜像阁楼。
## 每个世界都是自成一体的封闭小场地：平台 + 边界碰撞 + 一处回程门，玩家走进去、看一圈、再走回来。
## 世界之间相距很远，也和太阳系（原点附近）完全分开，所以互不干扰。

const WORLD_KEYS := ["snow", "cloud", "firefly", "alley", "mirror", "dungeon"]

## 镜牢回廊的门禁碰撞（每道隔墙一个），战斗室清空前挡住门洞
var _dungeon_door_blockers: Array = []
## 静镜室的镜印台：room -> [三枚镜印碎片节点 + 锚点]
var _dungeon_boon_stands: Dictionary = {}

## 镜牢回廊的房间序列：战斗室 / 静镜室（镜印）/ 内厅（镜心）
const DUNGEON_ROOM_KINDS := ["combat", "boon", "combat", "combat", "boon", "boss"]
const DUNGEON_ROOM_LENGTH := 12.0
const DUNGEON_ROOM_HALF_X := 4.5

const PLATFORM_HALF := 13.0
## 原作四个远方的场地尺度（来自伴随版 HTML 的可行走区域），
## 用来把本作的场地放大到原作大小并对齐中心。
##   世界 -> [原作深度(z), 原作中心 z]
const ARENA_SCALE := {
	"snow": [36.28, -22.16],
	"cloud": [41.26, -24.65],
	"firefly": [43.18, -25.61],
	"alley": [39.18, -23.61],
}
## 各世界的原点：沿 -Y 方向层层排开，远离阁楼（-40000）与太阳系。
const WORLD_BASE_Y := -46000.0
const WORLD_GAP := 400.0

var worlds: Dictionary = {}
var player = null

## 每个世界里「小事」的三个装置状态：world_key -> [bool, bool, bool]
var device_states: Dictionary = {}
## 可旋转装置的当前档位（冰镜 / 水兽铜阀）：world_key -> [int, int, int]
var device_values: Dictionary = {}
## 装置节点与锚点：world_key -> Array[{node, anchor, mesh, kind}]
var device_nodes: Dictionary = {}
## 小事完成后的纪念是否已生成：world_key -> bool
var world_done: Dictionary = {}

## 三个小游戏的入口锚点：cloud -> chime / firefly -> firefly / alley -> rain
var minigame_anchors: Dictionary = {}

## 雨巷听雨院：三盏听雨灯 + 檐下长凳
var court_lamps: Array = []
var court_lamp_values: Array = [false, false, false]
var court_bench = null
var court_rested := false

## 雪夜冰钓：三处冰洞与对应的冰灯
var fishing_holes: Array = []
var fish_names := ["冰纹鲫", "星鳞鱼", "极光鳟"]


func build() -> void:
	for i in range(WORLD_KEYS.size()):
		var key: String = WORLD_KEYS[i]
		var origin := Vector3(0.0, WORLD_BASE_Y - float(i) * WORLD_GAP, 0.0)
		var holder := Node3D.new()
		holder.name = "World_%s" % key.capitalize()
		holder.position = origin
		add_child(holder)
		# 内容层：按原作尺度缩放并平移对齐。玩家挂在外层 holder（不缩放），
		# 所以放大场地不会改到玩家的重力、步速与体积。
		var content := Node3D.new()
		content.name = "Content"
		holder.add_child(content)
		var arena: Array = ARENA_SCALE.get(key, [])
		if not arena.is_empty() and PLATFORM_HALF > 0.0:
			var scale_factor: float = float(arena[0]) / (PLATFORM_HALF * 2.0)
			content.scale = Vector3.ONE * scale_factor
			content.position = Vector3(0.0, 0.0, float(arena[1]))
		var entry := {}
		match key:
			"snow":
				entry = _build_snow(content)
			"cloud":
				entry = _build_cloud(content)
			"firefly":
				entry = _build_firefly(content)
			"alley":
				entry = _build_alley(content)
			"mirror":
				entry = _build_mirror(content)
			"dungeon":
				entry = _build_dungeon(content)
		# 出生点写在内容层的坐标里，换算到 holder 空间（玩家在这一层）
		if entry.has("spawn"):
			var spawn_local: Vector3 = entry["spawn"]
			entry["spawn"] = content.transform * spawn_local
		entry["content"] = content
		entry["node"] = holder
		entry["origin"] = origin
		worlds[key] = entry
		if key == "cloud":
			# 风琴礁：一段伸向云海的石台，尽头是四面风铃
			minigame_anchors["cloud"] = _build_wind_chime(content)
			# 云舟与三盏云灯浮标
			_build_boat(content)
			# 巡游的飞艇
			_build_airship(content)
		elif key == "firefly":
			# 树根夜路：三条交错的树根，尽头一盏提灯
			minigame_anchors["firefly"] = _build_root_path(content)
		elif key == "alley":
			# 檐下水槽：巷子一侧的排水槽与四只石槽
			minigame_anchors["alley"] = _build_rain_gutter(content)
			# 听雨院：墙上三盏听雨灯 + 巷尾檐下的长凳
			_build_rain_court(content)
		if _world_has_props(key):
			_build_props(content, key)
		if key != "mirror":
			_add_devices(content, key)
			device_states[key] = [false, false, false]
			world_done[key] = false
			match key:
				"snow":
					# 三面冰镜初始朝向各不相同：要转到「共同的方向」才会折光
					device_values[key] = [1, 2, 0]
				"alley":
					# 三只铜阀初始都没有对准竖位
					device_values[key] = [1, 2, 1]
				_:
					device_values[key] = [0, 0, 0]


# --- 公共构件 ---------------------------------------------------------------

# --- Lux3D 摆件加载（2026-11-12 接入）----------------------------------------
#
# 六个口袋世界里的独立摆件（松树/路灯/望远镜/飞艇/灯笼/镜塔…）改用
# Aholo Lux3D 文生 3D 的写实模型；**地形、墙、栈桥、隔墙保持程序化** —— 
# 那些必须精确对齐、能走上去，AI 模型尺寸不可控会穿模。
#
# ⚠ 全部可回退：模型在 assets/models/props/attic-worlds/（.gitignore 例外名单），
#   别人 clone 若缺失，照样退回程序化几何，世界不会空也不会崩。
const WORLD_PROP_DIR := "res://assets/models/props/attic-worlds/"
var _world_prop_cache: Dictionary = {}


## 取一个世界摆件实例，失败返回 null（调用方回退程序化）。
## target_height 用于归一化：模型原始尺寸不可控，按高度缩放最稳。
func _prop(name: String, target_height: float) -> Node3D:
	if _world_prop_cache.has(name):
		var cached = _world_prop_cache[name]
		if cached == null:
			return null
		return (cached as Node3D).duplicate() as Node3D
	var dir: String = WORLD_PROP_DIR + name + "/"
	var glb_path := ""
	for candidate in ["model.glb", "model_glb.glb"]:
		if ResourceLoader.exists(dir + candidate):
			glb_path = dir + candidate
			break
	if glb_path == "":
		_world_prop_cache[name] = null
		return null
	var packed := load(glb_path) as PackedScene
	if packed == null:
		_world_prop_cache[name] = null
		return null
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_world_prop_cache[name] = null
		return null
	var aabb := AABB()
	var first := true
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walker: Node = mi
		while walker != null and walker != instance:
			if walker is Node3D:
				xf = (walker as Node3D).transform * xf
			walker = walker.get_parent()
		var box: AABB = xf * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if first or aabb.size.y < 0.0001:
		instance.queue_free()
		_world_prop_cache[name] = null
		return null
	var holder := Node3D.new()
	holder.name = "Prop_" + name
	holder.add_child(instance)
	var scale_k: float = target_height / aabb.size.y
	instance.scale = Vector3.ONE * scale_k
	instance.position = Vector3(
		-aabb.get_center().x * scale_k,
		-aabb.position.y * scale_k,
		-aabb.get_center().z * scale_k)
	_world_prop_cache[name] = holder
	return (holder as Node3D).duplicate() as Node3D


func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node


func _cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, material: Material,
		segments := 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node


func _sphere(parent: Node3D, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node


func _light(parent: Node3D, pos: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	parent.add_child(light)
	return light


func _anchor(parent: Node3D, anchor_name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = anchor_name
	node.position = pos
	parent.add_child(node)
	return node


## 每个世界都要有：地面碰撞、四面看不见的边界墙、一处回程门。
func _build_ground_and_bounds(holder: Node3D, ground_material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	holder.add_child(body)

	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(PLATFORM_HALF * 2.0, 1.0, PLATFORM_HALF * 2.0)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_collision.position = Vector3(0, -0.5, 0)
	body.add_child(floor_collision)

	# 四面边界墙，防止走出场地掉进虚空
	for side in [-1.0, 1.0]:
		for axis in [Vector3.RIGHT, Vector3.FORWARD]:
			var wall_shape := BoxShape3D.new()
			wall_shape.size = Vector3(PLATFORM_HALF * 2.0, 6.0, 1.0) if axis == Vector3.RIGHT \
				else Vector3(1.0, 6.0, PLATFORM_HALF * 2.0)
			var wall := CollisionShape3D.new()
			wall.shape = wall_shape
			var offset: Vector3 = axis * (PLATFORM_HALF + 0.5) * side
			wall.position = offset + Vector3(0, 3.0, 0)
			body.add_child(wall)

	var ground := _cyl(holder, PLATFORM_HALF, PLATFORM_HALF, 0.6, Vector3(0, -0.3, 0), ground_material, 40)
	ground.name = "Ground"
	return body


## 回程门：一道发光门框，靠近按 E 回阁楼。
func _build_return_portal(holder: Node3D, _key: String, color: Color, at: Vector3) -> Node3D:
	var frame := Node3D.new()
	frame.name = "ReturnPortal"
	frame.position = at
	holder.add_child(frame)
	var glow := _mat(color, 1.8)
	var wood := _mat(Color("4a3627"))
	for side in [-1.0, 1.0]:
		_box(frame, Vector3(0.16, 2.2, 0.16), Vector3(side * 0.62, 1.1, 0), wood)
	_box(frame, Vector3(1.42, 0.16, 0.16), Vector3(0, 2.2, 0), wood)
	_box(frame, Vector3(1.10, 1.92, 0.05), Vector3(0, 1.06, 0.02), glow)
	_light(frame, Vector3(0, 1.2, 0.6), color, 1.4, 7.0)
	var anchor := _anchor(frame, "WorldAnchor_Return", Vector3(0, 1.0, 1.1))
	return anchor


func _build_bench(holder: Node3D, at: Vector3, wood: Material, iron: Material) -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	bench.position = at
	holder.add_child(bench)
	_box(bench, Vector3(1.9, 0.1, 0.52), Vector3(0, 0.46, 0), wood)
	_box(bench, Vector3(1.9, 0.42, 0.1), Vector3(0, 0.70, -0.2), wood)
	for side in [-1.0, 1.0]:
		_box(bench, Vector3(0.1, 0.46, 0.46), Vector3(side * 0.82, 0.23, 0), iron)


func _build_pine(holder: Node3D, at: Vector3, scale: float, trunk: Material, needles: Material) -> void:
	var tree := Node3D.new()
	tree.position = at
	tree.scale = Vector3.ONE * scale
	holder.add_child(tree)
	# 优先用 Lux3D 模型（雪夜一次种 11 棵，是这套里收益最大的替换）。
	# 目标高度 3.2 m 对应原来的程序化松树总高（树干 3.2 + 冠层）。
	var pine := _prop("pine-tree", 3.2)
	if pine != null:
		tree.add_child(pine)
		return
	_cyl(tree, 0.16, 0.3, 3.2, Vector3(0, 1.6, 0), trunk, 8)
	for i in range(4):
		_cyl(tree, 0.0, 1.5 - i * 0.26, 2.2 - i * 0.16, Vector3(0, 3.0 + i * 0.95, 0), needles, 9)


func _build_motes(holder: Node3D, count: int, color: Color, spread: float, height: float,
		size: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "Motes"
	# 固定种子：让粒子发射可复现（视觉回归要能对得上，玩家看到的也更稳定）
	particles.use_fixed_seed = true
	particles.seed = 20261106
	particles.amount = count
	particles.lifetime = 9.0
	particles.preprocess = 4.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(spread, height * 0.5, spread)
	particles.position = Vector3(0, height * 0.5, 0)
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 60.0
	particles.initial_velocity_min = 0.12
	particles.initial_velocity_max = 0.45
	particles.gravity = Vector3(0, -0.08, 0)
	particles.scale_amount_min = size * 0.6
	particles.scale_amount_max = size * 1.3
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := _mat(color, 3.2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	particles.mesh = mesh
	holder.add_child(particles)
	return particles


# --- 雪夜 -------------------------------------------------------------------
func _build_snow(holder: Node3D) -> Dictionary:
	var snow_ground := _mat(Color("e8eef4"))
	var wood := _mat(Color("5a4534"))
	var iron := _mat(Color("3a4048"))
	_build_ground_and_bounds(holder, snow_ground)
	# 雪堆（数量按场地面积补）
	var drift_n := int(round(14.0 * _scenery_density("snow")))
	var drift_prop_tpl := _prop("snow-drift", 0.75)
	for i in range(drift_n):
		var angle := TAU * float(i) / float(drift_n) + 0.3
		var radius := 6.0 + float(i % 4) * 2.4
		var drift_at := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if drift_prop_tpl != null:
			var d: Node3D = drift_prop_tpl.duplicate() as Node3D
			d.position = drift_at
			d.rotation.y = float(i) * 1.7
			holder.add_child(d)
		else:
			var drift := _sphere(holder, 1.2 + float(i % 3) * 0.5,
				drift_at + Vector3(0, 0.1, 0), snow_ground)
			drift.scale = Vector3(1.6, 0.4, 1.4)
	# 松林：两圈，外圈错开，免得放大后中间空
	var pine_n := int(round(11.0 * _scenery_density("snow")))
	for i in range(pine_n):
		var angle := TAU * float(i) / float(pine_n) + 0.7
		var radius := 8.6 + float(i % 3) * 1.9
		_build_pine(holder, Vector3(cos(angle) * radius, 0, sin(angle) * radius),
			0.85 + float(i % 3) * 0.18, wood, _mat(Color("2d4a44")))
	_build_bench(holder, Vector3(-2.4, 0, 0.6), wood, iron)
	# 路灯
	var street_lamp := _prop("snow-lantern", 3.4)
	if street_lamp != null:
		street_lamp.position = Vector3(2.8, 0, 0.4)
		holder.add_child(street_lamp)
	else:
		_cyl(holder, 0.08, 0.12, 3.2, Vector3(2.8, 1.6, 0.4), iron, 8)
	var lamp_mat := _mat(Color("ffd9a0"), 1.8)
	var lamp_glow := _sphere(holder, 0.26, Vector3(2.8, 3.3, 0.4), lamp_mat)
	lamp_glow.name = "LampGlow"
	_light(holder, Vector3(2.8, 3.2, 0.4), Color("ffd9a0"), 2.0, 16.0)
	# 天上的冷月
	var moon := _sphere(holder, 26.0, Vector3(-90, 120, -160), _mat(Color("dfe9f6"), 0.9))
	moon.name = "Moon"
	_light(holder, Vector3(0, 24, 0), Color("c9dcf0"), 1.5, 60.0)
	var snow := _build_motes(holder, int(round(900.0 * _scenery_density("snow"))), Color("ffffff"), PLATFORM_HALF * 0.9, 14.0, 0.8)
	snow.name = "Snowfall"
	snow.lifetime = 7.0
	snow.initial_velocity_min = 1.0
	snow.initial_velocity_max = 1.8
	snow.direction = Vector3(0, -1, 0)
	snow.spread = 12.0
	_build_fishing_holes(holder)
	var anchor := _build_return_portal(holder, "snow", Color("cfe4f2"), Vector3(0, 0, 9.0))
	return {"spawn": Vector3(0, 1.05, 6.4), "return": anchor, "title": "雪夜"}


# --- 云海 -------------------------------------------------------------------
func _build_cloud(holder: Node3D) -> Dictionary:
	var stone := _mat(Color("8d949c"))
	var pale := _mat(Color("c3ccd4"))
	var brass := _mat(Color("b8913f"))
	# 地面照原作的可行走区搭（窄栈桥 + 圆场 + 岛），不套方形台与围墙
	_build_cloud_ground(holder, stone, pale)
	# 云海：铺在整条路线下面的一层云
	var cloud_mat := _mat(Color("dfe8f4"))
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.albedo_color = Color(0.88, 0.92, 0.98, 0.55)
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sea_center := _cloud_local(Vector3(0.0, 0.0, -25.0))
	var sea := _cyl(holder, _cloud_len(46.0), _cloud_len(46.0), 0.6, sea_center + Vector3(0, -3.2, 0),
		cloud_mat, 56)
	sea.name = "CloudSea"
	# 云团沿整条路线散开（不再是绕一个圆心排一圈）
	var puff_n := int(round(26.0 * _scenery_density("cloud")))
	# 云团用 Lux3D 模型；模板只加载一次，之后 duplicate。
	var puff_tpl := _prop("cloud-cluster", 4.5)
	for i in range(puff_n):
		var t := float(i) / float(maxi(1, puff_n))
		var wz := -2.0 - t * 50.0
		var wx := sin(float(i) * 2.1) * (6.0 + float(i % 4) * 3.2)
		var at := _cloud_local(Vector3(wx, 0.0, wz))
		var puff_y: float = -2.6 + float(i % 3) * 0.5
		if puff_tpl != null:
			var c: Node3D = puff_tpl.duplicate() as Node3D
			c.position = at + Vector3(0, puff_y, 0)
			c.rotation.y = float(i) * 0.9
			# 大小抖动，避免一模一样
			var k: float = (3.0 + float(i % 4) * 1.6) / 4.5
			c.scale = Vector3.ONE * k
			holder.add_child(c)
		else:
			var puff := _sphere(holder, _cloud_len(3.0 + float(i % 4) * 1.6),
				at + Vector3(0, puff_y, 0), cloud_mat)
			puff.scale = Vector3(1.5, 0.35, 1.5)
	# 望远镜：挪到西岛上（原作也在西侧）
	var scope := Node3D.new()
	scope.name = "Telescope"
	scope.position = _cloud_local(Vector3(-15.0, 0.0, -29.0))
	holder.add_child(scope)
	# 望远镜本体：Lux3D 模型（三脚架+镜筒是一体的）
	var scope_prop := _prop("telescope", 1.9)
	if scope_prop != null:
		scope_prop.rotation = Vector3(0, 0.3, 0)
		scope.add_child(scope_prop)
	else:
		for i in range(3):
			var angle := TAU * float(i) / 3.0
			_cyl(scope, 0.05, 0.05, 1.5, Vector3(cos(angle) * 0.32, 0.72, sin(angle) * 0.32), brass, 6)
		var tube := _cyl(scope, 0.16, 0.2, 1.5, Vector3(0, 1.55, 0), brass, 10)
		tube.rotation = Vector3(-0.6, 0.3, 0.0)
	# 观星桌：望远镜旁边摆一张摊开星图的桌子
	var chart_prop := _prop("star-chart-table", 0.85)
	if chart_prop != null:
		chart_prop.position = _cloud_local(Vector3(-12.4, 0.0, -28.2))
		holder.add_child(chart_prop)
	var dawn := _light(holder, Vector3(0, 26, 0), Color("ffd2a8"), 1.8, 70.0)
	dawn.name = "DawnLight"
	# 回程门立在栈桥入口（原作的入口在 z ≈ -4 一带）
	var anchor := _build_return_portal(holder, "cloud", Color("bcd2e8"),
		_cloud_local(Vector3(0.0, 0.0, -5.4)))
	return {"spawn": _cloud_local(Vector3(0.0, 1.05, -9.0)), "return": anchor, "title": "云海"}


# --- 萤火 -------------------------------------------------------------------
func _build_firefly(holder: Node3D) -> Dictionary:
	var moss := _mat(Color("31503f"))
	var wood := _mat(Color("3f3024"))
	_build_ground_and_bounds(holder, moss)
	var pine_n := int(round(13.0 * _scenery_density("firefly")))
	for i in range(pine_n):
		var angle := TAU * float(i) / float(pine_n) + 0.5
		var radius := 8.0 + float(i % 4) * 2.2
		_build_pine(holder, Vector3(cos(angle) * radius, 0, sin(angle) * radius),
			0.7 + float(i % 3) * 0.2, wood, _mat(Color("1e3a30")))
	# 火塘
	# 石圈用 Lux3D 模型；**余烬 ember 与光源保留程序化** —— 那是「火在烧」的视觉。
	var pit_prop := _prop("stone-firepit", 0.5)
	if pit_prop != null:
		pit_prop.position = Vector3(0, 0, 0)
		holder.add_child(pit_prop)
	else:
		var pit := _cyl(holder, 1.5, 1.7, 0.36, Vector3(0, 0.18, 0), _mat(Color("4a4238")), 16)
		pit.name = "FirePit"
	var ember := _sphere(holder, 0.42, Vector3(0, 0.45, 0), _mat(Color("ff8a3c"), 2.6))
	ember.name = "Ember"
	_light(holder, Vector3(0, 1.1, 0), Color("ff9a4c"), 2.4, 16.0)
	_build_bench(holder, Vector3(2.6, 0, 1.0), wood, _mat(Color("2a2622")))
	# 倒木：森林里的散落倒木
	for log_i in range(3):
		var log_prop := _prop("forest-log", 0.45)
		if log_prop == null:
			break
		var la: float = 2.2 + float(log_i) * 2.1
		log_prop.position = Vector3(cos(la) * 7.5, 0, sin(la) * 7.5)
		log_prop.rotation.y = la + float(log_i) * 0.8
		holder.add_child(log_prop)
	# 萤火
	var fireflies := _build_motes(holder, int(round(700.0 * _scenery_density("firefly"))), Color("d8f07a"), PLATFORM_HALF * 0.85, 5.0, 0.55)
	fireflies.name = "Fireflies"
	fireflies.lifetime = 12.0
	fireflies.initial_velocity_min = 0.25
	fireflies.initial_velocity_max = 0.9
	var anchor := _build_return_portal(holder, "firefly", Color("cfe08a"), Vector3(0, 0, 9.0))
	return {"spawn": Vector3(0, 1.05, 6.4), "return": anchor, "title": "萤火"}


# --- 雨巷 -------------------------------------------------------------------
func _build_alley(holder: Node3D) -> Dictionary:
	var pavement := _mat(Color("4d5057"))
	var wall := _mat(Color("5d646b"))
	var iron := _mat(Color("2c3036"))
	_build_ground_and_bounds(holder, pavement)
	# 两侧高墙，形成一条巷子
	for side in [-1.0, 1.0]:
		var wall_node := _box(holder, Vector3(0.5, 7.0, PLATFORM_HALF * 1.8),
			Vector3(side * 3.4, 3.5, 0), wall)
		wall_node.name = "AlleyWall"
		# 墙面上的窗与管
		for i in range(6):
			var z := -9.0 + float(i) * 3.4
			_box(holder, Vector3(0.08, 0.7, 0.9), Vector3(side * 3.12, 3.4, z), _mat(Color("2b3a48"), 0.9))
			_box(holder, Vector3(0.1, 0.1, 0.1), Vector3(side * 3.05, 5.2, z), iron)
		# 立管：每侧一根 Lux3D 排水管（原来是 12 米长的圆柱横躺在墙上）
		var pipe_prop := _prop("wall-pipe", 5.6)
		if pipe_prop != null:
			pipe_prop.position = Vector3(side * 3.06, 0, -3.0)
			holder.add_child(pipe_prop)
		else:
			_cyl(holder, 0.07, 0.07, 12.0, Vector3(side * 3.06, 5.8, 0), iron, 6).rotation.x = PI * 0.5
	# 积水
	var puddle_n := int(round(6.0 * _scenery_density("alley")))
	for i in range(puddle_n):
		var puddle := _box(holder, Vector3(2.6, 0.03, 1.4), Vector3(0, 0.03, -8.0 + float(i) * 3.2),
			_mat(Color("6e7c88"), 0.12))
		puddle.name = "Puddle"
	# 屋檐灯笼
	var lamp_n := int(round(4.0 * _scenery_density("alley")))
	for i in range(lamp_n):
		var z := -7.0 + float(i) * 4.4
		# 灯笼本体用 Lux3D 模型；发光球（Lantern 节点）保留 —— 它是「亮着」的视觉，
		# 模型本身不带自发光。
		var lamp_prop := _prop("alley-lantern", 0.55)
		if lamp_prop != null:
			lamp_prop.position = Vector3(0, 2.95, z)
			holder.add_child(lamp_prop)
		else:
			var lamp := _sphere(holder, 0.24, Vector3(0, 3.2, z), _mat(Color("ffb867"), 2.4))
			lamp.name = "Lantern"
		var glow := _sphere(holder, 0.20, Vector3(0, 3.2, z), _mat(Color("ffb867"), 2.4))
		glow.name = "LanternGlow"
		_cyl(holder, 0.02, 0.02, 0.8, Vector3(0, 3.7, z), iron, 5)
		_light(holder, Vector3(0, 3.2, z), Color("ffb867"), 1.5, 11.0)
	# 巷子尽头的门
	var end_door := _prop("alley-end-door", 2.4)
	if end_door != null:
		end_door.position = Vector3(0, 0, -11.0)
		holder.add_child(end_door)
	else:
		_box(holder, Vector3(1.6, 2.4, 0.12), Vector3(0, 1.2, -11.0), _mat(Color("3a2f28")))
	_light(holder, Vector3(0, 14, 0), Color("8fa6c0"), 1.2, 40.0)
	# 雨
	var rain := _build_motes(holder, int(round(1200.0 * _scenery_density("alley"))), Color("cfe0ee"), PLATFORM_HALF * 0.8, 12.0, 0.5)
	rain.name = "Rain"
	rain.lifetime = 2.2
	rain.initial_velocity_min = 9.0
	rain.initial_velocity_max = 13.0
	rain.direction = Vector3(0.1, -1, 0)
	rain.spread = 4.0
	rain.gravity = Vector3(0, -9.0, 0)
	var anchor := _build_return_portal(holder, "alley", Color("a8b0b8"), Vector3(0, 0, 9.0))
	return {"spawn": Vector3(0, 1.05, 7.4), "return": anchor, "title": "雨巷"}


# --- 镜界 -------------------------------------------------------------------
func _build_mirror(holder: Node3D) -> Dictionary:
	# 镜像阁楼：同样的房间轮廓，但冷色、反向、空无一人。
	var floor_mat := _mat(Color("3d4450"), 0.16)
	var wall_mat := _mat(Color("55606e"), 0.20)
	var glow := _mat(Color("cfe0e6"), 0.6)
	_build_ground_and_bounds(holder, floor_mat)
	# 露天镜面庭院：地板 + 三面墙（正面敞开，方便从外面看进去）
	var half_x := 6.0
	var half_z := 5.0
	var height := 3.4
	_box(holder, Vector3(half_x * 2.0, 0.2, half_z * 2.0), Vector3(0, 0.1, 0), floor_mat)
	for side in [-1.0, 1.0]:
		_box(holder, Vector3(0.3, height, half_z * 2.0), Vector3(side * half_x, height * 0.5, 0), wall_mat)
	# 只有背面（-Z）与两侧，正面 +Z 敞开
	_box(holder, Vector3(half_x * 2.0, height, 0.3), Vector3(0, height * 0.5, -half_z), wall_mat)
	# 镜面倒影：地面上一块更亮的区域 + 竖向反光条
	_box(holder, Vector3(7.4, 0.02, 6.2), Vector3(0, 0.22, 0), glow)
	for i in range(7):
		var x := -4.8 + float(i) * 1.6
		_box(holder, Vector3(0.06, 2.6, 0.06), Vector3(x, 1.5, -half_z + 0.5), glow)
	# 棱镜之心：悬浮在房间中央的台座上
	var pedestal := _cyl(holder, 0.55, 0.75, 1.0, Vector3(0, 0.7, 0), _mat(Color("4a5260")), 10)
	pedestal.name = "Pedestal"
	# 用 Lux3D 棱镜模型当**外观**，但里面保留一颗强自发光核心 ——
	# 它是剧情核心物件，必须「看得出发光」，外部模型的 PBR 材质做不到。
	var heart_prop := _prop("prism-heart", 1.5)
	if heart_prop != null:
		heart_prop.position = Vector3(0, 1.3, 0)
		heart_prop.name = "PrismHeartModel"
		holder.add_child(heart_prop)
	var heart := _cyl(holder, 0.0, 0.22, 1.1, Vector3(0, 2.0, 0), _mat(Color("d9efff"), 2.6), 6)
	heart.name = "PrismHeart"
	if heart_prop != null:
		# 有模型时把自发光核心缩小、塞进模型内部当「心脏」
		heart.scale = Vector3(0.55, 0.7, 0.55)
	var heart_base := _cyl(holder, 0.22, 0.0, 0.7, Vector3(0, 2.0, 0), _mat(Color("d9efff"), 2.6), 6)
	heart_base.rotation.z = PI
	if heart_prop != null:
		heart_base.scale = Vector3(0.55, 0.7, 0.55)
	_light(holder, Vector3(0, 1.9, 0), Color("d9efff"), 3.4, 20.0)
	_light(holder, Vector3(-4.0, 2.6, 3.0), Color("b9cfe0"), 2.0, 16.0)
	_light(holder, Vector3(4.0, 2.6, -3.0), Color("b9cfe0"), 2.0, 16.0)
	_light(holder, Vector3(0, 3.0, 4.2), Color("dfe9f6"), 1.6, 12.0)
	var heart_anchor := _anchor(holder, "WorldAnchor_PrismHeart", Vector3(0, 1.6, 1.2))
	var portal_anchor := _build_return_portal(holder, "mirror", Color("cfe0e6"), Vector3(0, 0, 8.4))
	# 镜牢门：镜界东侧一道更高的门，通向镜牢回廊
	var gate_root := Node3D.new()
	gate_root.name = "DungeonGate"
	gate_root.position = Vector3(5.6, 0.0, -1.0)
	holder.add_child(gate_root)
	var gate_mat := _mat(Color("3a4250"))
	var gate_glow := _mat(Color("cfe0e6"), 1.2)
	for side in [-1.0, 1.0]:
		_box(gate_root, Vector3(0.36, 4.0, 0.5), Vector3(side * 1.3, 2.0, 0), gate_mat)
	_box(gate_root, Vector3(3.0, 0.5, 0.5), Vector3(0, 4.2, 0), gate_mat)
	var gate_pane := _box(gate_root, Vector3(2.2, 3.6, 0.06), Vector3(0, 2.0, 0.06), gate_glow)
	gate_pane.name = "DungeonGatePane"
	_light(gate_root, Vector3(0, 2.2, 0.8), Color("cfe0e6"), 1.8, 12.0)
	var gate_anchor := _anchor(gate_root, "WorldAnchor_DungeonGate", Vector3(0, 1.0, 1.4))
	return {"spawn": Vector3(0, 1.05, 6.0), "return": portal_anchor,
		"heart": heart, "heart_anchor": heart_anchor, "gate_anchor": gate_anchor, "title": "镜界"}


# --- 对外接口 ---------------------------------------------------------------



# --- 「小事」装置：每个门后世界三处，全部完成才得纪念 --------------------------

## 三处装置的本地坐标与配色（按同伴版的布局：分散在场地四周，玩家要逐个走过去）。
const DEVICE_LAYOUT := {
	"snow": [Vector3(-5.2, 0.0, -2.4), Vector3(4.6, 0.0, -3.2), Vector3(0.4, 0.0, -7.2)],
	"cloud": [Vector3(1.9, 0.0, 1.5), Vector3(-2.6, 0.0, -5.6), Vector3(3.2, 0.0, -9.0)],
	"firefly": [Vector3(-5.8, 0.0, 0.8), Vector3(5.4, 0.0, -1.2), Vector3(0.0, 0.0, -6.8)],
	"alley": [Vector3(-2.2, 0.0, -4.2), Vector3(2.2, 0.0, -6.4), Vector3(0.0, 0.0, -10.2)],
}

const DEVICE_COLOR := {
	"snow": Color("cfe4f2"),
	"cloud": Color("ffd9a0"),
	"firefly": Color("d8f07a"),
	"alley": Color("a8c8d8"),
}


## ---------------------------------------------------------------------------
## 原作外围道具（木牌与各处小交互）
## id -> [世界, 相对位置, 提示语, 互动文案]
## 位置是相对该世界 holder 原点的坐标。
## ---------------------------------------------------------------------------
const PROP_TABLE := {
	# --- 雪夜小屋 ---
	"sign_snow": ["snow", Vector3(-3.6, 0.0, 4.2), "E · 读静冰湾的木牌",
		"木牌上写着：静冰湾的冰下还醒着几条鱼。对准冰洞按 E，蓄力抛竿，浮标沉下时提竿，再用按住与松开稳住张力。"],
	"sled": ["snow", Vector3(6.4, 0.0, 5.0), "E · 推一把雪橇",
		"雪橇沿着旧雪辙滑了出去。风从耳边过去，松林替你数着路。"],
	"lantern_snow": ["snow", Vector3(-6.2, 0.0, -1.6), "E · 点亮提灯",
		"一盏提灯，把通往木屋的路照亮了。"],
	# --- 金色云海 ---
	"sign_cloud": ["cloud", Vector3(5.04, 0.0, 2.93), "E · 读风琴礁的木牌",
		"木牌上写着：北风高、西风暖、回风轻。三种来风各奏一次，礁石会记住你。"],
	"cloud_beacon": ["cloud", Vector3(8.82, 0.0, -2.74), "E · 点亮云灯塔",
		"云灯塔亮起，飞艇循着光靠泊了。"],
	"cloud_winch": ["cloud", Vector3(2.30, 0.0, -4.19), "E · 放下云桥",
		"绞盘转动，云桥正缓缓落下"],
	"cloud_scope": ["cloud", Vector3(-9.45, 0.0, -2.74), "E · 望进云海",
		"望远镜里，巡游的飞艇正缓缓穿过云层"],
	"hearth_snow": ["snow", Vector3(8.6, 0.0, -2.2), "E · 给壁炉添柴",
		"你添了一根柴，木屋更暖了"],
	"wind_organ": ["cloud", Vector3(6.62, 0.0, 4.51), "E · 奏响风琴",
		"风琴礁的石台在等一阵来风。"],
	# --- 萤火森林 ---
	"sign_firefly": ["firefly", Vector3(-4.4, 0.0, 4.4), "E · 读森林的木牌",
		"木牌上写着：水车转、符文亮、木鼓响，林子的光就换一层。玻璃罐在树桩上，收满三簇再去放飞处。"],
	"ranger_lamp": ["firefly", Vector3(4.6, 0.0, 2.6), "E · 点亮护林灯",
		"护林灯亮起，树屋的路从暗处显出来了。"],
	"waterwheel": ["firefly", Vector3(-7.4, 0.0, -2.2), "E · 转动水车",
		"水车转起来，林子里的光跟着晃了一层。"],
	"wood_drum": ["firefly", Vector3(6.8, 0.0, -3.4), "E · 敲响木鼓",
		"鼓声沿着树根，传进森林更深处。"],
	"mushroom": ["firefly", Vector3(2.2, 0.0, 4.8), "E · 轻碰窗边的蘑菇",
		"蘑菇醒了，森林便有了回应。"],
	# --- 雨巷水钟 ---
	"sign_alley": ["alley", Vector3(-3.8, 0.0, 4.4), "E · 读雨巷的木牌",
		"木牌上写着：拨正三只檐兽，水钟就会醒来。伞下没有雨，只有灯和一小片安静。"],
	"umbrella": ["alley", Vector3(3.4, 0.0, -4.2), "E · 撑开油纸伞",
		"伞下没有雨，只有灯和一小片安静。"],
	"stone_cat": ["alley", Vector3(6.2, 0.0, -1.4), "E · 摇响石猫的铃铛",
		"铃铛一响，雨声也轻了一拍。"],
	"paper_boat": ["alley", Vector3(-5.6, 0.0, -2.8), "E · 把纸船放进水槽",
		"纸船正顺着水槽漂向水钟。"],
}

## 道具已触发状态：id -> bool
var prop_used: Dictionary = {}
## 道具锚点：id -> Node3D
var prop_anchors: Dictionary = {}

## ---------------------------------------------------------------------------
## 云海的内容照原作布局搭：窄栈桥 + 圆场 + 岛。
## 这些是原作的「世界坐标」，用它换算到内容层坐标。
func _cloud_scale() -> float:
	var arena: Array = ARENA_SCALE.get("cloud", [])
	if arena.is_empty() or PLATFORM_HALF <= 0.0:
		return 1.0
	return float(arena[0]) / (PLATFORM_HALF * 2.0)


func _cloud_local(world_pos: Vector3) -> Vector3:
	var arena: Array = ARENA_SCALE.get("cloud", [])
	if arena.is_empty():
		return world_pos
	var factor := _cloud_scale()
	return Vector3(world_pos.x / factor, world_pos.y, (world_pos.z - float(arena[1])) / factor)


## 原作的尺寸换算到内容层
func _cloud_len(world_len: float) -> float:
	return world_len / _cloud_scale()


## 云海的巡游飞艇（原作演示里镜头会仰头看它）
var airship_node: Node3D
## 飞艇巡游中心与半径（内容层坐标：都要按云海的缩放换算）
var airship_center := Vector3(0.0, 7.56, -3.37)
var airship_radius := 6.93
var _airship_phase := 0.0
## 截图/回归用：冻结飞艇，别让它继续巡游（默认关，玩法不受影响）
var airship_frozen := false

## 云桥：0 = 收起，1 = 完全放下。bridge_t 是过渡进度。
var bridge_t := 0.0
var bridge_target := 0.0
var bridge_down := false
var bridge_node: Node3D
## 雪夜炉火三档：0 一小团暖光 / 1 添了一根柴 / 2 明亮
var hearth_level := 1
var hearth_node: Node3D
var hearth_light: OmniLight3D
## 望远镜是否在看
var scope_active := false

## 云舟：可划的小舟（照原作 boatRide）
## ---------------------------------------------------------------------------
## 是否在船上
var boat_active := false
## 船的位置与朝向（世界坐标的 x/z，y 固定在水平面上）
var boat_pos := Vector2(2.14, -7.47)
var boat_heading := 0.4
## 当前速度（划桨推进）
var boat_speed := 0.0
## 云灯浮标已点的状态
var buoy_lit := [false, false, false]
## 云舟的 3D 节点与三盏浮标
var boat_node: Node3D
var buoy_nodes: Array = []
## 木栈桥（系舟点）
const BOAT_DOCK := Vector2(1.008, -8.41)
## 划桨手感：加速、阻力、转向速率
const BOAT_ACCEL := 3.4
const BOAT_DRAG := 1.25
const BOAT_TURN := 1.5
const BOAT_MAX_SPEED := 3.6
## 靠灯的距离、靠岸的距离
const BUOY_REACH := 2.6
const DOCK_REACH := 2.4


## 风琴礁：三种来风的听风记录在 progress 里，这里只做造型与锚点
const WIND_NAMES := ["北风", "西风", "回风"]
const WIND_LINES := [
	"北风穿过最高的音管，云海向远处让开",
	"西风放缓，低音把礁石烘得暖融融的",
	"回风绕岛一圈，每一根音管都轻轻相和",
]


## 布景密度系数：场地放大 s 倍后，面积是 s²，
## 数量要按 s² 补回来，否则同样面积里布景会明显变稀。
func _scenery_density(key: String) -> float:
	var arena: Array = ARENA_SCALE.get(key, [])
	if arena.is_empty() or PLATFORM_HALF <= 0.0:
		return 1.0
	var factor: float = float(arena[0]) / (PLATFORM_HALF * 2.0)
	return factor * factor


## 这个世界有没有登记道具
func _world_has_props(key: String) -> bool:
	for id in PROP_TABLE.keys():
		if String(PROP_TABLE[id][0]) == key:
			return true
	return false


## 世界的道具 id 列表
func prop_ids_in(key: String) -> Array:
	var list: Array = []
	for id in PROP_TABLE.keys():
		if String(PROP_TABLE[id][0]) == key:
			list.append(id)
	return list


## 道具锚点
func prop_anchor(id: String) -> Node3D:
	return prop_anchors.get(id, null) as Node3D


## 道具的提示语（互动前后可能不同）
func prop_prompt(id: String) -> String:
	if id == "wind_organ":
		var heard := _wind_heard_count()
		if bool(_wind_solved()):
			return "E · 再听一遍来风"
		if heard > 0:
			return "E · 换一种来风（%d/3）" % heard
		return "E · 奏响风琴"
	if id == "cloud_winch":
		# 用目标值判断，别等过渡动画跑完（放下的一瞬提示就该变成「收起」）
		return "E · 收起云桥" if bridge_target > 0.5 else "E · 放下云桥"
	if id == "hearth_snow":
		return "E · 让炉火歇一歇" if hearth_level >= 2 else "E · 给壁炉添柴"
	if not PROP_TABLE.has(id):
		return ""
	if bool(prop_used.get(id, false)):
		return "已经回应过了"
	return String(PROP_TABLE[id][2])


## 世界里的玩家站在某个道具旁：返回道具 id（空串表示没有）
func near_prop(world_key: String, player_pos: Vector3, radius := 2.2) -> String:
	for id in prop_ids_in(world_key):
		var anchor := prop_anchor(String(id))
		if anchor == null:
			continue
		if player_pos.distance_to(anchor.global_position) < radius:
			return String(id)
	return ""


## 用一次道具：返回 {ok, message, solved}
## 风琴礁单独处理（三来风），其余道具是「一次性回应」。
func use_prop(id: String) -> Dictionary:
	if id == "wind_organ":
		return use_wind_organ()
	if id == "cloud_winch":
		return use_winch()
	if id == "cloud_scope":
		return use_scope()
	if id == "hearth_snow":
		return use_hearth()
	if not PROP_TABLE.has(id):
		return {"ok": false, "message": "", "solved": false}
	if bool(prop_used.get(id, false)):
		return {"ok": false, "message": "已经回应过了", "solved": false}
	prop_used[id] = true
	# 让造型亮起来（提灯 / 护林灯 / 云灯塔 / 蘑菇 / 石猫铃铛之类有发光件）
	_lighten_prop(id)
	return {"ok": true, "message": String(PROP_TABLE[id][3]), "solved": false}


## 让道具造型亮一层：找到子节点里的发光件调亮
func _lighten_prop(id: String) -> void:
	var anchor := prop_anchor(id)
	if anchor == null:
		return
	for child in anchor.get_children():
		if child is OmniLight3D:
			(child as OmniLight3D).light_energy = minf((child as OmniLight3D).light_energy * 2.2, 6.0)
		elif child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			var material := mesh.material_override
			if material is StandardMaterial3D:
				var std := material as StandardMaterial3D
				if std.emission_enabled:
					std.emission_energy_multiplier = minf(std.emission_energy_multiplier * 1.8, 4.0)


## ---------------------------------------------------------------------------
## 风琴礁：北风 / 西风 / 回风，三种各听一次即和鸣
## ---------------------------------------------------------------------------
## 风琴礁状态存在 progress 里（随行囊存档），attic_worlds 只做代理。
var progress_ref: Node


func _wind_heard_count() -> int:
	return progress_ref.wind_heard_count() if progress_ref != null else 0


func _wind_solved() -> bool:
	return bool(progress_ref.wind_solved) if progress_ref != null else false


## 云桥绞盘：放下 / 收起。照原作，人还在桥上（桥那头）时不能收。
func use_winch() -> Dictionary:
	# 判「人是否已经在桥外侧」由 main 传进来，这里只看状态机
	bridge_target = 0.0 if bridge_target > 0.5 else 1.0
	if bridge_target <= 0.5:
		bridge_down = false
		return {"ok": true, "message": "云桥收起，风从断开的地方穿过", "down": false}
	return {"ok": true, "message": "绞盘转动，云桥正缓缓落下", "down": true}


## 云桥每帧过渡（由 main 调用）
func update_bridge(delta: float) -> void:
	if bridge_node == null:
		return
	var speed := 1.1
	bridge_t = move_toward(bridge_t, bridge_target, speed * delta)
	# 收起时桥面贴着平台、并绕轴翻转一点，放下时水平伸出
	bridge_node.rotation.x = lerpf(-0.55, 0.0, bridge_t)
	bridge_node.position.y = lerpf(1.35, 0.02, bridge_t)
	bridge_node.visible = bridge_t > 0.02
	if bridge_t >= 0.999:
		bridge_down = true


## 望远镜：望进云海（由 main 接管相机），返回要看的文案
func use_scope() -> Dictionary:
	scope_active = true
	var beacon_on := bool(prop_used.get("cloud_beacon", false))
	var message := "循着灯光，飞艇正靠向云港" if beacon_on else "望远镜里，巡游的飞艇正缓缓穿过云层"
	return {"ok": true, "message": message, "scope": true}


func close_scope() -> void:
	scope_active = false


## 雪夜炉火：三档循环（照原作 hearthLevel = (level + 1) % 3）
func use_hearth() -> Dictionary:
	hearth_level = (hearth_level + 1) % 3
	var lines := [
		"炉火收成一小团暖光，仍在这里等你",
		"你添了一根柴，木屋更暖了",
		"炉火明亮起来，雪夜被关在门外",
	]
	_apply_hearth()
	return {"ok": true, "message": String(lines[hearth_level]), "level": hearth_level}


## 炉火亮度的三档表现
func _apply_hearth() -> void:
	if hearth_node == null:
		return
	var energies := [0.55, 1.8, 3.4]
	var reaches := [4.0, 7.0, 10.0]
	if hearth_light != null and is_instance_valid(hearth_light):
		hearth_light.light_energy = float(energies[clampi(hearth_level, 0, 2)])
		hearth_light.omni_range = float(reaches[clampi(hearth_level, 0, 2)])
	# 火苗大小跟着变
	for child in hearth_node.get_children():
		if child is MeshInstance3D and String((child as MeshInstance3D).name) == "Flame":
			var flame := child as MeshInstance3D
			var scale_table: Array = [0.6, 1.0, 1.45]
			var scale_factor: float = float(scale_table[clampi(hearth_level, 0, 2)])
			flame.scale = Vector3.ONE * scale_factor


## 奏响风琴：轮换到下一种来风
func use_wind_organ() -> Dictionary:
	if progress_ref == null:
		return {"ok": false, "message": "", "solved": false, "wind": -1}
	return progress_ref.hear_wind()


## 生成某个世界里的全部道具造型与锚点
func _build_props(holder: Node3D, key: String) -> void:
	for id in PROP_TABLE.keys():
		var row: Array = PROP_TABLE[id]
		if String(row[0]) != key:
			continue
		var at: Vector3 = row[1]
		var anchor := Node3D.new()
		anchor.name = "PropAnchor_%s" % id
		anchor.position = at
		holder.add_child(anchor)
		prop_anchors[id] = anchor
		_make_prop_mesh(anchor, String(id))


## 按 id 造对应的立体造型（都以锚点为父，原点在道具脚下）
func _make_prop_mesh(anchor: Node3D, id: String) -> void:
	# ── Lux3D 模型优先（2026-11-12）────────────────────────────────
	#
	# 13 个纯装饰/结构性道具直接用 Lux3D 模型；**带发光件的保留程序化发光体**，
	# 因为 `_lighten_prop()` 靠遍历 anchor 子节点里 emission 材质来「用一次就亮」，
	# 换成不搞自发光的外部模型，这个交互反馈就没了。
	#
	# 映射表：id -> [模型名, 目标高度米]
	# ⚠ GDScript 没有元组字面量，`("a", 0.5)` 会解析失败，必须用数组 []。
	# 高度按各分支原来程序化造型的视觉高度估的，改模型尺寸时只需改这里。
	var prop_map := {
		"sled": ["snow-sled", 0.55],
		"cloud_scope": ["telescope", 1.75],
		"wood_drum": ["wood-drum", 1.0],
		"mushroom": ["glow-mushroom", 0.55],
		"umbrella": ["paper-umbrella", 1.75],
		"stone_cat": ["stone-cat", 0.95],
		"paper_boat": ["paper-boat", 0.35],
		"cloud_winch": ["cloud-wincht", 1.2],
		"wind_organ": ["wind-organ", 1.7],
		"waterwheel": ["waterwheel", 2.3],
	}
	if prop_map.has(id):
		var spec: Array = prop_map[id]
		var model := _prop(String(spec[0]), float(spec[1]))
		if model != null:
			anchor.add_child(model)
			return
	# 带发光件的道具：只把「外壳」换模型，发光体在后面各自保留。
	#   sign_*      → wooden-sign（牌子本身没发光）
	#   lantern_snow / ranger_lamp / cloud_beacon / hearth_snow → 保留程序化外壳+火焰
	if id.begins_with("sign_"):
		var sign_model := _prop("wooden-sign", 1.45)
		if sign_model != null:
			anchor.add_child(sign_model)
			return
	var wood := _mat(Color("6b5138"))
	var dark := _mat(Color("3c2e20"))
	var stone := _mat(Color("8d949c"))
	var brass := _mat(Color("b8913f"))
	match id:
		"sign_snow", "sign_cloud", "sign_firefly", "sign_alley":
			# 木牌：一根柱子 + 一块小牌子（路牌尺寸，别做得像一堵墙）
			_cyl(anchor, 0.045, 0.06, 1.15, Vector3(0, 0.58, 0), dark, 8)
			var board := _box(anchor, Vector3(0.72, 0.34, 0.05), Vector3(0, 1.18, 0),
				_mat(Color("d8cbae")))
			board.rotation.x = -0.10
			_box(anchor, Vector3(0.62, 0.035, 0.06), Vector3(0, 1.31, -0.008), dark)
			_box(anchor, Vector3(0.62, 0.035, 0.06), Vector3(0, 1.05, -0.008), dark)
			# 牌面上一道浅刻痕，远看也知道是块写了字的牌子
			_box(anchor, Vector3(0.44, 0.022, 0.058), Vector3(0, 1.2, 0.002),
				_mat(Color("6f6350")))
		"sled":
			# 雪橇：两条滑板 + 几根横木
			for side in [-0.28, 0.28]:
				_box(anchor, Vector3(0.1, 0.08, 1.9), Vector3(float(side), 0.06, 0), wood)
				var tip := _box(anchor, Vector3(0.1, 0.08, 0.42), Vector3(float(side), 0.24, -1.05), wood)
				tip.rotation.x = -0.7
			for i in range(4):
				_box(anchor, Vector3(0.72, 0.06, 0.14), Vector3(0, 0.2, -0.7 + float(i) * 0.46), dark)
		"cloud_winch":
			# 云桥绞盘：木箱 + 铁轴 + 黄铜转盘 + 摇柄
			var iron := _mat(Color("4a4f56"))
			var pale := _mat(Color("cdbfa4"))
			_box(anchor, Vector3(0.8, 0.45, 0.8), Vector3(0, 0.22, 0), dark)
			_cyl(anchor, 0.13, 0.13, 0.65, Vector3(0, 0.57, 0), iron, 12)
			var handle := Node3D.new()
			handle.name = "WinchHandle"
			handle.position = Vector3(0, 0.62, 0)
			anchor.add_child(handle)
			_box(handle, Vector3(1.05, 0.1, 0.1), Vector3(0.48, 0, 0), brass)
			_cyl(handle, 0.16, 0.16, 0.08, Vector3(0, 0, 0), _mat(Color("8f6f2f")), 16)
			_box(handle, Vector3(0.055, 0.055, 0.35), Vector3(0.98, -0.25, 0), dark)
			# 桥面本体（收起时贴着平台，放下时伸出去）
			bridge_node = Node3D.new()
			bridge_node.name = "CloudBridge"
			bridge_node.position = Vector3(0, 0.02, 1.4)
			anchor.add_child(bridge_node)
			for i in range(14):
				_box(bridge_node, Vector3(2.5, 0.14, 0.32),
					Vector3(0, 0, -0.35 - float(i) * 0.33),
					wood if i % 4 != 0 else pale)
			for side in [-1.2, 1.2]:
				_box(bridge_node, Vector3(0.1, 0.11, 4.6), Vector3(float(side), 0.86, -2.2), dark)
		"cloud_scope":
			# 望远镜：三脚架 + 黄铜镜筒（指向云海）
			var iron2 := _mat(Color("4a4f56"))
			for i in range(3):
				var ang := TAU * float(i) / 3.0
				var leg := _cyl(anchor, 0.05, 0.05, 1.5,
					Vector3(cos(ang) * 0.32, 0.72, sin(ang) * 0.32), iron2, 6)
				leg.rotation.z = cos(ang) * 0.18
			var tube := Node3D.new()
			tube.name = "ScopeTube"
			tube.position = Vector3(0, 1.5, 0)
			tube.rotation.x = PI * 0.5
			tube.rotation.z = -0.62
			anchor.add_child(tube)
			_cyl(tube, 0.15, 0.23, 1.75, Vector3(0, 0, 0), brass, 20)
			_cyl(tube, 0.31, 0.31, 0.1, Vector3(0, 0.86, 0), _mat(Color("8f6f2f")), 20)
			_cyl(tube, 0.24, 0.24, 0.08, Vector3(0, -0.86, 0), iron2, 20)
		"hearth_snow":
			# 雪夜炉火：石砌壁炉 + 柴堆 + 火苗
			var stone2 := _mat(Color("6f6a63"))
			_box(anchor, Vector3(1.5, 1.5, 0.7), Vector3(0, 0.75, 0), stone2)
			_box(anchor, Vector3(1.1, 0.75, 0.25), Vector3(0, 0.45, 0.28), _mat(Color("221a14")))
			_box(anchor, Vector3(1.6, 0.14, 0.8), Vector3(0, 1.56, 0), _mat(Color("807a72")))
			# 柴（横放）
			for i in range(3):
				_cyl(anchor, 0.07, 0.08, 0.7,
					Vector3(-0.2 + float(i) * 0.2, 0.3, 0.3), _mat(Color("4a3527")), 7).rotation.z = PI * 0.5
			# 火苗
			var flame := _sphere(anchor, 0.24, Vector3(0, 0.52, 0.3), _mat(Color("ff9b46"), 1.8))
			flame.name = "Flame"
			hearth_node = anchor
			hearth_light = _light(anchor, Vector3(0, 0.9, 0.5), Color("ffab5b"), 1.8, 7.0)
		"lantern_snow":
			# 提灯：柱子 + 灯笼
			_cyl(anchor, 0.05, 0.06, 1.5, Vector3(0, 0.75, 0), dark, 7)
			_cyl(anchor, 0.15, 0.13, 0.3, Vector3(0, 1.62, 0), _mat(Color("ffdca8"), 1.4), 10)
			_sphere(anchor, 0.09, Vector3(0, 1.62, 0), _mat(Color("fff0cc"), 2.2))
			_light(anchor, Vector3(0, 1.62, 0), Color("ffcf9a"), 1.6, 6.0)
		"cloud_beacon":
			# 云灯塔：下粗上细的石塔 + 顶灯
			_cyl(anchor, 0.5, 0.85, 3.4, Vector3(0, 1.7, 0), stone, 12)
			_cyl(anchor, 0.62, 0.62, 0.2, Vector3(0, 3.5, 0), brass, 12)
			_sphere(anchor, 0.34, Vector3(0, 3.86, 0), _mat(Color("ffe6b0"), 1.2))
			_light(anchor, Vector3(0, 3.86, 0), Color("ffd9a0"), 2.0, 10.0)
		"wind_organ":
			# 风琴礁：一排高低不一的音管 + 起奏石台
			_box(anchor, Vector3(3.0, 0.4, 1.6), Vector3(0, 0.2, 0), stone)
			for i in range(7):
				var h := 1.4 + float(i % 4) * 0.55
				var x := -1.2 + float(i) * 0.4
				_cyl(anchor, 0.11, 0.13, h, Vector3(x, 0.4 + h * 0.5, 0), brass, 9)
				_cyl(anchor, 0.13, 0.13, 0.06, Vector3(x, 0.4 + h, 0), _mat(Color("d8b463")), 9)
			_box(anchor, Vector3(0.8, 0.16, 0.6), Vector3(0, 0.48, 1.05), dark)
		"ranger_lamp":
			# 护林灯：细杆 + 灯罩
			_cyl(anchor, 0.06, 0.08, 1.8, Vector3(0, 0.9, 0), dark, 7)
			_cyl(anchor, 0.2, 0.14, 0.38, Vector3(0, 1.94, 0), _mat(Color("d8f07a"), 1.3), 10)
			_light(anchor, Vector3(0, 1.94, 0), Color("d6f282"), 1.4, 5.5)
		"waterwheel":
			# 水车：一个竖轮 + 支架
			for side in [-0.5, 0.5]:
				_cyl(anchor, 0.07, 0.07, 1.8, Vector3(float(side), 0.9, 0), dark, 6)
			_cyl(anchor, 0.9, 0.9, 0.12, Vector3(0, 1.1, 0), wood, 14)
			for i in range(8):
				var angle := float(i) * TAU / 8.0
				var paddle := _box(anchor, Vector3(0.34, 0.5, 0.1),
					Vector3(cos(angle) * 0.72, 1.1 + sin(angle) * 0.72, 0), _mat(Color("8a6f4d")))
				paddle.rotation.z = angle
		"wood_drum":
			# 木鼓：横放的鼓桶 + 两根鼓槌
			var drum := _cyl(anchor, 0.42, 0.42, 0.9, Vector3(0, 0.62, 0), _mat(Color("7a5230")), 14)
			drum.rotation.x = PI * 0.5
			_cyl(anchor, 0.44, 0.44, 0.06, Vector3(0, 0.62, -0.45), _mat(Color("d8c9a8")), 14).rotation.x = PI * 0.5
			_cyl(anchor, 0.44, 0.44, 0.06, Vector3(0, 0.62, 0.45), _mat(Color("d8c9a8")), 14).rotation.x = PI * 0.5
			_box(anchor, Vector3(0.06, 0.06, 0.7), Vector3(0.5, 0.9, 0), wood)
			_box(anchor, Vector3(0.06, 0.06, 0.7), Vector3(-0.5, 0.9, 0), wood)
		"mushroom":
			# 蘑菇丛：几个菌盖 + 细柄
			for i in range(4):
				var x := -0.32 + float(i % 2) * 0.5
				var z := -0.2 + float(i / 2) * 0.44
				var h := 0.18 + float(i % 3) * 0.07
				_cyl(anchor, 0.045, 0.055, h, Vector3(x, h * 0.5, z), _mat(Color("e8e0cd")), 7)
				_sphere(anchor, 0.13, Vector3(x, h + 0.05, z), _mat(Color("c85a54"), 0.5))
		"umbrella":
			# 油纸伞：伞面 + 伞骨 + 柄
			_cyl(anchor, 0.045, 0.045, 1.5, Vector3(0, 0.75, 0), dark, 7)
			var canopy := _cyl(anchor, 0.06, 0.92, 0.42, Vector3(0, 1.52, 0), _mat(Color("c96a52")), 16)
			canopy.name = "UmbrellaCanopy"
			for i in range(8):
				var angle := float(i) * TAU / 8.0
				_box(anchor, Vector3(0.03, 0.03, 0.9),
					Vector3(cos(angle) * 0.44, 1.34, sin(angle) * 0.44), dark).rotation.y = angle
		"stone_cat":
			# 石猫：蹲着的猫身 + 头 + 耳朵 + 铃铛
			_box(anchor, Vector3(0.42, 0.5, 0.68), Vector3(0, 0.25, 0), stone)
			_sphere(anchor, 0.26, Vector3(0, 0.72, -0.26), stone)
			for side in [-1.0, 1.0]:
				var ear := _cyl(anchor, 0.0, 0.11, 0.2, Vector3(float(side) * 0.14, 0.94, -0.26), stone, 4)
				ear.name = "CatEar"
			_box(anchor, Vector3(0.18, 0.52, 0.1), Vector3(0, 0.52, 0.36), stone)
			_sphere(anchor, 0.075, Vector3(0, 0.5, 0.2), _mat(Color("d8b463"), 0.8))
		"paper_boat":
			# 纸船：船底 + 两片折起的帆面
			_box(anchor, Vector3(0.42, 0.09, 0.66), Vector3(0, 0.06, 0), _mat(Color("efe6d2")))
			for side in [-1.0, 1.0]:
				var sail := _box(anchor, Vector3(0.02, 0.28, 0.58), Vector3(float(side) * 0.13, 0.2, 0),
					_mat(Color("f6efdd")))
				sail.rotation.z = float(side) * 0.5


func _add_devices(holder: Node3D, key: String) -> void:
	var layout: Array = DEVICE_LAYOUT.get(key, [])
	var color: Color = DEVICE_COLOR.get(key, Color.WHITE)
	var list: Array = []
	for i in range(layout.size()):
		var at: Vector3 = layout[i]
		var entry: Dictionary = {}
		match key:
			"snow":
				entry = _device_snow(holder, at, color, i)
			"cloud":
				entry = _device_cloud(holder, at, color, i)
			"firefly":
				entry = _device_firefly(holder, at, color, i)
			"alley":
				entry = _device_alley(holder, at, color, i)
		list.append(entry)
	device_nodes[key] = list


## 雪夜：一面可转三档的冰镜。对齐后镜面自发光变亮。
func _device_snow(holder: Node3D, at: Vector3, color: Color, index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Device_IceMirror_%d" % index
	root.position = at
	holder.add_child(root)
	var stone := _mat(Color("4a5666"))
	_cyl(root, 0.34, 0.46, 1.1, Vector3(0, 0.55, 0), stone, 8)
	var mirror_mat := _mat(color, 0.25)
	var frame := _mat(Color("6d7a88"))
	var glass := _box(root, Vector3(1.25, 1.55, 0.08), Vector3(0, 1.75, 0), mirror_mat)
	_box(root, Vector3(1.45, 0.12, 0.14), Vector3(0, 2.58, 0), frame)
	_box(root, Vector3(1.45, 0.12, 0.14), Vector3(0, 0.92, 0), frame)
	var anchor := _anchor(root, "DeviceAnchor_%d" % index, Vector3(0, 1.3, 0.9))
	return {"node": root, "anchor": anchor, "mesh": glass, "material": mirror_mat, "kind": "mirror"}


## 云海：一盏云灯浮标。点亮后自发光。
func _device_cloud(holder: Node3D, at: Vector3, color: Color, index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Device_Buoy_%d" % index
	root.position = at
	holder.add_child(root)
	var iron := _mat(Color("3d4650"))
	_cyl(root, 0.55, 0.42, 0.34, Vector3(0, 0.17, 0), iron, 12)
	_cyl(root, 0.10, 0.12, 1.35, Vector3(0, 1.0, 0), iron, 8)
	var lamp_mat := _mat(color, 0.12)
	var lamp := _sphere(root, 0.30, Vector3(0, 1.86, 0), lamp_mat)
	_cyl(root, 0.20, 0.34, 0.22, Vector3(0, 2.14, 0), iron, 10)
	var anchor := _anchor(root, "DeviceAnchor_%d" % index, Vector3(0, 1.1, 0.85))
	return {"node": root, "anchor": anchor, "mesh": lamp, "material": lamp_mat, "kind": "buoy"}


## 萤火：一只玻璃罐，靠近收集一簇萤火。
func _device_firefly(holder: Node3D, at: Vector3, color: Color, index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Device_Jar_%d" % index
	root.position = at
	holder.add_child(root)
	var wood := _mat(Color("3f3024"))
	_cyl(root, 0.28, 0.32, 0.55, Vector3(0, 0.27, 0), wood, 10)
	var jar_mat := _mat(Color("b9d8b0"), 0.18)
	jar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jar_mat.albedo_color = Color(0.72, 0.85, 0.72, 0.45)
	_cyl(root, 0.24, 0.26, 0.62, Vector3(0, 0.86, 0), jar_mat, 12)
	var glow_mat := _mat(color, 0.35)
	var glow := _sphere(root, 0.11, Vector3(0, 0.88, 0), glow_mat)
	var anchor := _anchor(root, "DeviceAnchor_%d" % index, Vector3(0, 0.8, 0.75))
	return {"node": root, "anchor": anchor, "mesh": glow, "material": glow_mat, "kind": "jar"}


## 雨巷：一只檐口水兽，铜阀可转。
func _device_alley(holder: Node3D, at: Vector3, color: Color, index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Device_Spout_%d" % index
	root.position = at
	holder.add_child(root)
	var stone := _mat(Color("7a8288"))
	var brass := _mat(Color("b8913f"))
	_cyl(root, 0.44, 0.52, 1.15, Vector3(0, 0.57, 0), stone, 10)
	_sphere(root, 0.38, Vector3(0, 1.10, 0), stone)
	_cyl(root, 0.16, 0.16, 0.75, Vector3(0, 1.02, 0.42), stone, 8).rotation.x = PI * 0.5
	var valve_mat := _mat(color, 0.2)
	var valve := _cyl(root, 0.20, 0.20, 0.12, Vector3(0, 1.02, 0.82), valve_mat, 10)
	valve.rotation.x = PI * 0.5
	_box(root, Vector3(0.52, 0.07, 0.07), Vector3(0, 1.02, 0.86), brass)
	var anchor := _anchor(root, "DeviceAnchor_%d" % index, Vector3(0, 0.95, 1.05))
	return {"node": root, "anchor": anchor, "mesh": valve, "material": valve_mat, "kind": "valve"}


func device_anchor(key: String, index: int):
	if not device_nodes.has(key):
		return null
	var list: Array = device_nodes[key]
	if index < 0 or index >= list.size():
		return null
	return list[index]["anchor"]


func device_done(key: String, index: int) -> bool:
	if not device_states.has(key):
		return false
	var states: Array = device_states[key]
	return index >= 0 and index < states.size() and states[index]


func devices_all_done(key: String) -> bool:
	if not device_states.has(key):
		return false
	for state in device_states[key]:
		if not state:
			return false
	return true


## 拨动一处装置。
## 返回 {changed, solved, aligned, message}：
##   changed  这一下有没有产生变化（已经完成的不会被重复拨动）
##   solved   这个世界的三处是否齐了（齐了才得纪念）
##   aligned  当前已完成/已对齐的处数
##   message  给玩家的一行提示
func activate_device(key: String, index: int) -> Dictionary:
	var result := {"changed": false, "solved": false, "aligned": 0, "message": ""}
	if not device_states.has(key) or not device_nodes.has(key):
		return result
	var states: Array = device_states[key]
	if index < 0 or index >= states.size():
		return result

	var values: Array = device_values.get(key, [0, 0, 0])
	var list: Array = device_nodes[key]
	var material: StandardMaterial3D = list[index]["material"]
	var _node: Node3D = list[index]["node"]

	match key:
		"snow":
			# 冰镜：每按一次转一档，三面转到同一方向才折出极光
			values[index] = (int(values[index]) + 1) % 3
			device_values[key] = values
			var yaw: float = float(values[index]) * 0.42
			(list[index]["mesh"] as MeshInstance3D).rotation.y = yaw
			var common: bool = values[0] == values[1] and values[1] == values[2]
			for i in range(3):
				states[i] = common
				var mat: StandardMaterial3D = list[i]["material"]
				mat.emission_enabled = common
				if common:
					mat.emission = DEVICE_COLOR.get(key, Color.WHITE)
					mat.emission_energy_multiplier = 2.0
				else:
					mat.emission_energy_multiplier = 0.0
			result["changed"] = true
			result["message"] = "冰镜同时折光，极光像帘子一样垂下来" if common else "冰镜偏开，光从镜边滑走"
		"alley":
			# 水兽铜阀：每按一次转一档，转到竖位（0 档）才算对齐
			values[index] = (int(values[index]) + 1) % 3
			device_values[key] = values
			var valve: MeshInstance3D = list[index]["mesh"]
			valve.rotation.z = float(values[index]) * (PI / 3.0)
			states[index] = int(values[index]) == 0
			material.emission_enabled = states[index]
			material.emission_energy_multiplier = 1.8 if states[index] else 0.0
			result["changed"] = true
			result["message"] = "水兽把雨水倒进石槽" if states[index] else "铜阀还没对准竖位"
		_:
			# 浮标 / 玻璃罐：一次性完成
			if states[index]:
				return result
			states[index] = true
			material.emission_enabled = true
			material.emission = DEVICE_COLOR.get(key, Color.WHITE)
			material.emission_energy_multiplier = 2.0
			result["changed"] = true
			result["message"] = "点亮了一盏云灯" if key == "cloud" else "收起了一簇萤火"

	device_states[key] = states
	var aligned := 0
	for state in states:
		if state:
			aligned += 1
	result["aligned"] = aligned
	if devices_all_done(key) and not bool(world_done.get(key, false)):
		_show_completion(key)
		result["solved"] = true
	return result


## 三处都完成：在该世界里给出可见的「成了」反馈。
func _show_completion(key: String) -> void:
	if not worlds.has(key):
		return
	var holder: Node3D = worlds[key]["node"]
	world_done[key] = true
	match key:
		"snow":
			# 极光：天上一层发光帘幕
			var aurora_mat := _mat(Color("9fe8c8"), 1.1)
			aurora_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			aurora_mat.albedo_color = Color(0.62, 0.95, 0.82, 0.22)
			aurora_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var aurora := _box(holder, Vector3(26.0, 0.08, 18.0), Vector3(0, 13.0, -6.0), aurora_mat)
			aurora.name = "Aurora"
			_light(holder, Vector3(0, 11.0, -4.0), Color("9fe8c8"), 2.2, 40.0)
		"cloud":
			# 云桥：从场地伸向云海的一道光桥
			var bridge_mat := _mat(Color("ffe1a8"), 0.7)
			bridge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bridge_mat.albedo_color = Color(1.0, 0.88, 0.66, 0.55)
			bridge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var bridge := _box(holder, Vector3(3.2, 0.12, 16.0), Vector3(0, 0.35, -16.0), bridge_mat)
			bridge.name = "CloudBridge"
			_light(holder, Vector3(0, 3.0, -12.0), Color("ffe1a8"), 2.0, 26.0)
		"firefly":
			# 树屋亮起：一团暖光
			var tree_glow := _mat(Color("ffd9a0"), 1.6)
			_box(holder, Vector3(2.4, 2.2, 2.4), Vector3(0, 4.2, -7.0), tree_glow).name = "TreeHouse"
			_light(holder, Vector3(0, 4.4, -7.0), Color("ffd9a0"), 2.4, 26.0)
		"alley":
			# 水钟醒：巷尾的水钟亮起
			var clock_mat := _mat(Color("cfe8f0"), 1.4)
			_cyl(holder, 1.1, 1.3, 0.5, Vector3(0, 3.4, -11.2), clock_mat, 16).name = "WaterClock"
			_light(holder, Vector3(0, 3.4, -11.0), Color("cfe8f0"), 2.2, 22.0)




## 冰钓：三处冰洞 + 三盏冰灯（钓上一尾亮一盏）。
func _build_fishing_holes(holder: Node3D) -> void:
	var spots := [Vector3(-7.6, 0.0, 3.6), Vector3(0.0, 0.0, -10.4), Vector3(7.8, 0.0, 3.2)]
	var ice_mat := _mat(Color("9fc6dc"))
	var hole_mat := _mat(Color("0b1a24"))
	var post_mat := _mat(Color("3b4650"))
	for i in range(spots.size()):
		var at: Vector3 = spots[i]
		var root := Node3D.new()
		root.name = "FishingHole_%d" % i
		root.position = at
		holder.add_child(root)
		# 冰面上的洞口
		_cyl(root, 1.15, 1.15, 0.10, Vector3(0, 0.06, 0), ice_mat, 18)
		_cyl(root, 0.72, 0.72, 0.06, Vector3(0, 0.09, 0), hole_mat, 16)
		# 冰灯：先暗，钓上鱼再亮
		_cyl(root, 0.06, 0.08, 1.35, Vector3(1.35, 0.68, 0.2), post_mat, 6)
		var lamp_mat := _mat(Color("cfe8f4"), 0.05)
		var lamp := _sphere(root, 0.19, Vector3(1.35, 1.44, 0.2), lamp_mat)
		var hole_anchor := _anchor(root, "FishAnchor_%d" % i, Vector3(0, 0.9, 0.0))
		fishing_holes.append({
			"node": root, "anchor": hole_anchor, "lamp": lamp,
			"material": lamp_mat, "caught": false, "name": fish_names[i % fish_names.size()],
		})


func hole_anchor(index: int):
	if index < 0 or index >= fishing_holes.size():
		return null
	return fishing_holes[index]["anchor"]


func hole_caught(index: int) -> bool:
	if index < 0 or index >= fishing_holes.size():
		return true
	return bool(fishing_holes[index]["caught"])


func hole_name(index: int) -> String:
	if index < 0 or index >= fishing_holes.size():
		return ""
	return String(fishing_holes[index]["name"])


## 钓上一尾：点亮该洞的冰灯，返回已钓尾数。
func catch_fish(index: int) -> int:
	if index < 0 or index >= fishing_holes.size():
		return 0
	var hole: Dictionary = fishing_holes[index]
	if bool(hole["caught"]):
		return caught_count()
	hole["caught"] = true
	fishing_holes[index] = hole
	var material: StandardMaterial3D = hole["material"]
	material.emission_enabled = true
	material.emission = Color("cfe8f4")
	material.emission_energy_multiplier = 2.2
	var lamp: MeshInstance3D = hole["lamp"]
	_light(lamp.get_parent() as Node3D, lamp.position + Vector3(0, 0.15, 0), Color("cfe8f4"), 1.6, 9.0)
	return caught_count()


func caught_count() -> int:
	var total := 0
	for hole in fishing_holes:
		if bool(hole["caught"]):
			total += 1
	return total




## 云海风琴礁：四面风铃挂在石架上，旁边一块起奏的石台。
## 云海的巡游飞艇：椭圆气囊 + 吊舱 + 尾鳍，绕着云海慢慢绕圈
func _build_airship(holder: Node3D) -> void:
	var hull := _mat(Color("d8d2c4"))
	var trim := _mat(Color("b8913f"))
	var dark := _mat(Color("3c4048"))
	var airship := Node3D.new()
	airship.name = "Airship"
	airship.position = airship_center
	holder.add_child(airship)
	# 飞艇本体优先用 Lux3D 模型。⚠ 巡游动画移动的是 airship 这个父节点，
	# 所以模型挂成子节点、local 位置归零即可，不影响 `_update_airship`。
	var airship_prop := _prop("airship", 5.2)
	if airship_prop != null:
		airship.add_child(airship_prop)
		_light(airship, Vector3(0, -2.5, 0), Color("ffd9a0"), 1.6, 9.0)
		airship_node = airship
		return
	# 气囊
	var bag := _sphere(airship, 1.9, Vector3(0, 0, 0), hull)
	bag.scale = Vector3(1.0, 1.0, 2.35)
	# 环带
	for z in [-2.2, 0.0, 2.2]:
		var ring := _cyl(airship, 1.92, 1.92, 0.09, Vector3(0, 0, float(z)), trim, 20)
		ring.rotation.x = PI * 0.5
	# 吊舱
	_box(airship, Vector3(1.0, 0.55, 2.0), Vector3(0, -2.15, 0), _mat(Color("6b5138")))
	_box(airship, Vector3(1.1, 0.12, 2.1), Vector3(0, -1.86, 0), dark)
	# 尾鳍
	for side in [-1.0, 1.0]:
		var fin := _box(airship, Vector3(0.08, 0.85, 0.7), Vector3(float(side) * 0.55, 0.35, 4.0), trim)
		fin.rotation.z = float(side) * 0.3
	_box(airship, Vector3(0.08, 0.9, 0.75), Vector3(0, 1.05, 4.0), trim)
	# 吊舱下的灯
	_light(airship, Vector3(0, -2.5, 0), Color("ffd9a0"), 1.6, 9.0)
	airship_node = airship


## 飞艇绕云海巡游（由 main 每帧调用）
func update_airship(delta: float) -> void:
	if airship_node == null or airship_frozen:
		return
	_airship_phase += delta * 0.085
	var angle := _airship_phase
	airship_node.position = airship_center + Vector3(cos(angle) * airship_radius,
		sin(angle * 1.7) * 0.9, sin(angle) * airship_radius * 0.72)
	# 机头朝向切线方向
	var next_angle := angle + 0.05
	var next_pos := airship_center + Vector3(cos(next_angle) * airship_radius,
		sin(next_angle * 1.7) * 0.9, sin(next_angle) * airship_radius * 0.72)
	var dir := next_pos - airship_node.position
	if dir.length() > 0.001:
		airship_node.look_at(airship_node.position + dir.normalized(), Vector3.UP)
		# look_at 让 -z 朝前，气囊长轴是 z，正好


## 截图/回归用：把飞艇摆到固定相位并冻住
func freeze_airship_at(phase: float) -> void:
	_airship_phase = phase
	airship_frozen = false
	update_airship(0.0)
	airship_frozen = true


## 云海的地面：照原作的可行走区搭。
## 不套用其它世界的方形台与围墙 —— 这里要的就是「栈桥」的窄，
## 所以只用多个矩形/圆柱拼出走道，四周不设墙（掉下去由 main 的落点救援兜住）。
func _build_cloud_ground(holder: Node3D, stone: Material, pale: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	holder.add_child(body)

	# 原作坐标下的矩形走道：[minX, minZ, maxX, maxZ]
	var rects := [
		[-2.80, -23.00, 2.80, -4.02],     # 主栈桥
		[-10.20, -29.55, -5.70, -27.90],  # 西连接
		[5.65, -30.30, 9.20, -28.30],     # 东连接
		[-1.38, -40.30, 1.38, -32.70],    # 尽头窄桥
		[2.40, -21.45, 8.60, -19.55],     # 东平台连接
		[5.35, -45.28, 7.10, -43.72],     # 尽头小段
	]
	for r in rects:
		var min_x := float(r[0])
		var min_z := float(r[1])
		var max_x := float(r[2])
		var max_z := float(r[3])
		var half_w := _cloud_len((max_x - min_x) * 0.5)
		var half_d := _cloud_len((max_z - min_z) * 0.5)
		var center := _cloud_local(Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5))
		# 碰撞
		var shape := BoxShape3D.new()
		shape.size = Vector3(half_w * 2.0, 0.6, half_d * 2.0)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = center + Vector3(0, -0.3, 0)
		body.add_child(collider)
		# 外观
		_box(holder, Vector3(half_w * 2.0, 0.6, half_d * 2.0), center + Vector3(0, -0.3, 0), stone)

	# 圆场与岛：[圆心 x, 圆心 z, 半径]
	var discs := [
		[10.50, -17.50, 4.00],  # 东平台
		[0.00, -26.40, 6.45],   # 中央圆场
		[-15.00, -29.00, 5.00], # 西岛
		[14.00, -29.00, 5.30],  # 东岛
		[0.00, -46.00, 6.35],   # 尽头圆场
	]
	for d in discs:
		var cx := float(d[0])
		var cz := float(d[1])
		var radius := _cloud_len(float(d[2]))
		var center2 := _cloud_local(Vector3(cx, 0.0, cz))
		var disc_shape := CylinderShape3D.new()
		disc_shape.radius = radius
		disc_shape.height = 0.6
		var disc_collider := CollisionShape3D.new()
		disc_collider.shape = disc_shape
		disc_collider.position = center2 + Vector3(0, -0.3, 0)
		body.add_child(disc_collider)
		_cyl(holder, radius, radius, 0.6, center2 + Vector3(0, -0.3, 0), stone, 32)

	# 栈桥两侧的石栏
	var rail_z := [-4.6, -8.0, -11.4, -14.8, -18.2, -21.6]
	for z in rail_z:
		for side in [-1.0, 1.0]:
			var at := _cloud_local(Vector3(float(side) * 3.05, 0.0, float(z)))
			_cyl(holder, 0.14, 0.18, 1.0, at + Vector3(0, 0.5, 0), pale, 8)
	# 中央圆场外圈的一圈栏
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var at2 := _cloud_local(Vector3(cos(angle) * 6.7, 0.0, -26.4 + sin(angle) * 6.7))
		_cyl(holder, 0.14, 0.18, 1.0, at2 + Vector3(0, 0.5, 0), pale, 8)
	return body


## 云海的云舟与三盏云灯浮标
func _build_boat(holder: Node3D) -> void:
	var wood := _mat(Color("6b5138"))
	var pale := _mat(Color("cdbfa4"))
	var brass := _mat(Color("b8913f"))

	# --- 木栈桥（系舟点，接在石台边上）---
	var dock := Node3D.new()
	dock.name = "BoatDock"
	dock.position = Vector3(BOAT_DOCK.x, 0.0, BOAT_DOCK.y)
	holder.add_child(dock)
	for i in range(4):
		_box(dock, Vector3(1.6, 0.08, 0.28), Vector3(0, 0.1 - float(i) * 0.02, float(i) * 0.34), pale)
	for sx in [-0.75, 0.75]:
		_cyl(dock, 0.06, 0.07, 1.0, Vector3(float(sx), -0.4, 0.5), wood, 6)

	# --- 云舟本体 ---
	boat_node = Node3D.new()
	boat_node.name = "CloudBoat"
	boat_node.position = Vector3(boat_pos.x, 0.0, boat_pos.y)
	boat_node.rotation.y = boat_heading
	holder.add_child(boat_node)
	# 船底（压扁的椭球）+ 船舷
	_sphere(boat_node, 0.5, Vector3(0, 0.06, 0), wood).scale = Vector3(0.78, 0.22, 1.5)
	for side in [-1.0, 1.0]:
		_box(boat_node, Vector3(0.08, 0.16, 1.5), Vector3(float(side) * 0.36, 0.16, 0), pale)
	_box(boat_node, Vector3(0.8, 0.16, 0.09), Vector3(0, 0.16, 0.75), pale)
	_box(boat_node, Vector3(0.8, 0.16, 0.09), Vector3(0, 0.16, -0.75), pale)
	# 坐板 + 桅杆 + 船头灯
	_box(boat_node, Vector3(0.66, 0.06, 0.24), Vector3(0, 0.24, 0.1), wood)
	_cyl(boat_node, 0.035, 0.04, 1.3, Vector3(0, 0.9, -0.42), wood, 6)
	_sphere(boat_node, 0.1, Vector3(0, 1.55, -0.42), _mat(Color("ffe2ac"), 1.6))

	# --- 三盏云灯浮标：在水面上各占一处 ---
	var buoy_spots := [Vector2(-3.15, -5.89), Vector2(3.78, -10.94), Vector2(-1.89, -13.78)]
	buoy_nodes.clear()
	for i in range(3):
		var spot: Vector2 = buoy_spots[i]
		var buoy := Node3D.new()
		buoy.name = "Buoy_%d" % i
		buoy.position = Vector3(spot.x, 0.0, spot.y)
		holder.add_child(buoy)
		# 浮圈 + 灯柱 + 玻璃罩（底下垫一圈深色水影，落在石台上更清楚）
		var shadow_mat := _mat(Color("2f3b44"))
		shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow_mat.albedo_color = Color(0.18, 0.24, 0.30, 0.35)
		shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cyl(buoy, 0.78, 0.78, 0.02, Vector3(0, 0.015, 0), shadow_mat, 20)
		_cyl(buoy, 0.46, 0.52, 0.16, Vector3(0, 0.06, 0), brass, 14)
		_cyl(buoy, 0.055, 0.075, 1.0, Vector3(0, 0.6, 0), brass, 8)
		var lamp := _sphere(buoy, 0.16, Vector3(0, 1.20, 0), _mat(Color("ffdca8"), 0.0))
		buoy_nodes.append({"node": buoy, "lamp": lamp, "index": i})
	# 云舟载入点（让玩家知道能上船）
	_anchor(boat_node, "BoatAnchor", Vector3(0, 0.3, 0))


## 云舟每帧推进（由 main 调用）
## row: -1 后退 / 0 不划 / +1 前进；turn: -1 左 / +1 右；delta: 帧时长
func update_boat(row: float, turn: float, delta: float) -> void:
	if not boat_active or boat_node == null:
		return
	if row != 0.0:
		boat_speed += BOAT_ACCEL * row * delta
	boat_speed = clampf(boat_speed, -BOAT_MAX_SPEED * 0.45, BOAT_MAX_SPEED)
	# 阻力
	boat_speed = move_toward(boat_speed, 0.0, BOAT_DRAG * delta)
	boat_heading += turn * BOAT_TURN * delta
	# 只有划得动才真正移动（划桨的水感）
	var forward := Vector2(sin(boat_heading), cos(boat_heading))
	boat_pos += forward * boat_speed * delta
	# 别划出石台范围
	var limit := 22.0
	boat_pos.x = clampf(boat_pos.x, -limit, limit)
	boat_pos.y = clampf(boat_pos.y, -limit, limit)
	boat_node.position = Vector3(boat_pos.x, 0.0, boat_pos.y)
	boat_node.rotation.y = boat_heading
	# 轻微起伏
	boat_node.position.y = sin(Time.get_ticks_msec() * 0.0016) * 0.05


## 上船
func board_boat(player_pos: Vector3) -> Dictionary:
	if boat_active:
		return {"ok": false, "message": "你已经在云舟上了"}
	if boat_distance_from(player_pos) > 3.7:
		return {"ok": false, "message": "再靠近云舟一些"}
	boat_active = true
	boat_speed = 0.0
	return {"ok": true, "message": "W/S 划桨，A/D 转向；靠近云灯后按 E 点亮"}


## 下船：只有划回栈桥附近才能系舟
func leave_boat() -> Dictionary:
	if not boat_active:
		return {"ok": false, "message": ""}
	if boat_pos.distance_to(BOAT_DOCK) > DOCK_REACH:
		return {"ok": false, "message": "把云舟划回木栈桥附近，才能系舟上岸"}
	boat_active = false
	boat_speed = 0.0
	return {"ok": true, "exit": Vector3(BOAT_DOCK.x, 0.0, BOAT_DOCK.y + 1.2),
		"message": "云舟系回木栈桥，脚下的木板重新有了回声"}


## 在船上时离哪盏云灯最近（-1 表示没有）
func near_buoy() -> int:
	if not boat_active:
		return -1
	for i in range(3):
		var spot := _buoy_position(i)
		if boat_pos.distance_to(spot) < BUOY_REACH:
			return i
	return -1


func _buoy_position(index: int) -> Vector2:
	var spots := [Vector2(-3.15, -5.89), Vector2(3.78, -10.94), Vector2(-1.89, -13.78)]
	if index < 0 or index >= spots.size():
		return Vector2.ZERO
	return spots[index]


## 点亮一盏云灯
func light_buoy(index: int) -> Dictionary:
	if index < 0 or index >= buoy_lit.size():
		return {"ok": false}
	if bool(buoy_lit[index]):
		return {"ok": false, "message": "这盏云灯已经亮着了"}
	buoy_lit[index] = true
	var lit_count := 0
	for flag in buoy_lit:
		if bool(flag):
			lit_count += 1
	# 灯亮起来
	if index < buoy_nodes.size():
		var entry: Dictionary = buoy_nodes[index]
		var lamp := entry["lamp"] as MeshInstance3D
		if lamp != null and lamp.material_override is StandardMaterial3D:
			var mat := lamp.material_override as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = Color("ffdca8")
			mat.emission_energy_multiplier = 2.2
	if lit_count >= 3:
		return {"ok": true, "lit": lit_count, "solved": true,
			"message": "三盏云灯连成航路，船头的灯也亮成了金色"}
	return {"ok": true, "lit": lit_count, "solved": false,
		"message": "点亮一盏云灯（%d/3）" % lit_count}


## 玩家上船时的船头朝向（供相机）
func boat_basis() -> Vector3:
	return Vector3(sin(boat_heading), 0.0, cos(boat_heading))


func _build_wind_chime(holder: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "WindChimeReef"
	root.position = Vector3(-9.6, 0.0, -6.4)
	holder.add_child(root)
	var stone := _mat(Color("8d949c"))
	var brass := _mat(Color("b8913f"))
	_box(root, Vector3(4.6, 0.5, 3.2), Vector3(0, 0.25, 0), stone)
	for side in [-1.0, 1.0]:
		_cyl(root, 0.14, 0.18, 3.0, Vector3(side * 1.9, 1.5, 0), stone, 8)
	_box(root, Vector3(4.0, 0.16, 0.16), Vector3(0, 3.0, 0), brass)
	for i in range(4):
		var x := -1.35 + float(i) * 0.9
		_cyl(root, 0.02, 0.02, 0.7, Vector3(x, 2.65, 0), brass, 5)
		var chime := _cyl(root, 0.13, 0.09, 0.62, Vector3(x, 1.98, 0), brass, 8)
		chime.name = "Chime_%d" % i
	var anchor := _anchor(root, "MiniAnchor_cloud", Vector3(0, 1.0, 1.9))
	return anchor


## 萤火树根：三条拱起的树根通向一盏提灯。
func _build_root_path(holder: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "RootPath"
	root.position = Vector3(9.8, 0.0, -5.2)
	holder.add_child(root)
	var bark := _mat(Color("3f3024"))
	var lamp_mat := _mat(Color("d8f07a"), 1.8)
	for i in range(3):
		var z := -1.2 + float(i) * 1.2
		var seg := _cyl(root, 0.34, 0.42, 4.2, Vector3(0, 0.42, z), bark, 8)
		seg.rotation.x = PI * 0.5
	for i in range(2):
		_cyl(root, 0.16, 0.2, 1.5, Vector3(-0.9 + float(i) * 1.8, 0.75, 2.1), bark, 7)
	_sphere(root, 0.22, Vector3(0, 1.15, 2.1), lamp_mat)
	_light(root, Vector3(0, 1.2, 2.1), Color("d8f07a"), 1.4, 9.0)
	var anchor := _anchor(root, "MiniAnchor_firefly", Vector3(0, 1.0, 2.6))
	return anchor


## 雨巷檐下水槽：一侧墙下的石槽与檐口。
func _build_rain_gutter(holder: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "RainGutter"
	# 贴着巷子一侧的墙根摆放，檐口顺着巷道方向，不横穿巷子
	root.position = Vector3(2.75, 0.0, 5.4)
	holder.add_child(root)
	var stone := _mat(Color("6b747a"))
	var brass := _mat(Color("b8913f"))
	_box(root, Vector3(1.0, 0.42, 3.4), Vector3(0, 0.21, 0), stone)
	for i in range(4):
		var z := -1.2 + float(i) * 0.8
		_cyl(root, 0.24, 0.24, 0.22, Vector3(0, 0.42, z), brass, 10)
	# 檐口：顺着墙、沿巷道方向的一根细横杆
	_box(root, Vector3(0.18, 0.16, 3.6), Vector3(0.35, 2.45, 0), brass)
	for i in range(3):
		_cyl(root, 0.06, 0.06, 0.5, Vector3(0.3, 2.2, -1.4 + float(i) * 1.4), brass, 6).rotation.z = 0.5
	var anchor := _anchor(root, "MiniAnchor_alley", Vector3(-0.6, 1.0, 0.0))
	return anchor


func minigame_anchor(key: String):
	return minigame_anchors.get(key, null)




## 听雨院：三盏听雨灯（墙上灯托）+ 巷尾檐下的长凳。
func _build_rain_court(holder: Node3D) -> void:
	var iron := _mat(Color("2c3036"))
	var wood := _mat(Color("4a3627"))
	var roof := _mat(Color("3a4048"))
	var spots := [Vector3(-3.05, 2.4, -2.0), Vector3(3.05, 2.4, -6.0), Vector3(-3.05, 2.4, -9.4)]
	for i in range(spots.size()):
		var at: Vector3 = spots[i]
		var root := Node3D.new()
		root.name = "CourtLamp_%d" % i
		root.position = at
		holder.add_child(root)
		# 灯托与灯罩
		_cyl(root, 0.05, 0.05, 0.5, Vector3(0, 0, 0), iron, 6).rotation.z = PI * 0.5
		_box(root, Vector3(0.34, 0.36, 0.34), Vector3(0, -0.30, 0), iron)
		var lamp_mat := _mat(Color("a8c8d8"), 0.06)
		var lamp := _sphere(root, 0.14, Vector3(0, -0.30, 0), lamp_mat)
		var anchor := _anchor(root, "CourtAnchor_%d" % i, Vector3(0, -0.1, 0.85))
		court_lamps.append({"node": root, "anchor": anchor, "lamp": lamp, "material": lamp_mat})
	# 巷尾檐下的长凳与雨棚
	var bench_root := Node3D.new()
	bench_root.name = "CourtBench"
	bench_root.position = Vector3(0.0, 0.0, -9.6)
	holder.add_child(bench_root)
	_box(bench_root, Vector3(0.6, 0.12, 3.4), Vector3(0, 3.0, 0), roof)
	for z in [-1.5, 1.5]:
		_cyl(bench_root, 0.08, 0.10, 3.0, Vector3(0, 1.5, z), iron, 6)
	_box(bench_root, Vector3(0.9, 0.1, 1.9), Vector3(0, 0.46, 0), wood)
	_box(bench_root, Vector3(0.12, 0.44, 1.9), Vector3(-0.4, 0.7, 0), wood)
	for side in [-1.0, 1.0]:
		_box(bench_root, Vector3(0.9, 0.46, 0.1), Vector3(0, 0.23, side * 0.85), iron)
	court_bench = _anchor(bench_root, "CourtAnchor_Bench", Vector3(0, 1.0, 0.0))


func court_lamp_anchor(index: int):
	if index < 0 or index >= court_lamps.size():
		return null
	return court_lamps[index]["anchor"]


func court_lamp_lit(index: int) -> bool:
	if index < 0 or index >= court_lamp_values.size():
		return false
	return bool(court_lamp_values[index])


func court_lit_count() -> int:
	var total := 0
	for value in court_lamp_values:
		if bool(value):
			total += 1
	return total


## 点亮一盏听雨灯，返回已点亮数。
func light_court_lamp(index: int) -> int:
	if index < 0 or index >= court_lamps.size() or bool(court_lamp_values[index]):
		return court_lit_count()
	court_lamp_values[index] = true
	var material: StandardMaterial3D = court_lamps[index]["material"]
	material.emission_enabled = true
	material.emission = Color("a8d8e8")
	material.emission_energy_multiplier = 2.0
	var lamp: MeshInstance3D = court_lamps[index]["lamp"]
	_light(lamp.get_parent() as Node3D, lamp.position + Vector3(0, -0.1, 0.3), Color("a8d8e8"), 1.5, 10.0)
	return court_lit_count()


func court_all_lit() -> bool:
	return court_lit_count() >= 3


func court_bench_anchor():
	return court_bench


func rest_in_court() -> bool:
	if court_rested or not court_all_lit():
		return false
	court_rested = true
	return true


# --- 镜牢回廊：六间房沿 -Z 排成一条走廊 ----------------------------------------

func _build_dungeon(holder: Node3D) -> Dictionary:
	var floor_mat := _mat(Color("2b313a"), 0.14)
	var wall_mat := _mat(Color("3f4753"), 0.18)
	var trim := _mat(Color("8894a2"))
	var glow := _mat(Color("cfe0e6"), 1.4)
	_build_ground_and_bounds(holder, floor_mat)

	var room_anchors: Array = []
	var total: int = DUNGEON_ROOM_KINDS.size()
	var leg := DUNGEON_ROOM_LENGTH
	var half_x := DUNGEON_ROOM_HALF_X
	for i in range(total):
		# 每间房的地板与两侧墙；房间沿 -Z 依次排开
		var center_z: float = -float(i) * leg
		_box(holder, Vector3(half_x * 2.0, 0.2, leg), Vector3(0, 0.1, center_z), floor_mat)
		for side in [-1.0, 1.0]:
			_box(holder, Vector3(0.3, 3.4, leg), Vector3(side * half_x, 1.7, center_z), wall_mat)
			# 墙上的灯带
			_box(holder, Vector3(0.06, 0.08, leg * 0.6), Vector3(side * (half_x - 0.2), 2.4, center_z), glow)
		# 房间之间的隔墙，中间留门洞
		if i < total - 1:
			var divider_z: float = center_z - leg * 0.5
			for side in [-1.0, 1.0]:
				var piece_w: float = half_x - 1.0
				_box(holder, Vector3(piece_w, 3.4, 0.28),
					Vector3(side * (1.0 + piece_w * 0.5), 1.7, divider_z), wall_mat)
			_box(holder, Vector3(2.0, 0.7, 0.28), Vector3(0, 3.05, divider_z), wall_mat)
			# 门框发光边
			for side in [-1.0, 1.0]:
				_box(holder, Vector3(0.08, 2.7, 0.34), Vector3(side * 1.0, 1.35, divider_z), glow)
			# 门禁：战斗室还有镜影时挡住门洞，清空后由战斗控制器打开
			var blocker_body := StaticBody3D.new()
			blocker_body.name = "DungeonDoor_%d" % i
			blocker_body.collision_layer = 1
			blocker_body.collision_mask = 0
			var blocker_shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2.0, 3.4, 0.3)
			blocker_shape.shape = box
			blocker_shape.position = Vector3(0, 1.7, divider_z)
			blocker_body.add_child(blocker_shape)
			holder.add_child(blocker_body)
			_dungeon_door_blockers.append(blocker_shape)
		# 房间中央的镜塔（不同房型不同配色）与地面嵌线
		var kind: String = DUNGEON_ROOM_KINDS[i]
		var accent: Color = {
			"combat": Color("9fb0c0"),
			"boon": Color("d8e0a0"),
			"boss": Color("c8a0d8"),
		}.get(kind, Color("9fb0c0"))
		var pillar_mat := _mat(accent, 0.4 if kind != "boss" else 0.9)
		# 镜塔：用 Lux3D 六边形镜面塔当外观，内部保留一根细发光柱 ——
		# 不同房型配色不同（combat 银 / boon 黄绿 / boss 紫），模型本身不带这层色，
		# 所以发光柱必须留着，否则「房型区分」就丢了。
		var tower_prop := _prop("mirror-tower", 2.6)
		if tower_prop != null:
			tower_prop.position = Vector3(0, 0, center_z)
			holder.add_child(tower_prop)
			_cyl(holder, 0.18, 0.24, 2.4, Vector3(0, 1.2, center_z), pillar_mat, 8)
		else:
			_cyl(holder, 0.5, 0.7, 2.6, Vector3(0, 1.3, center_z), pillar_mat, 8)
		_cyl(holder, 0.9, 0.9, 0.06, Vector3(0, 0.22, center_z), trim, 20)
		room_anchors.append(_anchor(holder, "DungeonRoomAnchor_%d" % i, Vector3(0, 1.0, center_z + leg * 0.1)))
		if kind == "boon":
			_dungeon_boon_stands[i] = _build_boon_stand(holder, center_z, i)

	# 归途门：入口处（玩家出生点旁）
	var return_anchor := _build_return_portal(holder, "dungeon", Color("cfe0e6"), Vector3(0, 0, leg * 0.42))
	# 镜心内厅的终点：最后一间房尽头的门
	var finish_root := Node3D.new()
	finish_root.name = "DungeonFinish"
	finish_root.position = Vector3(0, 0, -float(total - 1) * leg - leg * 0.45)
	holder.add_child(finish_root)
	var finish_mat := _mat(Color("c8a0d8"), 1.6)
	_box(finish_root, Vector3(3.2, 3.6, 0.25), Vector3(0, 1.8, 0), finish_mat)
	var finish_anchor := _anchor(finish_root, "DungeonFinishAnchor", Vector3(0, 1.0, 1.2))
	return {"spawn": Vector3(0, 1.05, leg * 0.30), "return": return_anchor,
		"room_anchors": room_anchors, "finish_anchor": finish_anchor,
		"room_count": total, "title": "镜牢回廊"}


## 第 i 道隔墙的门禁碰撞形状（位于房间 i 与 i+1 之间）
func dungeon_door_blocker(index: int):
	if index < 0 or index >= _dungeon_door_blockers.size():
		return null
	return _dungeon_door_blockers[index]


## 静镜室的镜印台：三枚悬浮的镜印碎片，挑一枚带走。
func _build_boon_stand(holder: Node3D, center_z: float, room: int) -> Array:
	var stand := Node3D.new()
	stand.name = "BoonStand_%d" % room
	stand.position = Vector3(0, 0, center_z - 3.4)
	holder.add_child(stand)
	var stone := _mat(Color("5a6472"), 0.2)
	var brass := _mat(Color("b8913f"), 0.25)
	_cyl(stand, 1.0, 1.2, 0.6, Vector3(0, 0.3, 0), stone, 14)
	_cyl(stand, 1.15, 1.15, 0.08, Vector3(0, 0.64, 0), brass, 16)
	var entries: Array = []
	for i in range(3):
		var angle := TAU * float(i) / 3.0 + 0.4
		var pos := Vector3(cos(angle) * 0.62, 1.05, sin(angle) * 0.62)
		var shard_mat := _mat(Color("d8e0a0"), 1.6)
		var shard := _cyl(stand, 0.0, 0.17, 0.42, pos, shard_mat, 6)
		shard.name = "BoonShard_%d_%d" % [room, i]
		# 碎片上再叠一小片，做出棱镜感
		var cap := _cyl(stand, 0.17, 0.0, 0.2, pos + Vector3(0, 0.3, 0), shard_mat, 6)
		cap.name = "BoonCap_%d_%d" % [room, i]
		var anchor := _anchor(stand, "BoonAnchor_%d_%d" % [room, i], pos + Vector3(0, -0.35, 0.0))
		entries.append({"shard": shard, "cap": cap, "anchor": anchor, "taken": false})
	# 台座中央的灯
	_light(stand, Vector3(0, 1.2, 0), Color("d8e0a0"), 1.6, 9.0)
	return entries


## 静镜室里第 index 枚镜印的锚点
func dungeon_boon_anchor(room: int, index: int):
	if not _dungeon_boon_stands.has(room):
		return null
	var entries: Array = _dungeon_boon_stands[room]
	if index < 0 or index >= entries.size():
		return null
	if bool(entries[index]["taken"]):
		return null
	return entries[index]["anchor"]


func dungeon_boon_count(room: int) -> int:
	if not _dungeon_boon_stands.has(room):
		return 0
	return (_dungeon_boon_stands[room] as Array).size()


## 取走一枚镜印：该房间剩下的碎片一并收起（每个静镜室只带走一枚）
func dungeon_take_boon(room: int, index: int) -> bool:
	if not _dungeon_boon_stands.has(room):
		return false
	var entries: Array = _dungeon_boon_stands[room]
	if index < 0 or index >= entries.size() or bool(entries[index]["taken"]):
		return false
	for entry in entries:
		entry["taken"] = true
		(entry["shard"] as MeshInstance3D).visible = false
		(entry["cap"] as MeshInstance3D).visible = false
	return true


func dungeon_boon_room_taken(room: int) -> bool:
	if not _dungeon_boon_stands.has(room):
		return true
	for entry in _dungeon_boon_stands[room]:
		if not bool(entry["taken"]):
			return false
	return true


func dungeon_room_count() -> int:
	if not worlds.has("dungeon"):
		return 0
	return int(worlds["dungeon"]["room_count"])


func dungeon_room_kind(index: int) -> String:
	if index < 0 or index >= DUNGEON_ROOM_KINDS.size():
		return ""
	return DUNGEON_ROOM_KINDS[index]


func dungeon_room_anchor(index: int):
	if not worlds.has("dungeon"):
		return null
	var list: Array = worlds["dungeon"]["room_anchors"]
	if index < 0 or index >= list.size():
		return null
	return list[index]


func dungeon_finish_anchor():
	if not worlds.has("dungeon"):
		return null
	return worlds["dungeon"]["finish_anchor"]


## 镜界里的镜牢门锚点
func dungeon_gate_anchor():
	if not worlds.has("mirror"):
		return null
	return worlds["mirror"].get("gate_anchor", null)


## 根据玩家所在的 z 判断在第几间房（0 起）；超出走廊返回最后一间。
func dungeon_room_at(world_position: Vector3) -> int:
	if not worlds.has("dungeon"):
		return 0
	var holder: Node3D = worlds["dungeon"]["node"]
	var local_z: float = holder.to_local(world_position).z
	var index := int(floor((-local_z + DUNGEON_ROOM_LENGTH * 0.5) / DUNGEON_ROOM_LENGTH))
	return clampi(index, 0, DUNGEON_ROOM_KINDS.size() - 1)


func world_node(key: String) -> Node3D:
	if not worlds.has(key):
		return null
	return worlds[key]["node"]


## 内容层坐标 -> 世界坐标。
## 世界内容挂在 content（带缩放与平移）下，而玩家挂在不缩放的 holder 上，
## 所以任何「用内容层坐标去摆玩家」的地方都要过这里。
func world_point(key: String, content_local: Vector3) -> Vector3:
	var holder := world_node(key)
	if holder == null:
		return content_local
	var content := worlds[key].get("content") as Node3D
	if content == null:
		return holder.to_global(content_local)
	return holder.to_global(content.transform * content_local)


## 世界坐标 -> 内容层坐标（world_point 的反向）
func content_point(key: String, world_pos: Vector3) -> Vector3:
	var holder := world_node(key)
	if holder == null:
		return world_pos
	var content := worlds[key].get("content") as Node3D
	if content == null:
		return holder.to_local(world_pos)
	return content.transform.affine_inverse() * holder.to_local(world_pos)


## 玩家（世界坐标）离云舟有多远（云舟坐标在内容层）
func boat_distance_from(world_pos: Vector3) -> float:
	var local := content_point("cloud", world_pos)
	return Vector2(local.x, local.z).distance_to(boat_pos)


func spawn_position(key: String) -> Vector3:
	if not worlds.has(key):
		return global_position
	return (worlds[key]["node"] as Node3D).to_global(worlds[key]["spawn"])


func return_anchor(key: String):
	if not worlds.has(key):
		return null
	return worlds[key]["return"]


func heart_anchor(key: String):
	if not worlds.has(key):
		return null
	return worlds[key].get("heart_anchor", null)


func heart_node(key: String):
	if not worlds.has(key):
		return null
	return worlds[key].get("heart", null)
