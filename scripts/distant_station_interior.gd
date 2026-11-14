"""远景空间站内部：环形观景舱。

设计原则（跟远景站本身一样，克制）：
  · 不做归航站那套「六廊 + 72 间舱室 + 大厅」——那是两千行的工程，
    这两座站是「飞过去看一眼」的布景，内部做到「能进去、能走、能看到星空」就够。
  · 一座环形观景舱：外环是舷窗（真透明，直接看到同场景的星空与行星），
    中央是控制台与休息区，四周四扇气闸通向外部。
  · 几何全部程序化，跟项目其它部分一致；不额外引入贴图。

布局（本节点局部坐标，Y 向上）：
  · 地板半径 0 ~ R，Y = 0
  · 舷窗外墙半径 R，高 3.2 米，带环形舷窗带
  · 中央控制台（半径 3 米的小圆台）
  · 出口：中央地面一个气闸口，走上去按 E 回飞船
"""
extends Node3D
const Precision = preload("res://scripts/procedural_dressing.gd")

## 舱半径（由 main.gd 按站体大小注入）
var hall_radius := 26.0
## 舱高
var ceiling_height := 4.2
## 舷窗带的高度区间
var window_bottom := 1.35
var window_top := 2.75

## 主色调：Alpha 走暖金（跟模型呼应），Beta 走冷白
var tint := Color("d9b879")

var _mats: Dictionary = {}


func build(radius: float, color: Color) -> void:
	# 舱室比站体小得多：站体半径 358 米，但人走的舱只要 14~18 米半径就够。
	# 第一版按 radius/12 算（30 米），配几件家具看着像空仓库，所以再收一半。
	hall_radius = clampf(radius * 0.042, 12.0, 20.0)
	# 舱高跟着半径走：半径 16 米配 5.2 米净高，观感接近「环形观景厅」。
	ceiling_height = clampf(hall_radius * 0.34, 4.6, 7.0)
	# 舷窗带：从视线高度往上，占舱高的一半 —— 形成一圈真正的环窗。
	window_bottom = clampf(ceiling_height * 0.26, 1.15, 1.9)
	window_top = ceiling_height * 0.80
	tint = color
	_make_materials()
	_build_floor()
	_build_ceiling()
	_build_outer_wall()
	_build_window_stars()
	_build_console()
	_build_benches()
	_build_pillars()
	_build_exit_marker()
	Precision.distant_hall(self, hall_radius, ceiling_height)
	_build_lighting()


func _make_materials() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.19, 0.20, 0.23)
	floor_mat.metallic = 0.35
	floor_mat.roughness = 0.55
	floor_mat.emission_enabled = true
	floor_mat.emission = Color(0.07, 0.08, 0.10)
	floor_mat.emission_energy_multiplier = 1.0
	_mats["floor"] = floor_mat

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.24, 0.26, 0.30)
	wall_mat.metallic = 0.35
	wall_mat.roughness = 0.55
	# 给墙一点自发光：远景站内部没有场景主光，纯靠反射会黑成一片。
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(0.10, 0.11, 0.14)
	wall_mat.emission_energy_multiplier = 1.0
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["wall"] = wall_mat

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = tint
	trim_mat.metallic = 0.6
	trim_mat.roughness = 0.3
	trim_mat.emission_enabled = true
	trim_mat.emission = tint
	trim_mat.emission_energy_multiplier = 0.55
	_mats["trim"] = trim_mat

	var console_mat := StandardMaterial3D.new()
	console_mat.albedo_color = Color(0.10, 0.11, 0.13)
	console_mat.metallic = 0.7
	console_mat.roughness = 0.28
	_mats["console"] = console_mat

	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.06, 0.10, 0.12)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.35, 0.85, 0.95)
	screen_mat.emission_energy_multiplier = 1.4
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats["screen"] = screen_mat


# ── 几何构件 ────────────────────────────────────────────────────────

func _mesh_instance(mesh: Mesh, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	(parent if parent != null else self).add_child(mi)
	return mi


func _cylinder(radius: float, height: float, segments: int, mat: Material,
		pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var mi := _mesh_instance(mesh, mat, parent)
	mi.position = pos
	return mi


func _box(size: Vector3, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := _mesh_instance(mesh, mat, parent)
	mi.position = pos
	return mi


func _build_floor() -> void:
	# 地板：一个薄圆柱，分段多到边缘看不出多边形
	_cylinder(hall_radius, 0.35, 96, _mats["floor"], Vector3(0.0, -0.175, 0.0))
	_disc_collision(-0.175, 0.35)
	# 地面环形嵌线（两圈发光带，暗示这是座「站」而不是空房间）
	for r in [hall_radius * 0.42, hall_radius * 0.78]:
		var ring := TorusMesh.new()
		ring.inner_radius = r - 0.08
		ring.outer_radius = r + 0.08
		ring.rings = 96
		ring.ring_segments = 8
		var mi := _mesh_instance(ring, _mats["trim"])
		mi.position = Vector3(0.0, 0.02, 0.0)


func _build_ceiling() -> void:
	_cylinder(hall_radius, 0.3, 96, _mats["wall"],
		Vector3(0.0, ceiling_height + 0.15, 0.0))
	_disc_collision(ceiling_height + 0.15, 0.3)
	# 顶部灯环
	var ring := TorusMesh.new()
	ring.inner_radius = hall_radius * 0.55
	ring.outer_radius = hall_radius * 0.60
	ring.rings = 96
	ring.ring_segments = 10
	var mi := _mesh_instance(ring, _mats["trim"])
	mi.position = Vector3(0.0, ceiling_height - 0.12, 0.0)


func _build_outer_wall() -> void:
	# 外墙分三段：舷窗下沿（实墙）、舷窗带（玻璃）、舷窗上沿（实墙）
	var seg := 96
	var lower_h := window_bottom
	var upper_h := ceiling_height - window_top

	_wall_band(0.0, lower_h, seg)
	_wall_band(window_top, upper_h, seg)
	_wall_collision(seg)

	# 舷窗带：真透明，不造网格（直接留空），只加一圈窗框立柱
	var frames := 32
	for i in range(frames):
		var a := TAU * float(i) / float(frames)
		var p := Vector3(cos(a), 0.0, sin(a)) * hall_radius
		var post := _box(Vector3(0.16, window_top - window_bottom, 0.16),
			_mats["trim"], p + Vector3(0.0, (window_top + window_bottom) * 0.5, 0.0))
		post.rotation.y = -a
	# 舷窗上下横梁
	for y in [window_bottom, window_top]:
		var rail := TorusMesh.new()
		rail.inner_radius = hall_radius - 0.10
		rail.outer_radius = hall_radius + 0.06
		rail.rings = seg
		rail.ring_segments = 6
		var mi := _mesh_instance(rail, _mats["trim"])
		mi.position = Vector3(0.0, y, 0.0)


## 造一圈实墙（用一段圆柱环，压扁成薄壳）
func _wall_band(y_base: float, height: float, segments: int) -> void:
	if height <= 0.01:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = hall_radius
	mesh.bottom_radius = hall_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	# A wall band is an open shell; caps would span the entire room at eye level.
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mi := _mesh_instance(mesh, _mats["wall"])
	mi.position = Vector3(0.0, y_base + height * 0.5, 0.0)
	# 翻转 X 让法线朝内（从舱内看得见墙、从舱外看不见）
	mi.scale = Vector3(-1.0, 1.0, 1.0)


func _wall_collision(segments: int) -> void:
	# Tangential box segments leave the interior empty while sealing the perimeter.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.28, ceiling_height, 2.0 * hall_radius * tan(PI / float(segments)) + 0.04)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3(cos(a) * hall_radius, ceiling_height * 0.5, sin(a) * hall_radius)
		collider.rotation.y = -a
		body.add_child(collider)
	add_child(body)


func _disc_collision(y: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = hall_radius
	shape.height = height
	collider.shape = shape
	collider.position.y = y
	body.add_child(collider)
	add_child(body)


## 舷窗外的一层「星幕」：一圈朝外的点状星。
##
## 为什么需要：舱内是封闭圆柱，窗外如果不给东西，看出去就是纯黑 ——
## 那这座站叫「观景舱」就没意义了。游戏里真实的星空由 sky shader 绘制，
## 但那是远景天球，贴着舷窗看会显得太远、太淡，所以这里补一层近景星点。
func _build_window_stars() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.92, 1.0)
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var p := (Vector2(x, y) + Vector2.ONE * 0.5) / 16.0 - Vector2.ONE
			image.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0.0, 1.0 - p.length()), 2.0)))
	image.generate_mipmaps()
	mat.albedo_texture = ImageTexture.create_from_image(image)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261110
	var count := 420
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = count
	for i in range(count):
		var a := rng.randf() * TAU
		# 星点分布在舷窗高度带附近，略微上下散开
		var y := rng.randf_range(window_bottom - 0.4, window_top + 0.4)
		var dist := hall_radius * rng.randf_range(1.08, 1.55)
		var size := rng.randf_range(0.08, 0.24)
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), Vector3(cos(a) * dist, y, sin(a) * dist)))
	var stars := MultiMeshInstance3D.new()
	stars.name = "WindowStars"
	stars.multimesh = multimesh
	stars.material_override = mat
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


func _build_console() -> void:
	# 控制台尺寸跟着舱半径走：舱半径 16 米时台子 2.4 米，
	# 固定 3.4 米在缩小后的舱里会显得像一口井。
	var cr: float = clampf(hall_radius * 0.15, 1.8, 3.0)
	var base := _cylinder(cr, 1.05, 48, _mats["console"], Vector3(0.0, 0.52, 0.0))
	base.name = "Console"
	var top := _cylinder(cr * 0.88, 0.12, 48, _mats["trim"], Vector3(0.0, 1.10, 0.0))
	top.name = "ConsoleTop"
	# 六块斜屏
	for i in range(6):
		var a := TAU * float(i) / 6.0
		# 屏幕贴在控制台斜面上：半径略小于台面、稍微向内倾。
		# 第一版放在 3.05 米、倾 16°，结果是一圈悬空的大黑板 ——
		# 因为控制台半径只有 3.4，屏幕却做成 1.5 米宽，绕一圈就互相挤成墙了。
		var inr: float = cr * 0.75
		var pos := Vector3(cos(a) * inr, 1.28, sin(a) * inr)
		var basis := Basis(Vector3.UP, -a - PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(-62.0))
		_box(Vector3(0.12, 0.20, 0.12), _mats["console"], pos - Vector3.UP * 0.1)
		var bezel := _box(Vector3(cr * 0.27 + 0.10, 0.50, 0.06), _mats["console"], pos)
		bezel.basis = basis
		var screen := _box(Vector3(cr * 0.27, 0.40, 0.014), _mats["screen"], pos + basis.z * 0.037)
		screen.basis = basis
		for line in range(4):
			var readout := _box(Vector3(cr * (0.15 + float(line % 2) * 0.05), 0.018, 0.008), _mats["console"],
				pos + basis * Vector3(0, -0.12 + float(line) * 0.075, 0.049))
			readout.basis = basis
	# 控制台碰撞
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = cr
	shape.height = 1.2
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, 0.6, 0.0)
	body.add_child(collider)
	add_child(body)


func _build_benches() -> void:
	# 四组休息长凳，绕外墙内侧
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var dist := hall_radius * 0.72
		var pos := Vector3(cos(a) * dist, 0.0, sin(a) * dist)
		var seat := _box(Vector3(2.4, 0.32, 0.9), _mats["console"], pos + Vector3(0.0, 0.42, 0.0))
		seat.rotation.y = -a + PI * 0.5
		var back := _box(Vector3(2.4, 0.55, 0.14), _mats["console"],
			pos + Vector3(0.0, 0.72, 0.0) + Vector3(cos(a), 0.0, sin(a)) * 0.40)
		back.rotation.y = -a + PI * 0.5
		var basis := Basis(Vector3.UP, -a + PI * 0.5)
		for side in [-1.0, 1.0]:
			var foot := _box(Vector3(0.14, 0.3, 0.72), _mats["trim"], pos + basis * Vector3(side * 0.85, 0.15, 0))
			foot.basis = basis
			var arm := _box(Vector3(0.10, 0.09, 0.75), _mats["trim"], pos + basis * Vector3(side * 1.1, 0.69, 0))
			arm.basis = basis


func _build_pillars() -> void:
	# 八根结构柱，从地板顶到天花板，让大厅有纵深
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var dist := hall_radius * 0.86
		var pos := Vector3(cos(a) * dist, ceiling_height * 0.5, sin(a) * dist)
		_cylinder(0.24, ceiling_height, 12, _mats["wall"], pos)


func _build_exit_marker() -> void:
	# 出口标记：地上一圈发光环 + 一个向上指的小灯柱，提示「站上去按 E」
	var ring := TorusMesh.new()
	ring.inner_radius = 3.9
	ring.outer_radius = 4.1
	ring.rings = 64
	ring.ring_segments = 6
	var mi := _mesh_instance(ring, _mats["trim"])
	mi.position = Vector3(0.0, 0.03, 0.0)


func _build_lighting() -> void:
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(cos(a) * hall_radius * 0.55, ceiling_height - 0.65, sin(a) * hall_radius * 0.55)
		lamp.light_color = tint.lightened(0.5)
		lamp.light_energy = 1.6
		lamp.omni_range = hall_radius * 1.3
		lamp.shadow_enabled = false
		add_child(lamp)


# ── 对外接口（与 station.gd 同名同义）────────────────────────────────

## 玩家从飞船进站后的落点：站在中央控制台旁边，面朝舷窗
func interior_spawn_transform() -> Transform3D:
	var spawn := Vector3(0.0, 0.05, hall_radius * 0.45)
	var look := Vector3(0.0, 0.05, hall_radius * 0.95)
	var basis := Basis.looking_at((look - spawn).normalized(), Vector3.UP)
	return Transform3D(basis, to_global(spawn))


## 这个位置算不算「在站内」：以站心为球心、舱半径稍微放大一点做粗判。
## 走出去（或者被挤出去）就会被主循环判定为掉出舱外，拉回来。
func is_interior_position(position: Vector3) -> bool:
	var local: Vector3 = to_local(position)
	return Vector2(local.x, local.z).length() <= hall_radius * 1.06 \
		and local.y > -3.0 and local.y < ceiling_height + 3.0


## 出口位置（中央地面上那圈环）
func airlock_position() -> Vector3:
	return to_global(Vector3(0.0, 0.05, 0.0))


## 玩家站在出口附近时提示「按 E 回飞船」
func is_at_airlock(position: Vector3) -> bool:
	return to_local(position).length() < 4.6
