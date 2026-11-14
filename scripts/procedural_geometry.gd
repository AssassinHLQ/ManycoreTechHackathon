extends RefCounted
## Shared render geometry. Collision dimensions and imported scenes stay authoritative.

static var _meshes: Dictionary = {}
static var _textures: Dictionary = {}

static func box(size: Vector3, bevel := -1.0) -> ArrayMesh:
	var smallest := minf(size.x, minf(size.y, size.z))
	var b := minf(smallest * 0.18, 0.065) if bevel < 0.0 else minf(bevel, smallest * 0.24)
	var key := "box:%s:%s" % [size, b]
	if _meshes.has(key):
		return _meshes[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var inset := h - Vector3.ONE * b
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			for pair in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = h[axis] * sign_value
				p[u] = inset[u] * pair.x
				p[v] = inset[v] * pair.y
				points.append(p)
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			_face(tool, points, normal)
	# Twelve bevel strips and eight planar corner cuts, with exact outer bounds.
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				for pair in [Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1)]:
					var p := Vector3.ZERO
					p[axis] = inset[axis] * pair.x
					p[u] = (h[u] if pair.y == 0 else inset[u]) * su
					p[v] = (inset[v] if pair.y == 0 else h[v]) * sv
					points.append(p)
				var normal := Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				_face(tool, points, normal.normalized())
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var signs := Vector3(sx, sy, sz)
				_face(tool, [Vector3(h.x, inset.y, inset.z) * signs,
					Vector3(inset.x, h.y, inset.z) * signs,
					Vector3(inset.x, inset.y, h.z) * signs], signs.normalized())
	tool.index()
	var result := tool.commit()
	result.set_meta("precision_geometry", "beveled_box")
	_meshes[key] = result
	return result

static func _face(tool: SurfaceTool, points: Array, normal: Vector3) -> void:
	for i in range(1, points.size() - 1):
		var a: Vector3 = points[0]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		if (b - a).cross(c - a).dot(normal) > 0.0:
			var swap := b
			b = c
			c = swap
		for p: Vector3 in [a, b, c]:
			tool.set_normal(normal)
			var dominant := normal.abs().max_axis_index()
			tool.set_uv(Vector2(p[(dominant + 1) % 3], p[(dominant + 2) % 3]))
			tool.add_vertex(p)

static func cylinder(top: float, bottom: float, height: float, segments := 32) -> ArrayMesh:
	var key := "cyl:%s:%s:%s:%d" % [top, bottom, height, segments]
	if _meshes.has(key):
		return _meshes[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bevel := minf(minf(top, bottom) * 0.09, minf(height * 0.14, 0.055))
	var levels := [Vector2(bottom - bevel, -height * 0.5), Vector2(bottom, -height * 0.5 + bevel),
		Vector2(top, height * 0.5 - bevel), Vector2(top - bevel, height * 0.5)]
	for j in range(levels.size() - 1):
		var lo: Vector2 = levels[j]
		var hi: Vector2 = levels[j + 1]
		var slope := (lo.x - hi.x) / maxf(hi.y - lo.y, 0.00001)
		for i in range(segments):
			var a := TAU * float(i) / float(segments)
			var b := TAU * float(i + 1) / float(segments)
			var p := [Vector3(cos(a) * lo.x, lo.y, sin(a) * lo.x), Vector3(cos(b) * lo.x, lo.y, sin(b) * lo.x),
				Vector3(cos(b) * hi.x, hi.y, sin(b) * hi.x), Vector3(cos(a) * hi.x, hi.y, sin(a) * hi.x)]
			# Smooth around the lathe; deliberate creases at the machined lip.
			for idx in [0, 1, 2, 0, 2, 3]:
				var angle := a if idx == 0 or idx == 3 else b
				tool.set_normal(Vector3(cos(angle), slope, sin(angle)).normalized())
				tool.set_uv(Vector2(angle * maxf(top, bottom), p[idx].y))
				tool.add_vertex(p[idx])
	for cap in [0, 3]:
		var level: Vector2 = levels[cap]
		var normal := Vector3.DOWN if cap == 0 else Vector3.UP
		for i in range(segments):
			var a := TAU * float(i) / float(segments)
			var b := TAU * float(i + 1) / float(segments)
			_face(tool, [Vector3(0, level.y, 0), Vector3(cos(a) * level.x, level.y, sin(a) * level.x),
				Vector3(cos(b) * level.x, level.y, sin(b) * level.x)], normal)
	tool.index()
	var result := tool.commit()
	result.set_meta("precision_geometry", "turned_cylinder")
	_meshes[key] = result
	return result

static func refine(mesh: Mesh, preserve_panels := false) -> Mesh:
	if mesh is BoxMesh:
		var size: Vector3 = mesh.size
		# Continuous slabs retain all their corners, including the attic floor joints.
		if preserve_panels and minf(size.x, minf(size.y, size.z)) < 0.20:
			return mesh
		return box(size)
	if mesh is CylinderMesh:
		# Low sided cones are authored crystal/rock silhouettes, not round hardware.
		if mesh.radial_segments <= 8 and (mesh.top_radius < mesh.bottom_radius * 0.25 or mesh.bottom_radius < mesh.top_radius * 0.25):
			return mesh
		if not mesh.cap_top or not mesh.cap_bottom:
			return mesh
		var segments := maxi(mesh.radial_segments, 32)
		if minf(mesh.top_radius, mesh.bottom_radius) > 0.001:
			return cylinder(mesh.top_radius, mesh.bottom_radius, mesh.height, segments)
		mesh.radial_segments = segments
	elif mesh is SphereMesh:
		mesh.radial_segments = maxi(mesh.radial_segments, 32)
		mesh.rings = maxi(mesh.rings, 16)
	elif mesh is CapsuleMesh:
		mesh.radial_segments = maxi(mesh.radial_segments, 32)
		mesh.rings = maxi(mesh.rings, 12)
	elif mesh is TorusMesh:
		mesh.rings = maxi(mesh.rings, 64)
		mesh.ring_segments = maxi(mesh.ring_segments, 12)
	return mesh

static func rock_shell(radius: float, height: float) -> ArrayMesh:
	var key := "rock_shell:%s:%s" % [radius, height]
	if _meshes.has(key):
		return _meshes[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 80
	var layers := 14
	for j in range(layers):
		for i in range(segments):
			var points: Array[Vector3] = []
			for pair: Vector2 in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
				var a := TAU * pair.x / float(segments)
				var y := height * (pair.y / float(layers) - 0.5)
				var r := radius + sin(a * 7.0 + y * 1.7) * 0.12 + sin(a * 17.0 - y * 3.0) * 0.06
				points.append(Vector3(cos(a) * r, y, sin(a) * r))
			var mid: Vector3 = (points[0] + points[2]) * 0.5
			var normal := (points[1] - points[0]).cross(points[3] - points[0]).normalized()
			if normal.dot(Vector3(mid.x, 0, mid.z)) > 0.0:
				normal = -normal
			_face(tool, points, normal)
	tool.index()
	var mesh := tool.commit()
	_meshes[key] = mesh
	return mesh

static func crystal(radius: float, height: float, sides := 6) -> ArrayMesh:
	var key := "crystal:%s:%s:%d" % [radius, height, sides]
	if _meshes.has(key):
		return _meshes[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels := [Vector2(radius * 0.72, -height * 0.5), Vector2(radius, -height * 0.37),
		Vector2(radius * 0.84, height * 0.18)]
	for i in range(sides):
		var a := TAU * float(i) / float(sides)
		var b := TAU * float(i + 1) / float(sides)
		for j in range(2):
			var lo: Vector2 = levels[j]
			var hi: Vector2 = levels[j + 1]
			var normal := Vector3(cos((a + b) * 0.5), (lo.x - hi.x) / (hi.y - lo.y), sin((a + b) * 0.5)).normalized()
			var shade := 0.76 + float((i * 3) % 5) * 0.055
			tool.set_color(Color(shade, shade, shade))
			_face(tool, [Vector3(cos(a) * lo.x, lo.y, sin(a) * lo.x), Vector3(cos(b) * lo.x, lo.y, sin(b) * lo.x),
				Vector3(cos(b) * hi.x, hi.y, sin(b) * hi.x), Vector3(cos(a) * hi.x, hi.y, sin(a) * hi.x)], normal)
		var hi: Vector2 = levels[2]
		var p := Vector3(cos(a) * hi.x, hi.y, sin(a) * hi.x)
		var q := Vector3(cos(b) * hi.x, hi.y, sin(b) * hi.x)
		var apex := Vector3(radius * 0.09, height * 0.5, radius * 0.04)
		var normal := (q - p).cross(apex - p).normalized()
		if normal.dot(Vector3(cos(a), 0, sin(a))) < 0.0:
			normal = -normal
		_face(tool, [p, q, apex], normal)
		var lo: Vector2 = levels[0]
		_face(tool, [Vector3.ZERO + Vector3.UP * lo.y, Vector3(cos(a) * lo.x, lo.y, sin(a) * lo.x),
			Vector3(cos(b) * lo.x, lo.y, sin(b) * lo.x)], Vector3.DOWN)
	tool.index()
	var mesh := tool.commit()
	_meshes[key] = mesh
	return mesh

static func finish_tree(node: Node, style := "stone", preserve_panels := true) -> void:
	if node is Node3D and node.scene_file_path.begins_with("res://assets/models/"):
		return
	if node is MeshInstance3D and node.mesh != null:
		var path: String = node.mesh.resource_path
		if not path.begins_with("res://assets/models/") and not path.contains(".glb"):
			node.mesh = refine(node.mesh, preserve_panels)
			if node.material_override is StandardMaterial3D:
				surface(node.material_override, style)
			for s in range(node.mesh.get_surface_count()):
				if node.mesh.surface_get_material(s) is StandardMaterial3D:
					surface(node.mesh.surface_get_material(s), style)
	for child in node.get_children():
		finish_tree(child, style, preserve_panels)

static func surface(material: StandardMaterial3D, style: String) -> void:
	if material.has_meta("precision_surface") or material.albedo_texture != null \
			or material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
			or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	material.set_meta("precision_surface", style)
	if material.metallic > 0.3:
		style = "metal"
	elif style == "wood":
		var c := material.albedo_color
		if c.b > c.r * 0.9 or c.g > c.r * 0.94:
			style = "plaster"
	var texture := _surface_texture(style)
	material.albedo_texture = texture
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * (1.4 if style == "wood" else 0.7)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Small color/roughness variation preserves authored light and dark values.
	material.roughness_texture = texture
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED

static func _surface_texture(style: String) -> ImageTexture:
	if _textures.has(style):
		return _textures[style]
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 8031
	noise.frequency = 0.12
	for y in range(128):
		for x in range(128):
			# Periodic coordinates make the repeat seam continuous.
			var px := cos(TAU * float(x) / 128.0) * 22.0
			var py := sin(TAU * float(x) / 128.0) * 22.0
			var n := noise.get_noise_3d(px, py, cos(TAU * float(y) / 128.0) * 22.0)
			var value := 0.96 + n * 0.045
			if style == "wood":
				value = 0.94 + sin(TAU * float(y) / 16.0 + n * 2.8) * 0.035 + n * 0.035
			elif style == "metal":
				value = 0.975 + sin(TAU * float(y) / 4.0) * 0.008 + n * 0.012
			elif style == "cloth":
				value = 0.96 + sin(TAU * float(x) / 4.0) * sin(TAU * float(y) / 4.0) * 0.025
			image.set_pixel(x, y, Color(value, value, value))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_textures[style] = texture
	return texture
