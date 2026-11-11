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
	if kind == "cangbo":
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
	cave_direction = (site_direction + tangent * (distance / radius)).normalized()
	cave_hole_angle = cave_mouth_radius / radius


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
const LUX_LAT_BINS := 96
const LUX_LON_BINS := 192
## Lux3D 模型的挂载根（缩放后挂在行星下）。
var _lux_root: Node3D


func _build_surface() -> void:
	if lux_model_path != "":
		if _build_lux3d_surface():
			return
		push_warning("Lux3D 星球加载失败，退回程序化地形：%s" % lux_model_path)
	surface = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
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
	# ── Lux3D 分支：模型可能拆成多个 MeshInstance3D，逐个建碰撞 ──
	if _lux_root != null:
		terrain_collision_done = true
		var body := StaticBody3D.new()
		body.name = "TerrainCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var inv: Transform3D = global_transform.affine_inverse()
		var count := 0
		for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
			var node := mi as MeshInstance3D
			if node.mesh == null:
				continue
			var shape := node.mesh.create_trimesh_shape()
			if shape == null:
				continue
			var col := CollisionShape3D.new()
			col.shape = shape
			# 子网格相对**本行星**的变换（碰撞体挂在行星下）
			col.transform = inv * node.global_transform
			body.add_child(col)
			count += 1
		if count > 0:
			add_child(body)
		else:
			push_warning("Lux3D 行星没有任何可建碰撞的子网格：%s" % planet_id)
		return
	if surface == null or surface.mesh == null:
		return
	terrain_collision_done = true
	var body2 := StaticBody3D.new()
	body2.name = "TerrainCollision"
	body2.collision_layer = 1
	body2.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = surface.mesh.create_trimesh_shape()
	body2.add_child(collision)
	add_child(body2)


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
	map = _median_filter_lux(map, 2, 2)
	_lux_height_map = map
	_lux_height_ready = true

	# ── 缩放并挂上模型（模型单位 → 米）──
	_lux_root.scale = Vector3.ONE * to_world
	# surface 变量指向第一个网格，供外部只读引用（碰撞走 _lux_root 分支）
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		surface = mi as MeshInstance3D
		break
	return true


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


## 按方向双线性插值取 Lux3D 高度表里的值。
func _sample_lux_height(dir: Vector3) -> float:
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
	var v00: float = _lux_height_map[y0 * LUX_LON_BINS + x0]
	var v01: float = _lux_height_map[y0 * LUX_LON_BINS + x1]
	var v10: float = _lux_height_map[y1 * LUX_LON_BINS + x0]
	var v11: float = _lux_height_map[y1 * LUX_LON_BINS + x1]
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


func _build_atmosphere() -> void:
	# 硫坞星 / 磐砂星 / 缄默星 不做大气壳：硫雾用灯光表现，光壳在近距离会露出低模面片。
	if kind not in ["qinglan", "cangbo", "zheya", "baiyao", "taiyuan"]:
		return
	atmosphere = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius * 1.035
	sphere.height = radius * 2.07
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
	if kind in ["qinglan", "cangbo"]:
		clouds = MeshInstance3D.new()
		var cloud_sphere := SphereMesh.new()
		cloud_sphere.radius = radius * 1.012
		cloud_sphere.height = radius * 2.024
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


func _surface_parent(direction: Vector3, altitude: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = surface_position(direction, altitude)
	root.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	return root


func _add_tree(direction: Vector3, _collidable := false) -> void:
	var size := rng.randf_range(1.0, 2.25)
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


func _flush_vegetation() -> void:
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
	var rotation := Basis.from_euler(Vector3(rng.randf() * PI, rng.randf() * PI, rng.randf() * PI))
	var scale := Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.7, 1.4), rng.randf_range(0.7, 1.3)) * size
	var transform := Transform3D(rotation.scaled(scale), surface_position(direction, altitude + size * 0.12))
	if not rock_queue.has(color):
		rock_queue[color] = []
	rock_queue[color].append(transform)


func _add_basalt(direction: Vector3) -> void:
	var root := _surface_parent(direction, 0.0)
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
	var root := _surface_parent(direction, altitude)
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
	var root := _surface_parent(direction, -1.0)
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
	var root := _surface_parent(Vector3.UP, -2.5)
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
	var root := _surface_parent(direction, 0.0)
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
		var root := _surface_parent(direction, 0.0)
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


func _build_ring() -> void:
	for i in range(3):
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = radius * (1.35 + i * 0.09)
		mesh.outer_radius = radius * (1.37 + i * 0.09)
		mesh.rings = 96
		mesh.ring_segments = 8
		ring.mesh = mesh
		ring.material_override = _material(accent_color.darkened(0.35), 0.45)
		ring.rotation_degrees = Vector3(18 + i * 3, i * 11, 24)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)


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
