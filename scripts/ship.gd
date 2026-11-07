extends Node3D

var game
var camera: Camera3D
var velocity := Vector3.ZERO
var landed := true
var landed_planet
var docked := false
var docked_station
var target
var autopilot := false
var fuel := 100.0
var hull := 100.0
var focus := false
var zoom := 1.0

## 船体椭球半轴（米）。所有贴附件的位置都从它推导，避免悬空。
const HULL_X := 1.75
const HULL_Y := 1.0
const HULL_Z := 3.25
const AUTOPILOT_ACCEL := 230.0
const AUTOPILOT_FUEL_PER_DV := 0.008
const MANUAL_FUEL_PER_DV := 0.00625
var thrust_level := 0.0
var mouse_sensitivity := 0.0018
const WEB_LOOK_SCALE := 0.5
var engine_materials: Array = []
var engine_lights: Array = []
## 按材质分组的盒体批次，_build_model 末尾统一合并提交。
var _batch := {}
var hull_body: StaticBody3D
var hull_shape: BoxShape3D
var station_velocity := Vector3.ZERO
var last_station_port := Vector3.ZERO
var dock_cooldown := 0.0
var impact_cooldown := 0.0
var fuel_empty_time := 0.0
var fuel_warning_cooldown := 0.0
const FUEL_LIFE_SUPPORT := 90.0
const STATION_COLLISION_RANGE := 400.0
const STATION_COLLISION_MASK := 5


func _ready() -> void:
	_build_model()
	hull_body = StaticBody3D.new()
	hull_body.name = "ShipCollision"
	hull_body.collision_layer = 1
	hull_body.collision_mask = 0
	var hull_collision := CollisionShape3D.new()
	hull_shape = BoxShape3D.new()
	hull_shape.size = Vector3(3.0, 1.8, 4.6)
	hull_collision.shape = hull_shape
	hull_collision.position = Vector3(0, -0.2, 0.2)
	hull_body.add_child(hull_collision)
	add_child(hull_body)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.54, -1.42)
	camera.fov = 72.0
	camera.near = 0.09
	camera.far = 60000.0
	add_child(camera)
	var headlight := SpotLight3D.new()
	headlight.position = Vector3(0, 0.2, -2.5)
	headlight.spot_range = 85.0
	headlight.spot_angle = 38.0
	headlight.light_energy = 2.5
	headlight.light_color = Color("c7e7ff")
	add_child(headlight)
	for child in get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = 1500.0


func _hull_r(z: float) -> float:
	# 船体是椭球：x 半轴 1.75、y 半轴 1.0、z 半轴 3.25。给定 z 返回归一化半径系数。
	return sqrt(maxf(0.0, 1.0 - pow(z / HULL_Z, 2.0)))



## 翼型截面：六点近似（前缘钝、后缘薄）。
func _wing_section(chord: float, thick: float, x: float, z_off: float, y_off: float) -> PackedVector3Array:
	var le := -chord * 0.5 + z_off
	var te := chord * 0.5 + z_off
	var half := thick * 0.5
	return PackedVector3Array([
		Vector3(x, y_off, le),
		Vector3(x, y_off + half, le + chord * 0.18),
		Vector3(x, y_off + half, te - chord * 0.26),
		Vector3(x, y_off, te),
		Vector3(x, y_off - half, te - chord * 0.26),
		Vector3(x, y_off - half, le + chord * 0.18),
	])


func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flip: bool) -> void:
	if flip:
		tool.add_vertex(a)
		tool.add_vertex(c)
		tool.add_vertex(b)
		tool.add_vertex(a)
		tool.add_vertex(d)
		tool.add_vertex(c)
	else:
		tool.add_vertex(a)
		tool.add_vertex(b)
		tool.add_vertex(c)
		tool.add_vertex(a)
		tool.add_vertex(c)
		tool.add_vertex(d)


## 渐缩机翼：根部截面 → 翼尖截面（带后掠），六条翼面 + 两端封盖。
func _wing_mesh(span: float, root_chord: float, tip_chord: float,
		root_thick: float, tip_thick: float, sweep: float, side: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flip := side < 0.0
	var root := _wing_section(root_chord, root_thick, 0.0, 0.0, 0.0)
	var tip := _wing_section(tip_chord, tip_thick, span * side, sweep * side, 0.0)
	for i in range(6):
		var j := (i + 1) % 6
		_quad(tool, root[i], root[j], tip[j], tip[i], flip)
	var root_center := Vector3.ZERO
	var tip_center := Vector3.ZERO
	for p in root:
		root_center += p
	for p in tip:
		tip_center += p
	root_center /= 6.0
	tip_center /= 6.0
	for i in range(6):
		var j := (i + 1) % 6
		if flip:
			tool.add_vertex(root_center)
			tool.add_vertex(root[i])
			tool.add_vertex(root[j])
			tool.add_vertex(tip_center)
			tool.add_vertex(tip[j])
			tool.add_vertex(tip[i])
		else:
			tool.add_vertex(root_center)
			tool.add_vertex(root[j])
			tool.add_vertex(root[i])
			tool.add_vertex(tip_center)
			tool.add_vertex(tip[i])
			tool.add_vertex(tip[j])
	tool.generate_normals()
	return tool.commit()


func _build_model() -> void:
	var ivory := _material(Color("b9b6a6"))
	ivory.metallic = 0.35
	ivory.roughness = 0.5
	var ivory_dark := _material(Color("9a9688"))
	ivory_dark.metallic = 0.35
	ivory_dark.roughness = 0.58
	var dark := _material(Color("26363e"))
	dark.metallic = 0.6
	var dark_soft := _material(Color("1b262c"))
	dark_soft.metallic = 0.45
	var copper := _material(Color("8d5a3d"))
	copper.metallic = 0.5
	var trim := _material(Color("7f8f8c"))
	trim.metallic = 0.75
	trim.roughness = 0.32
	var glass := _material(Color("224f63"), 0.3)
	glass.metallic = 0.55
	glass.roughness = 0.18
	var screen_mat := _material(Color("79e0ec"), 1.6)
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var seam := _material(Color("141c21"))
	seam.metallic = 0.3
	seam.roughness = 0.7

	# ===== 主壳体 =====
	var body := _mesh(_sphere(1.0, 26, 16), ivory, Vector3.ZERO)
	body.scale = Vector3(HULL_X, HULL_Y, HULL_Z)
	add_child(body)

	# ===== 两侧船壳板：贴着椭球表面，越靠艏艉越窄 =====
	for side in [-1.0, 1.0]:
		for z in [-2.15, -1.15, -0.15, 0.85, 1.85]:
			var r: float = _hull_r(z)
			if r < 0.30:
				continue
			var plate_x: float = side * HULL_X * r * 0.985
			var plate: MeshInstance3D = _mesh(_box(Vector3(0.075, 0.62 * r, 0.86)), ivory_dark,
				Vector3(plate_x, 0.06 * r, z))
			plate.rotation.y = side * (0.05 + 0.09 * absf(z) / HULL_Z)
			add_child(plate)
			# 板缝：贴在板与板之间的细暗条
			_batch_box(Vector3(0.03, 0.5 * r, 0.035), seam,
				Transform3D(Basis.IDENTITY, Vector3(plate_x + side * 0.03, 0.05 * r, z + 0.46 * r)))
		# 舷侧灯带：沿壳体中线，长度随船体收窄
		var strip: MeshInstance3D = _mesh(_box(Vector3(0.03, 0.05, 2.9)), screen_mat,
			Vector3(side * (HULL_X * _hull_r(0.0) * 0.99 - 0.01), -0.14, -0.35))
		add_child(strip)

	# ===== 背脊：紧贴壳体顶部的低矮整流脊 =====
	var spine := _mesh(_cylinder(0.20, 0.34, 3.1, 10), ivory_dark, Vector3(0, HULL_Y * 0.86, 0.35))
	spine.rotation.x = PI * 0.5
	add_child(spine)
	for i in range(3):
		var vent := _mesh(_box(Vector3(0.30, 0.04, 0.20)), seam, Vector3(0, HULL_Y * 0.90, -0.30 + i * 0.55))
		add_child(vent)

	# ===== 舰首：锥形鼻 + 探针 + 前照灯 =====
	var nose := _mesh(_cylinder(0.10, 0.62, 1.35, 14), ivory, Vector3(0, 0.0, -(HULL_Z * 0.86)))
	nose.rotation.x = -PI * 0.5
	add_child(nose)
	var nose_tip := _mesh(_cylinder(0.015, 0.11, 0.62, 10), trim, Vector3(0, 0.0, -(HULL_Z * 0.86) - 0.95))
	nose_tip.rotation.x = -PI * 0.5
	add_child(nose_tip)
	add_child(_mesh(_sphere(0.085, 10, 6), screen_mat, Vector3(0, 0.0, -(HULL_Z * 0.86) - 1.28)))
	_light_add(Vector3(0, 0.0, -HULL_Z * 0.80), Color("cfe9ff"), 1.0, 5.0)

	# ===== 腹部：深色底板 + 舱门 + 抓握条 =====
	var belly_y := -HULL_Y * 0.72
	add_child(_mesh(_box(Vector3(1.9, 0.42, 3.3)), dark, Vector3(0, belly_y, 0.25)))
	add_child(_mesh(_box(Vector3(1.25, 0.09, 1.6)), dark_soft, Vector3(0, belly_y - 0.24, 0.30)))
	for i in range(4):
		_batch_box(Vector3(0.8, 0.04, 0.07), trim,
			Transform3D(Basis.IDENTITY, Vector3(0, belly_y - 0.30, -0.40 + i * 0.38)))
	add_child(_mesh(_box(Vector3(0.05, 0.28, 0.8)), dark_soft, Vector3(0.95, belly_y, -0.75)))

	# ===== 座舱：玻璃罩 + 分段框条 + 纵向梁 + 内饰 =====
	var cockpit_y := HULL_Y * 0.56
	var cockpit := _mesh(_sphere(1.0, 22, 12), glass, Vector3(0, cockpit_y, -1.45))
	cockpit.scale = Vector3(1.15, 0.60, 1.30)
	add_child(cockpit)
	for i in range(7):
		var angle := PI * (0.10 + 0.80 * float(i) / 6.0)
		var p := Vector3(cos(angle) * 1.14, cockpit_y - 0.13, -1.45 + sin(angle) * 1.28)
		var bezel := _mesh(_box(Vector3(0.075, 0.10, 0.30)), trim, p)
		bezel.rotation.y = -angle + PI * 0.5
		add_child(bezel)
	for side in [-1.0, 1.0]:
		var rail := _mesh(_box(Vector3(0.06, 0.08, 2.1)), trim,
			Vector3(side * 0.56, cockpit_y + 0.34, -1.45))
		rail.rotation.x = 0.05
		add_child(rail)
	# 内饰：仪表台 + 三块屏 + 座椅
	add_child(_mesh(_box(Vector3(1.3, 0.14, 0.40)), dark, Vector3(0, cockpit_y - 0.12, -2.20)))
	add_child(_mesh(_box(Vector3(1.0, 0.04, 0.24)), screen_mat, Vector3(0, cockpit_y - 0.04, -2.18)))
	for side in [-1.0, 1.0]:
		add_child(_mesh(_box(Vector3(0.26, 0.035, 0.18)), screen_mat,
			Vector3(side * 0.36, cockpit_y - 0.05, -1.98)))
	add_child(_mesh(_box(Vector3(0.64, 0.26, 0.55)), dark_soft, Vector3(0, cockpit_y - 0.06, -0.95)))
	add_child(_mesh(_box(Vector3(0.64, 0.30, 0.14)), dark_soft, Vector3(0, cockpit_y + 0.16, -0.70)))

	# ===== 机翼：三段渐缩 + 前缘翼梁 + 后缘襟翼 + 翼刀 =====
	var wing_y := -HULL_Y * 0.22
	for side in [-1.0, 1.0]:
		# 主翼：自建渐缩翼型网格（根部厚、翼尖薄、带后掠），不再是三块拼板
		var wing: MeshInstance3D = _mesh(_wing_mesh(4.60, 1.98, 1.30, 0.26, 0.12, 0.30, side), ivory,
			Vector3(side * 0.55, wing_y, 0.42))
		add_child(wing)
		# 前缘翼梁（圆柱，给翼面一条圆润的边）
		var spar := _mesh(_cylinder(0.065, 0.065, 4.15, 10), trim, Vector3(side * 2.95, wing_y + 0.01, -0.58))
		spar.rotation.z = PI * 0.5
		add_child(spar)
		# 后缘襟翼
		var flap := _mesh(_box(Vector3(3.3, 0.07, 0.50)), trim, Vector3(side * 2.75, wing_y - 0.06, 1.32))
		flap.rotation.x = 0.14
		add_child(flap)
		# 翼刀
		add_child(_mesh(_box(Vector3(0.05, 0.26, 1.10)), trim, Vector3(side * 2.60, wing_y + 0.10, 0.40)))
		# 翼尖小翼（斜置短鳍，不是大平板）
		var fin := _mesh(_box(Vector3(0.10, 0.46, 0.95)), copper, Vector3(side * 5.05, wing_y + 0.22, 0.55))
		fin.rotation.z = side * 0.34
		add_child(fin)
		# 翼尖航行灯（左红右绿）
		var nav := _material(Color("ff5a4a") if side < 0.0 else Color("6affa0"), 3.0)
		nav.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		add_child(_mesh(_sphere(0.075, 10, 6), nav, Vector3(side * 5.16, wing_y + 0.40, 0.55)))
		# 翼下挂架 + 传感器吊舱
		add_child(_mesh(_box(Vector3(0.10, 0.24, 0.55)), trim, Vector3(side * 2.85, wing_y - 0.20, 0.30)))
		var pod := _mesh(_cylinder(0.12, 0.15, 0.62, 10), ivory_dark, Vector3(side * 2.85, wing_y - 0.46, 0.30))
		pod.rotation.x = PI * 0.5
		add_child(pod)
		add_child(_mesh(_sphere(0.075, 10, 6), screen_mat, Vector3(side * 2.85, wing_y - 0.46, -0.02)))

	# ===== 引擎舱：挂在机翼下方，尺寸受控 =====
	var engine_y := wing_y - 0.52
	for side in [-1.0, 1.0]:
		var nacelle := _mesh(_cylinder(0.36, 0.44, 2.10, 16), dark, Vector3(side * 2.75, engine_y, 0.95))
		nacelle.rotation.x = PI * 0.5
		add_child(nacelle)
		for i in range(2):
			var band := _mesh(_cylinder(0.47, 0.47, 0.10, 16), trim,
				Vector3(side * 2.75, engine_y, 0.55 + i * 0.80))
			band.rotation.x = PI * 0.5
			add_child(band)
		# 进气口：唇环 + 五片格栅（都在舱体半径内）
		var lip := _mesh(_cylinder(0.45, 0.40, 0.16, 16), trim, Vector3(side * 2.75, engine_y, -0.13))
		lip.rotation.x = PI * 0.5
		add_child(lip)
		for i in range(5):
			_batch_box(Vector3(0.62, 0.035, 0.13), trim, Transform3D(
				Basis(Vector3.RIGHT, 0.30), Vector3(side * 2.75, engine_y, -0.11 + i * 0.055)))
		add_child(_mesh(_cylinder(0.33, 0.33, 0.05, 16), dark_soft, Vector3(side * 2.75, engine_y, -0.06)))
		# 推进器钟口 + 发光盘 + 导流片
		var bell := _mesh(_cylinder(0.46, 0.34, 0.36, 16), trim, Vector3(side * 2.75, engine_y, 2.02))
		bell.rotation.x = PI * 0.5
		add_child(bell)
		var glow_mat := _material(Color("67dceb"), 2.8)
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		engine_materials.append(glow_mat)
		var exhaust := _mesh(_cylinder(0.30, 0.30, 0.06, 16), glow_mat, Vector3(side * 2.75, engine_y, 2.16))
		exhaust.rotation.x = PI * 0.5
		add_child(exhaust)
		for i in range(4):
			var vane_angle := TAU * float(i) / 4.0 + 0.4
			_batch_box(Vector3(0.05, 0.20, 0.26), trim, Transform3D(Basis.IDENTITY,
				Vector3(side * 2.75 + cos(vane_angle) * 0.30, engine_y + sin(vane_angle) * 0.30, 2.20)))
		var light := OmniLight3D.new()
		light.position = Vector3(side * 2.75, engine_y, 2.45)
		light.light_color = Color("67dceb")
		light.light_energy = 0.8
		light.omni_range = 6.0
		add_child(light)
		engine_lights.append(light)
		# 引擎挂架
		add_child(_mesh(_box(Vector3(0.14, 0.30, 0.70)), trim, Vector3(side * 2.75, wing_y - 0.28, 0.75)))

	# ===== RCS 姿控口：八处，贴着壳体表面 =====
	var rcs_mat := _material(Color("39474f"))
	rcs_mat.metallic = 0.5
	for entry in [[-0.55, 0.30], [0.30, 0.55], [0.62, -0.20], [-0.20, -0.62]]:
		var z_pos: float = 2.35 * entry[0]
		var r := _hull_r(z_pos)
		for side in [-1.0, 1.0]:
			var port := _mesh(_cylinder(0.06, 0.078, 0.14, 8), rcs_mat,
				Vector3(side * HULL_X * r * 0.93, HULL_Y * r * float(entry[1]), z_pos))
			port.rotation.x = PI * 0.5
			add_child(port)

	# ===== 天线：主桅 + 抛物面 + 鞭状天线 =====
	var mast_base := Vector3(0.55, HULL_Y * 0.72, 1.30)
	add_child(_mesh(_cylinder(0.018, 0.04, 1.35, 6), copper, mast_base + Vector3(0, 0.67, 0)))
	var dish := _mesh(_sphere(0.42, 14, 8), ivory, mast_base + Vector3(0, 1.42, 0))
	dish.scale = Vector3(1.0, 0.20, 1.0)
	add_child(dish)
	add_child(_mesh(_cylinder(0.015, 0.015, 0.32, 6), trim, mast_base + Vector3(0, 1.34, 0)))
	for side in [-1.0, 1.0]:
		var whip := _mesh(_cylinder(0.006, 0.014, 1.10, 5), trim,
			Vector3(side * 0.40, HULL_Y * 0.80, 1.75))
		whip.rotation.z = side * 0.30
		whip.rotation.x = -0.16
		add_child(whip)

	# ===== 起落架：支柱 + 液压杆 + 剪刀撑 + 驻脚 =====
	for leg in [Vector3(-1.15, -0.95, 0.55), Vector3(1.15, -0.95, 0.55), Vector3(0, -0.95, -1.25)]:
		var strut := _mesh(_cylinder(0.07, 0.10, 1.15, 10), dark, leg)
		strut.rotation.z = -signf(leg.x) * 0.30
		add_child(strut)
		var piston := _mesh(_cylinder(0.04, 0.045, 0.62, 8), trim, leg + Vector3(0, -0.26, 0))
		piston.rotation.z = -signf(leg.x) * 0.30
		add_child(piston)
		for s in [-1.0, 1.0]:
			var brace := _mesh(_cylinder(0.018, 0.022, 0.48, 6), trim, leg + Vector3(s * 0.13, -0.42, 0.07))
			brace.rotation.z = s * 0.50
			add_child(brace)
		add_child(_mesh(_box(Vector3(0.52, 0.10, 0.52)), dark, leg + Vector3(0, -0.62, 0)))
		for i in range(2):
			_batch_box(Vector3(0.44, 0.04, 0.08), trim,
				Transform3D(Basis.IDENTITY, leg + Vector3(0, -0.68, -0.13 + i * 0.26)))

	# ===== 尾段：尾锥 + 减速板 + 号牌 =====
	var tail_cone := _mesh(_cylinder(0.44, 0.20, 0.62, 14), ivory_dark, Vector3(0, 0.02, HULL_Z * 0.88))
	tail_cone.rotation.x = PI * 0.5
	add_child(tail_cone)
	for side in [-1.0, 1.0]:
		var brake := _mesh(_box(Vector3(0.85, 0.06, 0.52)), trim, Vector3(side * 0.42, 0.34, HULL_Z * 0.80))
		brake.rotation.z = side * -0.26
		add_child(brake)
		add_child(_mesh(_box(Vector3(0.025, 0.13, 0.95)), screen_mat,
			Vector3(side * (HULL_X * _hull_r(-0.35) - 0.02), 0.38, -0.35)))
	add_child(_mesh(_sphere(0.07, 8, 5), screen_mat, Vector3(0, 0.36, HULL_Z * 0.97)))

	# 批量小件统一提交，减少 draw call
	_batch_flush()


func _unhandled_input(event: InputEvent) -> void:
	if game.state != "ship" or game.paused or game.map_open:
		focus = false
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not landed and not docked:
		if not autopilot:
			# Web 的鼠标位移会被乘以 devicePixelRatio；screen_relative 在 4.7 里与 relative 相同。
			var look_delta: Vector2 = event.relative
			if OS.has_feature("web"):
				look_delta = look_delta / maxf(1.0, DisplayServer.screen_get_scale()) * WEB_LOOK_SCALE
			apply_look(look_delta)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		focus = event.pressed
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 1.18, 1.0, 16.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 1.18, 1.0, 16.0)
		if zoom < 1.01:
			zoom = 1.0


func apply_look(relative: Vector2) -> void:
	if game.state != "ship" or game.paused or game.map_open or landed or docked or autopilot:
		return
	relative = relative.limit_length(120.0)
	var sensitivity: float = mouse_sensitivity * (game.settings.sensitivity_multiplier() if game.settings != null else 1.0)
	rotate_object_local(Vector3.UP, -relative.x * sensitivity)
	rotate_object_local(Vector3.RIGHT, -relative.y * sensitivity)


func _physics_process(delta: float) -> void:
	if game.state != "ship" or game.paused or game.supernova_active or game.map_open:
		thrust_level = 0.0
		return
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	dock_cooldown = maxf(0.0, dock_cooldown - delta)
	if game.station != null:
		var port_now: Vector3 = game.station.docking_point()
		if last_station_port != Vector3.ZERO:
			var measured := (port_now - last_station_port) / maxf(delta, 0.0001)
			station_velocity = measured if measured.length() < 200.0 else Vector3.ZERO
		last_station_port = port_now
	var base_fov := 46.0 if focus else 72.0
	var target_fov := maxf(base_fov / zoom, 3.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 8.0))
	if docked:
		velocity = Vector3.ZERO
		thrust_level = 0.0
		fuel = minf(100.0, fuel + delta * 10.0)
		hull = minf(100.0, hull + delta * 2.0)
		fuel_empty_time = 0.0
		fuel_warning_cooldown = 0.0
		game.player.oxygen = 100.0
		if Input.is_action_just_pressed("jump"):
			undock()
		_update_engine(delta)
		return
	if landed:
		velocity = Vector3.ZERO
		thrust_level = 0.0
		fuel = minf(100.0, fuel + delta * 12.0)
		hull = minf(100.0, hull + delta * 2.0)
		fuel_empty_time = 0.0
		fuel_warning_cooldown = 0.0
		game.player.oxygen = 100.0
		if Input.is_action_just_pressed("jump"):
			takeoff()
		_update_engine(delta)
		return

	var planet = game.nearest_planet(global_position)
	var offset: Vector3 = global_position - planet.global_position
	var normal: Vector3 = offset.normalized()
	var altitude: float = offset.length() - planet.radius
	var gravity: Vector3 = -normal * (planet.gravity_strength * clampf(1.0 - altitude / (planet.radius * 0.6), 0.0, 1.0))
	var thrusting := false

	if autopilot and target != null:
		var to_target: Vector3 = target.global_position - global_position
		var target_altitude: float = to_target.length() - target.radius
		var desired_speed := clampf((target_altitude - 8.0) * 1.25, 18.0, 900.0)
		if target_altitude < 150.0:
			desired_speed = clampf((target_altitude - 4.0) * 0.28, 3.0, 42.0)
		var aim := _autopilot_aim(target.global_position)
		var desired_direction := (aim - global_position).normalized()
		var desired_velocity := desired_direction * desired_speed
		var before_velocity := velocity
		velocity = velocity.move_toward(desired_velocity, delta * AUTOPILOT_ACCEL)
		var delta_v := velocity.distance_to(before_velocity)
		if delta_v > 0.0001:
			if fuel > 0.0:
				fuel = maxf(0.0, fuel - delta_v * AUTOPILOT_FUEL_PER_DV)
			else:
				velocity = before_velocity
				autopilot = false
				game.hud.show_toast("推进剂耗尽 · 自动航行中止", 3.0)
		var up := normal if altitude < 900.0 else Vector3.UP
		if absf(desired_direction.dot(up)) > 0.96:
			up = Vector3.FORWARD
		var desired_basis := Basis.looking_at(desired_direction, up)
		var transform := global_transform
		transform.basis = transform.basis.slerp(desired_basis, clampf(delta * 3.0, 0.0, 1.0)).orthonormalized()
		global_transform = transform
		thrusting = autopilot and delta_v > 0.02
		thrust_level = 0.8 if thrusting else 0.0
	else:
		var thrust := Vector3.ZERO
		thrust.z = Input.get_axis("move_forward", "move_back")
		thrust.x = Input.get_axis("move_left", "move_right")
		thrust.y = Input.get_axis("thrust_down", "jump")
		thrust = thrust.limit_length(1.0)
		var boosting := Input.is_action_pressed("jetpack") and fuel > 0.0
		if thrust.length_squared() > 0.01 and fuel > 0.0:
			var acceleration := 150.0 if boosting else 72.0
			velocity += global_transform.basis * thrust * acceleration * delta
			fuel = maxf(0.0, fuel - delta * (1.6 if boosting else 0.45))
			thrusting = true
			thrust_level = 1.0 if boosting else 0.5
		else:
			thrust_level = 0.0
		if Input.is_action_pressed("brake") and fuel > 0.0:
			var before_brake := velocity
			velocity = velocity.move_toward(Vector3.ZERO, delta * 260.0)
			var brake_dv := velocity.distance_to(before_brake)
			if brake_dv > 0.0001:
				fuel = maxf(0.0, fuel - brake_dv * MANUAL_FUEL_PER_DV)
				thrusting = true
				thrust_level = 0.35
		velocity += gravity * delta

	if velocity.length() > 1600.0:
		velocity = velocity.normalized() * 1600.0
	_move_with_station_collision(delta)

	if game.station != null and not docked and not landed and dock_cooldown <= 0.0:
		var station_port: Vector3 = game.station.docking_point()
		if global_position.distance_to(station_port) < 24.0 and (velocity - station_velocity).length() < 18.0:
			dock_station(game.station)
			return

	planet = game.nearest_planet(global_position)
	offset = global_position - planet.global_position
	normal = offset.normalized()
	altitude = offset.length() - planet.terrain_height(normal)
	if altitude < 3.4:
		var impact_speed := velocity.length()
		if impact_speed < 14.0 or autopilot:
			land(planet)
		else:
			global_position = planet.global_position + planet.surface_position(normal, 5.0)
			velocity = normal * maxf(12.0, impact_speed * 0.42)
			if impact_cooldown <= 0.0:
				hull = maxf(0.0, hull - impact_speed * 0.42)
				impact_cooldown = 1.2
				autopilot = false
				game.hud.show_toast("撞击警告 · 船体 %d%% · X 制动后按 E 着陆" % int(hull), 3.2)
				game.audio.play_impact()
				if hull <= 0.0:
					game.begin_death("飞船在撞击中解体", 4.0)
	var sun_distance := global_position.length()
	if autopilot and sun_distance < game.sun_radius + 500.0:
		autopilot = false
		game.hud.show_toast("自动航行中止：距离恒星过近", 3.0)
	if sun_distance < game.sun_radius + 22.0:
		game.begin_death("飞船坠入了恒星", 4.6)
	elif sun_distance < 950.0:
		var heat_damage := (950.0 - sun_distance) / 950.0 * 22.0 * delta
		hull = maxf(0.0, hull - heat_damage)
		if hull <= 0.0:
			game.begin_death("船体被恒星高温熔穿", 4.2)
	if fuel <= 0.01:
		fuel_empty_time += delta
		fuel_warning_cooldown = maxf(0.0, fuel_warning_cooldown - delta)
		if fuel_warning_cooldown <= 0.0 and fuel_empty_time < FUEL_LIFE_SUPPORT:
			game.hud.show_toast("推进剂耗尽 · 生命维持约 %d 秒后停止" % maxi(0, int(FUEL_LIFE_SUPPORT - fuel_empty_time)), 4.0)
			fuel_warning_cooldown = 15.0
		if fuel_empty_time >= FUEL_LIFE_SUPPORT:
			game.begin_death("推进剂耗尽，飞船在深空失去动力", 4.0)
	else:
		fuel_empty_time = 0.0
	game.audio.set_engine(thrusting, thrust_level)
	_update_engine(delta)


func _move_with_station_collision(delta: float) -> void:
	var station = game.station
	var motion := velocity * delta
	if station == null or global_position.distance_to(station.global_position) > STATION_COLLISION_RANGE:
		global_position += motion
		return
	if _station_blocked(global_position):
		var rest := _station_rest(global_position)
		var normal: Vector3 = rest.get("normal", (global_position - station.global_position).normalized())
		var escape: Vector3 = global_position + normal * 1.5
		if _station_blocked(escape):
			normal = -normal
			escape = global_position + normal * 1.5
		if not _station_blocked(escape):
			global_position = escape
		velocity = normal * 8.0
		return
	if motion.length_squared() < 0.000001:
		return
	var steps := clampi(ceili(motion.length() / 3.0), 1, 32)
	var step := motion / float(steps)
	for _i in range(steps):
		var next := global_position + step
		if not _station_blocked(next):
			global_position = next
			continue
		var hit := _station_rest(next)
		var hit_normal: Vector3 = hit.get("normal", (global_position - station.global_position).normalized())
		var relative_velocity := velocity - station_velocity
		if hit_normal.dot(relative_velocity) > 0.0:
			hit_normal = -hit_normal
		var impact_speed := relative_velocity.length()
		if relative_velocity.dot(hit_normal) < 0.0:
			velocity -= hit_normal * relative_velocity.dot(hit_normal)
		velocity *= 0.22
		if autopilot:
			autopilot = false
			velocity = Vector3.ZERO
			game.hud.show_toast("自动航行中止：前方是归航站", 3.0)
		elif impact_speed > 14.0 and impact_cooldown <= 0.0:
			hull = maxf(0.0, hull - (impact_speed - 10.0) * 0.55)
			impact_cooldown = 1.2
			game.hud.show_toast("撞击空间站 · 船体 %d%% · X 制动" % int(hull), 3.2)
			game.audio.play_impact()
			if hull <= 0.0:
				game.begin_death("飞船撞上空间站解体", 4.2)
		return


func _station_blocked(at_position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull_shape
	query.transform = Transform3D(global_transform.basis, at_position + global_transform.basis * Vector3(0.0, -0.2, 0.2))
	query.collision_mask = STATION_COLLISION_MASK
	query.exclude = [hull_body.get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _station_rest(at_position: Vector3) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull_shape
	query.transform = Transform3D(global_transform.basis, at_position + global_transform.basis * Vector3(0.0, -0.2, 0.2))
	query.collision_mask = STATION_COLLISION_MASK
	query.exclude = [hull_body.get_rid()]
	return get_world_3d().direct_space_state.get_rest_info(query)


func _autopilot_aim(target_position: Vector3) -> Vector3:
	var to_target := target_position - global_position
	var distance := to_target.length()
	if distance < 1.0:
		return target_position
	var direction := to_target / distance
	var closest_t := clampf(-global_position.dot(direction), 0.0, distance)
	var closest := global_position + direction * closest_t
	var clearance: float = game.sun_radius + 1000.0
	var sun_distance := global_position.length()
	if closest.length() >= clearance and sun_distance >= clearance:
		return target_position
	var lateral := closest - direction * closest.dot(direction)
	if lateral.length_squared() < 1.0:
		lateral = direction.cross(Vector3.UP)
	if lateral.length_squared() < 1.0:
		lateral = direction.cross(Vector3.RIGHT)
	lateral = lateral.normalized()
	var severity := clampf((clearance - closest.length()) / clearance, 0.0, 1.0)
	var steer := direction + lateral * (1.2 + severity * 2.4)
	if sun_distance < clearance:
		steer += global_position.normalized() * (1.0 + (clearance - sun_distance) / clearance * 2.0)
	return global_position + steer.normalized() * distance


func dock_station(station_node) -> void:
	if docked or landed:
		return
	docked = true
	docked_station = station_node
	autopilot = false
	landed = false
	landed_planet = null
	velocity = Vector3.ZERO
	global_position = station_node.dock_ship_position()
	look_at(station_node.dock_look_target(), station_node.dock_up_direction())
	game.audio.play_ui(300.0)
	game.hud.show_toast("磁力对接完成 · 按 E 进入归航站", 4.0)


func undock() -> void:
	if not docked:
		return
	var station_node = docked_station
	var outward: Vector3 = station_node.up_direction()
	docked = false
	docked_station = null
	autopilot = false
	dock_cooldown = 3.0
	global_position += outward * 7.0
	velocity = outward * 20.0
	game.audio.play_ui(340.0)
	game.hud.show_toast("已脱离对接 · 手动驾驶", 3.0)


func takeoff() -> void:
	if docked:
		undock()
		return
	if not landed or landed_planet == null:
		return
	var normal: Vector3 = (global_position - landed_planet.global_position).normalized()
	reparent(game, true)
	landed = false
	landed_planet = null
	global_position += normal * 2.8
	velocity = normal * 24.0
	autopilot = false
	game.audio.play_ui(260.0)
	game.hud.show_toast("已升空 · Space 上升 / Ctrl 或 C 下降", 3.0)


func try_land() -> void:
	if landed or docked:
		return
	var planet = game.nearest_planet(global_position)
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	var altitude: float = global_position.distance_to(planet.global_position) - planet.terrain_height(normal)
	if altitude > 70.0:
		game.hud.show_toast("距离地表太远，无法着陆；请先接近到 70 米内。", 2.5)
	elif velocity.length() >= 45.0:
		game.hud.show_toast("相对速度过高 · 按住 X 制动", 2.0)
	else:
		velocity = Vector3.ZERO
		global_position = planet.global_position + planet.surface_position(normal, 3.4)
		land(planet)


func land(planet) -> void:
	if landed:
		return
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	velocity = Vector3.ZERO
	landed = true
	autopilot = false
	landed_planet = planet
	reparent(planet, true)
	global_position = planet.global_position + planet.surface_position(normal, 2.3)
	var transform := global_transform
	var align := Quaternion(transform.basis.y.normalized(), normal)
	transform.basis = (Basis(align) * transform.basis).orthonormalized()
	global_transform = transform
	game.audio.play_ui(330.0)
	game.hud.show_toast("已着陆 · " + planet.display_name + " · E 离船", 3.0)


func _update_engine(delta: float) -> void:
	for material in engine_materials:
		material.emission_energy_multiplier = lerpf(material.emission_energy_multiplier, 0.35 + thrust_level * 3.5, delta * 8.0)
	for light in engine_lights:
		light.light_energy = lerpf(light.light_energy, 0.15 + thrust_level * 1.8, delta * 8.0)


## 把一个盒体塞进按材质分组的 SurfaceTool 批次，用于铆钉 / 格栅 / 防滑条这类重复小件。
func _batch_box(size: Vector3, material: Material, xform: Transform3D) -> void:
	var key := material.get_instance_id()
	if not _batch.has(key):
		var created := SurfaceTool.new()
		created.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batch[key] = {"tool": created, "material": material}
	var entry: Dictionary = _batch[key]
	var tool: SurfaceTool = entry["tool"]
	tool.append_from(_box(size), 0, xform)


## 把批次合并成少量 MeshInstance3D，减少 draw call（网页版单线程，draw call 很贵）。
func _batch_flush() -> void:
	for key in _batch:
		var entry: Dictionary = _batch[key]
		var tool: SurfaceTool = entry["tool"]
		tool.generate_normals()
		var instance := MeshInstance3D.new()
		instance.mesh = tool.commit()
		instance.material_override = entry["material"]
		add_child(instance)
	_batch.clear()


func _light_add(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	add_child(light)


func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance


func _sphere(radius: float, segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return mesh
