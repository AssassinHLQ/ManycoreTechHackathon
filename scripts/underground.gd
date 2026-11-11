extends RefCounted

## 地下洞穴与可进入建筑内部。所有构件都使用地表局部坐标：+Y 为地表法线。
## 洞穴挂在星球自身的 cave_direction 上，建筑内部挂在 Architecture_* 根节点上。

const HOME_WALL_SEGMENTS := 16
const HOME_WALL_RADIUS := 6.55
const HOME_WALL_HEIGHT := 4.4
const HOME_WALL_CENTER_Y := 4.0
const HOME_DOOR_ANGLE := PI * 0.5
const HOME_DOOR_HALF := 0.34

const TIDE_DOOR_WIDTH := 2.2


static func build(planet, kind: String) -> void:
	if not planet.cave_enabled:
		return
	# ⚠ B 方案（用户 2026-11-11 定）：整座洞体跟着 prop_scale（×5）放大，
	#   和放大后的建筑、洞口半径（cave_mouth_radius ×5）同一套尺度。
	#   用 _surface_parent 会让洞还是人类尺寸，而星球已经大 5 倍。
	var root: Node3D = planet._prop_parent(planet.cave_direction, 0.0)
	if root == null:
		return
	root.name = "Cave_%s" % kind.capitalize()
	var palette := _palette(planet, kind)
	var shaft_radius: float = planet.cave_mouth_radius + 0.6
	var chamber_radius := shaft_radius + 9.5
	var floor_y := -13.0
	var ceiling_y := -5.6
	var body := StaticBody3D.new()
	body.name = "CaveCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	_build_rim(root, planet, kind, shaft_radius, palette, body)
	_build_shaft(root, body, shaft_radius, floor_y, palette)
	_build_ramp(root, body, shaft_radius, floor_y, palette)
	_build_chamber(root, body, shaft_radius, chamber_radius, floor_y, ceiling_y, palette, planet, kind)
	var anchor := Node3D.new()
	anchor.name = "CaveAnomalyAnchor"
	anchor.position = Vector3(0, floor_y + 0.1, -chamber_radius * 0.26)
	root.add_child(anchor)
	_limit_range(root, 900.0)


static func _limit_range(node: Node, end: float) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = end
	for child in node.get_children():
		_limit_range(child, end)


static func _palette(planet, kind: String) -> Dictionary:
	var rock_color := Color("4a5048")
	var accent := Color("ffb45c")
	match kind:
		"zheya":
			rock_color = Color("6f6a5c")
			accent = Color("ffd08a")
		"xuanjing":
			rock_color = Color("4d5157")
			accent = Color("ffab5e")
	var rock = planet._material(rock_color)
	var dark = planet._material(rock_color.darkened(0.28))
	var inner = planet._material(rock_color.darkened(0.08))
	inner.cull_mode = BaseMaterial3D.CULL_FRONT
	var glow = planet._material(accent, 1.9)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return {
		"rock": rock,
		"dark": dark,
		"inner": inner,
		"accent": planet._material(accent.darkened(0.15)),
		"glow": glow,
		"warm": planet._material(Color("ffc46b"), 1.5),
		"wood": planet._material(Color("6b4a33"))
	}


# -----------------------------------------------------------------------------
# 洞口：碎石环、门框和两根石柱。
# -----------------------------------------------------------------------------
static func _build_rim(root: Node3D, _planet, _kind: String, shaft_radius: float, palette: Dictionary, body: StaticBody3D) -> void:
	var rock: Material = palette.rock
	var dark: Material = palette.dark
	for i in range(22):
		var angle := TAU * float(i) / 22.0
		if _angle_distance(angle, HOME_DOOR_ANGLE) < 0.42:
			continue
		var radius := shaft_radius + 1.9 + float(i % 3) * 0.6
		var size := 1.2 + float(i % 4) * 0.42
		var boulder := _sphere(root, size, Vector3(cos(angle) * radius, -0.35, sin(angle) * radius), rock if i % 3 else dark)
		boulder.scale = Vector3(1.35, 0.72, 1.1)
		boulder.rotation.y = angle
		var boulder_collision := CollisionShape3D.new()
		var boulder_shape := SphereShape3D.new()
		boulder_shape.radius = size * 1.05
		boulder_collision.shape = boulder_shape
		boulder_collision.position = Vector3(cos(angle) * radius, -0.05, sin(angle) * radius)
		body.add_child(boulder_collision)
	var portal_z := shaft_radius + 0.9
	for side in [-1.0, 1.0]:
		_box(root, Vector3(1.05, 4.6, 1.05), Vector3(side * 2.35, 2.3, portal_z), dark)
		_box(root, Vector3(1.5, 0.55, 1.5), Vector3(side * 2.35, 4.72, portal_z), rock)
		var brace := _box(root, Vector3(0.7, 2.4, 0.7), Vector3(side * 3.7, 1.9, portal_z + 0.2), rock)
		brace.rotation.z = -side * 0.42
		_box_collider(body, Vector3(1.05, 4.6, 1.05), Vector3(side * 2.35, 2.3, portal_z))
	_box(root, Vector3(6.3, 0.8, 1.4), Vector3(0, 4.95, portal_z), rock)
	_box_collider(body, Vector3(6.3, 0.8, 1.4), Vector3(0, 4.95, portal_z))
	_box(root, Vector3(4.6, 0.28, 2.6), Vector3(0, -0.02, portal_z + 1.1), palette.dark)


# -----------------------------------------------------------------------------
# 竖井：14 面石壁，门洞一侧只保留地表以下部分。
# -----------------------------------------------------------------------------
static func _build_shaft(root: Node3D, body: StaticBody3D, shaft_radius: float, floor_y: float, palette: Dictionary) -> void:
	var segments := 14
	var chord := 2.0 * shaft_radius * PI / float(segments) + 0.8
	for i in range(segments):
		var angle := TAU * float(i) / segments
		var basis := Basis(Vector3.UP, -angle)
		var is_door := _angle_distance(angle, HOME_DOOR_ANGLE) < 0.46
		var material: Material = palette.rock if i % 2 == 0 else palette.dark
		if is_door:
			var lower_height := -floor_y + 0.2
			var lower_center := (floor_y - 0.2) * 0.5
			var lower_position := Vector3(cos(angle) * shaft_radius, lower_center, sin(angle) * shaft_radius)
			var panel := _box(root, Vector3(1.4, lower_height, chord), lower_position, material)
			panel.basis = basis
			_box_collider(body, Vector3(1.4, lower_height, chord), lower_position, basis)
		else:
			var height := -floor_y + 2.7
			var center := (floor_y + 2.7) * 0.5
			var position := Vector3(cos(angle) * shaft_radius, center, sin(angle) * shaft_radius)
			var panel := _box(root, Vector3(1.4, height, chord), position, material)
			panel.basis = basis
			_box_collider(body, Vector3(1.4, height, chord), position, basis)


# -----------------------------------------------------------------------------
# 螺旋坡道：40 段微倾石阶，从门口一直绕到洞底。
# -----------------------------------------------------------------------------
static func _build_ramp(root: Node3D, body: StaticBody3D, shaft_radius: float, floor_y: float, palette: Dictionary) -> void:
	var samples := 160
	var radius := shaft_radius - 2.2
	var half_width := 1.5
	var thickness := 0.45
	var start_angle := HOME_DOOR_ANGLE - 0.30
	var total_angle := 0.36 * 40.0
	var start_y := -0.2
	var end_y := floor_y + 0.15
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous_top := []
	var previous_bottom := []
	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var angle := start_angle + total_angle * t
		var y := lerpf(start_y, end_y, t)
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var center := radial * radius
		var inner := center - radial * half_width
		var outer := center + radial * half_width
		var top_inner := inner + Vector3(0, y, 0)
		var top_outer := outer + Vector3(0, y, 0)
		var bottom_inner := inner + Vector3(0, y - thickness, 0)
		var bottom_outer := outer + Vector3(0, y - thickness, 0)
		if i > 0:
			_quad(tool, previous_top[0], top_inner, top_outer, previous_top[1])
			_quad(tool, previous_bottom[0], previous_bottom[1], bottom_outer, bottom_inner)
			_quad(tool, previous_top[1], top_outer, bottom_outer, previous_bottom[1])
			_quad(tool, previous_top[0], previous_bottom[0], bottom_inner, top_inner)
		previous_top = [top_inner, top_outer]
		previous_bottom = [bottom_inner, bottom_outer]
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	surface.material_override = palette.rock
	root.add_child(surface)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	for i in range(0, samples, 10):
		var t := float(i) / float(samples)
		var angle := start_angle + total_angle * t
		var y := lerpf(start_y, end_y, t)
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		_cyl(root, 0.07, 0.11, 1.15, radial * (radius + half_width - 0.15) + Vector3(0, y + 0.45, 0), palette.accent, 6)


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
	tool.add_vertex(a)
	tool.add_vertex(c)
	tool.add_vertex(d)


# -----------------------------------------------------------------------------
# 洞室：圆形地面、16 面岩壁、环形顶板与钟乳石。
# -----------------------------------------------------------------------------
static func _build_chamber(root: Node3D, body: StaticBody3D, shaft_radius: float, chamber_radius: float, floor_y: float, ceiling_y: float, palette: Dictionary, planet, kind: String) -> void:
	var wall_height := ceiling_y - floor_y
	var _floor_mesh := _cyl(root, chamber_radius, chamber_radius + 0.6, 0.7, Vector3(0, floor_y - 0.35, 0), palette.rock, 36)
	_cylinder_collider(body, chamber_radius, 0.7, Vector3(0, floor_y - 0.35, 0))
	_cyl(root, chamber_radius - 1.2, chamber_radius - 1.2, 0.12, Vector3(0, floor_y + 0.02, 0), palette.dark, 36)

	var segments := 16
	var chord := 2.0 * chamber_radius * PI / float(segments) + 1.0
	for i in range(segments):
		var angle := TAU * float(i) / segments
		var basis := Basis(Vector3.UP, -angle)
		var height := wall_height + float(i % 3) * 0.5
		var y := floor_y + height * 0.5
		var position := Vector3(cos(angle) * (chamber_radius + 0.4), y, sin(angle) * (chamber_radius + 0.4))
		_box_collider(body, Vector3(1.1, height, chord), position, basis)
		if i % 4 == 0:
			var rib := _box(root, Vector3(0.5, wall_height * 0.9, 1.0), Vector3(cos(angle) * (chamber_radius - 0.5), floor_y + wall_height * 0.4, sin(angle) * (chamber_radius - 0.5)), palette.dark)
			rib.basis = basis

	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = chamber_radius
	wall_mesh.bottom_radius = chamber_radius
	wall_mesh.height = wall_height + 0.8
	wall_mesh.radial_segments = 40
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	var wall_visual := MeshInstance3D.new()
	wall_visual.mesh = wall_mesh
	wall_visual.material_override = palette.inner
	wall_visual.position.y = floor_y + wall_height * 0.5
	root.add_child(wall_visual)

	var ceiling_mesh := TorusMesh.new()
	ceiling_mesh.inner_radius = shaft_radius - 0.3
	ceiling_mesh.outer_radius = chamber_radius + 0.8
	ceiling_mesh.rings = 48
	ceiling_mesh.ring_segments = 6
	var ceiling_visual := MeshInstance3D.new()
	ceiling_visual.mesh = ceiling_mesh
	ceiling_visual.material_override = palette.inner
	ceiling_visual.position.y = ceiling_y
	ceiling_visual.scale = Vector3(1.0, 0.1, 1.0)
	root.add_child(ceiling_visual)

	var ring_segments := 12
	var mean_radius := (shaft_radius + chamber_radius) * 0.5
	var ring_width := chamber_radius - shaft_radius + 1.4
	for i in range(ring_segments):
		var angle := TAU * float(i) / ring_segments
		var basis := Basis(Vector3.UP, -angle)
		var chord_ceiling := 2.0 * mean_radius * PI / float(ring_segments) + 1.0
		var position := Vector3(cos(angle) * mean_radius, ceiling_y, sin(angle) * mean_radius)
		_box_collider(body, Vector3(ring_width, 0.8, chord_ceiling), position, basis)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4701 + kind.hash()
	for i in range(14):
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(1.0, chamber_radius - 2.0)
		var height := rng.randf_range(1.4, 4.2)
		var base := Vector3(cos(angle) * distance, floor_y, sin(angle) * distance)
		if i % 2 == 0:
			var radius := rng.randf_range(0.5, 1.4)
			_cyl(root, 0.0, radius, height, base + Vector3(0, height * 0.5, 0), palette.rock, 6)
			_cylinder_collider(body, radius * 0.7, height * 0.8, base + Vector3(0, height * 0.4, 0))
		else:
			var radius := rng.randf_range(0.6, 1.6)
			var stalactite := _cyl(root, 0.0, radius, height, Vector3(cos(angle) * distance, ceiling_y, sin(angle) * distance) + Vector3(0, -height * 0.5, 0), palette.dark, 6)
			stalactite.rotation.x = PI
			_cylinder_collider(body, radius * 0.7, height * 0.8, Vector3(cos(angle) * distance, ceiling_y, sin(angle) * distance) + Vector3(0, -height * 0.4, 0))
	_build_props(root, planet, kind, chamber_radius, floor_y, palette, body)
	_light(root, Vector3(0, floor_y + 3.4, 0), _accent_color(kind), 5.0, chamber_radius * 1.45)
	_light(root, Vector3(0, floor_y + 6.0, -chamber_radius * 0.6), _accent_color(kind).darkened(0.2), 2.6, chamber_radius * 1.2)
	_light(root, Vector3(0, floor_y + 1.4, -chamber_radius * 0.35), _accent_color(kind), 1.8, 12.0)


static func _accent_color(kind: String) -> Color:
	match kind:
		"zheya":
			return Color("ffd08a")
		"xuanjing":
			return Color("ffab5e")
	return Color("ffc46b")


# -----------------------------------------------------------------------------
# 每颗星球的洞内陈设。
# -----------------------------------------------------------------------------
static func _build_props(root: Node3D, _planet, kind: String, chamber_radius: float, floor_y: float, palette: Dictionary, body: StaticBody3D) -> void:
	match kind:
		"qinglan":
			var wood: Material = palette.wood
			for i in range(4):
				var angle := TAU * float(i) / 4.0 + 0.4
				var position := Vector3(cos(angle) * (chamber_radius - 4.0), floor_y + 0.6, sin(angle) * (chamber_radius - 4.0))
				_box(root, Vector3(1.3, 1.2, 1.3), position, wood)
				var lid := _box(root, Vector3(1.4, 0.14, 1.4), position + Vector3(0, 0.6, 0), palette.dark)
				lid.rotation.y = angle
				_box_collider(body, Vector3(1.3, 1.2, 1.3), position)
			for i in range(3):
				var angle := TAU * float(i) / 3.0 + 1.1
				var position := Vector3(cos(angle) * (chamber_radius - 3.2), floor_y + 2.6, sin(angle) * (chamber_radius - 3.2))
				_cyl(root, 0.12, 0.18, 5.4, position + Vector3(0, 2.4, 0), wood, 7)
				_box(root, Vector3(0.8, 1.0, 0.8), position + Vector3(0, 4.9, 0), palette.glow)
				_light(root, position + Vector3(0, 4.6, 0), Color("ffc46b"), 1.1, 9.0)
			for i in range(5):
				var angle := TAU * float(i) / 5.0 + 0.2
				var position := Vector3(cos(angle) * (chamber_radius - 1.2), floor_y + 3.4, sin(angle) * (chamber_radius - 1.2))
				var glyph := _box(root, Vector3(1.5, 0.3, 0.08), position, palette.glow)
				glyph.rotation.y = -angle
			var scope_base := Vector3(2.5, floor_y + 0.1, 2.0)
			_cyl(root, 1.1, 1.4, 0.5, scope_base + Vector3(0, 0.25, 0), palette.dark, 10)
			_cylinder_collider(body, 1.2, 0.8, scope_base + Vector3(0, 0.3, 0))
			var scope_dir := Vector3(0.4, 0.75, -0.3).normalized()
			_beam(root, scope_base + Vector3(0, 0.5, 0), scope_base + Vector3(0, 0.5, 0) + scope_dir * 4.6, 0.32, palette.wood, 10)
			_cyl(root, 0.42, 0.42, 0.18, scope_base + Vector3(0, 0.5, 0) + scope_dir * 4.6, palette.glow, 10)
		"zheya":
			_cyl(root, 5.4, 5.4, 0.18, Vector3(0, floor_y + 0.1, chamber_radius * 0.22), palette.glow, 28)
			_light(root, Vector3(0, floor_y + 1.2, chamber_radius * 0.22), Color("ff4a16"), 3.4, 16.0)
			for i in range(6):
				var angle := TAU * float(i) / 6.0 + 0.3
				var position := Vector3(cos(angle) * 8.0, floor_y, sin(angle) * 8.0)
				var height := 3.0 + float(i % 3) * 1.6
				_cyl(root, 0.55, 0.9, height, position + Vector3(0, height * 0.5, 0), palette.dark, 7)
				_cylinder_collider(body, 0.9, height, position + Vector3(0, height * 0.5, 0))
			for i in range(4):
				var angle := TAU * float(i) / 4.0 + 0.8
				var start := Vector3(cos(angle) * 3.4, floor_y + 1.0, sin(angle) * 3.4)
				_beam(root, start, start + Vector3(cos(angle) * 6.0, 4.0, sin(angle) * 6.0), 0.3, palette.accent, 8)
			for i in range(7):
				var angle := TAU * float(i) / 7.0 + 0.1
				var position := Vector3(cos(angle) * (chamber_radius - 1.6), floor_y + 1.6 + float(i % 3) * 1.4, sin(angle) * (chamber_radius - 1.6))
				_sphere(root, 0.22, position, palette.glow)
		"xuanjing":
			for i in range(8):
				var angle := TAU * float(i) / 8.0 + 0.15
				var distance := 6.0 + float(i % 3) * 3.2
				var height := 4.0 + float(i % 4) * 2.2
				var position := Vector3(cos(angle) * distance, floor_y, sin(angle) * distance)
				var crystal := _cyl(root, 0.0, 1.1 + float(i % 2) * 0.4, height, position + Vector3(0, height * 0.5, 0), palette.glow if i % 2 == 0 else palette.accent, 6)
				crystal.rotation.z = sin(float(i) * 1.4) * 0.16
				_cylinder_collider(body, 1.15, height * 0.8, position + Vector3(0, height * 0.4, 0))
			var ring := _ring(root, chamber_radius * 0.42, chamber_radius * 0.46, Vector3(0, floor_y + 0.6, 0), palette.glow)
			ring.rotation.x = 0.1
			for i in range(5):
				var angle := TAU * float(i) / 5.0
				_sphere(root, 0.42, Vector3(cos(angle) * chamber_radius * 0.55, floor_y + 2.4 + float(i % 2) * 1.2, sin(angle) * chamber_radius * 0.55), palette.accent)
			_light(root, Vector3(0, floor_y + 5.2, 0), Color("ffab5e"), 2.4, chamber_radius)


# -----------------------------------------------------------------------------
# 建筑内部。
# -----------------------------------------------------------------------------
static func build_interior(root: Node3D, planet, kind: String) -> void:
	match kind:
		"qinglan":
			_home_interior(root, planet)
		"cangbo":
			_tide_interior(root, planet)


static func _home_interior(root: Node3D, planet) -> void:
	var body := StaticBody3D.new()
	body.name = "InteriorCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var wood = planet._material(Color("6b4a33"))
	var dark_wood = planet._material(Color("3a2c25"))
	var pale = planet._material(Color("a9a291"))
	var brass = planet._material(Color("b88a46"))
	var warm = planet._material(Color("ffc46b"), 1.5)
	warm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glass = planet._material(Color("4e8ea0"), 0.6)
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_cyl(root, 5.95, 5.95, 0.26, Vector3(0, 1.63, 0), wood, 28)
	_cylinder_collider(body, 5.95, 0.26, Vector3(0, 1.63, 0))
	_box(root, Vector3(3.4, 0.05, 2.6), Vector3(-1.2, 1.78, -1.6), planet._material(Color("8a4f46"))).rotation.y = 0.18
	_cyl(root, 5.95, 5.95, 0.26, Vector3(0, 6.02, 0), dark_wood, 28)
	_cylinder_collider(body, 5.95, 0.26, Vector3(0, 6.02, 0))
	_ring(root, 5.6, 5.95, Vector3(0, 5.9, 0), brass)
	var exterior_chord := 2.0 * HOME_WALL_RADIUS * PI / float(HOME_WALL_SEGMENTS) + 0.5
	for i in range(HOME_WALL_SEGMENTS):
		var angle := TAU * float(i) / float(HOME_WALL_SEGMENTS)
		if _angle_distance(angle, HOME_DOOR_ANGLE) < HOME_DOOR_HALF:
			continue
		var basis := Basis(Vector3.UP, -angle)
		var position := Vector3(cos(angle) * HOME_WALL_RADIUS, HOME_WALL_CENTER_Y, sin(angle) * HOME_WALL_RADIUS)
		_box_collider(body, Vector3(0.62, HOME_WALL_HEIGHT, exterior_chord), position, basis)
	for side in [-1.0, 1.0]:
		var angle: float = HOME_DOOR_ANGLE + side * HOME_DOOR_HALF
		var basis := Basis(Vector3.UP, -angle)
		var jamb_position := Vector3(cos(angle) * 6.0, HOME_WALL_CENTER_Y, sin(angle) * 6.0)
		var jamb := _box(root, Vector3(0.6, HOME_WALL_HEIGHT, 0.5), jamb_position, pale)
		jamb.basis = basis
		_box_collider(body, Vector3(0.6, HOME_WALL_HEIGHT, 0.5), jamb_position, basis)

	var segments := HOME_WALL_SEGMENTS
	var chord := 2.0 * 5.72 * PI / float(segments) + 0.45
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		if _angle_distance(angle, HOME_DOOR_ANGLE) < HOME_DOOR_HALF:
			continue
		var basis := Basis(Vector3.UP, -angle)
		var position := Vector3(cos(angle) * 5.72, 3.83, sin(angle) * 5.72)
		var panel := _box(root, Vector3(0.24, 4.14, chord), position, wood if i % 2 == 0 else dark_wood)
		panel.basis = basis
		_box_collider(body, Vector3(0.24, 4.14, chord), position, basis)
		if i % 4 == 1:
			var window := _box(root, Vector3(0.08, 1.2, 1.7), position + Vector3(-cos(angle), 0.5, -sin(angle)) * 0.16, glass)
			window.basis = basis
			_light(root, position + Vector3(-cos(angle), 0.5, -sin(angle)) * 0.7, Color("7fd7e0"), 0.6, 5.0)

	for side in [-1.0, 1.0]:
		var _post := _box(root, Vector3(0.34, 3.6, 0.34), Vector3(side * 1.42, 3.62, 5.52), dark_wood)
		_box_collider(body, Vector3(0.34, 3.6, 0.34), Vector3(side * 1.42, 3.62, 5.52))
	_box(root, Vector3(3.3, 0.42, 0.4), Vector3(0, 5.36, 5.52), dark_wood)
	_box(root, Vector3(2.7, 0.2, 0.9), Vector3(0, 1.82, 5.9), pale)
	_box_collider(body, Vector3(2.7, 0.2, 0.9), Vector3(0, 1.82, 5.9))

	var _globe := _sphere(root, 1.05, Vector3(0.4, 3.4, -0.6), planet._material(planet.accent_color, 1.0))
	_ring(root, 1.35, 1.45, Vector3(0.4, 3.4, -0.6), brass).rotation = Vector3(1.2, 0.2, 0.3)
	_ring(root, 1.7, 1.78, Vector3(0.4, 3.4, -0.6), brass).rotation = Vector3(0.4, 1.1, 0.5)
	_cyl(root, 0.5, 0.8, 0.7, Vector3(0.4, 2.4, -0.6), dark_wood, 10)

	_box(root, Vector3(2.6, 0.14, 1.2), Vector3(-3.2, 2.6, 1.8), wood).rotation.y = 0.25
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.14, 0.9, 1.0), Vector3(-3.2 + side * 1.1, 2.1, 1.8), dark_wood)
	_box(root, Vector3(0.4, 0.5, 0.3), Vector3(-2.7, 2.9, 1.6), warm)
	_box(root, Vector3(1.6, 0.2, 2.2), Vector3(-1.8, 1.85, -2.6), planet._material(Color("8a4f46")))
	_box(root, Vector3(1.2, 1.8, 0.5), Vector3(4.5, 2.65, -3.4), wood).rotation.y = -0.35
	for i in range(4):
		_box(root, Vector3(0.9, 0.12, 0.45), Vector3(4.35, 2.0 + i * 0.42, -3.2), dark_wood).rotation.y = -0.35
	for i in range(6):
		_box(root, Vector3(0.12, 0.34, 1.1), Vector3(-5.0, 2.0 + i * 0.42, -2.2), dark_wood)

	_light(root, Vector3(0, 5.2, 0), Color("ffc46b"), 4.2, 19.0)
	_light(root, Vector3(0, 3.0, 4.2), Color("ffb45c"), 2.0, 9.0)
	_cyl(root, 0.06, 0.06, 0.7, Vector3(0, 5.55, 0), brass, 6)
	_box(root, Vector3(0.62, 0.62, 0.62), Vector3(0, 5.1, 0), warm)
	_box_collider(body, Vector3(2.6, 0.9, 1.2), Vector3(-3.2, 2.5, 1.8))
	_box_collider(body, Vector3(1.2, 1.8, 0.5), Vector3(4.5, 2.65, -3.4))
	_cylinder_collider(body, 0.8, 0.8, Vector3(0.4, 2.4, -0.6))
	var anchor := Node3D.new()
	anchor.name = "InteriorAnomalyAnchor"
	anchor.position = Vector3(0, 1.78, 0.3)
	root.add_child(anchor)


static func _tide_interior(root: Node3D, planet) -> void:
	var body := StaticBody3D.new()
	body.name = "InteriorCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var wall = planet._material(Color("98a9ad"))
	var floor_mat = planet._material(Color("41545c"))
	var dark = planet._material(Color("26333c"))
	var metal = planet._material(Color("71838b"))
	var glow = planet._material(planet.accent_color.lightened(0.2), 2.0)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var orange = planet._material(Color("ff9b42"), 1.8)
	orange.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var center := Vector3(-1.5, 0, 0)
	_box(root, Vector3(8.4, 0.3, 7.4), center + Vector3(0, 12.15, 0), floor_mat)
	_box_collider(body, Vector3(8.4, 0.3, 7.4), center + Vector3(0, 12.15, 0))
	_box(root, Vector3(8.4, 0.3, 7.4), center + Vector3(0, 16.75, 0), dark)
	_box_collider(body, Vector3(8.4, 0.3, 7.4), center + Vector3(0, 16.75, 0))

	_box(root, Vector3(0.3, 4.6, 7.4), center + Vector3(-4.2, 14.45, 0), wall)
	_box_collider(body, Vector3(0.3, 4.6, 7.4), center + Vector3(-4.2, 14.45, 0))
	_box(root, Vector3(0.3, 4.6, 7.4), center + Vector3(4.2, 14.45, 0), wall)
	_box_collider(body, Vector3(0.3, 4.6, 7.4), center + Vector3(4.2, 14.45, 0))
	_box(root, Vector3(8.4, 4.6, 0.3), center + Vector3(0, 14.45, -3.7), wall)
	_box_collider(body, Vector3(8.4, 4.6, 0.3), center + Vector3(0, 14.45, -3.7))

	var side_width := (8.4 - TIDE_DOOR_WIDTH) * 0.5
	for side in [-1.0, 1.0]:
		var offset_x: float = side * (TIDE_DOOR_WIDTH * 0.5 + side_width * 0.5)
		_box(root, Vector3(side_width, 4.6, 0.3), center + Vector3(offset_x, 14.45, 3.7), wall)
		_box_collider(body, Vector3(side_width, 4.6, 0.3), center + Vector3(offset_x, 14.45, 3.7))
	_box(root, Vector3(TIDE_DOOR_WIDTH, 1.4, 0.3), center + Vector3(0, 16.05, 3.7), wall)
	_box_collider(body, Vector3(TIDE_DOOR_WIDTH, 1.4, 0.3), center + Vector3(0, 16.05, 3.7))
	_box(root, Vector3(TIDE_DOOR_WIDTH + 0.7, 0.22, 0.6), center + Vector3(0, 15.45, 3.9), metal)
	var outer_basis := Basis(Vector3.RIGHT, 0.46)
	var outer_position := center + Vector3(0, 11.62, 6.17)
	var outer_ramp := _box(root, Vector3(2.8, 0.2, 1.0), outer_position, metal)
	outer_ramp.basis = outer_basis
	_box_collider(body, Vector3(2.8, 0.2, 1.0), outer_position, outer_basis)
	var inner_basis := Basis(Vector3.RIGHT, 0.44)
	var inner_position := center + Vector3(0, 12.03, 3.15)
	var inner_ramp := _box(root, Vector3(2.8, 0.16, 0.9), inner_position, metal)
	inner_ramp.basis = inner_basis
	_box_collider(body, Vector3(2.8, 0.16, 0.9), inner_position, inner_basis)

	for i in range(4):
		var position := center + Vector3(-3.2 + i * 1.9, 14.3, -3.5)
		_box(root, Vector3(1.5, 1.2, 0.12), position, glow if i % 2 == 0 else orange)
		_box(root, Vector3(1.6, 0.16, 0.2), position + Vector3(0, -0.72, 0.12), metal)
	_box(root, Vector3(6.6, 0.16, 1.2), center + Vector3(0, 13.2, -2.7), dark)
	_cyl(root, 1.05, 1.2, 0.9, center + Vector3(2.2, 12.75, -1.8), dark, 16)
	_cyl(root, 0.82, 0.82, 0.08, center + Vector3(2.2, 13.22, -1.8), glow, 16)
	_box(root, Vector3(1.2, 0.8, 1.2), center + Vector3(2.6, 13.0, 2.2), metal)
	for side in [-1.0, 1.0]:
		_cyl(root, 0.09, 0.12, 3.6, center + Vector3(side * 3.7, 14.4, 2.9), metal, 8)
	_cyl(root, 0.12, 0.18, 4.0, center + Vector3(3.3, 14.2, -2.8), metal, 8)
	_light(root, center + Vector3(0, 15.8, 0), Color("8fdbe6"), 2.4, 13.0)
	_light(root, center + Vector3(0, 13.8, 2.4), Color("ffb05c"), 1.1, 7.0)
	_box_collider(body, Vector3(6.6, 0.9, 1.4), center + Vector3(0, 13.2, -2.7))
	_cylinder_collider(body, 1.2, 0.9, center + Vector3(2.2, 12.75, -1.8))
	_box_collider(body, Vector3(1.2, 0.8, 1.2), center + Vector3(2.6, 13.0, 2.2))
	var anchor := Node3D.new()
	anchor.name = "InteriorAnomalyAnchor"
	anchor.position = center + Vector3(-3.2, 12.31, -1.7)
	root.add_child(anchor)


# -----------------------------------------------------------------------------
# 共享辅助函数。
# -----------------------------------------------------------------------------
static func _angle_distance(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


static func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, position, material)


static func _cyl(parent: Node3D, top: float, bottom: float, height: float, position: Vector3, material: Material, segments: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	return _mesh(parent, mesh, position, material)


static func _sphere(parent: Node3D, radius: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return _mesh(parent, mesh, position, material)


static func _ring(parent: Node3D, inner: float, outer: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 28
	mesh.ring_segments = 8
	return _mesh(parent, mesh, position, material)


static func _beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material, segments: int = 10) -> MeshInstance3D:
	var delta := b - a
	var beam := _cyl(parent, radius, radius, delta.length(), (a + b) * 0.5, material, segments)
	beam.quaternion = Quaternion(Vector3.UP, delta.normalized())
	return beam


static func _light(parent: Node3D, position: Vector3, color: Color, energy: float, distance: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = distance
	parent.add_child(light)
	return light


static func _mesh(parent: Node3D, mesh: Mesh, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance


static func _box_collider(body: StaticBody3D, size: Vector3, position: Vector3, basis := Basis.IDENTITY) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.transform = Transform3D(basis, position)
	body.add_child(collision)


static func _cylinder_collider(body: StaticBody3D, radius: float, height: float, position: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position = position
	body.add_child(collision)
