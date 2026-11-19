extends RefCounted
## Authored construction details, batched by material. All positions are visual only;
## floors, door clearance, interaction anchors and collision remain in their builders.
const Geo = preload("res://scripts/procedural_geometry.gd")

var parent: Node3D
var buckets: Dictionary = {}
var pieces := 0
var metal: StandardMaterial3D
var dark: StandardMaterial3D
var pale: StandardMaterial3D
var glow: StandardMaterial3D

func _init(target: Node3D, color := Color("91a8b2"), accent := Color("80cbbb")) -> void:
	parent = target
	metal = _mat(color, 0.65)
	dark = _mat(color.darkened(0.65), 0.3)
	pale = _mat(color.lightened(0.22), 0.15)
	glow = _mat(accent, 0.0)
	glow.emission_enabled = true
	glow.emission = accent
	glow.emission_energy_multiplier = 0.6

func _mat(color: Color, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.55 if metallic > 0.3 else 0.82
	Geo.surface(mat, "metal" if metallic > 0.3 else "stone")
	return mat

func _add(mesh: Mesh, pos: Vector3, mat: Material, basis := Basis.IDENTITY) -> void:
	var key := mat.get_instance_id()
	if not buckets.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		buckets[key] = [st, mat]
	(buckets[key][0] as SurfaceTool).append_from(mesh, 0, Transform3D(basis, pos))
	pieces += 1

func _box(size: Vector3, pos: Vector3, mat: Material, basis := Basis.IDENTITY) -> void:
	_add(Geo.box(size), pos, mat, basis)

func _beam(a: Vector3, b: Vector3, width: float, mat: Material) -> void:
	_add(Geo.cylinder(width, width, a.distance_to(b), 24), (a + b) * 0.5, mat,
		Basis(Quaternion(Vector3.UP, (b - a).normalized())))

func _ring(pos: Vector3, radius: float, tube: float, mat: Material, basis := Basis.IDENTITY) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - tube
	mesh.outer_radius = radius + tube
	mesh.rings = 64
	mesh.ring_segments = 12
	_add(mesh, pos, mat, basis)

func _bolt(pos: Vector3, mat: Material, radius := 0.045, axis := Vector3.UP) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = radius * 0.6
	mesh.radial_segments = 6
	_add(mesh, pos, mat, Basis(Quaternion(Vector3.UP, axis)))

func _panel(center: Vector3, size: Vector2, basis := Basis.IDENTITY) -> void:
	# Bezel and a recessed plate; fasteners occupy the bezel, not the display.
	_box(Vector3(size.x, size.y, 0.075), center, dark, basis)
	_box(Vector3(size.x - 0.10, size.y - 0.10, 0.028), center + basis.z * 0.041, metal, basis)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_bolt(center + basis * Vector3(sx * (size.x * 0.5 - 0.045), sy * (size.y * 0.5 - 0.045), 0.05), pale, 0.025, basis.z)
	for k in range(4):
		_box(Vector3(size.x * 0.60, 0.018, 0.022), center + basis * Vector3(0, (float(k) - 1.5) * 0.065, 0.065), dark, basis)

func _flush(label: String) -> void:
	var mesh := ArrayMesh.new()
	for entry: Array in buckets.values():
		var st: SurfaceTool = entry[0]
		st.set_material(entry[1])
		st.index()
		st.commit(mesh)
	if mesh.get_surface_count() > 0:
		var node := MeshInstance3D.new()
		node.name = "Precision_" + label
		node.mesh = mesh
		node.set_meta("detail_pieces", pieces)
		node.visibility_range_end = 1800.0
		parent.add_child(node)

static func landmark(root: Node3D, kind: String, accent: Color) -> void:
	var d := new(root, Color("8e968d"), accent)
	match kind:
		"qinglan":
			d.metal.albedo_color = Color("9c783d")
			# Tower stave joints and copper rivets, confined to the wooden upper storey.
			for i in range(32):
				var a := TAU * float(i) / 32.0
				var radial := Vector3(cos(a), 0, sin(a))
				d._beam(radial * 5.88 + Vector3.UP * 6.3, radial * 5.73 + Vector3.UP * 10.8, 0.025, d.dark)
				for y in [6.45, 10.65]:
					d._bolt(radial * 5.91 + Vector3.UP * y, d.metal, 0.06, radial)
			# Ribs and root plates rotate with each windmill sail.
			for i in range(6):
				var a := TAU * float(i) / 6.0
				var basis := Basis(Vector3.BACK, -a)
				var center := Vector3(0, 11.6, 7.2) + basis * Vector3(0, 2.9, 0)
				for k in range(7):
					var pos := center + basis * Vector3(0, -2.1 + float(k) * 0.7, 0.145)
					d._box(Vector3(1.35, 0.055, 0.045), pos, d.dark, basis)
				d._box(Vector3(0.16, 4.85, 0.07), center + Vector3.BACK * 0.17, d.metal, basis)
		"zheya":
			# Salt collector straps and segmented siphons follow the four tilted troughs.
			for i in range(4):
				var side := -1.0 if i % 2 == 0 else 1.0
				var z := -7.0 if i < 2 else 7.0
				var basis := Basis.from_euler(Vector3(-0.16, 0.2 * side, 0.1 * side))
				var pos := Vector3(side * 14, 3.6, z)
				for k in [-1.8, 0.0, 1.8]:
					d._box(Vector3(0.11, 0.56, 1.67), pos + basis.x * k, d.dark, basis)
				d._beam(Vector3(side * 14, 0.6, z), pos - Vector3.UP * 0.3, 0.12, d.metal)
			for i in range(8):
				var a := TAU * float(i) / 8.0
				var pos := Vector3(cos(a) * 8.8, 0, sin(a) * 8.8)
				for y in [3.2, 5.8, 8.4, 10.0]:
					d._ring(pos + Vector3.UP * y, 1.0 if y > 5 else 1.16, 0.045, d.metal)
		"cangbo":
			# Catwalk stringers stay below its walking face; deck fasteners sit flush.
			for z in [-1.45, 1.45]:
				d._beam(Vector3(9, 10.6, z), Vector3(31, 10.6, z), 0.13, d.dark)
				for i in range(11):
					d._bolt(Vector3(9.2 + float(i) * 1.85, 11.527, z), d.metal, 0.055)
			for x in [-4.6, -2.5, -0.4, 1.7]:
				d._box(Vector3(1.62, 0.08, 0.16), Vector3(x, 15.51, 4.13), d.metal)
			for x in [-6.0, 0.0, 6.0]:
				for z in [-4.0, 4.0]:
					d._ring(Vector3(x, 2.2, z), 0.51, 0.07, d.metal)
					d._ring(Vector3(x, 9.7, z), 0.42, 0.07, d.metal)
		"xuanjing":
			# Ruptured annulus: curved splice plates, alternating exposed conduits.
			for i in range(18):
				var a := TAU * float(i) / 18.0
				var b := a + 0.17
				var center := Vector3(0, 19.4, 0)
				for r in [6.1, 6.7]:
					var basis := Basis.from_euler(Vector3(0.14, 0, -0.09))
					d._beam(center + basis * Vector3(cos(a) * r, 0.14, sin(a) * r), center + basis * Vector3(cos(b) * r, 0.14, sin(b) * r), 0.045, d.metal)
		"xuanyuan":
			for side in [-1.0, 1.0]:
				for y in [6.0, 12.0, 18.0, 24.0]:
					d._box(Vector3(3.94, 0.13, 3.94), Vector3(side * 10, y, 0), d.metal)
					d._panel(Vector3(side * 10, y + 1.1, 1.925), Vector2(0.8, 1.3))
			for i in range(36):
				var a := TAU * float(i) / 36.0
				var p := Vector3(cos(a) * 9.0, 16 + sin(a) * 9.0, -0.75)
				d._box(Vector3(0.22, 0.50, 0.15), p, d.pale, Basis(Vector3.BACK, a - PI * 0.5))
		"baiyao":
			d.metal.albedo_color = Color("92bdcd")
			# Frost fissures follow the ice terraces, kept below the walk surface.
			for i in range(24):
				var a := TAU * float(i) / 24.0
				var b := a + 0.18
				for layer in [Vector2(14.0, 0.55), Vector2(11.5, 1.55), Vector2(8.8, 2.35)]:
					d._beam(Vector3(cos(a) * layer.x, layer.y, sin(a) * layer.x), Vector3(cos(b) * layer.x, layer.y + 0.12, sin(b) * layer.x), 0.025, d.metal)
		"pansha":
			d.metal.albedo_color = Color("a98c63")
			for i in range(6):
				var a := TAU * float(i) / 6.0
				var h := 9.0 + float(i % 3) * 2.6
				var center := Vector3(cos(a) * 7, 1.8, sin(a) * 7)
				# Weathered sediment seams and shallow vertical flutes.
				for k in range(5):
					var y := 1.0 + float(k) * h / 5.0
					d._ring(center + Vector3.UP * y, lerpf(1.5, 1.15, y / h), 0.026, d.dark)
				for k in range(8):
					var b := TAU * float(k) / 8.0
					var radial := Vector3(cos(b), 0, sin(b))
					d._beam(center + radial * 1.41 + Vector3.UP, center + radial * 1.20 + Vector3.UP * (h - 0.5), 0.018, d.metal)
		"taiyuan":
			d.metal.albedo_color = Color("788571")
			# Beacon louvres and mortar joints belong to the existing tower.
			for i in range(16):
				var a := TAU * float(i) / 16.0
				var basis := Basis(Vector3.UP, -a)
				for y in [6.1, 9.1, 12.1]:
					var r: float = lerpf(2.1, 1.5, (y - 2.1) / 11.0)
					d._box(Vector3(0.08, 0.5, 0.10), Vector3(cos(a) * r, y, sin(a) * r), d.dark, basis)
			for r in [7.6, 11.0, 15.0]:
				for i in range(24):
					var a := TAU * float(i) / 24.0
					d._box(Vector3(0.05, 1.1, 0.06), Vector3(cos(a) * (r + 0.35), 2.45, sin(a) * (r + 0.35)), d.dark)
		"liuwu":
			d.metal.albedo_color = Color("a78854")
			# Open-web crane girders with gussets, cables and a pulley axle.
			for z in [-8.0, 8.0]:
				for i in range(12):
					var x := -9.0 + float(i) * 1.5
					d._beam(Vector3(x, 15.9, z + 0.61), Vector3(x + 1.5, 17.0, z + 0.61), 0.055, d.dark)
					d._beam(Vector3(x, 17.0, z + 0.61), Vector3(x + 1.5, 15.9, z + 0.61), 0.055, d.dark)
				for x in [-10.0, 10.0]:
					d._panel(Vector3(x, 14.5, z + 0.90), Vector2(0.7, 0.8))
			for x in [-0.6, 0.6]:
				d._beam(Vector3(x, 16.85, -8), Vector3(x, 16.85, 8), 0.10, d.dark)
			for z in [-4.0, 4.0]:
				for x in [-0.6, 0.6]:
					d._box(Vector3(0.08, 1.1, 0.34), Vector3(x, 16.3, z), d.dark)
				d._beam(Vector3(-0.7, 15.8, z), Vector3(0.7, 15.8, z), 0.07, d.metal)
				d._ring(Vector3(0, 15.8, z), 0.48, 0.11, d.dark, Basis(Vector3.BACK, PI * 0.5))
				d._beam(Vector3(0, 15.5, z + 0.38), Vector3(0, 13.49, z + 0.38), 0.035, d.metal)
		"jianmo":
			d.metal.albedo_color = Color("65566f")
			for i in range(3):
				var a := TAU * float(i) / 3.0
				var center := Vector3(cos(a) * 9.5, 0.6, sin(a) * 9.5)
				var basis := Basis(Vector3.UP, -a + PI * 0.5)
				for side in [-1.0, 1.0]:
					for y in [3.0, 6.0, 9.0]:
						d._panel(center + basis * Vector3(side * 3.1, y, 0.66), Vector2(0.6, 1.2), basis)
				for k in range(9):
					d._box(Vector3(0.05, 0.35, 0.07), center + basis * Vector3(-2.4 + float(k) * 0.6, 12.0, 0.7), d.pale, basis)
	d._flush("Landmark_" + kind)
	Geo.finish_tree(root, "wood" if kind == "qinglan" else "stone")

static func attic(root: Node3D) -> void:
	var d := new(root, Color("8b613c"), Color("dab276"))
	# Continuous cornice, peg joints, roof purlins and ridge cover. Keep door faces clear.
	for side in [-1.0, 1.0]:
		d._box(Vector3(0.07, 0.10, 5.58), Vector3(side * 3.27, 2.40, 0), d.dark)
		d._box(Vector3(6.52, 0.08, 0.06), Vector3(0, 2.40, side * 2.78), d.metal)
		for z in [-2.6, 0.0, 2.6]:
			d._box(Vector3(0.16, 0.19, 0.20), Vector3(side * 3.25, 2.41, z), d.metal)
			for x in [side * 3.21, side * 3.29]:
				d._bolt(Vector3(x, 2.42, z + 0.107), d.pale, 0.016, Vector3.BACK)
		for x in [1.0, 2.0]:
			var y: float = 3.6 - x * 1.1 / 3.4 - 0.09
			d._box(Vector3(0.075, 0.075, 5.62), Vector3(side * x, y, 0), d.dark)
	# Window apron and restrained panel mouldings below the sill.
	d._box(Vector3(1.95, 0.075, 0.09), Vector3(0, 1.05, 2.77), d.metal)
	for x in [-0.62, 0.62]:
		d._box(Vector3(0.06, 0.55, 0.06), Vector3(x, 0.73, 2.79), d.metal)
	# Floor nail pairs stay flush on the established continuous boards.
	for z in [-2.68, -1.44, -0.20, 1.04, 2.28]:
		for x in [-3.05, 3.05]:
			d._bolt(Vector3(x, 0.002, z), d.dark, 0.009)
	d._flush("AtticJoinery")
	Geo.finish_tree(root, "wood")

static func pocket(root: Node3D, kind: String) -> void:
	var d := new(root, Color("82918f"), Color("b6dbc4"))
	match kind:
		"snow":
			d.metal.albedo_color = Color("9a8266")
			# A framed slatted seat with metal shoes, on the existing bench footprint.
			for x in [-3.15, -1.65]:
				d._box(Vector3(0.12, 0.08, 0.65), Vector3(x, 0.06, 0.6), d.dark)
			for i in range(5):
				d._box(Vector3(1.65, 0.025, 0.07), Vector3(-2.4, 0.52, 0.34 + float(i) * 0.12), d.metal)
		"cloud":
			# Deck board ends get paired nail heads; timber piles get retaining bands.
			var dock := root.get_node_or_null("BoatDock")
			if dock != null:
				var joinery := new(dock, Color("9e8258"))
				for i in range(4):
					for x in [-0.65, 0.65]:
						joinery._bolt(Vector3(x, 0.143 - float(i) * 0.02, float(i) * 0.34), joinery.dark, 0.018)
				joinery._flush("DockFasteners")
			var boat := root.get_node_or_null("CloudBoat")
			if boat != null:
				var ship := new(boat, Color("9c794f"))
				for z in [-0.60, -0.30, 0.30, 0.60]:
					ship._box(Vector3(0.60, 0.018, 0.05), Vector3(0, 0.15, z), ship.dark)
				for side in [-1.0, 1.0]:
					ship._beam(Vector3(side * 0.36, 0.25, -0.70), Vector3(side * 0.36, 0.25, 0.70), 0.025, ship.metal)
				ship._ring(Vector3(0, 0.32, -0.42), 0.044, 0.008, ship.dark)
				ship._flush("BoatRibs")
		"firefly":
			d.metal.albedo_color = Color("85744d")
			var roots := root.get_node_or_null("RootPath")
			if roots != null:
				var bark := new(roots, Color("746044"))
				for z in [-1.2, 0.0, 1.2]:
					for side in [-1.0, 1.0]:
						bark._beam(Vector3(side * 0.22, 0.62, z - 1.95), Vector3(side * 0.18, 0.65, z + 1.95), 0.014, bark.dark)
				bark._ring(Vector3(0, 1.15, 2.1), 0.27, 0.022, bark.metal)
				bark._flush("RootBark")
		"alley":
			d.metal.albedo_color = Color("5b6670")
			for side in [-1.0, 1.0]:
				# Inner wall brick courses and window casings fit within the wall recess.
				for row in range(16):
					var y := 0.35 + float(row) * 0.39
					d._box(Vector3(0.012, 0.014, 22.9), Vector3(side * 3.143, y, 0), d.dark)
					for i in range(17):
						var z := -10.8 + float(i) * 1.30 + (0.65 if row % 2 else 0.0)
						d._box(Vector3(0.014, 0.37, 0.012), Vector3(side * 3.14, y + 0.19, z), d.dark)
				for i in range(6):
					var z := -9.0 + float(i) * 3.4
					for dz in [-0.51, 0.51]:
						d._box(Vector3(0.12, 0.85, 0.07), Vector3(side * 3.08, 3.4, z + dz), d.metal)
					d._box(Vector3(0.19, 0.08, 1.10), Vector3(side * 3.04, 3.0, z), d.pale)
		"mirror":
			d.metal.albedo_color = Color("9dabb4")
			# Shallow wall skirting and edge-capped parapets, without spanning any entry.
			for side in [-1.0, 1.0]:
				d._box(Vector3(0.08, 0.16, 9.9), Vector3(side * 5.81, 0.28, 0), d.dark)
				d._box(Vector3(0.34, 0.07, 10.0), Vector3(side * 6.0, 3.43, 0), d.metal)
				d._panel(Vector3(side * 5.81, 1.5, -3.4), Vector2(1.1, 1.4), Basis(Vector3.UP, -side * PI * 0.5))
	# The actual return portal is identified by its anchor, so all five keep the same layout.
	for portal in root.find_children("ReturnPortal", "Node3D", true, false):
		var p: Vector3 = root.to_local(portal.global_position)
		for side in [-1.0, 1.0]:
			for y in [0.35, 1.85]:
				d._box(Vector3(0.12, 0.22, 0.025), Vector3(p.x + side * 0.62, y, p.z + 0.088), d.metal)
	d._flush("World_" + kind)
	Geo.finish_tree(root, "wood" if kind in ["snow", "cloud", "firefly"] else "stone")

static func cave(root: Node3D, radius: float, floor_y: float, kind: String) -> void:
	var colors := {"qinglan": Color("7b9185"), "zheya": Color("b29166"), "xuanjing": Color("858fa7")}
	var d := new(root, colors.get(kind, Color("82918f")))
	# Geological laminae sit on the chamber perimeter, outside the ramp and floor.
	for level in range(3):
		for i in range(28):
			var a := TAU * float(i) / 28.0
			var b := a + 0.15
			var r := radius - 0.32 - float(level) * 0.10
			var y := floor_y + 1.0 + float(level) * 1.65
			d._beam(Vector3(cos(a) * r, y, sin(a) * r), Vector3(cos(b) * r, y + 0.20, sin(b) * r), 0.045, d.metal)
	for i in range(8):
		var a := TAU * (float(i) + 0.5) / 8.0
		var r := radius - 0.5
		d._panel(Vector3(cos(a) * r, floor_y + 2.2, sin(a) * r), Vector2(0.5, 0.7), Basis(Vector3.UP, -a - PI * 0.5))
	d._flush("CaveStrata")
	Geo.finish_tree(root, "stone")

static func station_hub(root: Node3D) -> void:
	var d := new(root)
	# Six door surrounds: every added part sits above or beside the clear opening.
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var basis := Basis(Vector3.UP, -a)
		var center := Vector3(cos(a) * 30.0, 0, sin(a) * 30.0)
		for side in [-1.0, 1.0]:
			var p := center + basis * Vector3(0, 0, side * 3.70)
			for y in [-1.3, 1.2, 2.5]:
				d._box(Vector3(0.14, 0.24, 0.44), p + Vector3.UP * y, d.metal, basis)
			for y in [-0.6, 0.8, 2.2]:
				d._bolt(p + Vector3.UP * y - basis.x * 0.12, d.pale, 0.065, -basis.x)
		# Door number indicator housing, well above head height.
		d._box(Vector3(0.12, 0.24, 1.2), center - basis.x * 0.20 + Vector3.UP * 2.9, d.dark, basis)
		for k in range(i + 1):
			d._box(Vector3(0.02, 0.12, 0.07), center - basis.x * 0.265 + Vector3.UP * 2.9 + basis.z * (-0.4 + float(k) * 0.15), d.glow, basis)
	d._flush("HubDoorHardware")

static func station_exterior(shell: Node3D, rotating_ring: Node3D) -> void:
	# Hub details share the shell's visibility switch, keeping all six corridors clear.
	var d := new(shell, Color("83918e"), Color("78c9c6"))
	for i in range(24):
		var a := TAU * float(i) / 24.0
		var radial := Vector3(cos(a), 0, sin(a))
		for y in [-15.0, 15.0]:
			var r := sqrt(34.0 * 34.0 - y * y)
			var normal: Vector3 = (radial * r + Vector3.UP * y).normalized()
			d._panel(normal * 34.02, Vector2(1.8, 1.0), Basis.looking_at(-normal, Vector3.UP))
		for y in [-23.0, 23.0]:
			var r := sqrt(34.0 * 34.0 - y * y)
			var normal: Vector3 = (radial * r + Vector3.UP * y).normalized()
			d._bolt(normal * 34.02, d.pale, 0.16, normal)
	d._flush("HubHullHatches")
	var ring := new(rotating_ring, Color("7b8e95"), Color("78c9c6"))
	# Expansion joints, paired clamps and inspection sockets sit on the outer roof.
	for i in range(64):
		var a := TAU * float(i) / 64.0
		var basis := Basis(Vector3.UP, -a)
		var center := Vector3(cos(a) * 280, 8.13, sin(a) * 280)
		ring._box(Vector3(18.8, 0.12, 0.15), center, ring.dark, basis)
		for side in [-1.0, 1.0]:
			var p: Vector3 = center + basis.x * (side * 8.8)
			ring._box(Vector3(0.64, 0.28, 0.50), p, ring.metal, basis)
			ring._bolt(p + Vector3.UP * 0.16, ring.pale, 0.12)
		if i % 4 == 0:
			ring._box(Vector3(1.5, 0.10, 1.2), center + basis.z * 0.9, ring.metal, basis)
			ring._box(Vector3(0.9, 0.04, 0.6), center + basis.z * 0.9 + Vector3.UP * 0.08, ring.dark, basis)
	ring._flush("RingExpansionJoints")

static func distant_hall(root: Node3D, radius: float, height: float) -> void:
	var d := new(root)
	for i in range(24):
		var a := TAU * float(i) / 24.0
		var radial := Vector3(cos(a), 0, sin(a))
		var basis := Basis(Vector3.UP, -a - PI * 0.5)
		# Window sill brackets, low access panels and ceiling service ribs.
		d._box(Vector3(0.13, 0.10, 0.55), radial * (radius - 0.18) + Vector3.UP * 1.0, d.metal, basis)
		if i % 3 == 0:
			d._panel(radial * (radius - 0.20) + Vector3.UP * 0.58, Vector2(1.0, 0.58), basis)
		d._beam(radial * (radius * 0.28) + Vector3.UP * (height - 0.13), radial * (radius * 0.94) + Vector3.UP * (height - 0.13), 0.04, d.dark)
	for r in [radius * 0.4, radius * 0.9]:
		d._ring(Vector3(0, height - 0.12, 0), r, 0.025, d.metal)
	d._flush("HallServices")
	Geo.finish_tree(root, "metal")

static func scanner(root: Node3D, color: Color, variant := "anomaly") -> void:
	var d := new(root, Color("5e7480"), color)
	var r := 1.7 if variant == "anomaly" else 1.15
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var p := Vector3(cos(a) * r, 0.35, sin(a) * r)
		d._bolt(p, d.metal, 0.065)
		d._box(Vector3(0.13, 0.04, 0.28), p + Vector3.UP * 0.04, d.dark, Basis(Vector3.UP, -a))
	if variant == "anomaly":
		for side in [-1.0, 1.0]:
			d._box(Vector3(0.055, 4.4, 0.055), Vector3(side * 0.60, 3.0, -0.39), d.metal)
			for y in [1.0, 5.0]:
				d._bolt(Vector3(side * 0.56, y, -0.42), d.pale, 0.045, Vector3.FORWARD)
	else:
		for i in range(8):
			var a := TAU * float(i) / 8.0
			var radial := Vector3(cos(a), 0, sin(a))
			d._beam(radial * 0.25 + Vector3.UP * 0.45, radial * 1.05 + Vector3.UP * 0.45, 0.025, d.metal)
	d._flush("Signal_" + variant)
	Geo.finish_tree(root, "metal")

static func enemy(root: Node3D, boss: bool) -> void:
	var d := new(root, Color("566e85"), Color("b0c4dc"))
	if boss:
		# Segmented containment cage instead of an unadorned glowing sphere.
		for i in range(8):
			var a := TAU * float(i) / 8.0
			var radial := Vector3(cos(a), 0, sin(a))
			# Follow the spherical envelope; straight chords disappear inside the core.
			for k in range(12):
				var p := 0.22 + (PI - 0.44) * float(k) / 12.0
				var q := 0.22 + (PI - 0.44) * float(k + 1) / 12.0
				d._beam(radial * (sin(p) * 0.99) + Vector3.UP * (1.5 + cos(p) * 0.99),
					radial * (sin(q) * 0.99) + Vector3.UP * (1.5 + cos(q) * 0.99), 0.032, d.metal)
			d._beam(radial * 0.99 + Vector3.UP * 1.5, radial * 1.22 + Vector3.UP * 1.5, 0.045, d.dark)
			d._box(Vector3(0.20, 0.22, 0.18), radial * 1.35 + Vector3.UP * 1.5, d.dark, Basis(Vector3.UP, -a))
		for y in [1.05, 1.5, 1.95]:
			d._ring(Vector3(0, y, 0), sqrt(0.99 * 0.99 - pow(y - 1.5, 2)), 0.024, d.metal)
		for y in [0.53, 2.47]:
			d._ring(Vector3(0, y, 0), 0.22, 0.045, d.dark)
	else:
		# Faceplate, eye slit, shoulder shards and segmented lower armour.
		d._box(Vector3(0.37, 0.27, 0.10), Vector3(0, 1.64, -0.24), d.dark)
		d._box(Vector3(0.25, 0.025, 0.015), Vector3(0, 1.66, -0.30), d.glow)
		for side in [-1.0, 1.0]:
			d._box(Vector3(0.19, 0.30, 0.31), Vector3(side * 0.35, 1.29, 0), d.metal, Basis(Vector3.BACK, side * 0.28))
		for y in [0.35, 0.65, 0.95]:
			var radius := lerpf(0.42, 0.28, y / 1.5)
			d._box(Vector3(0.30, 0.14, 0.07), Vector3(0, y, -radius - 0.025), d.dark,
				Basis(Vector3.RIGHT, atan((0.42 - 0.28) / 1.5)))
		d._ring(Vector3(0, 1.15, 0), 0.31, 0.025, d.metal)
	d._flush("EnemyArmour")
	Geo.finish_tree(root, "metal")
