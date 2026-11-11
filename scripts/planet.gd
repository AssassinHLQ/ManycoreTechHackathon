extends Node3D

const ArchitectureScript = preload("res://scripts/architecture.gd")
const UndergroundScript = preload("res://scripts/underground.gd")
const PlanetShader = preload("res://shaders/planet.gdshader")
const CloudShader = preload("res://shaders/clouds.gdshader")

var game: Node3D
var planet_id := ""
var display_name := ""
var description := ""
var kind := "rock"
var radius := 300.0
var gravity_strength := 18.0
var orbit_radius := 2000.0
var orbit_phase := 0.0
var orbit_speed := 0.0
var orbit_height := 0.0
var base_color := Color.GRAY
var accent_color := Color.WHITE
var surface: MeshInstance3D
## 行星环（只有悬晶星/玄渊星有）。一整片 annulus，见 _build_ring。
var ring_node: MeshInstance3D
var atmosphere: MeshInstance3D
var clouds: MeshInstance3D
var rng := RandomNumberGenerator.new()
var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var site_direction := Vector3.UP
var site_height := 0.0
var site_pad_radius := 0.0
var cave_enabled := false
var cave_direction := Vector3.UP
var cave_mouth_radius := 0.0
var cave_hole_angle := 0.0
var water_shell: MeshInstance3D
var terrain_collision_done := false
var pine_queue: Array = []
var broad_queue: Array = []
var rock_queue: Dictionary = {}

## AI 生成道具（Lux3D）的模型路径。
##
## ⚠ 2026-11-11 用户要求：「星球需要更多物体、环境、地形、特殊点，
##   而且不能是程序化的，必须 AI 生成」。
##   所以树、岩石、遗迹、晶体、信号塔这些都是 Lux3D 文生 3D 出来的 GLB。
##
## 命名约定：`-lo` 是低模变体（约 2 千面）用来铺量，无后缀是高模用来当地标。
## 某个 id 缺资产时 `_prop_mesh()` 返回 null，调用方自动回退程序化几何。
## 每类 AI 道具的实例上限（防止面数爆炸）。
##
## ⚠ 2026-11-11 实测：青岚星 350 棵高模树 × 34468 面 = 1206 万面，
##   单星球合计 1403 万面 —— 完全渲染不动。
##   Lux3D 的模型是 2~3 万面的「高模」，只能当地标；
##   低模变体（*-lo，1 万面）才能拿来铺量，且每类仍要限额。
const PROP_INSTANCE_CAP := {
	"alien-tree": 18,
	"alien-tree-lo": 90,
	"rock-cluster": 18,
	"rock-cluster-lo": 90,
	"rock-spire": 18,
	"rock-spire-lo": 90,
	"ruin-arch": 6,
	"obelisk": 8,
	"dome-habitat": 4,
	"signal-tower": 4,
	"crystal-cluster": 10,
	"vent": 8,
	"floating-rock": 8,
}

const PROP_MODELS := {
	"alien-tree": "res://assets/models/props/alien-tree/model.glb",
	"alien-tree-lo": "res://assets/models/props/alien-tree-lo/model.glb",
	"rock-cluster": "res://assets/models/props/rock-cluster/model.glb",
	"rock-cluster-lo": "res://assets/models/props/rock-cluster-lo/model.glb",
	"rock-spire": "res://assets/models/props/rock-spire/model.glb",
	"rock-spire-lo": "res://assets/models/props/rock-spire-lo/model.glb",
	"ruin-arch": "res://assets/models/props/ruin-arch/model.glb",
	"obelisk": "res://assets/models/props/obelisk/model.glb",
	"dome-habitat": "res://assets/models/props/dome-habitat/model.glb",
	"signal-tower": "res://assets/models/props/signal-tower/model.glb",
	"crystal-cluster": "res://assets/models/props/crystal-cluster/model.glb",
	"vent": "res://assets/models/props/vent/model.glb",
	"floating-rock": "res://assets/models/props/floating-rock/model.glb",
}

## 已加载的 AI 网格缓存（prop_id -> Mesh），同一进程里 20 颗星球共用一份。
static var _prop_mesh_cache := {}

## 待落地的高模地标：prop_id -> Array[Dictionary]（见 _add_prop）
var prop_queue: Dictionary = {}
## 待落地的低模散布：同上
var scatter_prop_queue: Dictionary = {}


func _ready() -> void:
	rng.seed = abs(planet_id.hash()) + 9217
	terrain_noise.seed = abs(planet_id.hash()) + 41
	terrain_noise.frequency = 1.0
	terrain_noise.fractal_octaves = 4
	detail_noise.seed = abs(planet_id.hash()) + 817
	detail_noise.frequency = 1.0
	if kind == "qinglan":
		site_direction = Vector3(-0.06, 1.0, -0.04).normalized()
	site_pad_radius = 34.0
	match kind:
		"qinglan":
			site_pad_radius = 46.0
		"zheya":
			site_pad_radius = 46.0
		"xuanjing":
			site_pad_radius = 42.0
		"xuanyuan":
			site_pad_radius = 30.0
		"baiyao":
			site_pad_radius = 40.0
		"pansha":
			site_pad_radius = 44.0
		"taiyuan":
			site_pad_radius = 42.0
		"liuwu":
			site_pad_radius = 44.0
		"jianmo":
			site_pad_radius = 34.0
	# ⚠ 2026-11-11 平地半径跟着**行星半径**一起放大。
	#
	#   上面那些 34~46 米是按「半径 400 米的青岚星」标定的人类尺度场地。
	#   用户先后把星球放大（半径 ×3 → ×5），但这条一直是**绝对固定值**，
	#   于是星球越大地形起伏越大，而平地还是原来那么一小块 ——
	#   洞穴螺旋坡道（外缘离站点约 39 米）就压到了平地之外的起伏地形上，
	#   walk_test 的 sample 144 因此反复翻红。
	#
	#   这里按「实际半径 / 设计半径 400 米」等比放大，
	#   保证平地的**相对比例**与当初标定时一致。
	if radius > 0.0 and terrain_reference_radius > 0.0:
		prop_scale = radius / terrain_reference_radius
		site_pad_radius *= prop_scale
	site_height = _raw_terrain_height(site_direction)
	_setup_cave()
	_update_orbit()
	_build_surface()
	# ⚠ Lux3D 星球的高度表是在 `_build_surface()` 里烘焙的，上面那次 `site_height`
	# 走的是程序化噪声（表还没就绪）。烘焙完必须**重算一次** ——
	# 建筑平地的基准高度、`terrain_height` 的平地混合都以它为准，
	# 差了几十米的话观测塔会整栋悬空或埋进地里。
	if _lux_height_ready:
		site_height = _raw_terrain_height(site_direction)
	_build_atmosphere()
	_build_landscape()
	ArchitectureScript.build(self, kind)
	UndergroundScript.build(self, kind)
	_build_ground_scatter()
	if kind in ["xuanjing", "xuanyuan"]:
		_build_ring()
	# ⚠ 2026-11-11 Lux3D 星球**不再叠这层半透明水面球**。
	#
	#   用户：「星球上面那些水怎么处理」——沧波星上能看到一层玻璃球罩套在
	#   星球外面，边缘有硬边，还有一块块方块状的穿插痕迹。
	#   原因是 `_build_water()` 用一个**规则球面**（半径 site_height + 潮位）
	#   去表现海水，而 Lux3D 的地表是起伏不规则的 —— 球面和地形到处相交，
	#   交界处就是那些方块。
	#
	#   Lux3D 星球的海洋本来就画在贴图里（沧波是冰架与潮汐裂缝），
	#   叠一层几何水面只会打架，所以这类星球直接跳过。
	if kind == "cangbo" and lux_model_path == "":
		_build_water()


func _setup_cave() -> void:
	cave_enabled = kind in ["qinglan", "zheya", "xuanjing"]
	if not cave_enabled:
		return
	var tangent := site_direction.cross(Vector3.FORWARD)
	if kind == "xuanjing":
		tangent = Vector3.RIGHT.cross(site_direction)
	if tangent.length_squared() < 0.01:
		tangent = site_direction.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var distance := 31.0
	match kind:
		"zheya":
			distance = 33.0
			cave_mouth_radius = 9.0
		"xuanjing":
			distance = 29.0
			cave_mouth_radius = 8.5
		_:
			cave_mouth_radius = 10.0
	# ⚠ 2026-11-11 洞穴也按 prop_scale 放大。
	#
	#   原因：洞体（underground.gd）用的是绝对米数 —— 竖井半径 10.6 米、
	#   洞室 +9.5 米、井深 13 米。星球半径 ×5 之后，这个洞相对星球变成了
	#   一个针眼，而碰撞球面的格子（384 等分 = 33 米弧长）比洞口（10 米）还大，
	#   _cut_cave_hole 连一个三角形都裁不掉 → 洞口被地形封死，
	#   冒烟测试『the open mouth drops all the way to the cave floor』翻红。
	#   放大 5 倍后 cave_hole_angle = 50/2000 = 0.025 rad > 一格 0.0164 rad，
	#   洞口能在碰撞网格上真正开出来；同时和放大后的建筑保持同一尺度。
	# ⚠ 2026-11-11（B 方案，用户定）：洞穴跟着 prop_scale ×5 一起放大。
	#
	#   为什么不放大不行：星球半径 ×5、建筑 65 米高、平地 230 米，
	#   而洞还是 10 米宽、井深 13 米 —— 比例完全不对，而且
	#   cave_hole_angle = 10/2000 = 0.005 rad 比碰撞网格一格（0.0164 rad）还小，
	#   _cut_cave_hole 一个三角形都裁不掉，洞口直接被地形封死。
	#
	#   放大后：竖井半径 53 米、井深 65 米、洞室 +47 米，
	#   cave_hole_angle = 50/2000 = 0.025 rad > 一格 0.0164 rad，
	#   配合 _build_heightfield_surface_mesh 里的洞口局部细分，洞能开得干净。
	#   underground.gd 也必须用 _prop_parent（同一个缩放），两者才对得上。
	# ⚠ cave_mouth_radius **不要**在这里乘 prop_scale。
	#   它是 underground.gd 的**局部单位**（shaft_radius = 本值 + 0.6），
	#   而 underground 整棵子树已经由 _prop_parent 乘了一次 prop_scale。
	#   这里再乘一次 = 缩放两次 → 世界竖井半径 253 米，而洞口只有 57 米，
	#   会变成「小洞口下面一个巨大洞厅」的穿帮。
	#   世界尺度的洞口角只在这里算一次：
	#     洞口世界半径 = cave_mouth_radius * prop_scale（+ 下面 _build_lux3d_surface 的余量）
	distance *= prop_scale
	cave_direction = (site_direction + tangent * (distance / radius)).normalized()
	cave_hole_angle = (cave_mouth_radius * prop_scale) / radius


func _near_cave(direction: Vector3, margin: float) -> bool:
	if not cave_enabled:
		return false
	return direction.angle_to(cave_direction) < cave_hole_angle + margin


## 地形起伏幅度的**参考半径**（米）。0 = 用 `radius` 自己。
##
## ⚠ 2026-11-11 世界放大后新增。`_raw_terrain_height` 原来是
##   `radius + continental*radius*amplitude + detail*radius*0.004`，
##   起伏**绝对值正比于行星半径**。星球半径 ×3 之后，地面起伏也变成 3 倍：
##   青岚星峰峰值 9.4 米 → 28 米，相邻一步落差 0.52 → 1.56 米。
##
##   后果不是「视觉上更崎岖」，而是**贴地行走被判定为瞬移**：
##   walk_test 里「每帧位移 < 1.5 米」有三条直接翻红（出门、进门、潮汐站台阶）。
##   观测塔和潮汐站是**人类尺度**的建筑（台阶十几厘米），地面起伏放大 3 倍后
##   建筑与地面的接缝处就出现了米级的落差。
##
##   所以起伏幅度按「设计半径」算、不按放大后的 radius 算 ——
##   行星变大，但地表的绝对起伏保持原样，建筑、台阶、行走手感都不受影响。
var terrain_reference_radius := 0.0
## 地面物件的统一缩放系数 = 实际半径 / 设计半径（现在 = 5）。
##
## ⚠ 2026-11-11 用户：「为什么每个星球就一个星球在，没有东西」。
##   星球半径 ×5 之后，只有 `site_pad_radius` 跟着放大了（46 → 230 米），
##   而建筑、熔岩柱、晶体、树、岩石的尺寸**全是绝对米数**没动：
##     观测塔 13 米高，搁在半径 2000 米的星球上 = 地球上一根 40 米长的针；
##     全星球 170 棵树，平均 15 万平方米一棵。
##   结果从驾驶舱看下去，每颗星球都是一颗光球，上面什么都没有。
##   这里统一乘上 5：建筑变 20~65 米、树变 18~40 米，从空中一眼就能看见。
var prop_scale := 1.0


func terrain_height(direction: Vector3) -> float:
	var dir := direction.normalized()
	var raw := _raw_terrain_height(dir)
	if radius <= 0.0:
		return raw
	var angular := acos(clampf(dir.dot(site_direction), -1.0, 1.0))
	var pad_angle := site_pad_radius / radius
	var blend := 1.0 - smoothstep(pad_angle, pad_angle * 1.6, angular)
	return lerpf(raw, site_height, blend)


func _raw_terrain_height(direction: Vector3) -> float:
	var dir := direction.normalized()
	# Lux3D 星球：高度直接查烘焙好的表（见 _build_lux3d_surface）
	if _lux_height_ready:
		return _sample_lux_height(dir)
	var continental := terrain_noise.get_noise_3d(dir.x * 5.2, dir.y * 5.2, dir.z * 5.2)
	var detail := detail_noise.get_noise_3d(dir.x * 37.0, dir.y * 37.0, dir.z * 37.0)
	# 起伏按参考半径算（世界放大后 = 设计半径），球面本身仍按 radius。
	var ref: float = terrain_reference_radius if terrain_reference_radius > 0.0 else radius
	var amplitude := 0.026
	match kind:
		"zheya": amplitude = 0.030
		"cangbo": amplitude = 0.005
		"xuanjing": amplitude = 0.055
		"xuanyuan": amplitude = 0.024
		"baiyao": amplitude = 0.018
		"pansha": amplitude = 0.034
		"taiyuan": amplitude = 0.022
		"liuwu": amplitude = 0.028
		"jianmo": amplitude = 0.020
	return radius + continental * ref * amplitude + detail * ref * 0.004


func surface_position(direction: Vector3, altitude := 0.0) -> Vector3:
	var dir := direction.normalized()
	return dir * (terrain_height(dir) + altitude)


## ── Lux3D 生成的星球模型（Aholo Lux3D text-to-3D）──────────────────
##
## 用户 2026-11-11：「青岚星接入 + 其余 9 颗也走 Lux3D」。
##
## 设了 `lux_model_path` 就用它当**可见表面**，否则用程序化球面。
##
## ⚠ 关键约束：游戏里所有地面交互都走 `_raw_terrain_height(direction) -> float`
##   （着陆、玩家贴地、撞击、建筑平地、洞穴裁剪），也就是说星球必须能
##   「按方向取一个高度」。而 Lux3D 给的是一坨静态网格，没有这个函数。
##
##   实测青岚星那颗 GLB：36 万面、最近/最远顶点半径比 4.56（**有内部壳层**）、
##   19.9% 的方向格里有表面折叠（风车塔、洞穴口）。所以不能简单套「星形体」假设。
##
##   做法：从模型**顶点**按方向分格烘一张高度表，每格取 `max r`（最外层表面），
##   空洞用邻格扩散补齐，查询时双线性插值。内部壳层（r=0.137 那层）自然被
##   max 丢掉 —— 玩家要落的是外壳。
var lux_model_path := ""
## 方向 → 高度 的表（单位：米，已是行星世界半径）。空 = 未就绪。
var _lux_height_map := PackedFloat32Array()
var _lux_height_ready := false
## 纬度分格数；经度是它的两倍（经线在极点收敛，这样格子近似方正）。
const LUX_LAT_BINS := 192
const LUX_LON_BINS := 384
## Lux3D 模型的挂载根（缩放后挂在行星下）。
var _lux_root: Node3D
## 站点平地高度（Lux3D 分支压平网格后记下来，供 _ready 重算 site_height 对照）。
var _lux_pad_height := 0.0


func _build_surface() -> void:
	if lux_model_path != "":
		if _build_lux3d_surface():
			return
		push_warning("Lux3D 星球加载失败，退回程序化地形：%s" % lux_model_path)
	surface = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	# ⚠ 这里保持 256/128（原来就是），**不要跟着碰撞那套提到 384×192**。
	#   程序化星球的碰撞体直接复用这块可视网格（见 _ensure_terrain_collision
	#   的非 Lux3D 分支），可视面 = 碰撞面，本来就没有「不一致」。
	#   盲提高分辨率只会让可视网格从 6.5 万面涨到 14.7 万面，白烧 GPU。
	#   （2026-11-11 修「卡死」时误改过这里一次，已回退。）
	sphere.radial_segments = 256 if cave_enabled else 128
	sphere.rings = 128 if cave_enabled else 64
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		var direction := vertices[i].normalized()
		vertices[i] = direction * terrain_height(direction)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if cave_enabled:
		arrays[Mesh.ARRAY_INDEX] = _cut_cave_hole(arrays, vertices)
	var displaced := ArrayMesh.new()
	displaced.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface_tool := SurfaceTool.new()
	surface_tool.create_from(displaced, 0)
	surface_tool.generate_normals()
	surface.mesh = surface_tool.commit()
	var material := ShaderMaterial.new()
	material.shader = PlanetShader
	material.set_shader_parameter("base_color", base_color)
	material.set_shader_parameter("accent_color", accent_color)
	material.set_shader_parameter("seed", float(abs(planet_id.hash()) % 997))
	var biome := 0
	match kind:
		"zheya": biome = 5
		"cangbo": biome = 6
		"xuanjing": biome = 7
		"xuanyuan": biome = 8
		"baiyao": biome = 9
		"pansha": biome = 10
		"taiyuan": biome = 11
		"liuwu": biome = 12
		"jianmo": biome = 13
	material.set_shader_parameter("biome", biome)
	surface.material_override = material
	add_child(surface)
	# 碰撞不在这里建：见 _ensure_terrain_collision()（靠近时才建，省下启动最贵的一项）。


func _ensure_terrain_collision() -> void:
	# 地形碰撞的 trimesh 是启动阶段最贵的一项（三个大星球各约 155 ms，五颗共约 530 ms，
	# 占整场构建的两成）。改成飞船或玩家靠近本星球时再建，落地前早就建好了。
	if terrain_collision_done:
		return
	# ── Lux3D 分支 ──
	#
	# ⚠ 碰撞体**不能用** Lux3D 网格，要用按高度表生成的程序化球面，原因：
	#   Lux3D 网格 15 万面摊在整个球上，顶点间距约 11 米；
	#   而站点平地半径 46 米只容得下约 4 个顶点 —— 那么粗的网格表达不了
	#   「一块平地」，玩家走上去会踩在参差的三角面上，洞穴坡道那 12.85 米
	#   的下沉会被顶穿（实测 walk_test 的 spiral ramp 因此翻红）。
	#
	#   程序化球面是 256×128，间距约 30 米但**均匀且与 terrain_height 同源**，
	#   所以物理表面与地形查询、以及 Lux3D 的可视表面三者一致。
	if _lux_root != null:
		terrain_collision_done = true
		var col_mesh := _build_heightfield_surface_mesh()
		if col_mesh == null:
			push_warning("Lux3D 行星建不出碰撞网格：%s" % planet_id)
			return
		var body := StaticBody3D.new()
		body.name = "TerrainCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = col_mesh.create_trimesh_shape()
		body.add_child(collision)
		add_child(body)
		return
	if surface == null or surface.mesh == null:
		return
	terrain_collision_done = true
	var body2 := StaticBody3D.new()
	body2.name = "TerrainCollision"
	body2.collision_layer = 1
	body2.collision_mask = 0
	var collision2 := CollisionShape3D.new()
	collision2.shape = surface.mesh.create_trimesh_shape()
	body2.add_child(collision2)
	add_child(body2)


## 按 `terrain_height()` 生成一张**专用的地形网格**（只用于碰撞，不显示）。
##
## 与 `_build_surface` 的程序化分支同一套做法，但独立成函数，好让 Lux3D 星球
## 也能拿到一张「与高度查询完全同源」的物理表面。
func _build_heightfield_surface_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	# ⚠ 2026-11-11 分辨率从 128×64（cave 256×128）提到 384×192。
	#
	#   这是「地形把人物卡死」的根因：Lux3D 的高度表本身是 96×192 格
	#   （半径 2000 米时每格约 65 米），而旧碰撞球面在赤道只有 128 格
	#   = **每格 98 米**，比高度表本身还粗 —— 采样不足导致碰撞面在地下
	#   切出一条条几十米宽的大折面，玩家走在折面棱上就被卡住。
	#   现在的 384×192（每格约 32 米）是高度表的 2 倍过采样，能完整表达它。
	sphere.radial_segments = 384
	sphere.rings = 192
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		var d := vertices[i].normalized()
		vertices[i] = d * terrain_height(d)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if cave_enabled:
		# ⚠ 2026-11-11 洞口必须**局部细分**，否则开不出洞。
		#
		#   矛盾点：碰撞球面整球 384×192，一格约 33 米弧长；
		#   而洞口只有 cave_mouth_radius（青岚星 10 米）—— **洞口比一格还小**。
		#   `_cut_cave_hole` 按三角形重心角度判据裁，重心永远落不进洞口，
		#   于是一个三角形都裁不掉，洞口被地形封死（冒烟测试
		#   『the open mouth drops all the way to the cave floor』翻红）。
		#
		#   之前能用是因为星球半径只有 400 米、一格 19 米，也差不多是侥幸。
		#   现在把洞口周围递归切 3 轮（33 → 16.5 → 8.2 → 4.1 米），
		#   洞口边缘才有足够密的顶点，裁出来的洞才对得上 underground 的竖井。
		var refined := _refine_around_cave(vertices, arrays[Mesh.ARRAY_INDEX])
		vertices = refined[0]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = _cut_cave_hole(arrays, vertices)
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(raw, 0)
	st.generate_normals()
	var committed := st.commit()
	return committed


## 加载 Lux3D 模型当可见表面，并烘出「方向 → 高度」表。
##
## 返回 true 表示接成功了；失败返回 false，调用方会退回程序化地形。
func _build_lux3d_surface() -> bool:
	var packed: PackedScene = load(lux_model_path)
	if packed == null:
		push_warning("Lux3D 模型加载失败：%s" % lux_model_path)
		return false
	var inst := packed.instantiate() as Node3D
	if inst == null:
		push_warning("Lux3D 模型实例化失败：%s" % lux_model_path)
		return false

	_lux_root = Node3D.new()
	_lux_root.name = "Lux3dSurface"
	_lux_root.add_child(inst)
	add_child(_lux_root)

	# ── 收集顶点 + 法线到 _lux_root 的局部空间 ──
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var inv: Transform3D = _lux_root.global_transform.affine_inverse()
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		var rel: Transform3D = inv * node.global_transform
		# 法线要用法线矩阵变换（非等比缩放时不能直接乘 basis）
		var nrm_basis: Basis = rel.basis.inverse().transposed()
		for s in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nn: Variant = arrays[Mesh.ARRAY_NORMAL]
			var has_n: bool = nn != null and (nn as PackedVector3Array).size() == vv.size()
			for i in range(vv.size()):
				verts.append(rel * vv[i])
				if has_n:
					normals.append((nrm_basis * (nn as PackedVector3Array)[i]).normalized())
				else:
					normals.append(Vector3.ZERO)
	if verts.is_empty():
		push_warning("Lux3D 模型没有顶点：%s" % lux_model_path)
		return false

	# ── 按方向分格取每格最大的 r（= 最外层表面）──
	#
	# ⚠ 两步过滤，针对实测的「diorama 星球」问题：
	#   ① **法线朝内**的顶点不要 —— 那颗 GLB 有内部壳层（最近顶点 r=0.137，
	#      半径比 4.56），内部壳的法线多半朝里，剔掉能少一大批干扰。
	#   ② 逐格取 max 拿外壳（壳外的树叶、岩石会顶上来，交给后面的中值滤波）。
	var cells := LUX_LAT_BINS * LUX_LON_BINS
	var map := PackedFloat32Array()
	map.resize(cells)
	map.fill(-1.0)
	var skipped_inward := 0
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var r: float = v.length()
		if r < 0.000001:
			continue
		var d: Vector3 = v / r
		var n: Vector3 = normals[i]
		# 有法线且明显朝内 → 内部结构，跳过
		if n != Vector3.ZERO and n.dot(d) < -0.15:
			skipped_inward += 1
			continue
		var li := clampi(int((asin(clampf(d.y, -1.0, 1.0)) / PI + 0.5) * LUX_LAT_BINS),
			0, LUX_LAT_BINS - 1)
		var oi := clampi(int((atan2(d.z, d.x) / TAU + 0.5) * LUX_LON_BINS),
			0, LUX_LON_BINS - 1)
		var k := li * LUX_LON_BINS + oi
		if r > map[k]:
			map[k] = r
	if skipped_inward > 0:
		print("[Lux3D] %s：剔除朝内法线顶点 %d 个" % [planet_id, skipped_inward])

	# ── 取中位数当「单位半径」，这样起伏围绕行星半径对称 ──
	var filled: Array[float] = []
	for i in range(cells):
		if map[i] > 0.0:
			filled.append(map[i])
	if filled.is_empty():
		push_warning("Lux3D 高度表全空：%s" % lux_model_path)
		return false
	filled.sort()
	var unit: float = filled[filled.size() / 2]

	# ── 缩放到行星世界半径，并补空洞 ──
	var to_world: float = radius / unit
	for i in range(cells):
		if map[i] > 0.0:
			map[i] = map[i] * to_world
	_fill_lux_gaps(map)
	# ── 中值滤波：压掉树尖 / 岩尖 ──
	#
	# 这一步是「diorama 星球」能落地的关键。逐格取 max 之后，凡是格子里
	# 有树或岩石，取到的就是**树顶**；格子在树之间的，取到的是地面。
	# 于是高度表就是一片锯齿 —— 走上去等于在树冠之间蹦。
	#
	# 中值滤波能把「孤立的尖峰」抹掉而**保留大块平台**：
	#   · 一棵树在赤道上约占 2 格（格宽 = 2πR/192，R=1200 时约 39 米）
	#   · 观测台那块平台约占 10 格以上
	# 半径 2（5×5）、跑 2 遍，正好吃掉树冠、留下平台。
	map = _median_filter_lux(map, 4, 2)
	_lux_height_map = map
	_lux_height_ready = true

	# ── 把模型在「站点附近」压平，让可视网格 = 碰撞体 = terrain_height ──
	#
	# ⚠ 这是 Lux3D 星球特有的坑，程序化星球没有：
	#   `terrain_height()` 在建筑站点附近会把高度**混合压平**成 site_height，
	#   但碰撞体用的是**原始 GLB 网格**（没被压平）。两者一高一低，
	#   洞穴坡道那 12.85 米的下沉就会被地表顶穿 ——
	#   实测 walk_test 的「spiral ramp sample 64」因此翻红。
	#
	#   所以这里按**完全相同的混合公式**把网格顶点也压平，
	#   三份数据（可视 / 碰撞 / 高度查询）从此一致。
	var site_raw: float = _sample_lux_map(map, site_direction.normalized())
	var pad_angle: float = site_pad_radius / radius
	var pad_outer: float = pad_angle * 1.6
	# ⚠ Lux3D 星球把洞穴口稍微放宽一点：
	#   程序化星球的地表在洞口附近本来就是起伏的，玩家被洞口边缘挡住时会顺着
	#   斜坡滑下去；而 Lux3D 星球这里被压成了**一块平地**，洞口边缘变成一道
	#   硬台阶，玩家会被抬到台面上而不是落进坡道。
	#
	#   ⚠ 2026-11-11 B 方案：原来写的是 cave_hole_angle *= 1.4（放宽 40%）。
	#   洞 ×5 之后洞本身就大了 5 倍，再放宽 40% 会开出直径 140 米的大窟窿，
	#   大到射线从洞口穿过去都打不到东西。改成**按米加的固定余量**：
	#   洞口半径 = cave_mouth_radius + 1.5 * prop_scale（放大后多留 7.5 米），
	#   这个余量只用来把压平产生的台阶推出坡道之外，和尺度无关。
	if cave_enabled:
		# 世界尺度算：洞体世界半径 = cave_mouth_radius * prop_scale
		# （underground 的竖井 + 0.6 局部 ≈ +3 世界米，这里一并算进余量）
		var rim_extra: float = 1.5 * prop_scale
		cave_hole_angle = ((cave_mouth_radius + 0.6) * prop_scale + rim_extra) / radius
	_displace_lux_mesh_to_pad(to_world, site_raw, pad_angle, pad_outer)
	# 站点基准高度用**压平后的**值，后面 _ready 里重算时会得到同一个数
	_lux_pad_height = site_raw

	# ── 换成「带平铺细节」的材质 ──
	# Lux3D 原材质是 StandardMaterial3D + 一张 2048² 包全星球的贴图
	# （每像素约 6 米），近看必然糊。这里把它的 albedo 贴图抽出来当基色，
	# 叠一层每 8 米重复的程序化颗粒（三向投影），近看就有质感了。
	_apply_detail_material(to_world)

	# ── 缩放并挂上模型（模型单位 → 米）──
	_lux_root.scale = Vector3.ONE * to_world
	# surface 变量指向第一个网格，供外部只读引用（碰撞走 _lux_root 分支）
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		surface = mi as MeshInstance3D
		break
	return true


## 把 Lux3D 网格的顶点在站点附近按 `terrain_height` 的平地混合公式压平。
##
## 混合公式必须与 `terrain_height` 里那句完全一致：
##     angular = acos(dir · site_direction)
##     blend   = 1 - smoothstep(pad_angle, pad_outer, angular)
##     h       = lerp(原始高度, site_height, blend)
func _displace_lux_mesh_to_pad(to_world: float, site_h: float,
		pad_angle: float, pad_outer: float) -> void:
	if _lux_root == null or to_world <= 0.0:
		return
	var site_dir: Vector3 = site_direction.normalized()
	var touched := 0
	# ⚠ 2026-11-11 额外一步：把**所有**顶点朝高度表靠拢，消掉尖片。
	#   混入比例 MESH_CONFORM：1 = 完全跟随平滑高度表（最平），0 = 原始几何。
	# ⚠ 2026-11-11 从 0.95 提到 1.0。
	#   0.95 意味着每个顶点仍保留 5% 的原始 GLB 起伏，
	#   而碰撞/地形查询只认 `terrain_height` —— 两份表面差几十米，
	#   玩家就会「看着在地上、实际陷在碰撞面里」，走两步被卡死。
	#   1.0 = 可视网格完全落在 terrain_height 上，三份数据真正同源。
	var conform := 1.0
	# ⚠ 2026-11-11 性能强化（用户：「加载变久那么多,一直卡开始」）。
	#
	#   实测：20 颗行星建场 43.7 秒，其中 41 秒全在这一段 ——
	#   每颗 12~19 万个顶点，每个顶点做三件贵事：
	#     ① _sample_lux_map()  双线性插值查表
	#     ② acos()             反三角函数
	#     ③ generate_normals() 整网格重算法线（在 surface 循环里，按面数跑）
	#
	#   三个优化，都**不改变几何结果**（数学等价，只是少做无用功）：
	#
	#   A. 站点压平只在近处算 acos：
	#      之前对**所有** 16 万顶点都算 acos(dir·site_dir)，
	#      但只有 angular < pad_outer 的才需要。pad_outer 通常 < 0.15 rad，
	#      所以先用**平方距离/点积近似**快速排除远处顶点 —— acos 只在
	#      点积超过 cos(pad_outer) 时才调用。远处顶点直接跳过整个 ② 步。
	#
	#   B. conform == 1.0 时省掉一次 lerp：
	#      lerpf(a, b, 1.0) 恒等于 b，直接赋值即可（本来就要 conform=1.0）。
	#
	#   C. generate_normals 只在**顶点真的动过**时才做：
	#      原代码无条件重算；现在 changed_any 为 false 就跳过，
	#      连 SurfaceTool 都不用建。
	var site_cos: float = cos(pad_outer)
	var site_cos_pad: float = cos(pad_angle)
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		var new_mesh := ArrayMesh.new()
		var changed_any := false
		for s in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var local_changed := false
			for i in range(verts.size()):
				var v: Vector3 = verts[i]
				var r: float = v.length()
				if r < 0.000001:
					continue
				var dir: Vector3 = v / r
				# ① 朝平滑高度表靠拢（全星球范围，消尖片）
				var smooth_r: float = _sample_lux_map(_lux_height_map, dir)
				var blended: float
				if conform >= 0.9999:
					blended = smooth_r
				else:
					blended = lerpf(r * to_world, smooth_r, conform)
				# ② 站点附近再压平 —— **只在近处调 acos**
				var dot: float = dir.dot(site_dir)
				if dot > site_cos:
					# 到这里才真的在 pad_outer 范围内，才值得算角度
					var angular: float = acos(clampf(dot, -1.0, 1.0))
					var blend: float
					if dot >= site_cos_pad:
						blend = 1.0          # 完全在平地区内
					else:
						blend = 1.0 - smoothstep(pad_angle, pad_outer, angular)
					blended = lerpf(blended, site_h, blend)
				verts[i] = dir * (blended / to_world)
				local_changed = true
				touched += 1
			arrays[Mesh.ARRAY_VERTEX] = verts
			if not local_changed:
				# 顶点一个都没动：原样搬过去，省掉 generate_normals
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var mat0: Material = node.mesh.surface_get_material(s)
				if mat0 != null:
					new_mesh.surface_set_material(s, mat0)
				continue
			changed_any = true
			# 顶点动过之后重算法线：尖片的硬边一半来自法线不连续，
			# 平滑法线能让起伏看起来像丘陵而不是碎玻璃。
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
			st.generate_normals()
			var rebuilt := st.commit()
			var mat2: Material = node.mesh.surface_get_material(s)
			if mat2 != null:
				rebuilt.surface_set_material(s, mat2)
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
				rebuilt.surface_get_arrays(0))
			if mat2 != null:
				new_mesh.surface_set_material(s, mat2)
			continue

		if changed_any:
			node.mesh = new_mesh
	if touched > 0:
		print("[Lux3D] %s：压平站点周围顶点 %d 个（与 terrain_height 对齐）" % [
			planet_id, touched])


## 把 Lux3D 星球的材质换成「基色贴图 + 平铺细节」。
const DETAIL_SHADER := preload("res://shaders/planet_detail.gdshader")


func _apply_detail_material(world_scale: float) -> void:
	if _lux_root == null:
		return
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		for s in range(node.mesh.get_surface_count()):
			var src: Material = node.mesh.surface_get_material(s)
			if src == null:
				src = node.material_override
			if src == null:
				continue
			var albedo_tex: Texture2D = null
			var rough: float = 0.88
			if src is StandardMaterial3D:
				albedo_tex = (src as StandardMaterial3D).albedo_texture
				rough = clampf((src as StandardMaterial3D).roughness, 0.0, 1.0)
			if albedo_tex == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = DETAIL_SHADER
			mat.set_shader_parameter("base_tex", albedo_tex)
			mat.set_shader_parameter("detail_meters", 8.0)
			mat.set_shader_parameter("model_scale", world_scale)
			# 暗色星球（玄渊/缄默）细节弱一点，否则会显得脏
			var strength: float = 0.20 if kind in ["xuanyuan", "jianmo"] else 0.30
			mat.set_shader_parameter("detail_strength", strength)
			mat.set_shader_parameter("roughness_value", rough)
			node.mesh.surface_set_material(s, mat)


## 对高度表做中值滤波（经度环绕、纬度夹紧）。
##
## 为什么用**中值**而不是均值：均值会把树尖的高度「摊」到周围一片，
## 让整片地面抬高；中值直接丢到中间值，孤立的尖峰不影响邻域。
func _median_filter_lux(map: PackedFloat32Array, radius: int, passes: int) -> PackedFloat32Array:
	for _pass in range(passes):
		var src := map.duplicate()
		var side := radius * 2 + 1
		var vals := PackedFloat32Array()
		vals.resize(side * side)
		for li in range(LUX_LAT_BINS):
			for oi in range(LUX_LON_BINS):
				var w := 0
				for dy in range(-radius, radius + 1):
					var yy := clampi(li + dy, 0, LUX_LAT_BINS - 1)
					for dx in range(-radius, radius + 1):
						var xx := (oi + dx + LUX_LON_BINS) % LUX_LON_BINS
						vals[w] = src[yy * LUX_LON_BINS + xx]
						w += 1
				var part := vals.slice(0, w)
				part.sort()
				map[li * LUX_LON_BINS + oi] = part[part.size() / 2]
	return map


## 把高度表里的空洞（没有顶点的方向格）用邻格扩散补上。
##
## 83% 填充率意味着约 17% 的格子是空的：不补的话那些方向采样会得到 -1，
## 玩家走到那里就会掉下去或者瞬移回原点。
func _fill_lux_gaps(map: PackedFloat32Array) -> void:
	var cells := LUX_LAT_BINS * LUX_LON_BINS
	# 最多扩散这么多轮；每轮把「有值格」的邻居填上。
	# 96×192 的格子，17% 空洞最多几轮就能全部覆盖。
	for _pass in range(24):
		var changed := 0
		var snapshot := map.duplicate()
		for li in range(LUX_LAT_BINS):
			for oi in range(LUX_LON_BINS):
				var k: int = li * LUX_LON_BINS + oi
				if snapshot[k] > 0.0:
					continue
				var sum := 0.0
				var n := 0
				# 四邻域；经度环绕，纬度夹紧
				var lon_l: int = (oi - 1 + LUX_LON_BINS) % LUX_LON_BINS
				var lon_r: int = (oi + 1) % LUX_LON_BINS
				var up: int = clampi(li + 1, 0, LUX_LAT_BINS - 1)
				var dn: int = clampi(li - 1, 0, LUX_LAT_BINS - 1)
				for nk in [li * LUX_LON_BINS + lon_l, li * LUX_LON_BINS + lon_r,
						up * LUX_LON_BINS + oi, dn * LUX_LON_BINS + oi]:
					if snapshot[nk] > 0.0:
						sum += snapshot[nk]
						n += 1
				if n > 0:
					map[k] = sum / float(n)
					changed += 1
		if changed == 0:
			break
	# 兜底：极端情况下（整行都空）用行星半径填
	for i in range(cells):
		if map[i] <= 0.0:
			map[i] = radius


## 按方向双线性插值取高度表里的值。
func _sample_lux_height(dir: Vector3) -> float:
	return _sample_lux_map(_lux_height_map, dir)


## 对任意高度表按方向做双线性插值（`_sample_lux_height` 的通用版）。
func _sample_lux_map(map: PackedFloat32Array, dir: Vector3) -> float:
	var lat: float = asin(clampf(dir.y, -1.0, 1.0)) / PI + 0.5     # 0..1
	var lon: float = atan2(dir.z, dir.x) / TAU + 0.5                 # 0..1
	var fy: float = lat * float(LUX_LAT_BINS) - 0.5
	var fx: float = lon * float(LUX_LON_BINS) - 0.5
	var y0 := clampi(int(floorf(fy)), 0, LUX_LAT_BINS - 1)
	var y1 := clampi(y0 + 1, 0, LUX_LAT_BINS - 1)
	var ty: float = clampf(fy - float(y0), 0.0, 1.0)
	var x0i := int(floorf(fx))
	var tx: float = fx - float(x0i)
	var x0 := (x0i % LUX_LON_BINS + LUX_LON_BINS) % LUX_LON_BINS
	var x1 := (x0 + 1) % LUX_LON_BINS
	var v00: float = map[y0 * LUX_LON_BINS + x0]
	var v01: float = map[y0 * LUX_LON_BINS + x1]
	var v10: float = map[y1 * LUX_LON_BINS + x0]
	var v11: float = map[y1 * LUX_LON_BINS + x1]
	var a: float = lerpf(v00, v01, tx)
	var b: float = lerpf(v10, v11, tx)
	return lerpf(a, b, ty)


func _cut_cave_hole(arrays: Array, vertices: PackedVector3Array) -> PackedInt32Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in range(vertices.size()):
			indices[i] = i
	var kept := PackedInt32Array()
	var cos_limit := cos(cave_hole_angle)
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		if (a + b + c).normalized().dot(cave_direction) > cos_limit:
			continue
		kept.push_back(indices[i])
		kept.push_back(indices[i + 1])
		kept.push_back(indices[i + 2])
	return kept


## 在洞口附近把三角形递归细分，让洞口边缘的格子小到能表达洞。
##
## 输入输出都是「方向 * terrain_height(方向)」的顶点表 + 索引表，
## 返回 [vertices, indices]。细分只发生在洞口附近的三角形上，
## 整球分辨率不变（否则 20 颗星球的面数会炸）。
##
## 做法：1→4 细分（三条边各取中点）。中点方向取两端点方向的球面中点，
## 再乘 terrain_height 贴地，所以新顶点同样落在地形表面上。
##
## ⚠ 注意 GDScript 的 PackedVector3Array 是**写时复制**：
##   往函数参数里 push_back 不会传回调用方。所以这里自己维护一个
##   Array[Vector3] 工作副本，最后再转回 PackedVector3Array。
func _refine_around_cave(vertices: PackedVector3Array, indices: PackedInt32Array) -> Array:
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in range(vertices.size()):
			indices[i] = i
	var cos_zone: float = cos(cave_hole_angle * 2.6)   # 洞口外 2.6 倍角范围
	var work: Array = []
	work.resize(vertices.size())
	for i in range(vertices.size()):
		work[i] = vertices[i]
	var idx: PackedInt32Array = indices.duplicate()
	for _round in range(3):
		var cache := {}
		var next := PackedInt32Array()
		var refined_count := 0
		for i in range(0, idx.size(), 3):
			var ia: int = idx[i]
			var ib: int = idx[i + 1]
			var ic: int = idx[i + 2]
			var a: Vector3 = work[ia]
			var b: Vector3 = work[ib]
			var c: Vector3 = work[ic]
			var centroid: Vector3 = (a + b + c).normalized()
			if centroid.dot(cave_direction) < cos_zone:
				next.push_back(ia)
				next.push_back(ib)
				next.push_back(ic)
				continue
			var ab: int = _edge_midpoint(cache, work, ia, ib)
			var bc: int = _edge_midpoint(cache, work, ib, ic)
			var ca: int = _edge_midpoint(cache, work, ic, ia)
			next.push_back(ia)
			next.push_back(ab)
			next.push_back(ca)
			next.push_back(ab)
			next.push_back(ib)
			next.push_back(bc)
			next.push_back(ca)
			next.push_back(bc)
			next.push_back(ic)
			next.push_back(ab)
			next.push_back(bc)
			next.push_back(ca)
			refined_count += 1
		idx = next
		if refined_count == 0:
			break
	var out := PackedVector3Array()
	out.resize(work.size())
	for i in range(work.size()):
		out[i] = work[i]
	return [out, idx]


## 取 (ia, ib) 边的球面中点顶点索引（同一轮内同一条边只加一次）。
## work 是 Array[Vector3]，可以原地 push_back。
func _edge_midpoint(cache: Dictionary, work: Array, ia: int, ib: int) -> int:
	var key: int = mini(ia, ib) * 1048576 + maxi(ia, ib)
	if cache.has(key):
		return int(cache[key])
	var a: Vector3 = work[ia]
	var b: Vector3 = work[ib]
	var dir: Vector3 = a.normalized() + b.normalized()
	var new_index: int = work.size()
	if dir.length_squared() < 0.000001:
		work.append((a + b) * 0.5)
	else:
		var d: Vector3 = dir.normalized()
		work.append(d * terrain_height(d))
	cache[key] = new_index
	return new_index


func _build_atmosphere() -> void:
	# 硫坞星 / 磐砂星 / 缄默星 不做大气壳：硫雾用灯光表现，光壳在近距离会露出低模面片。
	# 纭潪鏄?/ 纾愮爞鏄?/ 缂勯粯鏄?涓嶅仛澶ф皵澹筹細纭浘鐢ㄧ伅鍏夎〃鐜帮紝鍏夊３鍦ㄨ繎璺濈浼氶湶鍑轰綆妯￠潰鐗囥€?	# ⚠ 2026-11-11 Lux3D 星球**不加大气层壳**：
	#   实测那圈深色硬边和内部的方块状穿插都来自这个 cull_front 的规则球壳
	#   （Lux3D 贴图本身已经画了大气般的边缘过渡）。
	if lux_model_path != "":
		return
	if kind not in ["qinglan", "cangbo", "zheya", "baiyao", "taiyuan"]:
		return
	# ⚠ 2026-11-11 Lux3D 星球：外壳半径必须**推到地形最高点之外**。
	#
	#   用户：「星球上面那些水怎么处理」——沧波星外面那圈硬边和方块。
	#   根因不是水，是这两个**规则球壳**：
	#     · 大气层 radius × 1.035
	#     · 云层   radius × 1.012
	#   而 Lux3D 地形起伏是 0.92 ~ 1.073 倍半径，于是两个壳都被地形顶穿，
	#   从地表冒出来的那一片就是那些方块状穿插。
	#   这里把壳的基准半径换成「地形最高点」，两个壳整体抬到地表之上。
	var shell_base: float = radius
	if _lux_height_ready:
		var peak := 0.0
		for h in _lux_height_map:
			peak = maxf(peak, h)
		if peak > radius:
			shell_base = peak
	atmosphere = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = shell_base * 1.035
	sphere.height = shell_base * 2.07
	# 分段数提高，避免近距离看到大气球的多边形面片。
	sphere.radial_segments = 96
	sphere.rings = 48
	atmosphere.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.albedo_color = Color(accent_color, 0.07 if kind != "zheya" else 0.035)
	atmosphere.material_override = material
	atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atmosphere)
	# ⚠ 2026-11-11 Lux3D 星球**不加程序化云层**。
	#
	#   用户：「星球上面那些水怎么处理」——沧波星和青岚星外面的方块状穿插。
	#   排查过程：先怀疑水面球（已关，没用）→ 再怀疑大气层被地形顶穿
	#   （实测高度表只有 1274.6~1302.4，起伏 1.02 倍，根本没顶穿）。
	#   最后把同一个 GLB 拿到 Blender 里渲染对照：**模型本身完全干净**。
	#   所以方块是游戏里额外叠的 `CloudShader` 云层球 —— 噪声贴在一个规则球面上，
	#   而 Lux3D 贴图里本来就画了云和冰盖，两层打架就成块。
	#   这类星球直接跳过云层。
	if kind in ["qinglan", "cangbo"] and lux_model_path == "":
		clouds = MeshInstance3D.new()
		var cloud_sphere := SphereMesh.new()
		cloud_sphere.radius = shell_base * 1.012
		cloud_sphere.height = shell_base * 2.024
		cloud_sphere.radial_segments = 64
		cloud_sphere.rings = 32
		clouds.mesh = cloud_sphere
		var cloud_material := ShaderMaterial.new()
		cloud_material.shader = CloudShader
		cloud_material.set_shader_parameter("cloud_color", Color(0.64, 0.82, 0.88, 0.2 if kind == "qinglan" else 0.32))
		cloud_material.set_shader_parameter("seed", float(abs(planet_id.hash()) % 100))
		clouds.material_override = cloud_material
		clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(clouds)


func _build_landscape() -> void:
	var count := 170
	# ⚠ 星球放大 5 倍后表面积 ×25，物件数量也翻倍，否则空旷得像荒星。
	#   没有再乘 5：每棵树都带一个 StaticBody3D 碰撞体，
	#   20 颗星球 × 850 个碰撞体太贵，×2 已经足够看出层次。
	count *= 2
	match kind:
		"zheya": count = 140
		"cangbo": count = 70
		"xuanjing": count = 160
		"xuanyuan": count = 105
		"baiyao": count = 130
		"pansha": count = 120
		"taiyuan": count = 150
		"liuwu": count = 110
		"jianmo": count = 90
	for i in range(count):
		var direction := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		if direction.distance_to(Vector3.UP) < 0.25:
			continue
		if _near_cave(direction, 0.03):
			continue
		if kind == "qinglan" and direction.distance_to(Vector3(-0.45, 1.0, -0.28).normalized()) < 0.28:
			continue
		match kind:
			"qinglan":
				if i % 5 == 0:
					_add_rock(direction, rng.randf_range(1.4, 5.8), base_color.lightened(0.15), 0.0)
				else:
					_add_tree(direction, true)
			"zheya":
				if i % 3 == 0:
					_add_crystal(direction, Color("e8e2d2"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.0, 3.6), Color("cdc6b4"), 0.0)
			"cangbo":
				if i % 3 == 0:
					_add_spout(direction)
				else:
					_add_rock(direction, rng.randf_range(2.0, 7.0), Color("286d76"), -1.5)
			"xuanjing":
				if i % 3 == 0:
					_add_crystal(direction, Color("c8cdd4"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(2.0, 8.0), base_color.lightened(0.15), 0.0)
			"xuanyuan":
				_add_rock(direction, rng.randf_range(1.0, 5.0), Color("27373d"), 0.0)
			"baiyao":
				if i % 3 == 0:
					_add_crystal(direction, Color("eef7ff"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.8), Color("dfe9ef"), 0.0)
			"pansha":
				_add_rock(direction, rng.randf_range(1.6, 6.4), Color("b99a6b"), 0.0)
			"taiyuan":
				if i % 2 == 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.0, 3.8), Color("5e6b52"), 0.0)
			"liuwu":
				if i % 4 == 0:
					_add_crystal(direction, Color("d8e05a"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.4, 5.2), Color("8a8244"), 0.0)
			"jianmo":
				if i % 3 == 0:
					_add_crystal(direction, Color("9b7fd0"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.2), Color("241f2b"), 0.0)
	if kind == "cangbo":
		_add_landing_island()
	elif kind == "qinglan":
		_add_home_ruin()
	elif kind == "xuanyuan":
		_add_eye_spires()
	_build_site_cluster()
	_flush_vegetation()


func _build_site_cluster() -> void:
	var site := Vector3.UP
	if kind == "qinglan":
		site = Vector3(-0.06, 1.0, -0.04).normalized()
	for i in range(130):
		var scatter := Vector3(rng.randf_range(-0.32, 0.32), rng.randf_range(-0.32, 0.32), rng.randf_range(-0.32, 0.32))
		var direction := (site + scatter).normalized()
		if direction.distance_to(Vector3.UP) < 0.1:
			continue
		if _near_cave(direction, 0.035):
			continue
		if kind == "qinglan" and direction.distance_to(Vector3.UP) < 0.085:
			continue
		match kind:
			"qinglan":
				if i % 4 == 0:
					_add_rock(direction, rng.randf_range(0.8, 3.2), base_color.lightened(0.18), 0.0)
				else:
					_add_tree(direction, true)
			"zheya":
				if i % 3 == 0:
					_add_crystal(direction, Color("e8e2d2"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.0, 3.6), Color("cdc6b4"), 0.0)
			"cangbo":
				if i % 3 == 0:
					_add_crystal(direction, Color("dff4fb"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.0), Color("5c7480"), -1.0)
			"xuanjing":
				if i % 3 == 0:
					_add_crystal(direction, Color("c8cdd4"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.0), base_color.lightened(0.15), 0.0)
			"xuanyuan":
				_add_rock(direction, rng.randf_range(0.8, 3.0), Color("27373d"), 0.0)
			"baiyao":
				if i % 3 == 0:
					_add_crystal(direction, Color("f2fbff"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(0.8, 3.0), Color("e6eff5"), 0.0)
			"pansha":
				if i % 4 == 0:
					_add_crystal(direction, Color("d8c39a"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(0.9, 3.4), Color("c0a274"), 0.0)
			"taiyuan":
				if i % 3 == 0:
					_add_rock(direction, rng.randf_range(0.7, 2.6), Color("6b7860"), 0.0)
				else:
					_add_tree(direction, true)
			"liuwu":
				if i % 4 == 0:
					_add_crystal(direction, Color("e2e46a"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(0.8, 3.2), Color("8f8748"), 0.0)
			"jianmo":
				if i % 2 == 0:
					_add_crystal(direction, Color("a98ce0"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(0.6, 2.8), Color("2a2433"), 0.0)


func _build_ground_scatter() -> void:
	var site := Vector3.UP
	if kind == "qinglan":
		site = Vector3(-0.06, 1.0, -0.04).normalized()
	var mesh: Mesh
	var color := Color.WHITE
	var emission := 0.0
	var emission_color := Color.WHITE
	var height := 1.0
	var count := 700
	var grass := false
	match kind:
		"qinglan":
			mesh = _grass_tuft_mesh()
			color = Color("4a7d6a")
			height = 0.8
			count = 5600
			grass = true
		"zheya":
			mesh = _cylinder(0.0, 0.11, 1.5, 4)
			color = Color("e8e2d2")
			emission = 0.0
			height = 1.5
			count = 2200
		"cangbo":
			mesh = _cylinder(0.02, 0.15, 1.4, 4)
			color = Color("dff4fb")
			height = 1.4
			count = 1800
		"xuanjing":
			mesh = _cylinder(0.0, 0.11, 1.8, 4)
			color = Color("c8cdd4")
			emission = 0.35
			emission_color = Color("ffab5e")
			height = 1.8
			count = 2600
		"baiyao":
			# 白垩冰原：细冰针。
			mesh = _cylinder(0.0, 0.09, 1.2, 4)
			color = Color("f2fbff")
			height = 1.2
			count = 2400
		"pansha":
			# 沙海：低矮的干砾与枯草根。
			mesh = _box(Vector3(0.12, 0.62, 0.12))
			color = Color("a28a5f")
			height = 0.62
			count = 2000
		"taiyuan":
			# 苔原：真正的草簇。
			mesh = _grass_tuft_mesh()
			color = Color("5d8a5c")
			height = 0.72
			count = 4200
			grass = true
		"liuwu":
			# 硫磺带：黄色晶针，微微自发光。
			mesh = _cylinder(0.0, 0.10, 1.4, 4)
			color = Color("ccc45c")
			emission = 0.25
			emission_color = Color("e2e46a")
			height = 1.4
			count = 2000
		"jianmo":
			# 黑曜石地：细碎玻璃棱。
			mesh = _box(Vector3(0.10, 0.75, 0.10))
			color = Color("2a2433")
			emission = 0.12
			emission_color = Color("8a6fc0")
			height = 0.75
			count = 1200
		_:
			mesh = _box(Vector3(0.14, 1.3, 0.14))
			color = Color("3a3d46")
			height = 1.3
			count = 1600
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	if grass:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = emission_color if emission_color != Color.WHITE else color
		material.emission_energy_multiplier = emission
	if mesh is PrimitiveMesh:
		mesh.material = material
	else:
		mesh.surface_set_material(0, material)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	for i in range(count):
		var angle := rng.randf() * TAU
		var radius_offset := sqrt(rng.randf()) * 0.24
		var tangent_a := site.cross(Vector3.UP)
		if tangent_a.length_squared() < 0.02:
			tangent_a = site.cross(Vector3.RIGHT)
		tangent_a = tangent_a.normalized()
		var tangent_b := site.cross(tangent_a).normalized()
		var direction := (site + (tangent_a * cos(angle) + tangent_b * sin(angle)) * radius_offset).normalized()
		if _near_cave(direction, 0.018):
			continue
		var ground_up := _terrain_normal(direction)
		var scale_xz := rng.randf_range(0.75, 1.45)
		var scale_y := scale_xz * rng.randf_range(0.8, 1.35)
		var align := Basis(Quaternion(Vector3.UP, ground_up)).scaled(Vector3(scale_xz, scale_y, scale_xz))
		var base := surface_position(direction, 0.0) - ground_up * 0.24
		var position := base
		if not grass:
			position += ground_up * (height * scale_y * 0.5 - 0.28)
		multimesh.set_instance_transform(i, Transform3D(align, position))
		var tint := color.lightened(rng.randf_range(-0.14, 0.22))
		multimesh.set_instance_color(i, tint)
	var scatter := MultiMeshInstance3D.new()
	scatter.multimesh = multimesh
	scatter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scatter.visibility_range_end = 340.0
	scatter.add_to_group("ground_scatter")
	add_child(scatter)


func _terrain_normal(direction: Vector3) -> Vector3:
	var dir := direction.normalized()
	var tangent_a := dir.cross(Vector3.UP)
	if tangent_a.length_squared() < 0.01:
		tangent_a = dir.cross(Vector3.RIGHT)
	tangent_a = tangent_a.normalized()
	var tangent_b := dir.cross(tangent_a).normalized()
	var epsilon := 0.008
	var center := surface_position(dir)
	var side_a := surface_position((dir + tangent_a * epsilon).normalized())
	var side_b := surface_position((dir + tangent_b * epsilon).normalized())
	var normal := (side_a - center).cross(side_b - center).normalized()
	if normal.dot(dir) < 0.0:
		normal = -normal
	return normal


func _grass_tuft_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = abs(planet_id.hash()) + 3301
	for blade in range(9):
		var angle := local_rng.randf() * TAU
		var distance := local_rng.randf_range(0.0, 0.26)
		var height := local_rng.randf_range(0.36, 0.78)
		var width := local_rng.randf_range(0.025, 0.055)
		var bend := local_rng.randf_range(0.08, 0.22)
		var base := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var side := Vector3(cos(angle + PI * 0.5), 0.0, sin(angle + PI * 0.5)) * width
		var tip := base + Vector3(cos(angle) * bend, height, sin(angle) * bend)
		surface_tool.add_vertex(base - side)
		surface_tool.add_vertex(base + side)
		surface_tool.add_vertex(tip)
	surface_tool.generate_normals()
	return surface_tool.commit()


## 和 `_surface_parent` 一样，但把整棵子树按 `prop_scale` 放大。
##
## 只给**户外摆件**用（建筑、熔岩柱、晶体、喷口、遗迹、落点岛）。
## 洞穴内部（underground.gd）故意不用它 —— 那是给人走的手工空间，
## 保持人类尺度才对。
func _prop_parent(direction: Vector3, altitude: float) -> Node3D:
	var root := _surface_parent(direction, altitude)
	if root != null and not is_equal_approx(prop_scale, 1.0):
		root.scale = Vector3.ONE * prop_scale
	return root


func _surface_parent(direction: Vector3, altitude: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = surface_position(direction, altitude)
	root.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	return root


func _add_tree(direction: Vector3, _collidable := false) -> void:
	# ⚠ 2026-11-11：优先用 Lux3D 生成的异星树（AI 资产）。
	#   树高按 prop_scale 放大到 18~40 米，和放大后的星球/建筑一个尺度。
	#   资产缺失时退回下面的程序化树（原逻辑完整保留）。
	var tree_id := "alien-tree-lo" if _prop_mesh("alien-tree-lo") != null else "alien-tree"
	if _prop_mesh(tree_id) != null:
		_add_prop(tree_id, direction, rng.randf_range(18.0, 40.0) * prop_scale / 5.0,
			0.0, _prop_tint())
		return
	var size := rng.randf_range(1.0, 2.25) * prop_scale
	var up := direction.normalized()
	var origin := surface_position(direction, -0.85)
	var transform := Transform3D(Basis(Quaternion(Vector3.UP, up)).scaled(Vector3.ONE * size), origin)
	if rng.randf() < 0.28:
		broad_queue.append(transform)
	else:
		pine_queue.append(transform)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(Basis(Quaternion(Vector3.UP, up)), origin)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.42 * size
	shape.height = 3.6 * size
	collision.shape = shape
	collision.position.y = 1.8 * size
	body.add_child(collision)
	add_child(body)




## 多面体碎块岩石：低多边形球体做径向抖动 + 去索引，得到硬棱面。
func _rock_mesh(tint: Color) -> ArrayMesh:
	var source := SphereMesh.new()
	source.radius = 1.0
	source.height = 2.0
	source.radial_segments = 8
	source.rings = 5
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = int(tint.r * 1000.0) + int(tint.g * 100.0) + 517
	noise.frequency = 1.0
	for i in range(vertices.size()):
		var dir := vertices[i].normalized()
		if dir == Vector3.ZERO:
			continue
		var wobble := noise.get_noise_3d(dir.x * 2.6, dir.y * 2.6, dir.z * 2.6)
		var tier := 0.22 * sin(dir.y * 5.4)
		vertices[i] = dir * (1.0 + wobble * 0.38 + tier)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var displaced := ArrayMesh.new()
	displaced.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tool := SurfaceTool.new()
	tool.create_from(displaced, 0)
	tool.deindex()  # 去索引后重算法线 → 硬边棱面，而不是光滑球
	tool.generate_normals()
	return tool.commit()


## 多棱柱晶簇：一根主棱 + 三四根副棱 + 底部碎晶座。
func _crystal_cluster_mesh(height: float) -> ArrayMesh:
	var tool := _merged_tool()
	var main_basis := Basis(Vector3.BACK, 0.06)
	tool.append_from(_cylinder(0.0, 1.15, height, 6), 0,
		Transform3D(main_basis, Vector3(0, height * 0.5, 0)))
	var side_count := 3 + (int(height) % 2)
	for i in range(side_count):
		var angle := TAU * float(i) / float(side_count) + 0.45
		var sub_height := height * (0.34 + 0.16 * float(i % 3))
		var lean := Vector3(cos(angle) * 0.26, 1.0, sin(angle) * 0.26).normalized()
		var basis := Basis(Quaternion(Vector3.UP, lean))
		tool.append_from(_cylinder(0.0, 0.46, sub_height, 5), 0,
			Transform3D(basis, Vector3(cos(angle) * 0.85, sub_height * 0.46, sin(angle) * 0.85)))
	# 底部碎晶座
	tool.append_from(_sphere_mesh(1.5, 7, 4), 0,
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.15, 0.28, 1.15)), Vector3(0, 0.18, 0)))
	tool.generate_normals()
	return tool.commit()


## 载入一个 AI 道具网格（带缓存）。缺失或损坏时返回 null，调用方回退。
##
## GLB 是场景而不是裸网格，所以实例化一次、取第一个 MeshInstance3D 的 mesh，
## 立刻释放实例 —— mesh 资源本身会被 MultiMesh 持有。
static func _prop_mesh(prop_id: String) -> Mesh:
	if _prop_mesh_cache.has(prop_id):
		return _prop_mesh_cache[prop_id]
	var mesh: Mesh = null
	var path: String = PROP_MODELS.get(prop_id, "")
	if path != "" and ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			var inst = (packed as PackedScene).instantiate()
			if inst != null:
				for mi in inst.find_children("*", "MeshInstance3D", true, false):
					var m: Mesh = (mi as MeshInstance3D).mesh
					if m != null:
						mesh = m
						break
				inst.free()
	_prop_mesh_cache[prop_id] = mesh
	return mesh


## 把 AI 网格包成可被 MultiMesh 实例化的版本：
##   · 复制一份（各星球独立，互不影响材质）
##   · 每个面的材质复制后打开 vertex_color_use_as_albedo，
##     这样 MultiMesh 的实例色能直接给整颗星球的道具调色，
##     而 AI 生成的贴图本身仍然是原样
static func _prop_mesh_for_instancing(prop_id: String) -> Mesh:
	var base: Mesh = _prop_mesh(prop_id)
	if base == null:
		return null
	var copy: Mesh = base.duplicate()
	for s in range(copy.get_surface_count()):
		var mat: Material = copy.surface_get_material(s)
		if mat is StandardMaterial3D:
			var dup: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
			dup.vertex_color_use_as_albedo = true
			copy.surface_set_material(s, dup)
	return copy


## 排入一个 AI 道具（地标）。size 是**世界米数**（道具高度）。
## altitude 是相对地表的抬升（负值=压入地面）。
func _add_prop(prop_id: String, direction: Vector3, size: float,
		altitude := 0.0, tint := Color.WHITE) -> void:
	if _prop_mesh(prop_id) == null:
		return
	if not prop_queue.has(prop_id):
		prop_queue[prop_id] = []
	# 限额：超过上限的调用直接丢弃，避免面数爆炸（见 PROP_INSTANCE_CAP 的说明）。
	var cap: int = int(PROP_INSTANCE_CAP.get(prop_id, 20))
	if (prop_queue[prop_id] as Array).size() >= cap:
		return
	prop_queue[prop_id].append({
		"dir": direction.normalized(),
		"size": size,
		"altitude": altitude,
		"yaw": rng.randf() * TAU,
		"tint": tint,
	})


## 给站点附近的道具补静态碰撞体。
##
## 为什么只补站点附近：一颗星球有 ~180 个道具实例，全加 StaticBody3D 太贵
## （每个都是独立物理对象）。玩家真正会走进去的只有基地周围那一片，
## 远处的高山巨石纯属背景，穿过去也没人发现。
## 半径 = 2.2 倍平地半径，正好覆盖「看得清细节」的范围。
## 每类道具最多补多少个碰撞体。
##
## ⚠ 2026-11-11 实测教训：一开始只给「站点 2.2 倍平地半径（506 米弧长）」内的
##   实例加碰撞体，结果 90 个树实例里**命中 0 个** —— 因为 _build_landscape 的
##   方向是整球随机分布，506 米只占周长的 4%。
##   现在改成「站点附近的优先 + 按队列顺序补到上限」，两种覆盖都拿到。
const PROP_COLLIDER_CAP := 34


func _add_prop_colliders(entries: Array, prop_id: String) -> void:
	var limit: float = site_pad_radius * 2.2
	var profile := _prop_collider_profile(prop_id)
	var site_dir: Vector3 = site_direction.normalized()
	# 先挑出站点附近的（玩家真会走过去），再按顺序补到上限。
	var picked: Array = []
	var rest: Array = []
	for e in entries:
		var arc: float = acos(clampf((e["dir"] as Vector3).dot(site_dir), -1.0, 1.0)) * radius
		if arc <= limit:
			picked.append(e)
		else:
			rest.append(e)
	for e in rest:
		if picked.size() >= PROP_COLLIDER_CAP:
			break
		picked.append(e)
	picked = picked.slice(0, PROP_COLLIDER_CAP)
	for e in picked:
		var dir: Vector3 = e["dir"]
		var size: float = float(e["size"])
		var origin: Vector3 = surface_position(dir, float(e["altitude"]))
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), origin)
		var collision := CollisionShape3D.new()
		if profile.x < 0.3:
			var shape := CylinderShape3D.new()
			shape.radius = profile.x * size
			shape.height = profile.y * size
			collision.shape = shape
			collision.position.y = profile.y * size * 0.5
		else:
			var shape := SphereShape3D.new()
			shape.radius = profile.x * size
			collision.shape = shape
			collision.position.y = profile.x * size
		body.add_child(collision)
		add_child(body)


## 把 prop_queue 里排好的道具落成 MultiMeshInstance3D。
##
## 关键点：GLB 自己的尺寸是「1 单位高」的不确定值，所以按**包围盒高度**归一化，
## 让 size 参数真正等于世界米数；原点也对齐到模型底面（否则会一半埋进地里）。
## 某个道具该用什么近似碰撞体。
## 竖直细长的（树/塔/方尖碑/晶簇）用胶囊，块状的（岩石/穹顶）用球。
## 返回 Vector2(半径系数, 高度系数)，都是相对「道具高度 size」的比例。
func _prop_collider_profile(prop_id: String) -> Vector2:
	if prop_id.contains("tree") or prop_id.contains("tower") \
			or prop_id.contains("obelisk") or prop_id.contains("spire") \
			or prop_id.contains("crystal"):
		return Vector2(0.16, 0.92)   # 细高：半径 16% 高度
	return Vector2(0.42, 0.62)       # 块状：半径 42% 高度


## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，
## 让同一套 AI 资产在 20 颗星球上呈现各自的色系（用户：「保留配色，呼应名字」）。
func _prop_tint() -> Color:
	var base: Color = base_color
	# 只在明度/饱和度上做轻微变化，别把 AI 贴图染成一块色板
	var j: float = rng.randf_range(-0.12, 0.18)
	return Color(
		clampf(base.r + j, 0.25, 1.0),
		clampf(base.g + j, 0.25, 1.0),
		clampf(base.b + j, 0.25, 1.0),
		1.0)


## 这颗星球的岩石更适合「尖峰」而不是「圆石堆」吗。
## 晶体/黑曜石/裂隙类用尖峰，其余用层积圆石。
func _prefers_spires() -> bool:
	return kind in ["xuanjing", "jianmo", "youdu", "jiangxiao", "xuanpu"]


func _flush_props() -> void:
	if prop_queue.is_empty():
		return
	for prop_id in prop_queue.keys():
		var entries: Array = prop_queue[prop_id]
		if entries.is_empty():
			continue
		var mesh: Mesh = _prop_mesh_for_instancing(prop_id)
		if mesh == null:
			continue
		var aabb: AABB = mesh.get_aabb()
		var base_h: float = maxf(aabb.size.y, 0.001)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = entries.size()
		for i in range(entries.size()):
			var e: Dictionary = entries[i]
			var dir: Vector3 = e["dir"]
			var k: float = float(e["size"]) / base_h
			var basis := Basis(Quaternion(Vector3.UP, dir))
			basis = basis.rotated(dir, float(e["yaw"]))
			basis = basis.scaled(Vector3.ONE * k)
			# 底面贴地：模型底面在 aabb.position.y*k 处，把它抬回 0
			var origin: Vector3 = surface_position(dir,
				float(e["altitude"]) - aabb.position.y * k)
			mm.set_instance_transform(i, Transform3D(basis, origin))
			mm.set_instance_color(i, e["tint"])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Prop_%s" % prop_id
		instance.multimesh = mm
		instance.visibility_range_end = 2200.0
		add_child(instance)
		_add_prop_colliders(entries, prop_id)


func _flush_vegetation() -> void:
	# 先把 AI 道具落地（地标 + 可能的低模散布），再补程序化回退部分。
	_flush_props()
	var bark := _material(Color("4a352a"))
	_flush_multimesh(_pine_trunk_mesh(), pine_queue, bark)
	_flush_multimesh(_pine_canopy_mesh(), pine_queue, _material(Color("2a5442")))
	_flush_multimesh(_broadleaf_trunk_mesh(), broad_queue, bark)
	_flush_multimesh(_broadleaf_canopy_mesh(), broad_queue, _material(Color("33684b")))
	for color in rock_queue.keys():
		var transforms: Array = rock_queue[color]
		if transforms.is_empty():
			continue
		var tool := _merged_tool()
		tool.append_from(_rock_mesh(color), 0, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.05, 1.0)), Vector3.ZERO))
		tool.generate_normals()
		_flush_multimesh(tool.commit(), transforms, _material(color))
		for transform in transforms:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var scale: Vector3 = transform.basis.get_scale()
			body.transform = Transform3D(transform.basis.orthonormalized(), transform.origin)
			var collision := CollisionShape3D.new()
			var shape := SphereShape3D.new()
			shape.radius = (scale.x + scale.y + scale.z) / 3.0
			collision.shape = shape
			body.add_child(collision)
			add_child(body)


func _flush_multimesh(mesh: Mesh, transforms: Array, material: Material) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.visibility_range_end = 320.0
	add_child(instance)


func _merged_tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


func _pine_trunk_mesh() -> ArrayMesh:
	var tool := _merged_tool()
	tool.append_from(_cylinder(0.21, 0.38, 4.2, 9), 0, Transform3D(Basis.IDENTITY, Vector3(0, 2.1, 0)))
	# 三根板根：从树干基部向外撇开，扎进地表
	for i in range(3):
		var angle := TAU * float(i) / 3.0 + 0.35
		var root_basis := Basis(Vector3.UP, angle) * Basis(Vector3.BACK, 0.62)
		tool.append_from(_cylinder(0.05, 0.17, 1.15, 6), 0,
			Transform3D(root_basis, Vector3(cos(angle) * 0.42, 0.30, sin(angle) * 0.42)))
	# 两根侧枝 + 一根上枝
	for entry in [[-0.62, 0.55, 2.6], [0.74, -0.50, 3.15], [0.11, 0.58, 3.6]]:
		var lean: float = entry[0]
		var yaw: float = entry[1]
		tool.append_from(_cylinder(0.04, 0.10, 1.7, 6), 0,
			Transform3D(Basis(Vector3.BACK, lean) * Basis(Vector3.UP, yaw), Vector3(cos(yaw) * 0.5, float(entry[2]), sin(yaw) * 0.5)))
	tool.generate_normals()
	return tool.commit()


func _pine_canopy_mesh() -> ArrayMesh:
	var tool := _merged_tool()
	for i in range(5):
		var width := 1.72 - i * 0.26
		var height := 2.6 - i * 0.18
		tool.append_from(_cylinder(0.0, width, height, 10), 0, Transform3D(Basis(Vector3.UP, i * 0.6), Vector3(0, 3.7 + i * 1.05, 0)))
	tool.generate_normals()
	return tool.commit()


func _broadleaf_trunk_mesh() -> ArrayMesh:
	var tool := _merged_tool()
	tool.append_from(_cylinder(0.25, 0.44, 4.8, 9), 0, Transform3D(Basis.IDENTITY, Vector3(0, 2.4, 0)))
	# 板根
	for i in range(4):
		var angle := TAU * float(i) / 4.0 + 0.2
		tool.append_from(_cylinder(0.06, 0.19, 1.25, 6), 0,
			Transform3D(Basis(Vector3.UP, angle) * Basis(Vector3.BACK, 0.70),
				Vector3(cos(angle) * 0.48, 0.32, sin(angle) * 0.48)))
	# 四根主枝 + 两根细枝
	for side in [-1.0, 1.0]:
		tool.append_from(_cylinder(0.07, 0.18, 2.5, 7), 0, Transform3D(Basis(Vector3.BACK, side * 0.72), Vector3(side * 0.65, 3.8, 0.12)))
		tool.append_from(_cylinder(0.05, 0.12, 1.9, 6), 0, Transform3D(Basis(Vector3.BACK, side * 0.95) * Basis(Vector3.UP, 1.3),
			Vector3(side * 0.95, 3.05, -0.35)))
	tool.append_from(_cylinder(0.04, 0.10, 1.6, 6), 0, Transform3D(Basis(Vector3.FORWARD, 0.42), Vector3(-0.18, 4.35, 0.30)))
	tool.append_from(_cylinder(0.035, 0.09, 1.4, 6), 0, Transform3D(Basis(Vector3.RIGHT, -0.55), Vector3(0.22, 4.55, -0.25)))
	tool.generate_normals()
	return tool.commit()


func _broadleaf_canopy_mesh() -> ArrayMesh:
	var tool := _merged_tool()
	for i in range(4):
		var radius := 1.65 - i * 0.16
		var position := Vector3(cos(i * 2.2) * 1.0, 5.0 + (i % 2) * 0.75, sin(i * 2.2) * 1.0)
		var basis := Basis.IDENTITY.scaled(Vector3(1.15, 0.72, 1.1))
		tool.append_from(_sphere_mesh(radius, 10, 6), 0, Transform3D(basis, position))
	tool.generate_normals()
	return tool.commit()


func _add_rock(direction: Vector3, size: float, color: Color, altitude: float) -> void:
	size *= prop_scale
	# ⚠ 2026-11-11：优先用 Lux3D 生成的岩石（层积巨岩 / 黑曜石尖峰）。
	#   哪个星球的岩石更「尖」按 kind 区分，和原来的配色意图一致。
	var rock_id := "rock-spire" if _prefers_spires() else "rock-cluster"
	if _prop_mesh(rock_id + "-lo") != null:
		rock_id += "-lo"
	if _prop_mesh(rock_id) != null:
		_add_prop(rock_id, direction, maxf(size, 1.0), altitude, color)
		return
	var rotation := Basis.from_euler(Vector3(rng.randf() * PI, rng.randf() * PI, rng.randf() * PI))
	var scale := Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.7, 1.4), rng.randf_range(0.7, 1.3)) * size
	var transform := Transform3D(rotation.scaled(scale), surface_position(direction, altitude + size * 0.12))
	if not rock_queue.has(color):
		rock_queue[color] = []
	rock_queue[color].append(transform)


func _add_basalt(direction: Vector3) -> void:
	var root := _prop_parent(direction, 0.0)
	var height := rng.randf_range(6.0, 24.0)
	root.rotation.y = rng.randf() * TAU
	root.add_child(_mesh(_cylinder(1.4, 2.1, height, 6), _material(Color("372d31")), Vector3(0, height * 0.42, 0)))
	if rng.randf() > 0.35:
		root.add_child(_mesh(_cylinder(0.7, 1.2, height * 0.65, 6), _material(Color("493139")), Vector3(2.4, height * 0.28, 0.7)))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = height * 0.8
	collision.shape = shape
	collision.position.y = height * 0.4
	body.add_child(collision)
	root.add_child(body)
	_limit_range(root, 1600.0)


func _add_crystal(direction: Vector3, color: Color, altitude: float) -> void:
	var root := _prop_parent(direction, altitude)
	var height := rng.randf_range(6.0, 18.0)
	var material := _material(color.darkened(0.2), 1.3)
	# 晶簇：一根主棱 + 三到四根副棱 + 底部碎晶座，不再是单锥
	var cluster := _mesh(_crystal_cluster_mesh(height), material, Vector3(0, height * 0.42, 0))
	cluster.rotation.z = rng.randf_range(-0.16, 0.16)
	root.add_child(cluster)
	# 散落的碎晶
	for i in range(rng.randi_range(2, 4)):
		var shard_angle := rng.randf_range(0.0, TAU)
		var shard := _mesh(_cylinder(0.0, rng.randf_range(0.25, 0.55), rng.randf_range(1.2, 3.0), 5), material,
			Vector3(cos(shard_angle) * rng.randf_range(1.4, 2.6), 0.5, sin(shard_angle) * rng.randf_range(1.4, 2.6)))
		shard.rotation = Vector3(rng.randf_range(-0.4, 0.4), shard_angle, rng.randf_range(-0.4, 0.4))
		root.add_child(shard)
	if rng.randf() > 0.65:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.2
		light.omni_range = 18.0
		light.position.y = height * 0.6
		root.add_child(light)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.4
	shape.height = height * 0.8
	collision.shape = shape
	collision.position.y = height * 0.4
	body.add_child(collision)
	root.add_child(body)
	_limit_range(root, 1600.0)


func _add_spout(direction: Vector3) -> void:
	var root := _prop_parent(direction, -1.0)
	root.scale = Vector3.ONE * rng.randf_range(3.5, 7.0)
	var material := _material(Color(0.38, 0.76, 0.85, 0.24))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(4):
		var cone := _mesh(_cylinder(2.4 - i * 0.45, 0.35 + i * 0.25, 7.0, 16), material, Vector3(0, 3.0 + i * 5.4, 0))
		cone.rotation.y = i * 0.8
		root.add_child(cone)
	_limit_range(root, 1600.0)


func _limit_range(node: Node, end: float) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = end
	for child in node.get_children():
		_limit_range(child, end)


func _add_landing_island() -> void:
	var root := _prop_parent(Vector3.UP, -2.5)
	var stone := SphereMesh.new()
	stone.radius = 34.0
	stone.height = 68.0
	stone.radial_segments = 32
	stone.rings = 16
	var island := _mesh(stone, _material(Color("397a78")), Vector3.ZERO)
	island.scale.y = 0.12
	root.add_child(island)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 33.0
	shape.height = 7.0
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	_limit_range(root, 3000.0)


func _add_home_ruin() -> void:
	var direction := Vector3(0.68, 0.65, -0.3).normalized()
	var root := _prop_parent(direction, 0.0)
	var stone := _material(Color("7c8175"))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	for i in range(7):
		var angle := float(i) / 7.0 * TAU
		var height := 12.0 + float(i % 2) * 6.0
		root.add_child(_mesh(_box(Vector3(1.4, height, 1.4)), stone, Vector3(cos(angle) * 10.0, height * 0.5, sin(angle) * 10.0)))
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.4, height, 1.4)
		collision.shape = shape
		collision.position = Vector3(cos(angle) * 10.0, height * 0.5, sin(angle) * 10.0)
		body.add_child(collision)
	root.add_child(_mesh(_cylinder(10.5, 11.5, 1.2, 24), stone, Vector3(0, 0.2, 0)))
	var floor_collision := CollisionShape3D.new()
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = 11.5
	floor_shape.height = 1.2
	floor_collision.shape = floor_shape
	floor_collision.position.y = 0.2
	body.add_child(floor_collision)
	root.add_child(body)
	_limit_range(root, 3000.0)


func _add_eye_spires() -> void:
	for i in range(11):
		var angle := float(i) / 11.0 * TAU
		var direction := Vector3(cos(angle) * 0.36, 1.0, sin(angle) * 0.36).normalized()
		var root := _prop_parent(direction, 0.0)
		var height := 22.0 + i * 2.2
		var spire := _mesh(_cylinder(0.0, 2.0, height, 5), _material(Color("263239")), Vector3(0, height * 0.42, 0))
		spire.rotation.z = 0.22
		root.add_child(spire)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 1.6
		shape.height = height * 0.85
		collision.shape = shape
		collision.position.y = height * 0.42
		body.add_child(collision)
		root.add_child(body)
		_limit_range(root, 3000.0)


## 行星环：**一整片**扁平半透明圆盘，不是几条细铁圈。
##
## ⚠ 2026-11-11 用户：「这些环不好看，能不能搞好点」。
##   旧实现是 3 个 `TorusMesh` 叠起来，三个致命问题：
##     · TorusMesh 是**实心圆管**，不是薄片 —— 看起来就是橙色管子
##     · outer − inner 只有半径的 2%（约 16 米），等于一条细线
##     · 三条环各自倾斜 18°/21°/24°，于是像三根铁丝歪着套在球上
##   现在改成一个 annulus（环形平面）+ 径向分带着色器（见 planet_ring.gdshader）：
##   一整片、有缝、内缘外缘淡出的环面。
const RING_SHADER := preload("res://shaders/planet_ring.gdshader")


func _build_ring() -> void:
	var inner: float = radius * 1.34
	var outer: float = radius * 2.15
	var ring := MeshInstance3D.new()
	ring.name = "PlanetRing"
	ring.mesh = _annulus_mesh(inner, outer, 192)

	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	# 配色从行星主色派生，但**去饱和**——环是碎冰和尘埃，不该是饱和的橙。
	#
	# ⚠ 2026-11-11 调暗一轮：第一版环偏亮偏白，比星球本体还抢眼，
	#   尤其玄渊星（近黑）配亮白环反差过大。整体压暗、透明度也降一点，
	#   让环退到星球后面当背景。暗色行星（玄渊/缄默）再额外压一档。
	var is_dark_planet: bool = kind in ["xuanyuan", "jianmo"]
	var light_col: Color = Color("b8b2a8").lerp(accent_color.lightened(0.35), 0.30)
	var dark_col: Color = Color("4a4642").lerp(accent_color.darkened(0.35), 0.22)
	if is_dark_planet:
		light_col = light_col.darkened(0.28)
		dark_col = dark_col.darkened(0.25)
	mat.set_shader_parameter("ring_light", Vector3(light_col.r, light_col.g, light_col.b))
	mat.set_shader_parameter("ring_dark", Vector3(dark_col.r, dark_col.g, dark_col.b))
	mat.set_shader_parameter("base_alpha", 0.52 if is_dark_planet else 0.64)
	mat.set_shader_parameter("inner_fade", 0.09)
	mat.set_shader_parameter("outer_fade", 0.26)
	mat.set_shader_parameter("seed", float(abs(planet_id.hash()) % 977) * 0.137)
	ring.material_override = mat

	# 整个环面**统一倾角**（不再每条各转一个角度），略绕 Y 轴错开让边缘不总正对镜头
	ring.rotation_degrees = Vector3(22.0, 14.0, 8.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring_node = ring


## 生成一个扁平圆环面（annulus）：法线朝 +Y，UV 的 v = 径向 0→1。
##
## 为什么不用 TorusMesh：那是**有截面厚度的圆管**，从侧面看是一根管子；
## 行星环在视觉上必须是一张零厚度的薄片。
func _annulus_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var c0: float = cos(a0)
		var s0: float = sin(a0)
		var c1: float = cos(a1)
		var s1: float = sin(a1)
		var in0 := Vector3(c0 * inner, 0.0, s0 * inner)
		var in1 := Vector3(c1 * inner, 0.0, s1 * inner)
		var out0 := Vector3(c0 * outer, 0.0, s0 * outer)
		var out1 := Vector3(c1 * outer, 0.0, s1 * outer)
		var u0: float = float(i) / float(segments)
		var u1: float = float(i + 1) / float(segments)
		# 两个三角组成一个环形四边形；法线统一朝上
		_annulus_tri(st, in0, out0, out1,
			Vector2(u0, 0.0), Vector2(u0, 1.0), Vector2(u1, 1.0))
		_annulus_tri(st, in0, out1, in1,
			Vector2(u0, 0.0), Vector2(u1, 1.0), Vector2(u1, 0.0))
	return st.commit()


func _annulus_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(Vector3.UP)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


func _build_water() -> void:
	water_shell = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	water_shell.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.5, 0.62, 0.32)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.12
	material.metallic = 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_shell.material_override = material
	water_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water_shell)
	_update_water()


func _update_water() -> void:
	if water_shell == null:
		return
	var t: float = game.elapsed if game != null else 0.0
	var loop_length: float = float(game.LOOP_DURATION) if game != null else 1020.0
	var phase := clampf(t / loop_length, 0.0, 1.0)
	var level := lerpf(-21.0, 1.5, smoothstep(0.0, 1.0, phase))
	level += sin(t * 0.018) * 0.7
	var sea_radius := site_height + level
	water_shell.scale = Vector3.ONE * sea_radius
	water_shell.position = Vector3.ZERO


func _process(_delta: float) -> void:
	if game != null:
		_update_orbit()
		_update_water()
		if not terrain_collision_done:
			# 飞船或玩家进入 4 倍半径就建地形碰撞，落地前早就建好。
			var limit := radius * 4.0
			var player_close: bool = game.player != null and global_position.distance_to(game.player.global_position) < limit
			var ship_close: bool = game.ship != null and global_position.distance_to(game.ship.global_position) < limit
			if player_close or ship_close:
				_ensure_terrain_collision()
	if clouds != null:
		clouds.rotation.y += _delta * 0.002


## 垂直起伏幅度（米）。⚠ 2026-11-11 轨道 ×10 之后这里也 ×10，
## 否则星系拉大后这段起伏会缩成几乎一条平线（相对尺度）。
const ORBIT_WOBBLE := 500.0


func _update_orbit() -> void:
	var t: float = game.elapsed if game != null else 0.0
	var angle := orbit_phase + orbit_speed * t
	position = Vector3(cos(angle) * orbit_radius, orbit_height + sin(angle * 1.7) * ORBIT_WOBBLE, sin(angle) * orbit_radius)


## 行星此刻的公转速度（米/秒，世界坐标）。
##
## 就是 `_update_orbit` 里那条轨迹对时间的导数：
##   p = (cos a·R, h + sin(1.7a)·W, sin a·R)，  a = phase + speed·t，W = ORBIT_WOBBLE
##   v = (−sin a·R·ω, cos(1.7a)·W·1.7·ω, cos a·R·ω)
##
## 为什么不直接拿两帧位置差去近似：`_process` 的 delta 会抖，
## 而且行星每秒只走 10～50 米，差分出来的噪声比信号还大。
## 解析式既准确又和 `elapsed` 严格同步。
##
## 飞船侧要用它的两个地方：
##   · 自动航行把「期望速度」加上它 —— 否则飞船是在追一个会跑的靶子，
##     落到地面附近时相对速度全被行星的公转抵掉，剖面就白算了；
##   · 撞击判定用「相对地面」的速度 —— 一颗以 50 m/s 掠过你的行星
##     扫过一艘静止的飞船，那是真撞击，不能因为飞船自己没动就免责。
func orbital_velocity() -> Vector3:
	var t: float = game.elapsed if game != null else 0.0
	var angle := orbit_phase + orbit_speed * t
	var w := orbit_speed
	return Vector3(
		-sin(angle) * orbit_radius * w,
		cos(angle * 1.7) * ORBIT_WOBBLE * 1.7 * w,
		cos(angle) * orbit_radius * w)


func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = Color(color, 1.0)
		material.emission_energy_multiplier = emission
	return material


func _mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance


func _sphere_mesh(radius: float, segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
