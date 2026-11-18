extends Node3D

## 地面线：阁楼。
##
## 设计取自同伴版本《借一扇晴天》的阁楼：一间斜顶阁楼、一张茶几（旅行小册 / 茶壶 / 两只杯子 /
## 茶叶罐）、一面旅行架（四格放纪念 + 棱镜之心）、四扇通往远方的门（雪夜 / 云海 / 萤火 / 雨巷）、
## 一面自愿走进的镜界回廊，以及一扇能看见天的窗。
## 比例与按键一律按本项目的尺度与操作约定重做，不照搬网页版。

const Placement := preload("res://scripts/prop_placement.gd")
const Precision = preload("res://scripts/procedural_dressing.gd")
const PrecisionGeometry = preload("res://scripts/procedural_geometry.gd")

const ROOM_HALF_X := 3.4
const ROOM_HALF_Z := 2.9
const WALL_HEIGHT := 2.5
const RIDGE_HEIGHT := 3.6
const DOOR_WIDTH := 1.05
const DOOR_HEIGHT := 2.05
const GROUND_Y := 0.0
const SWALLOW_SILL_OFFSET := Vector3(0.36, -0.26, 0.23)

var doors: Array = []          # 四扇远方门：{node, key, title, color}
var prism_heart: MeshInstance3D # 旅行架第三层的棱镜之心（从镜界带回后才出现）
## 黄铜天气旋钮：按「云海 → 萤火森林 → 雨巷 → 雪夜」轮换窗外天气
const WEATHER_ORDER := ["cloud", "firefly", "alley", "snow"]
const WEATHER_TITLES := {"cloud": "云海", "firefly": "萤火森林", "alley": "雨巷", "snow": "雪夜"}
var dial_index := 0
var dial_pointer: MeshInstance3D
var weather_roots: Dictionary = {}
## 四个小世界的纪念：world_key -> 旅行架上的 MeshInstance3D
var keepsake_nodes: Dictionary = {}
## 茶席三步：0 未开始，1 水开，2 投茶，3 出汤
var tea_step := 0
var kettle_glow: MeshInstance3D
var tea_cups: Array = []
var tea_steam: MeshInstance3D
var anchors: Dictionary = {}   # 交互锚点：锚点名 -> Node3D
## 窗台燕子（雨停后才出现）
var swallow_node: Node3D
## 燕子的飞行进度：0 = 在窗台，1 = 落到壁炉边
var swallow_flight := -1.0
var chest_open := false
var chest_closed_visual: Node3D
var chest_open_visual: Node3D
var chest_lid_pivot: Node3D
var chest_lid_tween: Tween
var root: Node3D
var body: StaticBody3D

var _wood: StandardMaterial3D
var _wood_dark: StandardMaterial3D
var _plaster: StandardMaterial3D
var _paper: StandardMaterial3D
var _brass: StandardMaterial3D
var _glass: StandardMaterial3D
var _cloth: StandardMaterial3D
var _glow: StandardMaterial3D
var _mirror: StandardMaterial3D


func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _cloud_sky_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = 24187
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.45
	var width := 384
	var height := 256
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var sky_top := Color("4c94c4")
	var sky_horizon := Color("a6cee4")
	for y in range(height):
		var v := float(y) / float(height - 1)
		for x in range(width):
			var u := float(x) / float(width - 1)
			var edge := 0.43 + noise.get_noise_2d(u * 7.2, 7.2) * 0.15 \
				+ noise.get_noise_2d(u * 15.0, 12.6) * 0.045
			var billow := noise.get_noise_2d(u * 5.0 + 4.0, v * 4.0) * 0.13 \
				+ noise.get_noise_2d(u * 13.0, v * 10.0) * 0.045
			var cloud_depth := v - edge + billow
			var coverage := clampf((cloud_depth + 0.03) / 0.07, 0.0, 1.0)
			coverage = coverage * coverage * (3.0 - 2.0 * coverage)
			var sky := sky_top.lerp(sky_horizon, v)
			var depth := clampf((cloud_depth + 0.04) / 0.32, 0.0, 1.0)
			var cloud := Color("fbfdff").lerp(Color("d3e2eb"), depth * 0.32)
			var light_noise := noise.get_noise_2d(u * 8.0 + 13.0, v * 7.0)
			cloud = cloud.lightened(maxf(0.0, light_noise) * 0.08)
			image.set_pixel(x, y, sky.lerp(cloud, coverage))
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return material


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	parent.add_child(node)
	return node


func _cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3,
		material: Material, segments := 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	parent.add_child(node)
	return node


func _box_collider(size: Vector3, pos: Vector3, rot_y := 0.0) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation.y = rot_y
	body.add_child(shape)


func _anchor(anchor_name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = anchor_name
	node.position = pos
	root.add_child(node)
	anchors[anchor_name] = node
	return node


# --- Lux3D 生成道具的加载（2026-11-12 接入）--------------------------------------
#
# 阁楼里的家具原本全是程序化几何（BoxMesh / CylinderMesh 拼的）。
# 现在改用 Aholo Lux3D 文生 3D 的写实模型，观感提升明显。
#
# ⚠ 设计原则：**必须能回退**。
#   · 模型文件在 assets/models/props/attic/<name>/model*.glb
#   · 该目录已在 .gitignore 中（用户要求省仓库流量），所以**别人 clone 下来不会有这些模型**
#   · 因此每个 _build_* 都要先试 prop()，拿不到就照旧用程序化几何
#   · 这样无论有没有模型，阁楼都不会空、也不会崩
const PROP_DIR := "res://assets/models/props/attic/"
var _prop_placer := Placement.new()


func prop(name: String, target_height: float) -> Node3D:
	var model := _prop_placer.instantiate(name, target_height, [PROP_DIR])
	if model != null and name in ["rug", "travel-notebook"]:
		Placement.lay_flat(model)
	return model


## Use the visual envelope and its complete parent transform for furniture collision.
func _collide_prop(model: Node3D) -> void:
	var box := Placement.bounds(model)
	var xf := Transform3D.IDENTITY
	var walker: Node = model
	while walker != root:
		if walker is Node3D:
			xf = walker.transform * xf
		walker = walker.get_parent()
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collision := CollisionShape3D.new()
	collision.name = String(model.name) + "Collision"
	collision.shape = shape
	collision.transform = xf * Transform3D(Basis.IDENTITY, box.get_center())
	body.add_child(collision)



func up_direction() -> Vector3:
	# 阁楼是固定房间，重力方向就是房间自身的上方向。
	return global_transform.basis.y.normalized()


func is_interior_position(world_position: Vector3) -> bool:
	var local := to_local(world_position)
	return absf(local.x) < ROOM_HALF_X + 0.6 and absf(local.z) < ROOM_HALF_Z + 0.6 \
		and local.y > -1.0 and local.y < RIDGE_HEIGHT + 0.6


func build() -> void:
	root = Node3D.new()
	root.name = "AtticBody"
	add_child(root)

	body = StaticBody3D.new()
	body.name = "AtticCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)

	_wood = _material(Color("7a5a3c"))
	_wood_dark = _material(Color("4a3627"))
	_plaster = _material(Color("d8cdb6"))
	_paper = _material(Color("e6dcc4"))
	_brass = _material(Color("b8913f"))
	_glass = _material(Color("9fb8c4"), 0.12)
	_cloth = _material(Color("8d5b4c"))
	_glow = _material(Color("ffca7a"), 1.35)
	_mirror = _material(Color("cfe0e6"), 0.35)
	PrecisionGeometry.surface(_cloth, "cloth")
	PrecisionGeometry.surface(_paper, "paper")
	PrecisionGeometry.surface(_plaster, "plaster")
	_brass.metallic = 0.68
	_brass.roughness = 0.36
	PrecisionGeometry.surface(_brass, "metal")

	_build_shell()
	_build_window()
	_build_window_scenes()
	_build_dial()
	_build_doors()
	_build_mirror_corridor()
	_build_tea_table()
	_build_shelf()
	_build_furniture()
	_build_lighting()
	Precision.attic(root)


# --- 壳体：地板、四壁、斜顶与椽条 -------------------------------------------------
func _build_shell() -> void:
	# Adjacent boards overlap by 2 mm; the backing closes every visual seam.
	var pitch := ROOM_HALF_Z * 2.0 / 14.0
	var backing := _box(root, Vector3(ROOM_HALF_X * 2.0, 0.08, ROOM_HALF_Z * 2.0),
		Vector3(0, -0.08, 0), _wood_dark)
	backing.name = "FloorUnderlay"
	for i in range(14):
		var board := _box(root, Vector3(ROOM_HALF_X * 2.0, 0.08, pitch + 0.002),
			Vector3(0, -0.04, -ROOM_HALF_Z + (float(i) + 0.5) * pitch),
			_wood if i % 2 == 0 else _wood_dark)
		board.name = "Floorboard_%02d" % i
	_box_collider(Vector3(ROOM_HALF_X * 2.0, 0.2, ROOM_HALF_Z * 2.0), Vector3(0, -0.1, 0))
	var solid_walls := [
		[Vector3(0, WALL_HEIGHT * 0.5, -ROOM_HALF_Z), Vector3(ROOM_HALF_X * 2.0 + 0.16, WALL_HEIGHT, 0.16)],
		[Vector3(-ROOM_HALF_X, WALL_HEIGHT * 0.5, 0), Vector3(0.16, WALL_HEIGHT, ROOM_HALF_Z * 2.0 + 0.16)],
		[Vector3(ROOM_HALF_X, WALL_HEIGHT * 0.5, 0), Vector3(0.16, WALL_HEIGHT, ROOM_HALF_Z * 2.0 + 0.16)],
	]
	for wall in solid_walls:
		_box(root, wall[1], wall[0], _plaster)
		_box_collider(wall[1], wall[0])
	var window_half := 0.85
	var window_low := 1.19
	var window_high := 2.31
	var side_width := ROOM_HALF_X - window_half
	for side in [-1.0, 1.0]:
		_box(root, Vector3(side_width, WALL_HEIGHT, 0.16),
			Vector3(side * (window_half + side_width * 0.5), WALL_HEIGHT * 0.5, ROOM_HALF_Z), _plaster)
	_box(root, Vector3(window_half * 2.0, window_low, 0.16), Vector3(0, window_low * 0.5, ROOM_HALF_Z), _plaster)
	_box(root, Vector3(window_half * 2.0, WALL_HEIGHT - window_high, 0.16),
		Vector3(0, (WALL_HEIGHT + window_high) * 0.5, ROOM_HALF_Z), _plaster)
	_box_collider(Vector3(ROOM_HALF_X * 2.0, WALL_HEIGHT, 0.16), Vector3(0, WALL_HEIGHT * 0.5, ROOM_HALF_Z))
	var slope_length := Vector2(ROOM_HALF_X, RIDGE_HEIGHT - WALL_HEIGHT).length() + 0.16
	var slope_angle := atan2(RIDGE_HEIGHT - WALL_HEIGHT, ROOM_HALF_X)
	for side in [-1.0, 1.0]:
		var roof := _box(root, Vector3(slope_length, 0.14, ROOM_HALF_Z * 2.0 + 0.22),
			Vector3(side * ROOM_HALF_X * 0.5, (WALL_HEIGHT + RIDGE_HEIGHT) * 0.5, 0), _wood)
		roof.name = "Roof_Left" if side < 0 else "Roof_Right"
		roof.rotation.z = -side * slope_angle
		_box_collider(roof.mesh.size, roof.position)
		body.get_child(-1).rotation.z = roof.rotation.z
		for i in range(7):
			var z := -ROOM_HALF_Z + 0.15 + float(i) * (ROOM_HALF_Z * 2.0 - 0.3) / 6.0
			var rafter := _box(root, Vector3(slope_length, 0.11, 0.11),
				roof.position + Vector3(0, -0.10, z), _wood_dark)
			rafter.rotation.z = roof.rotation.z
	_box(root, Vector3(0.20, 0.20, ROOM_HALF_Z * 2.0 + 0.1),
		Vector3(0, RIDGE_HEIGHT - 0.08, 0), _wood_dark)
	# Solid gables overlap the roof slopes and end-wall edges.
	for side in [-1.0, 1.0]:
		var gable := CSGPolygon3D.new()
		gable.name = "Gable_Front" if side > 0 else "Gable_Back"
		gable.mode = CSGPolygon3D.MODE_DEPTH
		gable.polygon = PackedVector2Array([
			Vector2(-ROOM_HALF_X - 0.12, WALL_HEIGHT - 0.04),
			Vector2(0, RIDGE_HEIGHT + 0.12),
			Vector2(ROOM_HALF_X + 0.12, WALL_HEIGHT - 0.04),
		])
		gable.depth = 0.24
		gable.position.z = side * ROOM_HALF_Z
		gable.material = _plaster
		gable.use_collision = true
		gable.collision_layer = 1
		gable.collision_mask = 0
		root.add_child(gable)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(ROOM_HALF_X * 2.0, 0.16, 0.08),
			Vector3(0, 0.08, side * (ROOM_HALF_Z - 0.09)), _wood)
		_box(root, Vector3(0.08, 0.16, ROOM_HALF_Z * 2.0),
			Vector3(side * (ROOM_HALF_X - 0.09), 0.08, 0), _wood)


# --- 窗：一把能看见天的窗，窗台可坐 ------------------------------------------------
func _build_window() -> void:
	var wall_z: float = ROOM_HALF_Z - 0.09
	var center_y := 1.75
	# 窗洞框。
	_box(root, Vector3(1.9, 0.12, 0.22), Vector3(0, center_y + 0.62, wall_z), _wood)
	_box(root, Vector3(1.9, 0.12, 0.22), Vector3(0, center_y - 0.62, wall_z), _wood)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.12, 1.36, 0.22), Vector3(side * 0.9, center_y, wall_z), _wood)
	# 窗玻璃：半透明，透过去能看到窗外那套天候小景（原来的「天色发光板」已移除，
	# 否则会挡住窗外的景）。
	var pane_material := StandardMaterial3D.new()
	pane_material.albedo_color = Color(0.86, 0.93, 0.97, 0.16)
	pane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pane_material.roughness = 0.1
	pane_material.metallic = 0.2
	_box(root, Vector3(1.7, 1.12, 0.03), Vector3(0, center_y, wall_z - 0.02), pane_material)
	# 十字窗棂与窗台。
	_box(root, Vector3(0.06, 1.12, 0.1), Vector3(0, center_y, wall_z - 0.04), _wood)
	_box(root, Vector3(1.7, 0.06, 0.1), Vector3(0, center_y, wall_z - 0.04), _wood)
	_box(root, Vector3(2.1, 0.12, 0.42), Vector3(0, center_y - 0.72, wall_z - 0.12), _wood)
	_box_collider(Vector3(2.1, 0.12, 0.42), Vector3(0, center_y - 0.72, wall_z - 0.12))
	# 窗台的燕子窝与一只小陶罐。
	_cyl(root, 0.16, 0.2, 0.16, Vector3(-0.62, center_y - 0.58, wall_z - 0.12), _cloth, 10)
	_cyl(root, 0.09, 0.12, 0.22, Vector3(0.68, center_y - 0.55, wall_z - 0.12), _brass, 8)
	var sill := _anchor("AtticAnchor_Window", Vector3(0, center_y - 0.4, wall_z - 0.35))
	# 雨停后落到这里的燕子（默认藏着）
	_build_swallow(sill, SWALLOW_SILL_OFFSET)
	# 壁炉边：燕子飞过去落脚的地方



## 窗台上的燕子：小身体 + 两只翅膀 + 剪刀尾，默认隐藏。
func _build_swallow(parent: Node3D, at: Vector3) -> Node3D:
	var swallow := Node3D.new()
	swallow.name = "Swallow"
	swallow.position = at
	swallow.visible = false
	parent.add_child(swallow)
	# 优先用 Lux3D 模型。⚠ 燕子会从窗台飞到壁炉（swallow_flight 驱动），
	#   所以这里只放「本体」，飞行位移仍由父节点 swallow 的 position 控制，
	#   模型本身的 local position 保持 0，不影响原有飞行动画。
	var swallow_prop := prop("swallow", 0.16)
	if swallow_prop != null:
		swallow.add_child(swallow_prop)
		swallow_node = swallow
		return swallow
	var body_mat := _material(Color("2c3a48"), 0.0)
	var belly_mat := _material(Color("e8e2d4"), 0.0)
	# 身体（略扁的椭球）
	var body := _sphere(swallow, 0.075, Vector3.ZERO, body_mat)
	body.scale = Vector3(1.0, 0.85, 1.5)
	# 白色的腹部
	var belly := _sphere(swallow, 0.055, Vector3(0, -0.028, 0.01), belly_mat)
	belly.scale = Vector3(0.9, 0.6, 1.25)
	# 头 + 喙
	_sphere(swallow, 0.05, Vector3(0, 0.035, -0.1), body_mat)
	_box(swallow, Vector3(0.028, 0.02, 0.05), Vector3(0, 0.03, -0.15), _material(Color("c8913f"), 0.0))
	# 两只翅膀
	for side in [-1.0, 1.0]:
		var wing := _box(swallow, Vector3(0.13, 0.012, 0.19),
			Vector3(float(side) * 0.07, 0.02, 0.0), body_mat)
		wing.name = "Wing_%s" % ("L" if side < 0 else "R")
		wing.rotation.z = float(side) * 0.22
	# 剪刀尾
	_box(swallow, Vector3(0.028, 0.01, 0.11), Vector3(-0.028, 0.0, 0.12), body_mat).rotation.y = 0.34
	_box(swallow, Vector3(0.028, 0.01, 0.11), Vector3(0.028, 0.0, 0.12), body_mat).rotation.y = -0.34
	swallow_node = swallow
	return swallow


## 雨巷完成后让燕子出现在窗台（照原作：雨停后窗台会多一只避雨的燕子）
func show_swallow() -> bool:
	if swallow_node == null or swallow_node.visible:
		return false
	swallow_node.visible = true
	# -1 = 停在窗台（还没起飞）
	swallow_flight = -1.0
	return true


## 燕子是否已经在窗台上
func swallow_on_sill() -> bool:
	return swallow_node != null and swallow_node.visible and swallow_flight < 0.5 \
		and swallow_flight >= -1.0


## 燕子是否已经落在壁炉边
func swallow_perched() -> bool:
	return swallow_node != null and swallow_node.visible and swallow_flight >= 0.999


## 招呼窗台的燕子：让它飞过炉火、落到壁炉边
func greet_swallow() -> Dictionary:
	if swallow_node == null or not swallow_node.visible:
		return {"ok": false, "message": ""}
	if swallow_flight >= 0.999:
		return {"ok": true, "message": "燕子歪了歪头，尾羽轻轻扫过壁炉的暖光"}
	if swallow_flight >= 0.0:
		return {"ok": false, "message": "燕子正在飞"}
	# 停在窗台：起飞
	swallow_flight = 0.0
	return {"ok": true, "message": "燕子从窗台起飞，掠过炉火，落在壁炉边", "started": true}


## 燕子飞行插值（由 main 每帧调用）
func update_swallow(delta: float) -> void:
	if swallow_node == null or swallow_flight < 0.0:
		return  # 还停在窗台，没起飞
	if swallow_flight >= 0.999:
		# 已落到壁炉边
		return
	swallow_flight = minf(1.0, swallow_flight + delta * 0.42)
	var sill := anchors.get("AtticAnchor_Window") as Node3D
	var perch := anchors.get("AtticAnchor_HearthPerch") as Node3D
	if sill == null or perch == null:
		swallow_flight = 1.0
		return
	var from_pos: Vector3 = sill.position + SWALLOW_SILL_OFFSET
	var to_pos: Vector3 = perch.position
	# 弧线：中间抬高一些，模拟掠过炉火
	var t := swallow_flight
	var lift := sin(t * PI) * 0.9
	swallow_node.position = sill.to_local(root.to_global(from_pos.lerp(to_pos, t) + Vector3(0, lift, 0)))
	# 翅膀扇动
	var flap := sin(t * 34.0) * 0.42
	for child in swallow_node.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh := child as MeshInstance3D
		if String(mesh.name) == "Wing_L":
			mesh.rotation.z = 0.22 + flap
		elif String(mesh.name) == "Wing_R":
			mesh.rotation.z = -0.22 - flap
	# 面朝飞行方向
	var dir := (to_pos - from_pos)
	if dir.length() > 0.001:
		swallow_node.rotation.y = atan2(-dir.x, -dir.z)
	if t >= 0.999:
		swallow_node.position = sill.to_local(root.to_global(to_pos))
		swallow_node.rotation.y = PI
		for child in swallow_node.get_children():
			if child is MeshInstance3D:
				var mesh2 := child as MeshInstance3D
				if String(mesh2.name) == "Wing_L":
					mesh2.rotation.z = 0.08
				elif String(mesh2.name) == "Wing_R":
					mesh2.rotation.z = -0.08


# --- 四扇门：雪夜 / 云海 / 萤火 / 雨巷 --------------------------------------------
func _build_doors() -> void:
	var wall_z: float = -ROOM_HALF_Z + 0.1
	var specs := [
		{"key": "snow", "title": "雪夜", "color": Color("cfe4f2"), "x": -2.1},
		{"key": "cloud", "title": "云海", "color": Color("bcd2e8"), "x": -0.7},
		{"key": "firefly", "title": "萤火", "color": Color("cfe08a"), "x": 0.7},
		{"key": "alley", "title": "雨巷", "color": Color("a8b0b8"), "x": 2.1},
	]
	for spec in specs:
		var x: float = spec["x"]
		var door_root := Node3D.new()
		door_root.name = "Door_%s" % String(spec["key"]).capitalize()
		door_root.position = Vector3(x, 0, wall_z)
		root.add_child(door_root)
		# 门框。优先 Lux3D 模型；碰撞与门牌另算，不依赖视觉。
		var frame_prop := prop("door-frame", DOOR_HEIGHT + 0.15)
		if frame_prop != null:
			frame_prop.position = Vector3(0, 0, 0.02)
			Placement.fit(frame_prop, Vector3(DOOR_WIDTH + 0.24, DOOR_HEIGHT + 0.15, 0.16))
			door_root.add_child(frame_prop)
		else:
			_box(door_root, Vector3(DOOR_WIDTH + 0.24, 0.12, 0.16), Vector3(0, DOOR_HEIGHT + 0.06, 0.02), _wood_dark)
			for side in [-1.0, 1.0]:
				_box(door_root, Vector3(0.12, DOOR_HEIGHT, 0.16),
					Vector3(side * (DOOR_WIDTH + 0.06) * 0.5, DOOR_HEIGHT * 0.5, 0.02), _wood_dark)
		# 门扇：木框 + 一块透出"那边天气"的嵌板。
		# ⚠ 嵌板 pane 是**交互提示**（不同世界不同颜色），必须保留 —— 
		#   但换模型后门板本身有细节了，嵌板要**缩小成一块小窗**，
		#   否则整扇门变成一块发光白板（实测踩过：白板盖住门板，门等于白做）。
		var leaf_prop := prop("wooden-door", DOOR_HEIGHT)
		if leaf_prop != null:
			leaf_prop.position = Vector3(0, 0, 0)
			Placement.fit(leaf_prop, Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.12))
			door_root.add_child(leaf_prop)
		else:
			_box(door_root, Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.07), Vector3(0, DOOR_HEIGHT * 0.5, 0), _wood)
		var pane_w: float = DOOR_WIDTH * (0.24 if leaf_prop != null else 1.0) - (0.34 if leaf_prop == null else 0.0)
		var pane_h: float = DOOR_HEIGHT * (0.12 if leaf_prop != null else 1.0) - (0.62 if leaf_prop == null else 0.0)
		var pane_y: float = DOOR_HEIGHT * (0.70 if leaf_prop != null else 0.52)
		var pane := _box(door_root, Vector3(pane_w, pane_h, 0.03),
			Vector3(0, pane_y, 0.071 if leaf_prop != null else 0.05), _glow)
		pane.material_override = _material(spec["color"], 0.18)
		# 门牌：一块小铜牌。
		var plate := _box(door_root, Vector3(0.34, 0.16, 0.02), Vector3(0, DOOR_HEIGHT - 0.28, 0.072), _brass)
		plate.set_meta("label", spec["title"])
		var title := Label3D.new()
		title.text = spec["title"]
		title.font_size = 32
		title.pixel_size = 0.002
		title.position = plate.position + Vector3(0, 0, 0.012)
		title.modulate = Color("382719")
		title.outline_size = 0
		door_root.add_child(title)
		# 门把手。
		_box(door_root, Vector3(0.05, 0.05, 0.14), Vector3(DOOR_WIDTH * 0.34, DOOR_HEIGHT * 0.46, 0.08), _brass)
		_box_collider(Vector3(DOOR_WIDTH + 0.24, DOOR_HEIGHT, 0.16), Vector3(x, DOOR_HEIGHT * 0.5, wall_z), 0.0)
		var anchor := _anchor("AtticAnchor_Door_%s" % String(spec["key"]).capitalize(),
			Vector3(x, DOOR_HEIGHT * 0.5, wall_z + 0.6))
		doors.append({"node": door_root, "key": spec["key"], "title": spec["title"],
			"color": spec["color"], "anchor": anchor})


# --- 镜界回廊：一面自愿走进的镜 ------------------------------------------------
func _build_mirror_corridor() -> void:
	var wall_x: float = -ROOM_HALF_X + 0.1
	var frame_root := Node3D.new()
	frame_root.name = "MirrorCorridor"
	frame_root.position = Vector3(wall_x + 0.08, 0, 0.9)
	frame_root.rotation.y = PI * 0.5
	root.add_child(frame_root)
	var height := 2.25
	var width := 1.12
	# 镜框用 Lux3D 模型；**镜面本体保留程序化** —— 它要透出冷光当"入口"，
	# 模型是空框，塞进去反而挡住。
	var frame_prop := prop("mirror-frame", height)
	if frame_prop != null:
		frame_prop.position = Vector3(0, 0, 0)
		Placement.fit(frame_prop, Vector3(width + 0.08, height, 0.2))
		frame_root.add_child(frame_prop)
	else:
		for side in [-1.0, 1.0]:
			_box(frame_root, Vector3(0.14, height, 0.14), Vector3(side * width * 0.5, height * 0.5, 0), _wood_dark)
		_box(frame_root, Vector3(width + 0.14, 0.14, 0.14), Vector3(0, height, 0), _wood_dark)
		_box(frame_root, Vector3(width + 0.14, 0.1, 0.14), Vector3(0, 0.05, 0), _wood_dark)
	# 镜面本体：微亮、带一点冷光，走进去是回廊。
	var surface := _box(frame_root, Vector3(width - 0.24, height - 0.40, 0.04), Vector3(0, height * 0.5, 0.02), _mirror)
	surface.material_override = _material(Color("d7e6ea"), 0.22)
	_box(frame_root, Vector3(width - 0.16, height - 0.36, 0.02), Vector3(0, height * 0.5, 0.06), _mirror)
	# 两侧的棱镜小灯。
	for side in [-1.0, 1.0]:
		var lamp := _cyl(frame_root, 0.07, 0.1, 0.34, Vector3(side * (width * 0.5 + 0.22), 1.5, 0.08), _brass, 8)
		lamp.set_meta("kind", "prism_lamp")
	_anchor("AtticAnchor_Mirror", Vector3(wall_x + 0.75, height * 0.5, 0.9))


# --- 茶几：旅行小册 / 茶壶 / 两只杯子 / 茶叶罐 ------------------------------------
func _build_tea_table() -> void:
	var table := Node3D.new()
	table.name = "TeaTable"
	table.position = Vector3(1.05, 0, 1.25)
	root.add_child(table)
	var table_prop := prop("tea-table", 0.70)
	if table_prop != null:
		Placement.fit(table_prop, Vector3(1.35, 0.70, 1.35))
		table.add_child(table_prop)
		_collide_prop(table_prop)
	else:
		_box(table, Vector3(1.35, 0.07, 1.35), Vector3(0, 0.665, 0), _wood)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_box(table, Vector3(0.09, 0.63, 0.09), Vector3(sx * 0.48, 0.315, sz * 0.48), _wood_dark)
		_box_collider(Vector3(1.35, 0.70, 1.35), table.position + Vector3(0, 0.35, 0))
	var surface_y := 0.70
	if table_prop != null:
		surface_y = Placement.support_y(table_prop, Vector2.ZERO, 0.8)
	var book_pos := Vector3(-0.25, surface_y, 0.10)
	var book := prop("travel-notebook", 0.05)
	if book != null:
		Placement.fit(book, Vector3(0.42, 0.025, 0.28))
		book.position = book_pos
		table.add_child(book)
	else:
		_box(table, Vector3(0.42, 0.025, 0.28), book_pos + Vector3(0, 0.0125, 0), _paper)
	var pot_pos := Vector3(0.30, surface_y, -0.20)
	kettle_glow = _cyl(table, 0.11, 0.11, 0.006, pot_pos, _material(Color("ffb066")), 16)
	var pot := prop("teapot", 0.20)
	if pot != null:
		pot.position = pot_pos
		table.add_child(pot)
	else:
		_cyl(table, 0.10, 0.12, 0.20, pot_pos + Vector3(0, 0.1, 0), _brass, 12)
	for cup_x in [0.16, 0.43]:
		var saucer := prop("tea-saucer", 0.015)
		var cup_y := surface_y
		if saucer != null:
			Placement.fit(saucer, Vector3(0.15, 0.015, 0.15))
			saucer.position = Vector3(cup_x, surface_y, 0.24)
			table.add_child(saucer)
			cup_y += Placement.support_y(saucer, Vector2.ZERO, 0.03)
		var cup := prop("teacup", 0.075)
		if cup != null:
			cup.position = Vector3(cup_x, cup_y, 0.24)
			table.add_child(cup)
		else:
			_cyl(table, 0.05, 0.04, 0.075, Vector3(cup_x, cup_y + 0.0375, 0.24), _paper, 12)
		# The tea state owns a real liquid mesh, including when the cup is imported.
		var liquid := _cyl(table, 0.036, 0.036, 0.004,
			Vector3(cup_x, cup_y + 0.055, 0.24), _material(Color("b98a4e"), 0.5), 16)
		liquid.name = "TeaLiquid"
		liquid.visible = false
		tea_cups.append(liquid)
	var canister := prop("tea-canister", 0.15)
	if canister != null:
		canister.position = Vector3(-0.12, surface_y, -0.32)
		table.add_child(canister)
	else:
		_cyl(table, 0.07, 0.07, 0.15, Vector3(-0.12, surface_y + 0.075, -0.32), _cloth, 12)
	tea_steam = _cyl(table, 0.035, 0.015, 0.18, pot_pos + Vector3(0, 0.3, 0),
		_material(Color("e8f0f2")), 8)
	tea_steam.visible = false
	_anchor("AtticAnchor_Booklet", table.position + book_pos + Vector3(0, 0.1, 0))
	_anchor("AtticAnchor_Kettle", table.position + pot_pos + Vector3(0, 0.2, 0))
	_anchor("AtticAnchor_Tea", table.position + Vector3(0.28, surface_y + 0.1, 0.24))
	for stool_x in [0.35, 1.8]:
		var stool := prop("wooden-stool", 0.48)
		if stool != null:
			stool.position = Vector3(stool_x, 0, 2.15)
			stool.set_meta("kind", "stool")
			root.add_child(stool)
			_collide_prop(stool)
		else:
			_cyl(root, 0.19, 0.19, 0.48, Vector3(stool_x, 0.24, 2.15), _wood, 12)


# --- 旅行架：四格纪念 + 棱镜之心 ------------------------------------------------
func _build_shelf() -> void:
	var shelf := Node3D.new()
	shelf.name = "TravelShelf"
	shelf.position = Vector3(ROOM_HALF_X - 0.08 - 0.18, 0, -0.9)
	shelf.rotation.y = -PI * 0.5
	root.add_child(shelf)
	var model := prop("bookshelf", 1.65)
	if model != null:
		Placement.fit(model, Vector3(1.5, 1.65, 0.36))
		shelf.add_child(model)
		_collide_prop(model)
	else:
		for side in [-1.0, 1.0]:
			_box(shelf, Vector3(0.06, 1.65, 0.36), Vector3(side * 0.72, 0.825, 0), _wood_dark)
		_box(shelf, Vector3(1.5, 1.65, 0.04), Vector3(0, 0.825, -0.16), _wood_dark)
		for level in [0.07, 0.57, 1.08, 1.62]:
			_box(shelf, Vector3(1.5, 0.06, 0.36), Vector3(0, level, 0), _wood)
		_box_collider(Vector3(0.36, 1.65, 1.5), shelf.position + Vector3(0, 0.825, 0))
	var keys := ["snow", "cloud", "firefly", "alley"]
	for i in range(4):
		var x := -0.525 + float(i) * 0.35
		var top_y := 1.11
		if model != null:
			top_y = Placement.support_y(model, Vector2(x, 0.015), 1.35)
		var stand := _cyl(shelf, 0.11, 0.11, 0.012, Vector3(x, top_y + 0.006, 0.015), _brass, 16)
		stand.name = "KeepsakeStand_" + keys[i]
		var token := _build_keepsake(shelf, keys[i], Vector3(x, top_y + 0.012, 0.015))
		var box := Placement.bounds(token)
		var k := minf(1.0, minf(0.28 / maxf(box.size.x, 0.001), 0.28 / maxf(box.size.z, 0.001)))
		token.scale *= k
		token.visible = false
		keepsake_nodes[keys[i]] = token
	prism_heart = _cylinder_mesh(shelf, 0.09, 0.11, 0.2, Vector3(0, 1.75, 0), 6)
	prism_heart.material_override = _material(Color("cfe0e6"), 0.9)
	prism_heart.visible = false
	_anchor("AtticAnchor_Shelf", shelf.position + Vector3(-0.60, 1.0, 0))


func _sphere(parent: Node3D, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node


func _cylinder_mesh(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3,
		segments: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	parent.add_child(node)
	return node


# --- 陈设：地毯、箱子、挂画、提灯、唱片机 -----------------------------------------
func _build_furniture() -> void:
	var rug := prop("rug", 0.06)
	if rug != null:
		Placement.fit(rug, Vector3(2.6, 0.012, 1.9))
		rug.position = Vector3(0.6, 0.001, 0.95)
		root.add_child(rug)
	else:
		_box(root, Vector3(2.6, 0.012, 1.9), Vector3(0.6, 0.007, 0.95), _cloth)
	var chest_position := Vector3(-2.2, 0, 1.95)
	var chest_model := prop("wooden-chest", 0.62)
	chest_closed_visual = Node3D.new()
	chest_closed_visual.name = "ChestClosedVisual"
	chest_closed_visual.position = chest_position
	root.add_child(chest_closed_visual)
	if chest_model != null:
		chest_closed_visual.add_child(chest_model)
		_collide_prop(chest_model)
	else:
		_box(chest_closed_visual, Vector3(0.9, 0.62, 0.55), Vector3(0, 0.31, 0), _wood)
		_box_collider(Vector3(0.9, 0.62, 0.55), chest_position + Vector3(0, 0.31, 0))
	_build_open_chest(chest_position)
	_anchor("AtticAnchor_Chest", chest_position + Vector3(0, 0.38, 0.33))
	var cabinet := prop("side-cabinet", 0.52)
	var cabinet_z := ROOM_HALF_Z - 0.08 - 0.20
	if cabinet != null:
		Placement.fit(cabinet, Vector3(0.8, 0.52, 0.4))
		cabinet.position = Vector3(0, 0, cabinet_z)
		root.add_child(cabinet)
		_collide_prop(cabinet)
	else:
		_box(root, Vector3(0.8, 0.52, 0.4), Vector3(0, 0.26, cabinet_z), _wood)
		_box_collider(Vector3(0.8, 0.52, 0.4), Vector3(0, 0.26, cabinet_z))
	var lantern := prop("lantern", 0.34)
	if lantern != null:
		lantern.position = Vector3(0, 0.52, cabinet_z)
		root.add_child(lantern)
	else:
		_cyl(root, 0.09, 0.12, 0.24, Vector3(0, 0.64, cabinet_z), _brass, 12)
	_cyl(root, 0.025, 0.035, 0.07, Vector3(0, 0.65, cabinet_z), _glow, 12)
	_anchor("AtticAnchor_Lantern", Vector3(0, 0.9, cabinet_z - 0.35))
	# Paintings belong on a free wall, not over the fourth door.
	var painting := prop("painting", 0.54)
	if painting != null:
		painting.position = Vector3(ROOM_HALF_X - 0.08 - 0.017, 1.55, 1.1)
		painting.rotation.y = -PI * 0.5
		painting.set_meta("kind", "painting_frame")
		root.add_child(painting)
	else:
		_box(root, Vector3(0.04, 0.54, 0.72), Vector3(3.3, 1.82, 1.1), _wood_dark)
	# A second cabinet supports the record player, beside the mirror approach.
	var record_at := Vector3(-ROOM_HALF_X + 0.08 + 0.23, 0, -1.35)
	var record_cabinet := prop("side-cabinet", 0.66)
	if record_cabinet != null:
		Placement.fit(record_cabinet, Vector3(0.85, 0.66, 0.46))
		record_cabinet.name = "RecordCabinet"
		record_cabinet.position = record_at
		record_cabinet.rotation.y = PI * 0.5
		root.add_child(record_cabinet)
		_collide_prop(record_cabinet)
	else:
		_box(root, Vector3(0.46, 0.66, 0.85), record_at + Vector3(0, 0.33, 0), _wood_dark)
		_box_collider(Vector3(0.46, 0.66, 0.85), record_at + Vector3(0, 0.33, 0))
	var gram := prop("gramophone", 0.40)
	if gram != null:
		gram.position = record_at + Vector3(0, 0.66, -0.15)
		gram.rotation.y = PI * 0.5
		root.add_child(gram)
	else:
		_box(root, Vector3(0.28, 0.14, 0.32), record_at + Vector3(0, 0.73, -0.15), _wood_dark)
	_anchor("AtticAnchor_Record", record_at + Vector3(0.45, 0.85, 0))
	var record_label := Label3D.new()
	record_label.name = "RouteRecordLabel"
	record_label.text = "返回空间站\nE 互动"
	record_label.font = load("res://assets/ui_font.ttf")
	record_label.font_size = 36
	record_label.pixel_size = 0.003
	record_label.position = record_at + Vector3(0.28, 1.35, 0)
	record_label.rotation.y = PI * 0.5
	root.add_child(record_label)
	_anchor("AtticAnchor_HearthPerch", record_at + Vector3(0, 0.66, 0.25))


func _build_open_chest(chest_position: Vector3) -> void:
	chest_open_visual = Node3D.new()
	chest_open_visual.name = "ChestOpenVisual"
	chest_open_visual.position = chest_position
	chest_open_visual.visible = false
	root.add_child(chest_open_visual)

	var wood := _material(Color("61452f"))
	PrecisionGeometry.surface(wood, "wood")
	var plank := _material(Color("745439"))
	PrecisionGeometry.surface(plank, "wood")
	var cavity := _material(Color("21170f"))
	_box(chest_open_visual, Vector3(0.82, 0.46, 0.54), Vector3(0, 0.23, 0), wood)
	_box(chest_open_visual, Vector3(0.72, 0.02, 0.40), Vector3(0, 0.47, 0), cavity)
	_box(chest_open_visual, Vector3(0.82, 0.16, 0.04), Vector3(0, 0.54, 0.25), wood)
	_box(chest_open_visual, Vector3(0.82, 0.16, 0.04), Vector3(0, 0.54, -0.25), wood)
	for side in [-1.0, 1.0]:
		_box(chest_open_visual, Vector3(0.04, 0.16, 0.50), Vector3(side * 0.39, 0.54, 0), wood)
	for row in range(3):
		var y := 0.08 + float(row) * 0.15
		var board_material: Material = wood if row % 2 == 0 else plank
		_box(chest_open_visual, Vector3(0.74, 0.14, 0.018), Vector3(0, y, 0.28), board_material)
		_box(chest_open_visual, Vector3(0.74, 0.14, 0.018), Vector3(0, y, -0.28), board_material)
		for side in [-1.0, 1.0]:
			_box(chest_open_visual, Vector3(0.018, 0.14, 0.46), Vector3(side * 0.42, y, 0), board_material)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			_box(chest_open_visual, Vector3(0.035, 0.46, 0.022),
				Vector3(side * 0.36, 0.23, end * 0.29), _brass)

	chest_lid_pivot = Node3D.new()
	chest_lid_pivot.name = "ChestLidPivot"
	chest_lid_pivot.position = Vector3(0, 0.62, -0.25)
	chest_open_visual.add_child(chest_lid_pivot)
	_box(chest_lid_pivot, Vector3(0.86, 0.08, 0.56), Vector3(0, 0, 0.28), wood)
	for index in range(3):
		var z := 0.09 + float(index) * 0.185
		var lid_material: Material = plank if index == 1 else wood
		_box(chest_lid_pivot, Vector3(0.84, 0.012, 0.17), Vector3(0, 0.047, z), lid_material)
	for side in [-1.0, 1.0]:
		_box(chest_lid_pivot, Vector3(0.035, 0.014, 0.52), Vector3(side * 0.29, 0.05, 0.28), _brass)
	_box(chest_lid_pivot, Vector3(0.13, 0.08, 0.03), Vector3(0, -0.01, 0.55), _brass)


func toggle_chest() -> bool:
	chest_open = not chest_open
	if chest_lid_tween != null:
		chest_lid_tween.kill()
	if chest_open:
		chest_closed_visual.visible = false
		chest_open_visual.visible = true
		chest_lid_pivot.rotation.x = 0.0
		chest_lid_tween = create_tween()
		chest_lid_tween.tween_property(chest_lid_pivot, "rotation:x", -1.35, 0.32) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		chest_open_visual.visible = false
		chest_closed_visual.visible = true
		chest_lid_pivot.rotation.x = 0.0
	return chest_open


# --- 灯光：一盏吊灯、窗光、提灯与棱镜小灯 -----------------------------------------
func _build_lighting() -> void:
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.2, RIDGE_HEIGHT - 0.55, 0.5)
	lamp.light_color = Color("ffca7a")
	lamp.omni_range = 7.5
	lamp.light_energy = 1.5
	root.add_child(lamp)
	# 朝上的补光：把斜顶提亮，避免抬头一片黑。
	var bounce := OmniLight3D.new()
	bounce.position = Vector3(0.2, WALL_HEIGHT + 0.5, 0.5)
	bounce.light_color = Color("ffdcae")
	bounce.omni_range = 6.5
	bounce.light_energy = 0.9
	root.add_child(bounce)
	# 吊灯的灯罩。
	_cyl(root, 0.22, 0.34, 0.26, Vector3(0.2, RIDGE_HEIGHT - 0.42, 0.5), _brass, 12)
	_cyl(root, 0.02, 0.02, 0.5, Vector3(0.2, RIDGE_HEIGHT - 0.18, 0.5), _wood_dark, 6)

	var window_light := OmniLight3D.new()
	window_light.position = Vector3(0, 1.9, ROOM_HALF_Z - 0.5)
	window_light.light_color = Color("ffe9b8")
	window_light.omni_range = 5.0
	window_light.light_energy = 1.2
	root.add_child(window_light)

	var lantern_light := OmniLight3D.new()
	lantern_light.position = Vector3(0.0, 0.85, ROOM_HALF_Z - 0.55)
	lantern_light.light_color = Color("ffbe72")
	lantern_light.omni_range = 2.6
	lantern_light.light_energy = 0.9
	root.add_child(lantern_light)

	var mirror_light := OmniLight3D.new()
	mirror_light.position = Vector3(-ROOM_HALF_X + 0.75, 1.6, 0.9)
	mirror_light.light_color = Color("d7e6ea")
	mirror_light.omni_range = 3.2
	mirror_light.light_energy = 0.8
	root.add_child(mirror_light)


## 某个世界的纪念带回来之后，让它出现在旅行架上。
# --- 四件纪念的独立造型（放在托座上，约 0.2 米高） --------------------------------

## 冰镜极光：一面小冰镜 + 镜后一道极光带。
func _keepsake_snow(parent: Node3D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Keepsake_Snow"
	root.position = at
	parent.add_child(root)
	var ice := _material(Color("cfe4f2"), 0.35)
	var frame := _material(Color("7d8f9e"))
	var aurora := _material(Color("9fe8c8"), 1.6)
	# 底座与镜框
	_cyl(root, 0.06, 0.07, 0.02, Vector3(0, 0.01, 0), frame, 10)
	_box(root, Vector3(0.02, 0.13, 0.02), Vector3(-0.05, 0.075, 0), frame)
	_box(root, Vector3(0.02, 0.13, 0.02), Vector3(0.05, 0.075, 0), frame)
	_box(root, Vector3(0.12, 0.02, 0.02), Vector3(0, 0.15, 0), frame)
	_box(root, Vector3(0.08, 0.11, 0.012), Vector3(0, 0.075, 0), ice)
	# 镜后极光带：两道错开的斜片
	for i in range(2):
		var ribbon := _box(root, Vector3(0.10, 0.012, 0.012), Vector3(0.0, 0.13 + float(i) * 0.05, -0.03 - float(i) * 0.01), aurora)
		ribbon.rotation.z = 0.3 - float(i) * 0.6
	return root


## 云舟船灯：小舟 + 桅杆 + 灯笼 + 云影。
func _keepsake_cloud(parent: Node3D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Keepsake_Cloud"
	root.position = at
	parent.add_child(root)
	var hull := _material(Color("c8a878"))
	var brass := _material(Color("b8913f"))
	var lamp := _material(Color("ffd9a0"), 2.0)
	var cloud := _material(Color("f2e6cc"), 0.3)
	# 云影（船下的云）
	var puff := _sphere(root, 0.045, Vector3(0, 0.02, 0), cloud)
	puff.scale = Vector3(2.4, 0.6, 1.4)
	# 船体：中间宽两头尖
	_box(root, Vector3(0.13, 0.03, 0.05), Vector3(0, 0.045, 0), hull)
	_box(root, Vector3(0.05, 0.03, 0.035), Vector3(0.085, 0.05, 0), hull)
	_box(root, Vector3(0.05, 0.03, 0.035), Vector3(-0.085, 0.05, 0), hull)
	# 桅杆与灯笼
	_cyl(root, 0.006, 0.008, 0.13, Vector3(0, 0.115, 0), brass, 6)
	var lantern := _sphere(root, 0.025, Vector3(0.028, 0.135, 0), lamp)
	lantern.scale = Vector3(1.0, 1.25, 1.0)
	_cyl(root, 0.012, 0.016, 0.02, Vector3(0.028, 0.165, 0), brass, 8)
	return root


## 树屋萤火：小树 + 树上的灯窗 + 三簇萤火。
func _keepsake_firefly(parent: Node3D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Keepsake_Firefly"
	root.position = at
	parent.add_child(root)
	var bark := _material(Color("4a3627"))
	var leaves := _material(Color("2f5546"))
	var window := _material(Color("d8f07a"), 2.2)
	# 树干与树冠
	_cyl(root, 0.014, 0.022, 0.11, Vector3(0, 0.055, 0), bark, 7)
	var crown := _sphere(root, 0.055, Vector3(0, 0.145, 0), leaves)
	crown.scale = Vector3(1.15, 0.95, 1.15)
	# 树上的树屋与灯窗
	_box(root, Vector3(0.06, 0.045, 0.055), Vector3(0, 0.115, 0.01), bark)
	_box(root, Vector3(0.022, 0.02, 0.008), Vector3(0, 0.118, 0.042), window)
	# 三簇萤火绕树
	for i in range(3):
		var angle := TAU * float(i) / 3.0 + 0.5
		_sphere(root, 0.009, Vector3(cos(angle) * 0.062, 0.10 + float(i) * 0.035, sin(angle) * 0.062), window)
	return root


## 雨巷钟铃：檐下小铃 + 铃舌 + 水滴。
func _keepsake_alley(parent: Node3D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Keepsake_Alley"
	root.position = at
	parent.add_child(root)
	var wood := _material(Color("4a3627"))
	var brass := _material(Color("b8913f"), 0.25)
	var drip := _material(Color("a8c8d8"), 1.4)
	# 檐口横木与吊绳
	_box(root, Vector3(0.14, 0.014, 0.02), Vector3(0, 0.175, 0), wood)
	_cyl(root, 0.003, 0.003, 0.035, Vector3(0, 0.152, 0), wood, 5)
	# 钟铃：上窄下宽的锥台 + 铃口
	_cyl(root, 0.028, 0.052, 0.075, Vector3(0, 0.10, 0), brass, 12)
	_cyl(root, 0.055, 0.055, 0.012, Vector3(0, 0.058, 0), brass, 12)
	# 铃舌
	_sphere(root, 0.014, Vector3(0, 0.062, 0), brass)
	# 铃下水滴与积水
	_sphere(root, 0.010, Vector3(0, 0.030, 0), drip)
	_cyl(root, 0.045, 0.05, 0.012, Vector3(0, 0.006, 0), _material(Color("7f98a6"), 0.2), 12)
	return root


## 按世界 key 生成对应纪念模型。
func _build_keepsake(parent: Node3D, key: String, at: Vector3) -> Node3D:
	# 优先用 Lux3D 模型（四件信物各有一个专门生成的微缩件）。
	# ⚠ 信物原本是**微缩场景**（雪景球/云海小船/萤火树屋/雨巷钟铃），
	#   AI 模型是单体对象，观感更「干净」但少了场景感 —— 
	#   所以这里只在有模型时替换；没有就照旧用原来的微缩场景。
	var spec := {
		"snow": ["keepsake-snow", 0.20],
		"cloud": ["keepsake-cloud", 0.18],
		"firefly": ["keepsake-firefly", 0.20],
		"alley": ["keepsake-alley", 0.18],
	}
	if spec.has(key):
		var row: Array = spec[key]
		var model := prop(String(row[0]), float(row[1]))
		if model != null:
			var holder := Node3D.new()
			holder.name = "Keepsake_" + key.capitalize()
			holder.position = at
			holder.add_child(model)
			parent.add_child(holder)
			return holder
	match key:
		"snow":
			return _keepsake_snow(parent, at)
		"cloud":
			return _keepsake_cloud(parent, at)
		"firefly":
			return _keepsake_firefly(parent, at)
		"alley":
			return _keepsake_alley(parent, at)
	return _keepsake_snow(parent, at)


func add_keepsake(key: String) -> void:
	if keepsake_nodes.has(key):
		(keepsake_nodes[key] as Node3D).visible = true


## 茶席：壶的锚点（按 E 一步一步泡茶）。
func tea_anchor() -> Node3D:
	return anchors.get("AtticAnchor_Kettle")


## 推进茶席一步：返回 {step, message, done, changed}
func advance_tea() -> Dictionary:
	var result := {"step": tea_step, "message": "", "done": false, "changed": false}
	if tea_step >= 3:
		result["message"] = "这壶茶已经泡好了"
		result["done"] = true
		return result
	tea_step += 1
	result["step"] = tea_step
	result["changed"] = true
	match tea_step:
		1:
			if kettle_glow != null:
				var material: StandardMaterial3D = kettle_glow.material_override
				material.emission_enabled = true
				material.emission = Color("ffb066")
				material.emission_energy_multiplier = 1.8
			result["message"] = "水开了 · 壶底泛起一圈暖光"
		2:
			if tea_steam != null:
				tea_steam.visible = true
			result["message"] = "茶叶落进壶里 · 屋子里有了味道"
		3:
			for cup in tea_cups:
				(cup as MeshInstance3D).visible = true
			result["message"] = "出汤 · 两只杯子都满了 · 茶席三步完成"
			result["done"] = true
	return result


## 从镜界带回棱镜之心后，让它出现在旅行架上。
func show_prism_heart() -> void:
	if prism_heart != null:
		prism_heart.visible = true


# --- 黄铜天气旋钮与窗外四套天候小景 --------------------------------------------

## 窗外小景：四套，只有当前天气那套可见。窗洞朝 +Z，景挂在 z > ROOM_HALF_Z 之外。
func _build_window_scenes() -> void:
	var center_y := 1.75
	var base_z: float = ROOM_HALF_Z + 0.9
	weather_roots = {}
	for key in WEATHER_ORDER:
		var holder := Node3D.new()
		holder.name = "Weather_%s" % String(key).capitalize()
		holder.position = Vector3(0, center_y, base_z)
		root.add_child(holder)
		var palette: Color = {
			"cloud": Color("f0d9a8"),
			"firefly": Color("a8d878"),
			"alley": Color("8098a8"),
			"snow": Color("e6f2f8"),
		}[key]
		# 背景板：窗外那一片天/远景
		var backdrop_material := _cloud_sky_material() if key == "cloud" else _material(palette, 0.55)
		_box(holder, Vector3(3.4, 2.4, 0.06), Vector3(0, 0, 1.35), backdrop_material)
		match key:
			"snow":
				# 雪夜：白地、两棵松、月亮
				_box(holder, Vector3(3.2, 0.12, 1.6), Vector3(0, -0.72, 0.5), _material(Color("eaf2f6"), 0.25))
				for i in range(2):
					var x := -0.85 + float(i) * 1.7
					_cyl(holder, 0.09, 0.13, 0.9, Vector3(x, -0.24, 0.35), _material(Color("3d4a3c")), 7)
					for layer in range(3):
						_cyl(holder, 0.0, 0.42 - float(layer) * 0.08, 0.5,
							Vector3(x, 0.10 + float(layer) * 0.22, 0.35), _material(Color("2f4a42")), 8)
				_sphere(holder, 0.16, Vector3(-0.95, 0.78, 1.15), _material(Color("f2f8ff"), 1.2))
			"cloud":
				# The procedural sky texture forms one irregular cloud bank behind the window.
				_sphere(holder, 0.2, Vector3(0.95, 0.72, 1.1), _material(Color("ffd9a0"), 1.4))
			"firefly":
				# 萤火森林：暗林 + 几簇萤火
				for i in range(3):
					var x3 := -1.0 + float(i) * 1.0
					_cyl(holder, 0.08, 0.12, 1.1, Vector3(x3, -0.30, 0.45), _material(Color("2f2a22")), 7)
					_cyl(holder, 0.0, 0.5, 0.7, Vector3(x3, 0.35, 0.45), _material(Color("20362c")), 8)
				for i in range(6):
					var fx := -1.2 + float(i) * 0.48
					_sphere(holder, 0.05, Vector3(fx, -0.05 + float(i % 3) * 0.28, 0.75),
						_material(Color("d8f07a"), 2.4))
			"alley":
				# 雨巷：两道墙、一盏灯笼、湿地反光
				for side in [-1.0, 1.0]:
					_box(holder, Vector3(0.5, 1.9, 1.5), Vector3(side * 0.95, -0.1, 0.5), _material(Color("4d5158")))
				_box(holder, Vector3(2.4, 0.1, 1.5), Vector3(0, -0.72, 0.5), _material(Color("5a646c"), 0.2))
				_sphere(holder, 0.13, Vector3(0, 0.45, 0.4), _material(Color("ffb867"), 2.2))
		holder.visible = false
		weather_roots[key] = holder
	set_dial(0)


## 黄铜旋钮：一面圆盘 + 指针 + 四道刻度，装在后墙门上方。
func _build_dial() -> void:
	var wall_z: float = ROOM_HALF_Z - 0.12
	var dial := Node3D.new()
	dial.name = "WeatherDial"
	dial.position = Vector3(1.45, 1.58, wall_z)
	dial.rotation.y = PI
	root.add_child(dial)
	# 盘面用 Lux3D 模型；**指针 dial_pointer 必须保留程序化** ——
	# 切换天气时是旋转它，模型里没有独立指针节点。
	var dial_prop := prop("weather-dial", 0.42)
	if dial_prop != null:
		dial_prop.position = Vector3(0, -0.21, 0.0)
		dial.add_child(dial_prop)
	else:
		_cyl(dial, 0.17, 0.17, 0.06, Vector3(0, 0, 0), _brass, 16).rotation.x = PI * 0.5
		_cyl(dial, 0.12, 0.12, 0.07, Vector3(0, 0, -0.01), _wood_dark, 16).rotation.x = PI * 0.5
		for i in range(4):
			var angle := TAU * float(i) / 4.0
			_box(dial, Vector3(0.03, 0.05, 0.03), Vector3(cos(angle) * 0.20, sin(angle) * 0.20, 0.0), _brass)
	dial_pointer = _box(dial, Vector3(0.03, 0.15, 0.03), Vector3(0, 0.07, 0.04), _brass)
	_anchor("AtticAnchor_Dial", Vector3(1.45, 1.58, wall_z - 0.55))


## 切换窗外天气：index 0..3，对应 WEATHER_ORDER。
func set_dial(index: int) -> void:
	dial_index = int(fposmod(float(index), float(WEATHER_ORDER.size())))
	for i in range(WEATHER_ORDER.size()):
		var key: String = WEATHER_ORDER[i]
		if weather_roots.has(key):
			(weather_roots[key] as Node3D).visible = i == dial_index
	if dial_pointer != null:
		# 指针按档位转：0 = 正上方，顺时针每档 90°
		dial_pointer.rotation.z = -TAU * float(dial_index) / float(WEATHER_ORDER.size())


## 拨一档，返回 {index, key, title}
func cycle_dial() -> Dictionary:
	set_dial(dial_index + 1)
	var key: String = WEATHER_ORDER[dial_index]
	return {"index": dial_index, "key": key, "title": String(WEATHER_TITLES.get(key, key))}


func current_weather() -> String:
	return WEATHER_ORDER[dial_index]


func weather_title() -> String:
	return String(WEATHER_TITLES.get(current_weather(), current_weather()))


func dial_anchor():
	return anchors.get("AtticAnchor_Dial")


func door_by_key(key: String):
	for entry in doors:
		if entry["key"] == key:
			return entry
	return null
