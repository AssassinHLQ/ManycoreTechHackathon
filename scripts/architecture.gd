extends RefCounted

## 程序化地标建筑。所有尺寸均按「半径 400 米」的设计尺度写成米。
##
## ⚠ 2026-11-11 改：整棵子树现在由 `planet._prop_parent()` 按
##   `radius / 400` 统一放大（现在 ×5），所以这里的数字**不用动** ——
##   写 13 米的观测塔，在半径 2000 米的星球上就是 65 米高。
## _surface_parent() 返回的局部空间中，Y 轴为地表法线。

const UndergroundScript = preload("res://scripts/underground.gd")


static func build(planet, kind: String) -> void:
	if not ["qinglan", "zheya", "cangbo", "xuanjing", "xuanyuan",
			"baiyao", "pansha", "taiyuan", "liuwu", "jianmo"].has(kind):
		return

	var direction := Vector3.UP
	var altitude := -0.3
	if kind == "qinglan":
		direction = Vector3(-0.06, 1.0, -0.04).normalized()
	elif kind == "xuanjing":
		altitude = 0.8
	elif kind == "xuanyuan":
		altitude = -0.05

	var root: Node3D = planet._prop_parent(direction, altitude)
	if root == null:
		return
	root.name = "Architecture_%s" % kind.capitalize()

	match kind:
		"qinglan":
			_build_home(root, planet)
		"zheya":
			_build_ember(root, planet)
		"cangbo":
			_build_tide(root, planet)
		"xuanjing":
			_build_shard(root, planet)
		"xuanyuan":
			_build_eye(root, planet)
		"baiyao":
			_build_baiyao(root, planet)
		"pansha":
			_build_pansha(root, planet)
		"taiyuan":
			_build_taiyuan(root, planet)
		"liuwu":
			_build_liuwu(root, planet)
		"jianmo":
			_build_jianmo(root, planet)
	_add_collision(root, kind, planet)
	_detail_pass(root, kind, planet)
	_limit_range(root, 1500.0)


static func _limit_range(node: Node, end: float) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = end
	for child in node.get_children():
		_limit_range(child, end)


# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# HOME：风车村与引水渠（可推门进入的风车塔内部）。
static func _build_home(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var stone = planet._material(Color("59616a"))
	var pale_stone = planet._material(Color("89918f"))
	var wood = planet._material(Color("765038"))
	var dark_wood = planet._material(Color("352b28"))
	var metal = planet._material(Color("39434c"))
	var brass = planet._material(Color("b88a46"))
	var roof = planet._material(Color("324d52"))
	var glass = planet._material(Color("213f52"), 0.35)
	var warm_glow = planet._material(Color("ffc46b"), 1.35)
	var accent_glow = planet._material(accent.lightened(0.2), 1.15)

	# 分层石台与一圈不规则感矮护石。
	_cyl(root, 13.0, 14.0, 1.2, Vector3(0, 0.6, 0), stone, 32)
	_cyl(root, 12.0, 12.6, 0.55, Vector3(0, 1.48, 0), pale_stone, 32)
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var block := _box(root, Vector3(2.2, 0.8, 1.0), Vector3(cos(angle) * 11.5, 2.0, sin(angle) * 11.5), stone)
		block.rotation.y = -angle

	# 石砌底层（留出入口门洞）、木构上层、金属箍带与压扁的穹顶。
	_wall_ring(root, UndergroundScript.HOME_WALL_RADIUS, UndergroundScript.HOME_WALL_HEIGHT, UndergroundScript.HOME_WALL_CENTER_Y, UndergroundScript.HOME_WALL_SEGMENTS, stone, UndergroundScript.HOME_DOOR_ANGLE, UndergroundScript.HOME_DOOR_HALF, 0.62)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.34, 3.5, 0.34), Vector3(side * 1.45, 3.55, 6.35), dark_wood)
	_box(root, Vector3(3.4, 0.42, 0.42), Vector3(0, 5.32, 6.35), dark_wood)
	_cyl(root, 5.7, 5.9, 4.8, Vector3(0, 8.6, 0), wood, 16)
	_ring(root, 5.55, 6.05, Vector3(0, 6.25, 0), dark_wood)
	_ring(root, 5.45, 5.95, Vector3(0, 10.8, 0), brass)
	_cyl(root, 6.1, 6.3, 1.1, Vector3(0, 11.55, 0), dark_wood, 24)
	# 塔顶与风车转子：剪影是塔式风车，不再是带大口径镜筒的观测台。
	_cyl(root, 6.3, 5.4, 2.3, Vector3(0, 12.35, 0), dark_wood, 24)
	_cyl(root, 5.2, 6.35, 0.4, Vector3(0, 13.6, 0), roof, 24)
	_sphere(root, 0.34, Vector3(0, 13.95, 0), brass)
	var rotor_hub := Vector3(0.0, 11.6, 7.2)
	var hub := _cyl(root, 0.5, 0.6, 1.2, rotor_hub, metal, 12)
	hub.rotation.x = PI * 0.5
	# 六片叶板伸出塔顶轮廓（半径 2.9 + 半长 2.6 ≈ 5.5 米），从任何角度都能认出是风车。
	for i in range(6):
		var blade_angle := TAU * float(i) / 6.0
		var blade := _box(root, Vector3(1.45, 5.2, 0.26),
			rotor_hub + Vector3(sin(blade_angle) * 2.9, cos(blade_angle) * 2.9, 0.0), pale_stone)
		blade.rotation.z = -blade_angle
		_beam(root, rotor_hub, rotor_hub + Vector3(sin(blade_angle) * 2.9, cos(blade_angle) * 2.9, 0.0), 0.16, brass, 4)
	_box(root, Vector3(0.22, 1.1, 2.8), rotor_hub + Vector3(0.0, 4.9, -3.9), dark_wood)
	_beam(root, rotor_hub, Vector3(0.0, 11.2, 0.0), 0.46, metal, 8)

	# 引水渠：两道平行石梁 + 支承立柱，从平台边缘一路引到地面（村子的取水设施）。
	var aqueduct_dir := Vector3(0.66, 0.0, 0.75).normalized()
	var aqueduct_top := Vector3(aqueduct_dir.x * 11.6, 3.3, aqueduct_dir.z * 11.6)
	var aqueduct_end := aqueduct_dir * 26.0
	aqueduct_end.y = _ground_y(root, planet, aqueduct_end.x, aqueduct_end.z) + 1.2
	for side in [-1.0, 1.0]:
		var lateral: Vector3 = Vector3(-aqueduct_dir.z, 0.0, aqueduct_dir.x) * side * 0.55
		_beam(root, aqueduct_top + lateral, aqueduct_end + lateral, 0.22, pale_stone, 6)
	for i in range(3):
		var t := 0.3 + float(i) * 0.25
		var top: Vector3 = aqueduct_top.lerp(aqueduct_end, t)
		var ground: float = _ground_y(root, planet, top.x, top.z)
		var height: float = maxf(0.6, top.y - ground)
		_cyl(root, 0.34, 0.46, height, Vector3(top.x, ground + height * 0.5, top.z), stone, 10)

	# 三座小木屋，构成 Observatory 脚下的村落尺度参照。
	for i in range(3):
		var angle := TAU * (float(i) / 3.0 + 0.09)
		var center := Vector3(cos(angle) * 18.0, 0, sin(angle) * 18.0)
		var hut := Node3D.new()
		root.add_child(hut)
		hut.position = Vector3(center.x, _ground_y(root, planet, center.x, center.z) - 0.1, center.z)
		hut.rotation.y = -angle + PI * 0.5
		_box(hut, Vector3(4.4, 3.4, 4.0), Vector3(0, 1.8, 0), wood)
		var cap := _cyl(hut, 0.0, 3.6, 2.5, Vector3(0, 4.65, 0), roof, 4)
		cap.rotation.y = PI * 0.25
		_box(hut, Vector3(1.1, 2.1, 0.25), Vector3(0, 1.45, 2.05), dark_wood)
		_box(hut, Vector3(0.9, 0.8, 0.18), Vector3(1.35, 2.1, 2.08), warm_glow)

	# 灯笼均只有立柱、发光灯罩和实际光源三个节点。
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var p := Vector3(cos(angle) * 14.8, 0, sin(angle) * 14.8)
		p.y = _ground_y(root, planet, p.x, p.z)
		_cyl(root, 0.11, 0.16, 3.2, p + Vector3(0, 1.6, 0), dark_wood, 8)
		_box(root, Vector3(0.65, 0.9, 0.65), p + Vector3(0, 3.35, 0), warm_glow if i % 2 == 0 else accent_glow)
		_light(root, p + Vector3(0, 3.4, 0), Color("ffc875") if i % 2 == 0 else accent, 1.3, 8.0)

	# 村落生活细节：石板路、木箱、油桶、长椅与连接缆线。
	for i in range(9):
		var slab_x := sin(i * 0.7) * 0.45
		var slab_z := 15.4 + i * 1.55
		var slab := _box(root, Vector3(3.8, 0.16, 1.3), Vector3(slab_x, _ground_y(root, planet, slab_x, slab_z) + 0.06, slab_z), stone if i % 2 == 0 else pale_stone)
		slab.rotation.y = sin(i * 0.9) * 0.09
	for i in range(3):
		var crate_pos := Vector3(8.7 + i * 1.05, 0, 5.2 + (i % 2) * 0.9)
		crate_pos.y = _ground_y(root, planet, crate_pos.x, crate_pos.z) + 0.58
		var crate := _box(root, Vector3(1.15, 1.15, 1.15), crate_pos, wood)
		crate.rotation.y = 0.18 * i
		_box(root, Vector3(1.24, 0.12, 1.24), crate_pos, dark_wood).rotation.y = 0.18 * i
	for i in range(2):
		var barrel_pos := Vector3(7.4 + i * 1.15, 0, 3.4)
		barrel_pos.y = _ground_y(root, planet, barrel_pos.x, barrel_pos.z) + 0.55
		_cyl(root, 0.42, 0.48, 1.1, barrel_pos, dark_wood, 10)
		_ring(root, 0.44, 0.5, barrel_pos + Vector3(0, 0.3, 0), brass)
		_ring(root, 0.44, 0.5, barrel_pos - Vector3(0, 0.3, 0), brass)
	var bench_y: float = _ground_y(root, planet, -8.2, 7.0)
	_box(root, Vector3(2.6, 0.16, 0.75), Vector3(-8.2, bench_y + 0.72, 7.0), wood)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.16, 0.72, 0.68), Vector3(-8.2 + side * 1.0, bench_y + 0.36, 7.0), dark_wood)
	_beam(root, Vector3(0, 12.5, 0), Vector3(9.5, 3.5, 4.0), 0.025, brass, 5)
	_beam(root, Vector3(0, 12.5, 0), Vector3(-9.5, 3.5, -4.5), 0.025, brass, 5)

	# 平台木护栏、塔身立柱和穹顶金属箍，增加可读的结构层次。
	for i in range(18):
		var angle := TAU * float(i) / 18.0
		var post := Vector3(cos(angle) * 12.35, 2.55, sin(angle) * 12.35)
		_cyl(root, 0.1, 0.13, 1.7, post, dark_wood, 6)
	_ring(root, 12.2, 12.38, Vector3(0, 3.35, 0), metal)
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var rib := _box(root, Vector3(0.24, 4.9, 0.24), Vector3(cos(angle) * 5.92, 8.55, sin(angle) * 5.92), dark_wood)
		rib.rotation.y = -angle
	# 原来观测台的黄铜"皇冠"已移除：塔顶只保留盖板与风车转子，避免与转子在剪影上混在一起。
	for i in range(6):
		var angle := TAU * float(i) / 6.0 + 0.25
		var brace := _box(root, Vector3(0.6, 3.8, 0.9), Vector3(cos(angle) * 6.9, 2.0, sin(angle) * 6.9), stone)
		brace.rotation.y = -angle
	_box(root, Vector3(2.8, 0.5, 0.18), Vector3(0, 5.55, 6.9), dark_wood)
	_box(root, Vector3(2.2, 0.16, 0.1), Vector3(0, 5.55, 7.0), warm_glow)
	for i in range(3):
		var angle := TAU * (float(i) / 3.0 + 0.22)
		var window := _box(root, Vector3(0.9, 1.3, 0.08), Vector3(cos(angle) * 6.9, 4.6, sin(angle) * 6.9), warm_glow)
		window.rotation.y = -angle
	UndergroundScript.build_interior(root, planet, "qinglan")


# -----------------------------------------------------------------------------
# EMBER：盐谷观测环——盐柱阵列、卤水池间歇喷泉与分段断裂的观测巨环。
# -----------------------------------------------------------------------------
static func _build_ember(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var basalt = planet._material(Color("6d675b"))
	var basalt_edge = planet._material(Color("8b8574"))
	var iron = planet._material(Color("4a4a46"))
	var copper = planet._material(Color("b98a4e"))
	var brine = planet._material(Color("ffd08a"), 1.6)
	var core_mat = planet._material(Color("ffcf8a"), 3.4)

	_cyl(root, 12.5, 14.0, 1.4, Vector3(0, 0.7, 0), basalt, 12)
	_cyl(root, 10.8, 12.2, 1.0, Vector3(0, 1.85, 0), basalt_edge, 12)
	_ring(root, 9.8, 10.5, Vector3(0, 2.4, 0), copper)

	# 八根厚重盐岩柱，柱头朝向中央核心。
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var p := Vector3(cos(angle) * 8.8, 0, sin(angle) * 8.8)
		_cyl(root, 1.35, 1.65, 0.8, p + Vector3(0, 2.8, 0), basalt_edge, 6)
		_cyl(root, 0.85, 1.15, 7.0, p + Vector3(0, 6.6, 0), basalt, 6)
		_cyl(root, 1.5, 1.0, 0.9, p + Vector3(0, 10.45, 0), copper, 6)

	# 多层盐台围出的卤水池，池心是仍在活动的间歇喷泉柱（取代原来的日核祭坛）。
	_cyl(root, 3.6, 4.5, 2.0, Vector3(0, 3.4, 0), basalt, 12)
	_cyl(root, 2.5, 3.2, 1.1, Vector3(0, 4.95, 0), copper, 16)
	_cyl(root, 2.2, 2.35, 0.5, Vector3(0, 5.55, 0), brine, 16)
	var plume := _cyl(root, 0.35, 1.5, 7.5, Vector3(0, 9.6, 0), brine, 10)
	plume.rotation.x = 0.04
	_sphere(root, 1.15, Vector3(0, 13.6, 0), core_mat)
	for i in range(3):
		var vapour := _ring(root, 1.6 + i * 1.1, 1.85 + i * 1.1, Vector3(0, 8.4 + i * 2.0, 0), brine)
		vapour.rotation = Vector3(0.12 * i, 0.0, 0.08 * i)
	_light(root, Vector3(0, 8.6, 0), Color("ffc98a"), 2.6, 20.0)

	# 巨环位于 XY 平面；缺段和浮游离块让轮廓明显残破。
	var ring_center := Vector3(0, 17.0, -4.0)
	var radius := 12.0
	var missing := [2, 3, 11, 17, 18]
	for i in range(26):
		if missing.has(i):
			continue
		var a := TAU * float(i) / 26.0
		var b := TAU * (float(i) + 0.88) / 26.0
		var pa := ring_center + Vector3(cos(a), sin(a), 0) * radius
		var pb := ring_center + Vector3(cos(b), sin(b), 0) * radius
		_beam(root, pa, pb, 0.66, copper if i % 4 == 0 else basalt_edge, 8)
	for i in range(4):
		var angle := TAU * (float(i) * 0.19 + 0.1)
		var shard := _box(root, Vector3(1.0, 2.4, 1.1), ring_center + Vector3(cos(angle) * 13.4, sin(angle) * 13.4, 0.5), basalt_edge)
		shard.rotation = Vector3(0.3, angle, angle + 0.4)

	# 四道卤水收集槽（取代太阳能板）与细天线：把喷泉带上来的卤水导向外圈。
	for i in range(4):
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -7.0 if i < 2 else 7.0
		var p := Vector3(side * 14.0, 0, z)
		_cyl(root, 0.22, 0.3, 3.4, p + Vector3(0, 1.7, 0), iron, 8)
		var trough := _box(root, Vector3(5.2, 0.5, 1.6), p + Vector3(0, 3.6, 0), copper)
		trough.rotation = Vector3(-0.16, 0.2 * side, 0.1 * side)
		var liquid := _box(root, Vector3(4.9, 0.14, 1.35), p + Vector3(0, 3.88, 0), brine)
		liquid.rotation = trough.rotation
	for i in range(3):
		var p := Vector3(-5.0 + i * 5.0, 2.4, 10.0)
		_cyl(root, 0.07, 0.16, 5.0 + i, p + Vector3(0, (5.0 + i) * 0.5, 0), iron, 8)
		_sphere(root, 0.28, p + Vector3(0, 5.0 + i, 0), brine)
	for i in range(3):
		var angle := TAU * float(i) / 3.0
		_light(root, Vector3(cos(angle) * 8.0, 4.0, sin(angle) * 8.0), Color("ffd6a0"), 1.2, 10.0)


# -----------------------------------------------------------------------------
# TIDE：高脚研究站、长廊桥、雷达和四组悬浮设备。
# -----------------------------------------------------------------------------
static func _build_tide(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var dark = planet._material(Color("2f3f4a"))
	var metal = planet._material(Color("8fa6b0"))
	var white = planet._material(Color("d8e9f0"))
	var deck = planet._material(Color("5c7480"))
	var glass = planet._material(Color("17485d"), 0.45)
	var glow = planet._material(accent.lightened(0.25), 2.5)
	var beacon = planet._material(Color("9fe8ff"), 1.6)

	# 六根高脚及海底基座。
	var feet := [Vector2(-6, -4), Vector2(0, -4), Vector2(6, -4), Vector2(-6, 4), Vector2(0, 4), Vector2(6, 4)]
	for foot in feet:
		var p := Vector3(foot.x, 0, foot.y)
		_cyl(root, 0.38, 0.55, 11.0, p + Vector3(0, 5.5, 0), dark, 12)
		_cyl(root, 0.9, 1.15, 0.7, p + Vector3(0, 0.35, 0), metal, 12)
	for i in range(3):
		var x := -6.0 + i * 6.0
		_beam(root, Vector3(x, 2.0, -4), Vector3(x, 9.5, 4), 0.17, metal, 8)
		_beam(root, Vector3(x, 2.0, 4), Vector3(x, 9.5, -4), 0.17, metal, 8)
	_beam(root, Vector3(-6, 3.0, -4), Vector3(6, 9.0, -4), 0.18, metal, 8)
	_beam(root, Vector3(-6, 9.0, 4), Vector3(6, 3.0, 4), 0.18, metal, 8)

	# 主平台与上下两层实验舱。主舱外壳由室内构建脚本生成，正面留门洞。
	_box(root, Vector3(18, 1.0, 14), Vector3(0, 11.0, 0), deck)
	_box(root, Vector3(15.5, 0.45, 11.5), Vector3(0, 11.7, 0), white)
	_box(root, Vector3(9.0, 0.9, 8.0), Vector3(-1.5, 11.6, 0), white)
	_box(root, Vector3(5.0, 3.8, 6.0), Vector3(5.2, 13.85, 0), dark)
	_box(root, Vector3(9.8, 0.45, 8.8), Vector3(-1.5, 17.15, 0), dark)
	_box(root, Vector3(5.7, 0.4, 6.7), Vector3(5.2, 15.95, 0), metal)
	for i in range(4):
		_box(root, Vector3(1.5, 1.35, 0.16), Vector3(-4.6 + i * 2.1, 14.8, 4.06), glass)
		_box(root, Vector3(1.5, 0.18, 0.2), Vector3(-4.6 + i * 2.1, 14.0, 4.1), glow)

	# 廊桥面板、分道木板、护栏及末端观测平台。
	_box(root, Vector3(21.0, 0.65, 3.4), Vector3(18.5, 11.0, 0), dark)
	_box(root, Vector3(5.5, 0.8, 6.5), Vector3(30.0, 11.0, 0), deck)
	for i in range(11):
		_box(root, Vector3(1.65, 0.18, 3.15), Vector3(9.2 + i * 1.85, 11.43, 0), metal)
	for side in [-1.0, 1.0]:
		_beam(root, Vector3(9, 12.6, side * 1.6), Vector3(31.5, 12.6, side * 1.6), 0.08, white, 8)
		for i in range(4):
			_cyl(root, 0.07, 0.07, 1.4, Vector3(11.0 + i * 6.0, 12.0, side * 1.6), white, 8)
	for z in [-2.4, 2.4]:
		_beam(root, Vector3(27.5, 10.6, z), Vector3(24.0, 3.0, z), 0.2, dark, 8)

	# 雷达桅杆、扁平碟面、馈源和 VHF 天线。
	_cyl(root, 0.22, 0.42, 7.0, Vector3(-2.0, 20.7, 0), dark, 12)
	_cyl(root, 1.6, 2.0, 0.45, Vector3(-2.0, 17.65, 0), metal, 16)
	var dish_dir := Vector3(0.4, 0.82, 0.2).normalized()
	var dish := _sphere(root, 2.35, Vector3(-2.0, 24.0, 0), white)
	dish.scale = Vector3(1.0, 0.24, 1.0)
	dish.quaternion = Quaternion(Vector3.UP, dish_dir)
	_beam(root, Vector3(-2, 24, 0), Vector3(-2, 24, 0) + dish_dir * 2.0, 0.07, dark, 8)
	_sphere(root, 0.22, Vector3(-2, 24, 0) + dish_dir * 2.0, beacon)
	_cyl(root, 0.04, 0.09, 5.0, Vector3(5.5, 18.5, -1.8), metal, 8)
	_sphere(root, 0.18, Vector3(5.5, 21.0, -1.8), glow)

	# 悬浮探测设备：核心、水平稳定环和冷色灯。
	var drones := [Vector3(-13, 16, -6), Vector3(-12, 20, 7), Vector3(12, 18, -8), Vector3(25, 16, 7)]
	for i in range(drones.size()):
		var p: Vector3 = drones[i]
		_sphere(root, 0.8, p, dark)
		_ring(root, 1.15, 1.4, p, glow)
		_cyl(root, 0.0, 0.35, 1.2, p + Vector3(0, -1.0, 0), metal, 8)
		_light(root, p, accent if i % 2 == 0 else Color("bfeaff"), 1.0, 7.0)
	UndergroundScript.build_interior(root, planet, "cangbo")


# -----------------------------------------------------------------------------
# SHARD：环站残骸带——断裂的舱段骨架、被撕开的反应堆、散落舱板与磁性余辉。
# -----------------------------------------------------------------------------
static func _build_shard(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var rock = planet._material(Color("3f4249"))
	var stone = planet._material(Color("7d818a"))
	var pale = planet._material(Color("b3b7bf"))
	var metal = planet._material(Color("4f545c"))
	var ore = planet._material(Color("ffab5e"), 1.2)
	var core_glow = planet._material(accent.lightened(0.25), 2.8)

	# 主岛下方收束成悬浮岩锥，上方为三层神殿基座。
	_cyl(root, 10.5, 2.2, 6.5, Vector3(0, 5.8, 0), rock, 9)
	_cyl(root, 9.5, 10.0, 1.0, Vector3(0, 9.1, 0), stone, 16)
	_cyl(root, 8.0, 8.6, 0.8, Vector3(0, 10.0, 0), pale, 16)
	_ring(root, 7.3, 7.75, Vector3(0, 10.5, 0), metal)

	# 八根骨架：长度、倾角、断口各不相同，断裂端有外翻的金属板与甩出的缆束。
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var p := Vector3(cos(angle) * 6.2, 0, sin(angle) * 6.2)
		var height := 8.5 - float(i % 4) * 1.5
		var broken: bool = i % 3 != 0
		var lean_amount: float = (0.06 + float(i % 3) * 0.05) if broken else 0.0
		var lean := Vector3(cos(angle), 0.0, sin(angle)) * lean_amount
		_cyl(root, 0.85, 1.05, 0.65, p + Vector3(0, 10.85, 0), pale, 8)
		var strut := _cyl(root, 0.48, 0.62, height, p + Vector3(0, 10.85 + height * 0.5, 0), stone, 12)
		strut.rotation = Vector3(lean.z * height * 0.5, 0.0, -lean.x * height * 0.5)
		if broken:
			var tear := _box(root, Vector3(1.6, 0.32, 1.6), p + Vector3(lean.x * height, 10.85 + height, lean.z * height), metal)
			tear.rotation = Vector3(lean.z * 3.0, angle, -lean.x * 3.0)
			_beam(root, p + Vector3(0, 10.85 + height * 0.6, 0),
				p + Vector3(lean.x * height * 2.4, 10.5 + height * 0.85, lean.z * height * 2.4), 0.08, pale, 4)
		else:
			_cyl(root, 1.0, 0.7, 0.75, p + Vector3(0, 10.85 + height + 0.4, 0), pale, 8)
	# 顶圈歪斜，只剩两处横梁还连着。
	var truss := _ring(root, 6.0, 6.8, Vector3(0, 19.4, 0), metal)
	truss.rotation = Vector3(0.14, 0.0, -0.09)
	for i in range(2):
		var angle := TAU * float(i) / 2.0 + 0.4
		_beam(root, Vector3(cos(angle) * 4.4, 19.2, sin(angle) * 4.4),
			Vector3(-cos(angle) * 4.4, 19.6, -sin(angle) * 4.4), 0.26, pale, 8)

	# 中央矿核。
	_cyl(root, 2.4, 3.0, 1.0, Vector3(0, 11.0, 0), metal, 8)
	_cyl(root, 1.8, 2.2, 0.8, Vector3(0, 11.9, 0), pale, 8)
	# 反应堆外壳被撕开：外翻肋板之间露出仍在发光的核心环。
	var shell := _cyl(root, 2.0, 1.3, 5.4, Vector3(0, 15.2, 0), stone, 7)
	shell.rotation = Vector3(0.09, 0.0, -0.06)
	for i in range(5):
		var rib_angle := TAU * float(i) / 5.0 + 0.3
		var rib := _box(root, Vector3(0.34, 4.6, 1.4), Vector3(cos(rib_angle) * 2.1, 15.4, sin(rib_angle) * 2.1), metal)
		rib.rotation = Vector3(0.12 * cos(rib_angle), -rib_angle, 0.12 * sin(rib_angle))
	var core_ring := _ring(root, 1.5, 1.9, Vector3(0, 13.4, 0), core_glow)
	core_ring.rotation = Vector3(0.16, 0.0, 0.1)
	_light(root, Vector3(0, 14.6, 0), accent, 1.6, 9.0)

	# 背后的双巨环强调剪影。
	var halo := _ring(root, 12.8, 13.5, Vector3(0, 20.0, -4.5), metal)
	halo.rotation = Vector3(PI * 0.5, 0.12, 0.0)
	var inner_halo := _ring(root, 10.7, 11.05, Vector3(0, 20.0, -4.2), ore)
	inner_halo.rotation = Vector3(PI * 0.5, -0.1, 0.0)

	# 悬空阶梯从低处逐级升至主岛。
	for i in range(10):
		var step := _box(root, Vector3(4.0, 0.55, 1.65), Vector3(0, 1.0 + i * 0.86, 19.0 - i * 1.15), stone if i % 2 == 0 else pale)
		step.rotation.y = sin(float(i) * 1.7) * 0.08

	# 四块旁侧碎岛及其晶簇。
	var islands := [Vector3(-14, 7, -3), Vector3(13, 11, 1), Vector3(-11, 15, 8), Vector3(11, 5, -10)]
	for i in range(islands.size()):
		var p: Vector3 = islands[i]
		_cyl(root, 3.2, 0.55, 3.8, p, rock, 7)
		var hull := _box(root, Vector3(2.6, 0.5, 1.8), p + Vector3(0, 2.7, 0), metal if i % 2 == 0 else stone)
		hull.rotation = Vector3(0.18 * i, 0.7 * i, 0.12 * i)
		_beam(root, p, p + Vector3(0.4 * i - 0.6, 3.6, 0.3 * i), 0.3, pale, 6)
		if i % 2 == 0:
			var beacon := _ring(root, 1.1, 1.35, p + Vector3(0, 3.7, 0), core_glow)
			beacon.rotation = Vector3(0.2, 0.0, 0.15)
	for i in range(7):
		var angle := TAU * float(i) / 7.0
		var p := Vector3(cos(angle) * 8.5, 10.0 + (i % 3), sin(angle) * 8.5)
		var plate := _box(root, Vector3(0.5 + (i % 2) * 0.3, 2.4 + (i % 3), 1.2), p, metal if i % 2 == 0 else rock)
		plate.rotation = Vector3(cos(angle) * 0.5, angle * 1.7, sin(angle) * 0.4)
	for i in range(4):
		var fragment := _box(root, Vector3(1.1, 1.8, 0.9), Vector3(-16.0 + i * 10.0, 19.0 + i, -7.0 + i * 2.0), rock)
		fragment.rotation = Vector3(i * 0.3, i * 0.7, i * 0.2)
	_light(root, Vector3(0, 15, 0), accent, 2.5, 22.0)
	_light(root, Vector3(-12, 13, 5), Color("ffab5e"), 1.2, 12.0)
	_light(root, Vector3(12, 12, 0), Color("ffd0a0"), 1.2, 12.0)


# -----------------------------------------------------------------------------
# EYE：黑金外星巨门、坍缩前兆、四重同心环与浮石阵。
# -----------------------------------------------------------------------------
static func _build_eye(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var black = planet._material(Color("101218"))
	var obsidian = planet._material(Color("24222c"))
	var gold = planet._material(Color("b58a42"))
	var old_gold = planet._material(Color("6c5737"))
	var glow = planet._material(accent.lightened(0.2), 3.2)
	var white_hot = planet._material(Color("e9f5ff"), 4.0)

	# 黑金阶梯与门前长台阶。
	_cyl(root, 15.0, 16.0, 1.0, Vector3(0, 0.5, 0), black, 12)
	_cyl(root, 13.0, 14.0, 0.8, Vector3(0, 1.35, 0), obsidian, 12)
	_ring(root, 11.8, 12.35, Vector3(0, 1.85, 0), gold)
	for i in range(8):
		_box(root, Vector3(8.0 - i * 0.25, 0.45, 1.8), Vector3(0, 0.35 + i * 0.35, 20.0 - i * 1.45), obsidian if i % 2 == 0 else black)

	# 两根分节巨柱、金色嵌线和顶部尖塔。
	for side in [-1.0, 1.0]:
		var x: float = side * 10.0
		_box(root, Vector3(5.0, 2.0, 5.0), Vector3(x, 2.8, 0), black)
		_box(root, Vector3(3.8, 23.0, 3.8), Vector3(x, 15.0, 0), obsidian)
		_box(root, Vector3(4.5, 1.0, 4.5), Vector3(x, 26.7, 0), gold)
		_cyl(root, 0.0, 2.4, 5.5, Vector3(x, 30.0, 0), black, 4)
		_box(root, Vector3(0.3, 19.0, 0.18), Vector3(x - side * 1.15, 15.0, 1.98), gold)
		_box(root, Vector3(0.3, 19.0, 0.18), Vector3(x + side * 1.15, 15.0, 1.98), gold)
		for i in range(3):
			_box(root, Vector3(1.5, 0.3, 0.22), Vector3(x, 9.0 + i * 6.0, 2.0), glow)

	# 门楣、冠状构件与中央悬挂件。
	_box(root, Vector3(23.0, 3.0, 4.0), Vector3(0, 27.0, 0), black)
	_box(root, Vector3(19.0, 0.45, 4.2), Vector3(0, 25.8, 0), gold)
	_cyl(root, 0.0, 2.0, 4.0, Vector3(0, 30.2, 0), gold, 4)
	_beam(root, Vector3(0, 26.0, 0), Vector3(0, 22.5, 0), 0.12, glow, 8)

	# 坍缩暗核和四个垂直同心环；正面朝局部 +Z。
	var eye_center := Vector3(0, 16.0, 0.2)
	var radii := [4.2, 5.8, 7.4, 9.0]
	for i in range(radii.size()):
		var ring := _ring(root, radii[i] - 0.22, radii[i] + 0.22, eye_center + Vector3(0, 0, -0.35 * i), gold if i % 2 == 0 else old_gold)
		ring.rotation = Vector3(PI * 0.5, 0.0, (i - 1.5) * 0.08)
	var eye := _sphere(root, 2.7, eye_center + Vector3(0, 0, 0.65), gold)
	eye.scale = Vector3(1.55, 0.82, 0.42)
	var iris := _sphere(root, 1.25, eye_center + Vector3(0, 0, 1.45), glow)
	iris.scale.z = 0.38
	var pupil := _sphere(root, 0.53, eye_center + Vector3(0, 0, 1.85), black)
	pupil.scale.z = 0.3
	_sphere(root, 0.18, eye_center + Vector3(0.3, 0.3, 2.0), white_hot)
	_light(root, eye_center + Vector3(0, 0, 3), accent, 3.0, 24.0)

	# 浮石具有固定而非随机的空间节奏。
	for i in range(10):
		var angle := TAU * float(i) / 10.0
		var p := Vector3(cos(angle) * 16.0, 8.0 + (i % 4) * 4.0, sin(angle) * 7.0 - 2.0)
		var rock := _box(root, Vector3(1.2 + (i % 3) * 0.35, 2.1, 1.0), p, obsidian)
		rock.rotation = Vector3(angle * 0.35, angle, angle * 0.22)
		if i % 2 == 0:
			_box(root, Vector3(0.22, 1.4, 1.05), p, glow).rotation = rock.rotation

	# 两座侧方黑金方尖碑和地面符文灯。
	for side in [-1.0, 1.0]:
		var p := Vector3(side * 17.0, 0, 7.0)
		_box(root, Vector3(3.0, 1.0, 3.0), p + Vector3(0, 0.5, 0), black)
		_cyl(root, 1.0, 1.35, 7.0, p + Vector3(0, 4.3, 0), obsidian, 4)
		_cyl(root, 0.0, 1.05, 2.5, p + Vector3(0, 9.05, 0), gold, 4)
		_light(root, p + Vector3(0, 7.0, 0), accent, 1.1, 10.0)
	for i in range(4):
		var angle := TAU * (float(i) / 4.0 + 0.125)
		_light(root, Vector3(cos(angle) * 11.5, 2.5, sin(angle) * 11.5), Color("d5a34f"), 0.9, 8.0)


# -----------------------------------------------------------------------------
# BAIYAO：冰棱塔林。白垩冰台上斜插的七根冰棱 + 冰拱门 + 霜光。
# -----------------------------------------------------------------------------
static func _build_baiyao(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var ice = planet._material(Color("dfeef7"))
	var pale = planet._material(Color("f4fbff"))
	var deep = planet._material(Color("8fb3c6"))
	var glow = planet._material(accent.lightened(0.2), 1.6)

	# 三层冰台，向上收束。
	_cyl(root, 13.0, 15.5, 1.1, Vector3(0, 0.55, 0), deep, 12)
	_cyl(root, 10.6, 12.6, 0.9, Vector3(0, 1.55, 0), ice, 12)
	_cyl(root, 8.2, 9.4, 0.7, Vector3(0, 2.35, 0), pale, 12)
	_ring(root, 7.4, 8.0, Vector3(0, 2.8, 0), glow)

	# 七根冰棱：高度与倾角各不相同，向中心微倾。
	for i in range(7):
		var angle := TAU * float(i) / 7.0 + 0.22
		var radius_out := 9.6 - float(i % 3) * 0.8
		var p := Vector3(cos(angle) * radius_out, 2.4, sin(angle) * radius_out)
		var height := 13.0 + float(i % 4) * 3.4
		var lean := Vector3(cos(angle) * 0.10, 0.0, sin(angle) * 0.10)
		_crystal(root, p, 0.9 + float(i % 2) * 0.35, height, ice if i % 2 == 0 else pale, lean)
		_cyl(root, 0.5, 0.8, 0.6, p + Vector3(0, 0.3, 0), deep, 8)

	# 中央最高的主冰棱 + 顶部折光。
	_crystal(root, Vector3(0, 2.6, 0), 1.8, 24.0, pale, Vector3(0.02, 0.0, -0.03))
	_sphere(root, 1.05, Vector3(0.3, 26.0, -0.4), glow)
	_light(root, Vector3(0, 24.0, 0), accent, 1.8, 26.0)

	# 冰拱门：两根立柱 + 一道横梁，朝向 +Z 的入口。
	for side in [-1.0, 1.0]:
		_cyl(root, 0.85, 1.15, 9.0, Vector3(side * 3.4, 7.0, 13.0), ice, 8)
		_crystal(root, Vector3(side * 3.4, 11.5, 13.0), 0.6, 3.0, pale, Vector3(side * 0.07, 0.0, 0.0))
	_beam(root, Vector3(-3.4, 11.6, 13.0), Vector3(3.4, 11.6, 13.0), 0.55, pale, 8)
	_light(root, Vector3(0, 9.0, 13.0), Color("cfe9ff"), 1.1, 14.0)

	# 散落的碎冰与霜锥。
	for i in range(9):
		var angle := TAU * float(i) / 9.0 + 0.4
		var p := Vector3(cos(angle) * (17.0 + float(i % 3) * 2.0), 0.4, sin(angle) * (17.0 + float(i % 3) * 2.0))
		_crystal(root, p, 0.5 + float(i % 2) * 0.3, 2.0 + float(i % 3) * 1.2, deep, Vector3(cos(angle) * 0.2, 0.0, sin(angle) * 0.2))


# -----------------------------------------------------------------------------
# PANSHA：风蚀石柱阵。双环高低石柱 + 中央祭台 + 一根倒塌的柱。
# -----------------------------------------------------------------------------
static func _build_pansha(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var sand = planet._material(Color("c0a274"))
	var strata = planet._material(Color("9a7d55"))
	var dark = planet._material(Color("6b563d"))
	var lit = planet._material(accent.lightened(0.1), 0.8)

	_cyl(root, 12.0, 14.5, 1.0, Vector3(0, 0.5, 0), strata, 10)
	_cyl(root, 9.0, 10.5, 0.8, Vector3(0, 1.4, 0), sand, 10)
	_ring(root, 4.2, 4.9, Vector3(0, 1.9, 0), lit)

	# 内环六柱：高瘦，顶端被风磨圆。
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var p := Vector3(cos(angle) * 7.0, 1.8, sin(angle) * 7.0)
		var height := 9.0 + float(i % 3) * 2.6
		_cyl(root, 1.15, 1.5, height, p + Vector3(0, height * 0.5, 0), strata, 9)
		_sphere(root, 1.1, p + Vector3(0, height, 0), sand)
		_ring(root, 1.2, 1.5, p + Vector3(0, height * 0.35, 0), dark)

	# 外环十柱：矮而粗，像被沙埋了一半。
	for i in range(10):
		var angle := TAU * float(i) / 10.0 + 0.3
		var radius_out := 17.0 + float(i % 3) * 2.4
		var p := Vector3(cos(angle) * radius_out, 0.6, sin(angle) * radius_out)
		var height := 4.0 + float(i % 4) * 1.9
		_cyl(root, 1.7, 2.1, height, p + Vector3(0, height * 0.5, 0), sand, 8)
		_box(root, Vector3(2.4, 0.4, 2.4), p + Vector3(0, 0.2, 0), strata)

	# 中央祭台与风向标。
	_cyl(root, 2.6, 3.4, 1.6, Vector3(0, 2.2, 0), dark, 8)
	_cyl(root, 0.35, 0.45, 7.0, Vector3(0, 6.5, 0), strata, 6)
	_box(root, Vector3(3.2, 0.18, 0.7), Vector3(1.4, 9.6, 0), lit).rotation.z = 0.24

	# 一根倒塌的石柱，斜倚在沙面上。
	var fallen := _cyl(root, 1.3, 1.5, 12.0, Vector3(-13.0, 2.6, 9.0), strata, 9)
	fallen.rotation = Vector3(0.0, 0.7, 1.15)
	_light(root, Vector3(0, 4.0, 0), accent, 1.0, 12.0)


# -----------------------------------------------------------------------------
# TAIYUAN：苔垣迷宫。外墙留两道门，内环半墙与中央灯塔。
# -----------------------------------------------------------------------------
static func _build_taiyuan(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var moss = planet._material(Color("46583f"))
	var stone = planet._material(Color("6b7462"))
	var pale = planet._material(Color("9aa48f"))
	var lamp = planet._material(accent.lightened(0.15), 1.9)

	_cyl(root, 15.0, 17.0, 0.9, Vector3(0, 0.45, 0), stone, 12)
	_cyl(root, 6.0, 7.0, 1.2, Vector3(0, 1.5, 0), pale, 10)

	# 外墙（两道门）与内环半墙：形成可绕行的迷宫层。
	_wall_ring(root, 15.0, 3.6, 1.8, 24, moss, 0.0, 0.18, 0.7)
	_wall_ring(root, 11.0, 2.9, 1.8, 18, stone, PI, 0.2, 0.6)
	_wall_ring(root, 7.6, 2.2, 1.8, 14, moss, PI * 0.5, 0.26, 0.5)

	# 放射状短墙，把环间切成几段走廊。
	for i in range(6):
		var angle := TAU * float(i) / 6.0 + 0.55
		var inner := Vector3(cos(angle) * 8.0, 1.8, sin(angle) * 8.0)
		var outer := Vector3(cos(angle) * 13.6, 1.8, sin(angle) * 13.6)
		var wall := _box(root, Vector3(6.0, 2.4, 0.55), (inner + outer) * 0.5 + Vector3(0, 1.0, 0), stone)
		wall.rotation.y = -angle

	# 中央灯塔：塔身 + 灯室 + 顶盖。
	_cyl(root, 1.5, 2.1, 11.0, Vector3(0, 7.6, 0), pale, 8)
	_cyl(root, 2.4, 2.4, 2.2, Vector3(0, 14.0, 0), stone, 8)
	_sphere(root, 1.5, Vector3(0, 14.0, 0), lamp)
	_cyl(root, 2.9, 0.4, 1.6, Vector3(0, 16.0, 0), moss, 8)
	_light(root, Vector3(0, 14.0, 0), accent, 2.2, 24.0)

	# 苔石与矮灯柱散布在环间。
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + 0.2
		var p := Vector3(cos(angle) * 9.6, 1.8, sin(angle) * 9.6)
		_box(root, Vector3(1.6, 0.8, 1.3), p, moss if i % 2 == 0 else stone).rotation.y = angle


# -----------------------------------------------------------------------------
# LIUWU：废弃船坞。两道龙门吊 + 悬吊龙骨 + 三处喷气孔 + 控制塔。
# -----------------------------------------------------------------------------
static func _build_liuwu(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var ash = planet._material(Color("4a4636"))
	var iron = planet._material(Color("6e6047"))
	var rust = planet._material(Color("8a5a35"))
	var sulfur = planet._material(accent.lightened(0.1), 1.3)

	_cyl(root, 14.0, 16.0, 1.2, Vector3(0, 0.6, 0), ash, 12)
	_box(root, Vector3(26.0, 0.5, 3.0), Vector3(0, 1.35, 0), iron)

	# 两道龙门吊：立柱 + 横梁 + 斜撑。
	for z in [-8.0, 8.0]:
		for side in [-1.0, 1.0]:
			_cyl(root, 0.9, 1.3, 15.0, Vector3(side * 10.0, 8.7, z), iron, 8)
			_box(root, Vector3(1.6, 1.2, 1.6), Vector3(side * 10.0, 16.4, z), rust)
		_beam(root, Vector3(-10.0, 16.4, z), Vector3(10.0, 16.4, z), 0.75, rust, 8)
		for side in [-1.0, 1.0]:
			_beam(root, Vector3(side * 10.0, 14.0, z), Vector3(side * 5.2, 16.4, z), 0.28, iron, 6)

	# 悬吊的船体龙骨：被钢缆挂在两道横梁之间。
	var keel := _box(root, Vector3(4.4, 2.2, 15.0), Vector3(0, 12.4, 0), rust)
	keel.rotation.z = 0.05
	for z in [-8.0, 8.0]:
		for side in [-1.0, 1.0]:
			_beam(root, Vector3(side * 3.0, 16.2, z), Vector3(side * 1.6, 13.2, z * 0.55), 0.1, iron, 5)
	for i in range(4):
		_box(root, Vector3(3.8, 0.5, 0.6), Vector3(0, 11.6 + float(i) * 0.6, -6.0 + float(i) * 4.0), iron)

	# 三处喷气孔：矮环 + 自发光喉口。
	for i in range(3):
		var angle := TAU * float(i) / 3.0 + 0.6
		var p := Vector3(cos(angle) * 12.0, 1.4, sin(angle) * 12.0)
		_cyl(root, 2.6, 3.4, 2.0, p + Vector3(0, 1.0, 0), ash, 8)
		_cyl(root, 1.7, 2.2, 0.6, p + Vector3(0, 2.2, 0), sulfur, 8)
		_light(root, p + Vector3(0, 3.0, 0), accent, 0.9, 10.0)

	# 控制塔。
	_box(root, Vector3(6.0, 12.0, 5.0), Vector3(16.0, 7.2, -12.0), iron)
	_box(root, Vector3(7.0, 1.0, 6.0), Vector3(16.0, 13.4, -12.0), rust)
	_box(root, Vector3(3.2, 1.6, 2.0), Vector3(16.0, 11.0, -14.4), sulfur)
	_light(root, Vector3(0, 12.0, 0), Color("ffd58a"), 1.2, 18.0)


# -----------------------------------------------------------------------------
# JIANMO：静默门阵。三座黑曜石立门成三角，中央台座与悬浮光环。
# -----------------------------------------------------------------------------
static func _build_jianmo(root: Node3D, planet) -> void:
	var accent: Color = planet.accent_color
	var flint = planet._material(Color("15121c"))
	var glassy = planet._material(Color("2b2337"))
	var pale = planet._material(Color("4d4260"))
	var violet = planet._material(accent.lightened(0.2), 2.4)

	_cyl(root, 11.0, 13.0, 0.8, Vector3(0, 0.4, 0), flint, 10)
	_cyl(root, 5.2, 6.4, 1.0, Vector3(0, 1.2, 0), glassy, 10)
	_ring(root, 3.0, 3.6, Vector3(0, 1.8, 0), violet)

	# 三座立门：两柱 + 横梁，门内薄雾般的发光面。
	for i in range(3):
		var angle := TAU * float(i) / 3.0
		var center := Vector3(cos(angle) * 9.5, 0.6, sin(angle) * 9.5)
		var yaw := -angle + PI * 0.5
		var basis := Basis(Vector3.UP, yaw)
		for side in [-1.0, 1.0]:
			var p := center + basis * Vector3(side * 3.1, 0, 0)
			var pillar := _box(root, Vector3(1.0, 12.0, 1.4), p + Vector3(0, 6.0, 0), glassy)
			pillar.rotation.y = yaw
			_box(root, Vector3(1.5, 0.8, 1.9), p + Vector3(0, 12.4, 0), pale).rotation.y = yaw
		var lintel := _box(root, Vector3(7.4, 1.0, 1.5), center + Vector3(0, 12.0, 0), flint)
		lintel.rotation.y = yaw
		var veil := _box(root, Vector3(5.6, 10.4, 0.12), center + Vector3(0, 6.2, 0), glassy)
		veil.rotation.y = yaw
		# 门前的静默灯槽。
		_box(root, Vector3(4.4, 0.3, 0.9), center + basis * Vector3(0, 0.35, 1.4), violet)

	# 中央台座与悬浮环。
	_cyl(root, 1.6, 2.2, 5.0, Vector3(0, 4.0, 0), flint, 8)
	var halo := _ring(root, 5.2, 6.0, Vector3(0, 18.0, 0), violet)
	halo.rotation = Vector3(0.12, 0.0, -0.08)
	var halo2 := _ring(root, 3.4, 3.9, Vector3(0, 20.4, 0), pale)
	halo2.rotation = Vector3(-0.16, 0.2, 0.0)
	_sphere(root, 0.9, Vector3(0, 18.6, 0), violet)
	_light(root, Vector3(0, 18.0, 0), accent, 2.0, 26.0)

	# 地面上的低矮黑曜石棱。
	for i in range(12):
		var angle := TAU * float(i) / 12.0 + 0.15
		var p := Vector3(cos(angle) * (16.0 + float(i % 3) * 1.8), 0.3, sin(angle) * (16.0 + float(i % 3) * 1.8))
		_crystal(root, p, 0.45, 1.8 + float(i % 4) * 1.1, flint, Vector3(0.0, 0.0, 0.0))


# -----------------------------------------------------------------------------
# 地表高度查询：把局部坐标投影回星球表面。
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# 阶段 C：通用细节组件。所有小件按材质合并成一个网格再挂到地标上，
# 这样十个地标各加几十个小件也不会让 draw call 爆炸（网页单线程很在意）。
# -----------------------------------------------------------------------------
static var _detail_batch: Dictionary = {}


static func _detail_reset() -> void:
	_detail_batch.clear()


static func _detail_add(mesh: Mesh, material: Material, xform: Transform3D) -> void:
	var key: int = material.get_instance_id()
	if not _detail_batch.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_detail_batch[key] = {"tool": tool, "material": material}
	var entry: Dictionary = _detail_batch[key]
	(entry["tool"] as SurfaceTool).append_from(mesh, 0, xform)


static func _detail_flush(parent: Node3D) -> void:
	for key in _detail_batch:
		var entry: Dictionary = _detail_batch[key]
		var tool: SurfaceTool = entry["tool"]
		tool.generate_normals()
		var instance := MeshInstance3D.new()
		instance.name = "DetailBatch"
		instance.mesh = tool.commit()
		instance.material_override = entry["material"]
		parent.add_child(instance)
	_detail_batch.clear()


static func _d_box(size: Vector3, material: Material, pos: Vector3, yaw := 0.0) -> void:
	_detail_add(_box_mesh(size), material, Transform3D(Basis(Vector3.UP, yaw), pos))


static func _d_cyl(radius: float, height: float, material: Material, pos: Vector3, yaw := 0.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	_detail_add(mesh, material, Transform3D(Basis(Vector3.UP, yaw), pos))


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## 一圈螺栓：贴着指定半径的圆，按 count 均布。
static func _bolt_ring(radius: float, y: float, count: int, material: Material, size := 0.10) -> void:
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		_detail_add(_box_mesh(Vector3(size, size, size)), material,
			Transform3D(Basis(Vector3.UP, -angle), Vector3(cos(angle) * radius, y, sin(angle) * radius)))


## 壁板带：沿圆环均布的长条板，板间留缝。
static func _panel_band(radius: float, y: float, height: float, count: int, material: Material, thickness := 0.10) -> void:
	var step := TAU / float(count)
	for i in range(count):
		var angle := step * float(i)
		var width := 2.0 * radius * sin(step * 0.5) * 0.82
		var xform := Transform3D(Basis(Vector3.UP, -angle), Vector3(cos(angle) * radius, y, sin(angle) * radius))
		_detail_add(_box_mesh(Vector3(thickness, height, width)), material, xform)


## 栏杆：立柱 + 两道横杆，沿圆环布置。
static func _rail_ring(radius: float, y: float, count: int, height: float, material: Material) -> void:
	var step := TAU / float(count)
	for i in range(count):
		var angle := step * float(i)
		var base := Vector3(cos(angle) * radius, y, sin(angle) * radius)
		_detail_add(_box_mesh(Vector3(0.07, height, 0.07)), material,
			Transform3D(Basis.IDENTITY, base + Vector3(0, height * 0.5, 0)))
	for level in [height * 0.55, height * 0.95]:
		for i in range(count):
			var angle := step * float(i)
			var next := angle + step
			var a := Vector3(cos(angle) * radius, y + level, sin(angle) * radius)
			var b := Vector3(cos(next) * radius, y + level, sin(next) * radius)
			var mid := (a + b) * 0.5
			var length := a.distance_to(b)
			_detail_add(_box_mesh(Vector3(0.05, 0.05, length)), material,
				Transform3D(Basis(Vector3.UP, -angle - step * 0.5), mid))


## 管线：两段之间一根圆柱 + 两端法兰。
static func _pipe(a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.05:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 7
	var basis := Basis(Quaternion(Vector3.UP, delta.normalized()))
	_detail_add(mesh, material, Transform3D(basis, (a + b) * 0.5))
	for point in [a, b]:
		_detail_add(_box_mesh(Vector3(radius * 3.2, radius * 1.1, radius * 3.2)), material,
			Transform3D(basis, point))


## 灯带：沿圆环的短发光条。
static func _lights_ring(radius: float, y: float, count: int, material: Material, width := 0.42) -> void:
	var step := TAU / float(count)
	for i in range(count):
		var angle := step * float(i)
		_detail_add(_box_mesh(Vector3(0.06, 0.09, width)), material,
			Transform3D(Basis(Vector3.UP, -angle), Vector3(cos(angle) * radius, y, sin(angle) * radius)))


static func _detail_pass(root: Node3D, kind: String, planet) -> void:
	_detail_reset()
	var accent: Color = planet.accent_color
	match kind:
		"baiyao":
			_detail_baiyao(root, planet, accent)
		"pansha":
			_detail_pansha(root, planet, accent)
		"taiyuan":
			_detail_taiyuan(root, planet, accent)
		"liuwu":
			_detail_liuwu(root, planet, accent)
		"jianmo":
			_detail_jianmo(root, planet, accent)
		"qinglan", "zheya", "cangbo", "xuanjing", "xuanyuan":
			_detail_primary(root, planet, accent, kind)
	_detail_flush(root)


static func _detail_baiyao(root: Node3D, planet, accent: Color) -> void:
	var ice: Material = planet._material(Color("cfe4f2"))
	var metal: Material = planet._material(Color("7d93a3"))
	var glow: Material = planet._material(accent.lightened(0.2), 1.6)
	# 冰台上三道壁板带与螺栓圈
	_panel_band(13.2, 0.72, 0.55, 26, ice)
	_panel_band(10.9, 1.66, 0.45, 22, ice)
	_bolt_ring(13.9, 0.56, 30, metal, 0.09)
	_bolt_ring(11.6, 1.50, 26, metal, 0.08)
	# 顶层平台栏杆
	_rail_ring(8.0, 2.72, 18, 0.85, metal)
	# 冰拱门上的灯带与螺栓
	for side in [-1.0, 1.0]:
		_d_box(Vector3(0.14, 0.9, 0.14), glow, Vector3(side * 3.4, 10.2, 12.92))
	for i in range(6):
		var t := float(i) / 5.0
		_d_box(Vector3(0.10, 0.10, 0.34), glow, Vector3(-3.4 + 6.8 * t, 11.95, 13.0))
	# 主冰棱基座的金属箍
	_d_cyl(2.05, 0.22, metal, Vector3(0, 3.05, 0))
	_lights_ring(9.8, 2.55, 14, glow, 0.36)


static func _detail_pansha(root: Node3D, planet, accent: Color) -> void:
	var stone: Material = planet._material(Color("9a7d55"))
	var metal: Material = planet._material(Color("7a6448"))
	var glow: Material = planet._material(accent.lightened(0.1), 0.9)
	# 祭台壁板与栏杆
	_panel_band(3.2, 2.2, 1.1, 14, stone)
	_rail_ring(4.6, 1.95, 16, 0.8, metal)
	_bolt_ring(3.7, 1.75, 18, metal, 0.08)
	# 内环六柱各加三道石箍
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var height := 9.0 + float(i % 3) * 2.6
		for level in [0.28, 0.55, 0.82]:
			_d_cyl(1.62, 0.18, stone, Vector3(cos(angle) * 7.0, 1.8 + height * level, sin(angle) * 7.0))
	# 外环十柱的顶部刻槽
	for i in range(10):
		var angle := TAU * float(i) / 10.0 + 0.3
		var radius_out := 17.0 + float(i % 3) * 2.4
		var height := 4.0 + float(i % 4) * 1.9
		for k in range(3):
			_d_box(Vector3(3.5, 0.09, 0.18), metal,
				Vector3(cos(angle) * radius_out, 0.6 + height * (0.35 + 0.2 * float(k)), sin(angle) * radius_out), -angle)
	# 风向标下的灯带
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		_d_box(Vector3(0.12, 0.2, 0.12), glow, Vector3(cos(angle) * 5.2, 0.9, sin(angle) * 5.2))


static func _detail_taiyuan(root: Node3D, planet, accent: Color) -> void:
	var stone: Material = planet._material(Color("6b7462"))
	var _moss: Material = planet._material(Color("46583f"))
	var metal: Material = planet._material(Color("5d6656"))
	var lamp: Material = planet._material(accent.lightened(0.15), 1.7)
	# 三层环墙的压顶石：沿墙顶均布，宽度与墙体一致
	for ring in [[15.0, 3.6, 24], [11.0, 2.9, 18], [7.6, 2.2, 14]]:
		var radius: float = ring[0]
		var height: float = ring[1]
		var segments: int = ring[2]
		for i in range(segments):
			var angle := TAU * float(i) / float(segments)
			_d_box(Vector3(1.3, 0.16, 0.86), stone,
				Vector3(cos(angle) * radius, 1.8 + height + 0.08, sin(angle) * radius), -angle)
	# 灯塔身的分层箍与窗
	for level in [6.0, 9.0, 12.0]:
		_d_cyl(2.0, 0.14, metal, Vector3(0, level, 0))
	for i in range(4):
		var angle := TAU * float(i) / 4.0 + 0.4
		_d_box(Vector3(0.1, 0.42, 0.34), lamp, Vector3(cos(angle) * 1.86, 8.2, sin(angle) * 1.86), -angle)
	# 迷宫地面灯带
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		_d_box(Vector3(0.2, 0.16, 0.2), lamp, Vector3(cos(angle) * 12.4, 1.95, sin(angle) * 12.4))


static func _detail_liuwu(root: Node3D, planet, accent: Color) -> void:
	var iron: Material = planet._material(Color("6e6047"))
	var rust: Material = planet._material(Color("8a5a35"))
	var sulfur: Material = planet._material(accent.lightened(0.1), 1.2)
	# 龙门吊上的管线：两根主梁之间拉三根
	for z in [-8.0, 8.0]:
		for i in range(3):
			_pipe(Vector3(-9.4, 16.1 - i * 0.22, z), Vector3(9.4, 16.1 - i * 0.22, z), 0.09, iron)
	# 码头地面的格栅板
	for i in range(8):
		_d_box(Vector3(2.4, 0.06, 0.32), iron, Vector3(-7.0 + i * 2.0, 1.42, 0.0))
	# 悬吊龙骨的加强肋
	for i in range(5):
		_d_box(Vector3(4.5, 0.12, 0.16), rust, Vector3(0, 12.4, -6.4 + i * 3.2))
	# 控制塔窗带与警示条
	for i in range(3):
		_d_box(Vector3(5.0, 0.16, 0.10), sulfur, Vector3(16.0, 9.4 + i * 1.3, -12.0))
	# 龙门吊柱脚螺栓
	for z in [-8.0, 8.0]:
		for side in [-1.0, 1.0]:
			_bolt_ring(1.05, 1.62, 10, iron, 0.07)


static func _detail_jianmo(root: Node3D, planet, accent: Color) -> void:
	var flint: Material = planet._material(Color("15121c"))
	var pale: Material = planet._material(Color("4d4260"))
	var violet: Material = planet._material(accent.lightened(0.2), 2.0)
	# 三座门：门框上的刻纹板 + 门柱螺栓
	for i in range(3):
		var angle := TAU * float(i) / 3.0
		var center := Vector3(cos(angle) * 9.5, 0.6, sin(angle) * 9.5)
		var yaw := -angle + PI * 0.5
		var basis := Basis(Vector3.UP, yaw)
		for side in [-1.0, 1.0]:
			var p := center + basis * Vector3(side * 3.1, 0, 0)
			for k in range(4):
				_d_box(Vector3(0.16, 0.55, 0.16), pale, p + Vector3(0, 2.4 + k * 2.6, 0), yaw)
			_d_box(Vector3(1.25, 0.10, 0.10), violet, p + Vector3(0, 11.9, 0), yaw)
		# 门楣上的三道刻纹
		for k in range(3):
			_d_box(Vector3(6.2, 0.09, 0.10), violet, center + Vector3(0, 12.4, 0), yaw)
	# 中央台座的阶梯与地纹
	for i in range(3):
		_d_cyl(3.4 - float(i) * 0.55, 0.18, flint, Vector3(0, 1.75 + i * 0.18, 0))
	_lights_ring(5.6, 1.28, 16, violet, 0.30)


static func _detail_primary(root: Node3D, planet, accent: Color, kind: String) -> void:
	# 五颗主天体：统一补一圈壁板带 + 螺栓圈 + 栏杆，按各自配色
	var stone: Material = planet._material((planet.base_color as Color).lightened(0.12))
	var metal: Material = planet._material(Color("6f7a78"))
	var glow: Material = planet._material(accent.lightened(0.15), 1.3)
	var radius := 11.5
	var rail_y := 1.4
	match kind:
		"qinglan":
			radius = 13.0
			rail_y = 1.35
		"zheya":
			radius = 13.2
			rail_y = 1.9
		"cangbo":
			radius = 9.0
			rail_y = 11.2
		"xuanjing":
			radius = 9.8
			rail_y = 10.2
		"xuanyuan":
			radius = 14.5
			rail_y = 1.4
	_panel_band(radius, rail_y - 0.35, 0.7, 20, stone)
	_bolt_ring(radius + 0.55, rail_y - 0.35, 24, metal, 0.08)
	_lights_ring(radius + 0.20, rail_y + 0.10, 12, glow, 0.34)


static func _ground_y(root: Node3D, planet, x: float, z: float) -> float:
	var world: Vector3 = root.global_transform * Vector3(x, 0.0, z)
	var direction: Vector3 = (world - planet.global_position).normalized()
	var surface: Vector3 = planet.global_position + planet.surface_position(direction, 0.0)
	return (root.global_transform.affine_inverse() * surface).y


# -----------------------------------------------------------------------------
# 主要建筑使用简化碰撞代理，保证玩家能站在平台、撞到塔楼与立柱。
# -----------------------------------------------------------------------------
static func _add_collision(root: Node3D, kind: String, planet) -> void:
	var body := StaticBody3D.new()
	body.name = "BuildingCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	match kind:
		"qinglan":
			_cylinder_collider(body, 14.0, 1.2, Vector3(0, 0.6, 0))
			_cylinder_collider(body, 12.6, 0.55, Vector3(0, 1.48, 0))
			_cylinder_collider(body, 5.9, 6.3, Vector3(0, 9.35, 0))
			# 风车顶盖与转子（转子面朝 +Z，与几何一致）。
			_cylinder_collider(body, 6.3, 2.3, Vector3(0, 12.35, 0))
			_box_collider(body, Vector3(1.8, 13.0, 1.2), Vector3(0.0, 11.6, 7.2), 0.0)
			# 引水渠：两道石梁 + 支承立柱，玩家会撞到，所以要有碰撞代理。
			var aqueduct_dir := Vector3(0.66, 0.0, 0.75).normalized()
			var aqueduct_top := Vector3(aqueduct_dir.x * 11.6, 3.3, aqueduct_dir.z * 11.6)
			var aqueduct_end := aqueduct_dir * 26.0
			aqueduct_end.y = _ground_y(root, planet, aqueduct_end.x, aqueduct_end.z) + 1.2
			for side in [-1.0, 1.0]:
				var lateral: Vector3 = Vector3(-aqueduct_dir.z, 0.0, aqueduct_dir.x) * side * 0.55
				_beam_collider(body, aqueduct_top + lateral, aqueduct_end + lateral, 0.3)
			for i in range(3):
				var t := 0.3 + float(i) * 0.25
				var top: Vector3 = aqueduct_top.lerp(aqueduct_end, t)
				var ground: float = _ground_y(root, planet, top.x, top.z)
				var height: float = maxf(0.6, top.y - ground)
				_cylinder_collider(body, 0.46, height, Vector3(top.x, ground + height * 0.5, top.z))
			for i in range(3):
				var angle := TAU * (float(i) / 3.0 + 0.09)
				var center := Vector3(cos(angle) * 18.0, 0, sin(angle) * 18.0)
				center.y = _ground_y(root, planet, center.x, center.z)
				var yaw := -angle + PI * 0.5
				_box_collider(body, Vector3(4.4, 5.9, 4.0), center + Basis(Vector3.UP, yaw) * Vector3(0, 2.95, 0), yaw)
		"zheya":
			_cylinder_collider(body, 14.0, 1.4, Vector3(0, 0.7, 0))
			_cylinder_collider(body, 12.2, 1.0, Vector3(0, 1.85, 0))
			_cylinder_collider(body, 4.0, 7.0, Vector3(0, 5.0, 0))
			for i in range(8):
				var angle := TAU * float(i) / 8.0
				_cylinder_collider(body, 1.1, 8.0, Vector3(cos(angle) * 8.8, 6.8, sin(angle) * 8.8))
			# 卤水池心与喷泉柱
			_cylinder_collider(body, 3.2, 6.0, Vector3(0, 8.5, 0))
			# 四道卤水收集槽（与可见形体一致）
			for i in range(4):
				var side := -1.0 if i % 2 == 0 else 1.0
				var z := -7.0 if i < 2 else 7.0
				var trough_pos := Vector3(side * 14.0, 3.6, z)
				var trough_basis := Basis.from_euler(Vector3(-0.16, 0.2 * side, 0.1 * side))
				_box_collider_basis(body, Vector3(5.2, 0.5, 1.6), trough_basis, trough_pos)
		"cangbo":
			_box_collider(body, Vector3(18.0, 1.0, 14.0), Vector3(0, 11.0, 0))
			_box_collider(body, Vector3(15.5, 0.45, 11.5), Vector3(0, 11.7, 0))
			_box_collider(body, Vector3(9.0, 0.9, 8.0), Vector3(-1.5, 11.6, 0))
			_box_collider(body, Vector3(5.0, 3.8, 6.0), Vector3(5.2, 13.85, 0))
			_box_collider(body, Vector3(21.0, 0.8, 3.4), Vector3(18.5, 11.0, 0))
			_box_collider(body, Vector3(5.5, 0.8, 6.5), Vector3(30.0, 11.0, 0))
			_cylinder_collider(body, 0.5, 7.2, Vector3(-2.0, 20.7, 0))
			_sphere_collider(body, 2.35, Vector3(-2.0, 24.0, 0), Vector3(1.0, 0.24, 1.0), Quaternion(Vector3.UP, Vector3(0.4, 0.82, 0.2).normalized()))
			for drone_pos in [Vector3(-13, 16, -6), Vector3(-12, 20, 7), Vector3(12, 18, -8), Vector3(25, 16, 7)]:
				_sphere_collider(body, 0.9, drone_pos)
		"xuanjing":
			_cylinder_collider(body, 10.5, 6.5, Vector3(0, 5.8, 0))
			_cylinder_collider(body, 9.5, 1.0, Vector3(0, 9.1, 0))
			_cylinder_collider(body, 8.0, 0.8, Vector3(0, 10.0, 0))
			for i in range(8):
				var angle := TAU * float(i) / 8.0
				_cylinder_collider(body, 0.62, 9.0, Vector3(cos(angle) * 6.2, 15.5, sin(angle) * 6.2))
			for i in range(10):
				_box_collider(body, Vector3(4.0, 0.55, 1.65), Vector3(0, 1.0 + i * 0.86, 19.0 - i * 1.15), sin(float(i) * 1.7) * 0.08)
			for p in [Vector3(-14, 7, -3), Vector3(13, 11, 1), Vector3(-11, 15, 8), Vector3(11, 5, -10)]:
				_cylinder_collider(body, 3.2, 3.8, p)
		"xuanyuan":
			_cylinder_collider(body, 16.0, 2.1, Vector3(0, 0.7, 0))
			_cylinder_collider(body, 14.0, 0.8, Vector3(0, 1.35, 0))
			_box_collider(body, Vector3(4.2, 23.0, 4.2), Vector3(-10.0, 15.0, 0))
			_box_collider(body, Vector3(4.2, 23.0, 4.2), Vector3(10.0, 15.0, 0))
			_box_collider(body, Vector3(23.0, 3.0, 4.0), Vector3(0, 27.0, 0))
			for i in range(8):
				_box_collider(body, Vector3(8.0 - i * 0.25, 0.45, 1.8), Vector3(0, 0.35 + i * 0.35, 20.0 - i * 1.45))
			for i in range(10):
				var angle := TAU * float(i) / 10.0
				var floater_pos := Vector3(cos(angle) * 16.0, 8.0 + (i % 4) * 4.0, sin(angle) * 7.0 - 2.0)
				var floater_basis := Basis.from_euler(Vector3(angle * 0.35, angle, angle * 0.22))
				_box_collider_basis(body, Vector3(1.2 + (i % 3) * 0.35, 2.1, 1.0), floater_basis, floater_pos)
		"baiyao":
			_cylinder_collider(body, 15.5, 1.1, Vector3(0, 0.55, 0))
			_cylinder_collider(body, 12.6, 0.9, Vector3(0, 1.55, 0))
			_cylinder_collider(body, 9.4, 0.7, Vector3(0, 2.35, 0))
			# 七根冰棱与中央主棱。
			for i in range(7):
				var angle := TAU * float(i) / 7.0 + 0.22
				var radius_out := 9.6 - float(i % 3) * 0.8
				var height := 13.0 + float(i % 4) * 3.4
				_cylinder_collider(body, 1.1, height, Vector3(cos(angle) * radius_out, 2.4 + height * 0.5, sin(angle) * radius_out))
			_cylinder_collider(body, 1.9, 24.0, Vector3(0, 14.6, 0))
			# 冰拱门两柱与横梁。
			for side in [-1.0, 1.0]:
				_cylinder_collider(body, 1.15, 12.0, Vector3(side * 3.4, 7.0, 13.0))
			_box_collider(body, Vector3(7.4, 1.1, 1.2), Vector3(0, 11.6, 13.0))
		"pansha":
			_cylinder_collider(body, 14.5, 1.0, Vector3(0, 0.5, 0))
			_cylinder_collider(body, 10.5, 0.8, Vector3(0, 1.4, 0))
			for i in range(6):
				var angle := TAU * float(i) / 6.0
				var height := 9.0 + float(i % 3) * 2.6
				_cylinder_collider(body, 1.5, height, Vector3(cos(angle) * 7.0, 1.8 + height * 0.5, sin(angle) * 7.0))
			for i in range(10):
				var angle := TAU * float(i) / 10.0 + 0.3
				var radius_out := 17.0 + float(i % 3) * 2.4
				var height := 4.0 + float(i % 4) * 1.9
				_cylinder_collider(body, 2.1, height, Vector3(cos(angle) * radius_out, 0.6 + height * 0.5, sin(angle) * radius_out))
			_cylinder_collider(body, 3.4, 1.6, Vector3(0, 2.2, 0))
			_cylinder_collider(body, 0.45, 7.0, Vector3(0, 6.5, 0))
			var fallen_basis := Basis.from_euler(Vector3(0.0, 0.7, 1.15))
			_box_collider_basis(body, Vector3(2.9, 2.9, 12.0), fallen_basis, Vector3(-13.0, 2.6, 9.0))
		"taiyuan":
			_cylinder_collider(body, 17.0, 0.9, Vector3(0, 0.45, 0))
			_cylinder_collider(body, 7.0, 1.2, Vector3(0, 1.5, 0))
			# 三层环墙用切向盒代理（不能做成实心圆柱，否则玩家进不去迷宫）。
			_wall_colliders(body, 15.0, 3.6, 24, 0.0, 0.18)
			_wall_colliders(body, 11.0, 2.9, 18, PI, 0.2)
			_wall_colliders(body, 7.6, 2.2, 14, PI * 0.5, 0.26)
			for i in range(6):
				var angle := TAU * float(i) / 6.0 + 0.55
				var mid := Vector3(cos(angle) * 10.8, 2.8, sin(angle) * 10.8)
				_box_collider(body, Vector3(6.0, 2.4, 0.55), mid, -angle)
			_cylinder_collider(body, 2.1, 11.0, Vector3(0, 7.6, 0))
			_cylinder_collider(body, 2.4, 2.2, Vector3(0, 14.0, 0))
		"liuwu":
			_cylinder_collider(body, 16.0, 1.2, Vector3(0, 0.6, 0))
			_box_collider(body, Vector3(26.0, 0.5, 3.0), Vector3(0, 1.35, 0))
			for z in [-8.0, 8.0]:
				for side in [-1.0, 1.0]:
					_cylinder_collider(body, 1.3, 15.0, Vector3(side * 10.0, 8.7, z))
				_box_collider(body, Vector3(20.0, 1.5, 1.5), Vector3(0, 16.4, z))
			_box_collider(body, Vector3(4.4, 2.2, 15.0), Vector3(0, 12.4, 0))
			for i in range(3):
				var angle := TAU * float(i) / 3.0 + 0.6
				_cylinder_collider(body, 3.4, 2.0, Vector3(cos(angle) * 12.0, 2.4, sin(angle) * 12.0))
			_box_collider(body, Vector3(6.0, 12.0, 5.0), Vector3(16.0, 7.2, -12.0))
		"jianmo":
			_cylinder_collider(body, 13.0, 0.8, Vector3(0, 0.4, 0))
			_cylinder_collider(body, 6.4, 1.0, Vector3(0, 1.2, 0))
			for i in range(3):
				var angle := TAU * float(i) / 3.0
				var center := Vector3(cos(angle) * 9.5, 0.6, sin(angle) * 9.5)
				var yaw := -angle + PI * 0.5
				var basis := Basis(Vector3.UP, yaw)
				for side in [-1.0, 1.0]:
					var p := center + basis * Vector3(side * 3.1, 0, 0)
					_box_collider(body, Vector3(1.0, 12.0, 1.4), p + Vector3(0, 6.0, 0), yaw)
				_box_collider(body, Vector3(7.4, 1.0, 1.5), center + Vector3(0, 12.0, 0), yaw)
			_cylinder_collider(body, 2.2, 5.0, Vector3(0, 4.0, 0))


## 环形墙体的碰撞代理：沿圆环摆放切向盒，留出门洞（门洞角度与 _wall_ring 的几何一致）。
static func _wall_colliders(body: StaticBody3D, radius: float, height: float, segments: int,
		door_angle: float, door_half: float) -> void:
	var segment_angle := TAU / float(segments)
	var yaw_step := segment_angle * radius
	for i in range(segments):
		var angle := segment_angle * float(i)
		var delta: float = absf(wrapf(angle - door_angle, -PI, PI))
		if delta < door_half + segment_angle * 0.5:
			continue
		var center := Vector3(cos(angle) * radius, height * 0.5 + 1.8, sin(angle) * radius)
		_box_collider(body, Vector3(yaw_step + 0.15, height, 0.62), center, -angle)


static func _box_collider(body: StaticBody3D, size: Vector3, pos: Vector3, yaw := 0.0) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = pos
	collision.rotation.y = yaw
	body.add_child(collision)


static func _box_collider_basis(body: StaticBody3D, size: Vector3, basis: Basis, pos: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.transform = Transform3D(basis, pos)
	body.add_child(collision)


static func _sphere_collider(body: StaticBody3D, radius: float, pos: Vector3, scale := Vector3.ONE, rotation := Quaternion.IDENTITY) -> void:
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	collision.shape = shape
	collision.transform = Transform3D(Basis(rotation).scaled(scale), pos)
	body.add_child(collision)


static func _beam_collider(body: StaticBody3D, a: Vector3, b: Vector3, radius: float) -> void:
	var delta := b - a
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = delta.length()
	collision.shape = shape
	collision.transform = Transform3D(Basis(Quaternion(Vector3.UP, delta.normalized())), (a + b) * 0.5)
	body.add_child(collision)


static func _cylinder_collider(body: StaticBody3D, radius: float, height: float, pos: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position = pos
	body.add_child(collision)


# -----------------------------------------------------------------------------
# 共享构件辅助函数。
# -----------------------------------------------------------------------------
static func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, pos, material)


static func _cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, material: Material, segments: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	return _mesh(parent, mesh, pos, material)


static func _sphere(parent: Node3D, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	return _mesh(parent, mesh, pos, material)


static func _ring(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 40
	mesh.ring_segments = 10
	return _mesh(parent, mesh, pos, material)


static func _wall_ring(parent: Node3D, radius: float, height: float, center_y: float, segments: int, material: Material, door_angle: float, door_half: float, thickness: float) -> void:
	var chord := 2.0 * radius * PI / float(segments) + 0.5
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		if absf(wrapf(angle - door_angle, -PI, PI)) < door_half:
			continue
		var panel := _box(parent, Vector3(thickness, height, chord), Vector3(cos(angle) * radius, center_y, sin(angle) * radius), material)
		panel.basis = Basis(Vector3.UP, -angle)


static func _beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material, segments: int = 12) -> MeshInstance3D:
	var delta := b - a
	var beam := _cyl(parent, radius, radius, delta.length(), (a + b) * 0.5, material, segments)
	beam.quaternion = Quaternion(Vector3.UP, delta.normalized())
	return beam


static func _crystal(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, lean: Vector3) -> MeshInstance3D:
	var crystal := _cyl(parent, 0.0, radius, height, pos, material, 6)
	if lean.length_squared() > 0.0001:
		crystal.quaternion = Quaternion(Vector3.UP, (Vector3.UP + lean).normalized())
	return crystal


static func _light(parent: Node3D, pos: Vector3, color: Color, energy: float, distance: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = distance
	parent.add_child(light)
	return light


static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	parent.add_child(instance)
	return instance
