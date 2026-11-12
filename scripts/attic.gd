extends Node3D

## 地面线：阁楼。
##
## 设计取自同伴版本《借一扇晴天》的阁楼：一间斜顶阁楼、一张茶几（旅行小册 / 茶壶 / 两只杯子 /
## 茶叶罐）、一面旅行架（四格放纪念 + 棱镜之心）、四扇通往远方的门（雪夜 / 云海 / 萤火 / 雨巷）、
## 一面自愿走进的镜界回廊，以及一扇能看见天的窗。
## 比例与按键一律按本项目的尺度与操作约定重做，不照搬网页版。

const ROOM_HALF_X := 3.4
const ROOM_HALF_Z := 2.9
const WALL_HEIGHT := 2.5
const RIDGE_HEIGHT := 3.6
const DOOR_WIDTH := 1.05
const DOOR_HEIGHT := 2.05
const GROUND_Y := 0.0

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
## 加载缓存：避免同一次 build 里重复 load 同一个 glb
var _prop_cache: Dictionary = {}


## 取一个 Lux3D 道具实例，失败返回 null（调用方回退到程序化几何）。
##
## 返回的 Node3D 已经：
##   · 按 height_m 缩放到目标高度（模型原始尺寸不可控，用高度归一化最稳）
##   · 底面贴 y=0（放在地板上时直接给 x/z 即可）
##   · 关闭阴影投射以外的特殊设置（道具小，投阴影会脏地板）
func prop(name: String, target_height: float) -> Node3D:
	if _prop_cache.has(name):
		var cached = _prop_cache[name]
		if cached == null:
			return null
		return (cached as Node3D).duplicate() as Node3D
	var dir := PROP_DIR + name + "/"
	var glb_path := ""
	# 库产出的文件名可能是 model_glb.glb，也可能是 model.glb —— 两个都试
	for candidate in ["model.glb", "model_glb.glb"]:
		if ResourceLoader.exists(dir + candidate):
			glb_path = dir + candidate
			break
	if glb_path == "":
		_prop_cache[name] = null
		return null
	var packed := load(glb_path) as PackedScene
	if packed == null:
		_prop_cache[name] = null
		return null
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_prop_cache[name] = null
		return null
	# 量包围盒 → 缩放到目标高度 → 底面贴 0
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
		if mi.material_override == null:
			# 让道具投阴影，但不参与受光遮蔽（小物件）
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if first or aabb.size.y < 0.0001:
		instance.queue_free()
		_prop_cache[name] = null
		return null
	var holder := Node3D.new()
	holder.name = "Prop_" + name
	holder.add_child(instance)
	var scale_k: float = target_height / aabb.size.y
	instance.scale = Vector3.ONE * scale_k
	# 缩放后重新算底部：原始 aabb.position.y * scale_k
	instance.position = Vector3(
		-aabb.get_center().x * scale_k,
		-aabb.position.y * scale_k,
		-aabb.get_center().z * scale_k)
	_prop_cache[name] = holder
	return (holder as Node3D).duplicate() as Node3D


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


# --- 壳体：地板、四壁、斜顶与椽条 -------------------------------------------------
func _build_shell() -> void:
	# 地板：纵向木条拼出纹路。
	for i in range(14):
		var z := -ROOM_HALF_Z + 0.21 + float(i) * (ROOM_HALF_Z * 2.0 - 0.42) / 13.0
		_box(root, Vector3(ROOM_HALF_X * 2.0, 0.08, 0.37), Vector3(0, GROUND_Y - 0.04, z),
			_wood if i % 2 == 0 else _wood_dark)
	_box_collider(Vector3(ROOM_HALF_X * 2.0 + 0.4, 0.2, ROOM_HALF_Z * 2.0 + 0.4), Vector3(0, GROUND_Y - 0.1, 0))

	# 四面墙：抹灰墙面 + 木构梁。
	# 后墙（-Z）、两侧墙：整面。
	var solid_walls := [
		[Vector3(0, WALL_HEIGHT * 0.5, -ROOM_HALF_Z), Vector3(ROOM_HALF_X * 2.0, WALL_HEIGHT, 0.16)],
		[Vector3(-ROOM_HALF_X, WALL_HEIGHT * 0.5, 0), Vector3(0.16, WALL_HEIGHT, ROOM_HALF_Z * 2.0)],
		[Vector3(ROOM_HALF_X, WALL_HEIGHT * 0.5, 0), Vector3(0.16, WALL_HEIGHT, ROOM_HALF_Z * 2.0)],
	]
	for wall in solid_walls:
		_box(root, wall[1], wall[0], _plaster)
		_box_collider(wall[1], wall[0])
	# 前墙（+Z）中间留出窗洞：窗口 x ∈ [-0.85, 0.85]，y ∈ [1.19, 2.31]
	var window_half := 0.85
	var window_low := 1.19
	var window_high := 2.31
	var side_width := ROOM_HALF_X - window_half
	for side in [-1.0, 1.0]:
		var piece_x: float = side * (window_half + side_width * 0.5)
		_box(root, Vector3(side_width, WALL_HEIGHT, 0.16), Vector3(piece_x, WALL_HEIGHT * 0.5, ROOM_HALF_Z), _plaster)
	_box(root, Vector3(window_half * 2.0, window_low, 0.16),
		Vector3(0, window_low * 0.5, ROOM_HALF_Z), _plaster)
	_box(root, Vector3(window_half * 2.0, WALL_HEIGHT - window_high, 0.16),
		Vector3(0, (WALL_HEIGHT + window_high) * 0.5, ROOM_HALF_Z), _plaster)
	# 碰撞仍用整面前墙，窗洞只是视觉开口
	_box_collider(Vector3(ROOM_HALF_X * 2.0, WALL_HEIGHT, 0.16), Vector3(0, WALL_HEIGHT * 0.5, ROOM_HALF_Z))

	# 斜顶：两片斜面在屋脊处相遇。
	# 斜顶额外加长 0.45 米，让两片在屋脊处搭接，否则从室内会漏缝看见外面。
	var slope_length: float = sqrt(pow(ROOM_HALF_X, 2.0) + pow(RIDGE_HEIGHT - WALL_HEIGHT, 2.0)) + 0.45
	var slope_angle: float = atan2(RIDGE_HEIGHT - WALL_HEIGHT, ROOM_HALF_X)
	for side in [-1.0, 1.0]:
		# 顶面用亮一档的木色：斜顶常年背光，深色会读成黑洞。
		var roof := _box(root, Vector3(slope_length, 0.1, ROOM_HALF_Z * 2.0),
			Vector3(side * ROOM_HALF_X * 0.5, (WALL_HEIGHT + RIDGE_HEIGHT) * 0.5 - 0.06, 0), _wood)
		roof.rotation.z = side * slope_angle
	# 椽条与屋脊梁。
	for i in range(7):
		var z := -ROOM_HALF_Z + 0.4 + float(i) * (ROOM_HALF_Z * 2.0 - 0.8) / 6.0
		for side in [-1.0, 1.0]:
			var rafter := _box(root, Vector3(slope_length, 0.09, 0.11),
				Vector3(side * ROOM_HALF_X * 0.5, (WALL_HEIGHT + RIDGE_HEIGHT) * 0.5 - 0.09, z), _wood)
			rafter.rotation.z = side * slope_angle
	_box(root, Vector3(0.34, 0.3, ROOM_HALF_Z * 2.0), Vector3(0, RIDGE_HEIGHT - 0.02, 0), _wood)
	# 檐口填充：斜顶外沿挑出墙外，室内会从檐下缝隙看到天空，这里补两块板堵住。
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.7, 1.5, ROOM_HALF_Z * 2.2),
			Vector3(side * (ROOM_HALF_X + 0.16), WALL_HEIGHT + 0.55, 0), _plaster)
	# 封顶板：盖在屋脊之上、从室内看不见，彻底堵死斜顶接缝漏光（实拍发现过星空漏进来）。
	_box(root, Vector3(ROOM_HALF_X * 2.4, 0.12, ROOM_HALF_Z * 2.4), Vector3(0, RIDGE_HEIGHT + 0.12, 0), _wood_dark)
	_box_collider(Vector3(ROOM_HALF_X * 2.0, 0.2, ROOM_HALF_Z * 2.0), Vector3(0, RIDGE_HEIGHT, 0))

	# 山墙：斜顶两端各一片三角墙，否则抬头会直接看到黑。
	var gable_height: float = RIDGE_HEIGHT - WALL_HEIGHT
	for side in [-1.0, 1.0]:
		# 端墙用矩形而不是三角形：多出来的上角会被斜顶挡住（室内看不见），但能彻底堵住角部漏光。
		_box(root, Vector3(ROOM_HALF_X * 2.25, gable_height + 0.7, 0.14),
			Vector3(0, WALL_HEIGHT + (gable_height + 0.7) * 0.5 - 0.1, side * (ROOM_HALF_Z - 0.08)),
			_plaster)
		# 山墙外侧的木构三角梁。
		for edge in [-1.0, 1.0]:
			var brace := _box(root, Vector3(0.1, 0.1, 1.1),
				Vector3(edge * ROOM_HALF_X * 0.35, WALL_HEIGHT + gable_height * 0.55,
					side * (ROOM_HALF_Z - 0.02)), _wood_dark)
			brace.rotation.x = side * 0.0
			brace.rotation.z = edge * -0.72
	# 墙裙与顶角线。
	for side in [-1.0, 1.0]:
		_box(root, Vector3(ROOM_HALF_X * 2.0, 0.22, 0.06),
			Vector3(0, GROUND_Y + 0.11, side * (ROOM_HALF_Z - 0.1)), _wood)


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
	_build_swallow(sill, Vector3(0.36, 0.06, 0.0))
	# 壁炉边：燕子飞过去落脚的地方
	_anchor("AtticAnchor_HearthPerch", Vector3(-3.9, 1.35, -2.5))


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
	var from_pos: Vector3 = sill.position + Vector3(0.36, 0.06, 0.0)
	var to_pos: Vector3 = perch.position
	# 弧线：中间抬高一些，模拟掠过炉火
	var t := swallow_flight
	var lift := sin(t * PI) * 0.9
	swallow_node.position = from_pos.lerp(to_pos, t) + Vector3(0, lift, 0)
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
		swallow_node.position = to_pos
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
		# 门框。
		_box(door_root, Vector3(DOOR_WIDTH + 0.24, 0.12, 0.16), Vector3(0, DOOR_HEIGHT + 0.06, 0.02), _wood_dark)
		for side in [-1.0, 1.0]:
			_box(door_root, Vector3(0.12, DOOR_HEIGHT, 0.16),
				Vector3(side * (DOOR_WIDTH + 0.06) * 0.5, DOOR_HEIGHT * 0.5, 0.02), _wood_dark)
		# 门扇：木框 + 一块透出"那边天气"的嵌板。
		_box(door_root, Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.07), Vector3(0, DOOR_HEIGHT * 0.5, 0), _wood)
		var pane := _box(door_root, Vector3(DOOR_WIDTH - 0.34, DOOR_HEIGHT - 0.62, 0.03),
			Vector3(0, DOOR_HEIGHT * 0.52, 0.05), _glow)
		pane.material_override = _material(spec["color"], 0.75)
		# 门牌：一块小铜牌。
		var plate := _box(door_root, Vector3(0.34, 0.16, 0.02), Vector3(0, DOOR_HEIGHT - 0.28, 0.06), _brass)
		plate.set_meta("label", spec["title"])
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
	frame_root.position = Vector3(wall_x, 0, 0.9)
	frame_root.rotation.y = PI * 0.5
	root.add_child(frame_root)
	var height := 2.25
	var width := 1.12
	for side in [-1.0, 1.0]:
		_box(frame_root, Vector3(0.14, height, 0.14), Vector3(side * width * 0.5, height * 0.5, 0), _wood_dark)
	_box(frame_root, Vector3(width + 0.14, 0.14, 0.14), Vector3(0, height, 0), _wood_dark)
	_box(frame_root, Vector3(width + 0.14, 0.1, 0.14), Vector3(0, 0.05, 0), _wood_dark)
	# 镜面本体：微亮、带一点冷光，走进去是回廊。
	var surface := _box(frame_root, Vector3(width, height - 0.2, 0.04), Vector3(0, height * 0.5, 0.02), _mirror)
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
	table.position = Vector3(1.05, 0, 1.35)
	root.add_child(table)
	# 桌面与四条腿 —— 优先用 Lux3D 写实模型，拿不到才回退程序化 BoxMesh。
	# 桌面高度固定 0.66 m（道具都靠这个高度摆茶壶/杯子），碰撞也照旧。
	var table_prop := prop("tea-table", 0.70)
	if table_prop != null:
		table_prop.position = Vector3.ZERO
		table.add_child(table_prop)
	else:
		_box(table, Vector3(1.5, 0.07, 0.95), Vector3(0, 0.66, 0), _wood)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_box(table, Vector3(0.09, 0.62, 0.09), Vector3(sx * 0.65, 0.31, sz * 0.38), _wood_dark)
	_box_collider(Vector3(1.5, 0.09, 0.95), Vector3(1.05, 0.66, 1.35))
	# 旅行小册：摊开的册子。
	var book_prop := prop("travel-notebook", 0.05)
	if book_prop != null:
		book_prop.position = Vector3(-0.34, 0.70, 0.02)
		table.add_child(book_prop)
	else:
		_box(table, Vector3(0.44, 0.03, 0.32), Vector3(-0.34, 0.71, 0.02), _paper)
		_box(table, Vector3(0.44, 0.03, 0.32), Vector3(0.12, 0.71, 0.02), _paper)
		_box(table, Vector3(0.46, 0.02, 0.02), Vector3(-0.11, 0.72, 0.02), _cloth)
	# 茶壶与两只杯子。壶下先压一圈极暗的光，烧水后才会亮。
	# ⚠ kettle_glow 与 tea_steam 是**交互状态载体**（烧水会变亮），
	#   不能用导入模型替换，否则「烧水」的视觉反馈就没了 —— 这两个保留程序化。
	kettle_glow = _cyl(table, 0.2, 0.2, 0.02, Vector3(0.42, 0.70, -0.2), _material(Color("ffb066"), 0.0), 12)
	var pot_prop := prop("teapot", 0.20)
	if pot_prop != null:
		pot_prop.position = Vector3(0.42, 0.70, -0.2)
		table.add_child(pot_prop)
	else:
		_cyl(table, 0.13, 0.16, 0.2, Vector3(0.42, 0.79, -0.2), _brass, 12)
		_cyl(table, 0.03, 0.05, 0.1, Vector3(0.42, 0.94, -0.2), _brass, 8)
	var cup_prop := prop("teacup", 0.075)
	for cup_x in [0.28, 0.56]:
		if cup_prop != null:
			var c: Node3D = cup_prop.duplicate() as Node3D
			c.position = Vector3(cup_x, 0.70, 0.16)
			table.add_child(c)
			# tea_cups 用来做「倒茶」高亮，这里塞一个占位节点保持状态机可用
			var marker := Node3D.new()
			c.add_child(marker)
			tea_cups.append(marker)
		else:
			var cup := _cyl(table, 0.06, 0.045, 0.08, Vector3(cup_x, 0.73, 0.16), _paper, 10)
			tea_cups.append(cup)
	# 蒸汽：出汤后才出现
	tea_steam = _cyl(table, 0.05, 0.02, 0.3, Vector3(0.42, 1.12, -0.2), _material(Color("e8f0f2"), 0.0), 8)
	tea_steam.visible = false
	# 茶叶罐与小碟。
	_cyl(table, 0.07, 0.07, 0.14, Vector3(-0.05, 0.77, -0.26), _cloth, 10)
	_cyl(table, 0.12, 0.12, 0.015, Vector3(0.42, 0.7, 0.16), _brass, 12)
	_anchor("AtticAnchor_Booklet", table.position + Vector3(-0.34, 0.8, 0.02))
	_anchor("AtticAnchor_Kettle", table.position + Vector3(0.42, 0.95, -0.2))
	_anchor("AtticAnchor_Tea", table.position + Vector3(0.28, 0.82, 0.16))
	# 两把木凳。
	var stool_prop := prop("wooden-stool", 0.48)
	for i in range(2):
		var stool_x: float = 1.05 + (-0.75 if i == 0 else 0.75)
		if stool_prop != null:
			var s: Node3D = stool_prop.duplicate() as Node3D
			s.position = Vector3(stool_x, GROUND_Y, 2.15)
			s.set_meta("kind", "stool")
			root.add_child(s)
		else:
			var stool := _cyl(root, 0.19, 0.19, 0.06,
				Vector3(stool_x, 0.44, 2.15), _wood, 12)
			stool.set_meta("kind", "stool")
			for leg in [Vector3(-0.12, 0, -0.12), Vector3(0.12, 0, -0.12), Vector3(-0.12, 0, 0.12), Vector3(0.12, 0, 0.12)]:
				_box(root, Vector3(0.05, 0.42, 0.05),
					Vector3(stool_x, 0.21, 2.15) + leg, _wood_dark)


# --- 旅行架：四格纪念 + 棱镜之心 ------------------------------------------------
func _build_shelf() -> void:
	var shelf := Node3D.new()
	shelf.name = "TravelShelf"
	shelf.position = Vector3(ROOM_HALF_X - 0.22, 0, -1.2)
	shelf.rotation.y = -PI * 0.5
	root.add_child(shelf)
	# 侧板、背板与三层隔板 —— 优先 Lux3D 模型。
	# ⚠ 纪念托座与棱镜之心**保留程序化**：它们要精确落在某一层上，
	#   而 AI 模型的层高不可控，硬套会穿模。所以书架本体换模型，
	#   上面的小件仍按固定坐标摆。
	var shelf_prop := prop("bookshelf", 1.55)
	if shelf_prop != null:
		shelf_prop.position = Vector3.ZERO
		shelf.add_child(shelf_prop)
	else:
		for side in [-1.0, 1.0]:
			_box(shelf, Vector3(0.08, 1.5, 0.34), Vector3(side * 0.86, 0.95, 0), _wood_dark)
		_box(shelf, Vector3(1.8, 1.5, 0.05), Vector3(0, 0.95, -0.15), _wood_dark)
		for level in [0.42, 0.94, 1.46]:
			_box(shelf, Vector3(1.8, 0.06, 0.34), Vector3(0, level, 0), _wood)
	_box_collider(Vector3(1.8, 1.6, 0.4), Vector3(ROOM_HALF_X - 0.22, 0.95, -1.2))
	# 四个托座：各对应一个世界的纪念，带回来之前是空的。
	var keepsake_keys := ["snow", "cloud", "firefly", "alley"]
	for i in range(4):
		var x := -0.66 + float(i) * 0.44
		_cyl(shelf, 0.1, 0.1, 0.02, Vector3(x, 0.97, 0.02), _brass, 12)
		_box(shelf, Vector3(0.14, 0.02, 0.14), Vector3(x, 0.45, 0.02), _brass)
		var key: String = keepsake_keys[i]
		var token := _build_keepsake(shelf, key, Vector3(x, 0.99, 0.02))
		token.visible = false
		keepsake_nodes[key] = token
	# 第三层放棱镜之心（镜界回廊带回来的那件）——没取回来之前是空的。
	prism_heart = _cylinder_mesh(shelf, 0.09, 0.11, 0.2, Vector3(0.3, 1.58, 0.02), 6)
	prism_heart.material_override = _material(Color("cfe0e6"), 0.9)
	prism_heart.visible = false
	_anchor("AtticAnchor_Shelf", Vector3(ROOM_HALF_X - 0.6, 1.0, -1.2))


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
	# 地毯。铺在地板上，用很矮的目标高度（0.06）让模型几乎贴平。
	var rug_prop := prop("rug", 0.06)
	if rug_prop != null:
		rug_prop.position = Vector3(0.4, GROUND_Y, 0.7)
		root.add_child(rug_prop)
	else:
		_box(root, Vector3(2.4, 0.03, 1.7), Vector3(0.4, GROUND_Y + 0.02, 0.7), _cloth)
	# 旧木箱。
	var chest_prop := prop("wooden-chest", 0.62)
	if chest_prop != null:
		chest_prop.position = Vector3(-2.2, GROUND_Y, 1.9)
		root.add_child(chest_prop)
	else:
		_box(root, Vector3(0.9, 0.55, 0.55), Vector3(-2.2, 0.3, 1.9), _wood)
		_box(root, Vector3(0.94, 0.06, 0.59), Vector3(-2.2, 0.6, 1.9), _wood_dark)
	_box_collider(Vector3(0.94, 0.62, 0.59), Vector3(-2.2, 0.32, 1.9))
	# 靠窗的矮柜与提灯。
	var cabinet_prop := prop("side-cabinet", 0.52)
	if cabinet_prop != null:
		cabinet_prop.position = Vector3(0.0, GROUND_Y, ROOM_HALF_Z - 0.42)
		root.add_child(cabinet_prop)
	else:
		_box(root, Vector3(0.8, 0.5, 0.4), Vector3(0.0, 0.26, ROOM_HALF_Z - 0.42), _wood)
	_box_collider(Vector3(0.8, 0.5, 0.4), Vector3(0.0, 0.26, ROOM_HALF_Z - 0.42))
	# 提灯：火焰（flame）是**交互发光体**，必须保留程序化 —— 它才是「点灯」的视觉。
	# 灯笼外壳换成模型，火焰仍摆在罩内。
	var lantern_pos_z: float = ROOM_HALF_Z - 0.42
	var lantern_prop := prop("lantern", 0.34)
	if lantern_prop != null:
		lantern_prop.position = Vector3(0.0, 0.52, lantern_pos_z)
		root.add_child(lantern_prop)
	else:
		_cyl(root, 0.09, 0.12, 0.24, Vector3(0.0, 0.63, lantern_pos_z), _brass, 8)
	var flame := _cyl(root, 0.05, 0.06, 0.14, Vector3(0.0, 0.78, lantern_pos_z), _glow, 8)
	flame.material_override = _material(Color("ffca7a"), 1.6)
	_anchor("AtticAnchor_Lantern", Vector3(0.0, 0.9, ROOM_HALF_Z - 0.8))
	# 墙上挂画：一片晴天。挂画本身就是「一片晴天的图」，用模型更合适。
	var painting_prop := prop("painting", 0.54)
	if painting_prop != null:
		painting_prop.position = Vector3(1.9, 1.58, -ROOM_HALF_Z + 0.14)
		painting_prop.set_meta("kind", "painting_frame")
		root.add_child(painting_prop)
	else:
		var frame := _box(root, Vector3(0.72, 0.54, 0.04), Vector3(1.9, 1.85, -ROOM_HALF_Z + 0.14), _wood_dark)
		frame.set_meta("kind", "painting_frame")
		_box(root, Vector3(0.6, 0.42, 0.02), Vector3(1.9, 1.85, -ROOM_HALF_Z + 0.17),
			_material(Color("cfe4f2"), 0.5))
	# 唱片机。转盘（_cyl 那圈布面）是**播放状态的载体**，保留程序化。
	var gram_prop := prop("gramophone", 0.3)
	if gram_prop != null:
		gram_prop.position = Vector3(-1.9, 0.64, -1.9)
		root.add_child(gram_prop)
	else:
		_box(root, Vector3(0.62, 0.16, 0.46), Vector3(-1.9, 0.72, -1.9), _wood_dark)
	_cyl(root, 0.2, 0.2, 0.02, Vector3(-1.9, 0.81, -1.9), _cloth, 16)
	_box_collider(Vector3(0.62, 0.16, 0.46), Vector3(-1.9, 0.72, -1.9))
	_anchor("AtticAnchor_Record", Vector3(-1.9, 0.9, -1.6))


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
				(cup as MeshInstance3D).material_override = _material(Color("b98a4e"), 0.5)
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
		var backdrop := _box(holder, Vector3(3.4, 2.4, 0.06), Vector3(0, 0, 1.35), _material(palette, 0.5))
		backdrop.material_override = _material(palette, 0.55)
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
				# 云海：层叠的云与暖光
				for i in range(5):
					var x2 := -1.3 + float(i) * 0.65
					var puff := _sphere(holder, 0.34, Vector3(x2, -0.42 + float(i % 2) * 0.12, 0.6),
						_material(Color("f6ead0"), 0.45))
					puff.scale = Vector3(1.5, 0.5, 1.0)
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
	var wall_z: float = -ROOM_HALF_Z + 0.12
	var dial := Node3D.new()
	dial.name = "WeatherDial"
	dial.position = Vector3(0, 2.28, wall_z)
	root.add_child(dial)
	_cyl(dial, 0.17, 0.17, 0.06, Vector3(0, 0, 0), _brass, 16).rotation.x = PI * 0.5
	_cyl(dial, 0.12, 0.12, 0.07, Vector3(0, 0, -0.01), _wood_dark, 16).rotation.x = PI * 0.5
	for i in range(4):
		var angle := TAU * float(i) / 4.0
		_box(dial, Vector3(0.03, 0.05, 0.03), Vector3(cos(angle) * 0.20, sin(angle) * 0.20, 0.0), _brass)
	dial_pointer = _box(dial, Vector3(0.03, 0.15, 0.03), Vector3(0, 0.07, -0.03), _brass)
	_anchor("AtticAnchor_Dial", Vector3(0, 1.5, wall_z + 0.85))


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
