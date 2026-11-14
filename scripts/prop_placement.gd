extends RefCounted
## Generated models have arbitrary origins, orientation and proportions.
## Cache resources, not detached scene nodes or instances at a particular size.

var _scenes: Dictionary = {}


func instantiate(asset_name: String, target_height: float, directories: Array,
		orientation := Vector3.ZERO) -> Node3D:
	var path := ""
	for directory in directories:
		for filename in ["model.glb", "model_glb.glb"]:
			var candidate: String = String(directory) + asset_name + "/" + filename
			if ResourceLoader.exists(candidate):
				path = candidate
				break
		if not path.is_empty():
			break
	if path.is_empty():
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	var scene: PackedScene = _scenes[path]
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Prop_" + asset_name
	holder.set_meta("generated_asset", path)
	var pivot := Node3D.new()
	pivot.name = "ModelOrientation"
	holder.add_child(pivot)
	pivot.add_child(model)
	pivot.rotation = orientation
	var box := bounds(holder)
	if box.size.y < 0.00001:
		holder.free()
		return null
	var k := target_height / box.size.y
	pivot.scale *= k
	pivot.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * k
	return holder


## Bounds in the root node's local space, including every descendant transform.
static func bounds(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var result := boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result


static func _collect_bounds(node: Node3D, xf: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		boxes.append(xf * node.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_collect_bounds(child, xf * child.transform, boxes)


## Fit an architectural/furniture envelope. Zero axes retain their current size.
static func fit(node: Node3D, target_size: Vector3) -> void:
	var box := bounds(node)
	var factor := Vector3.ONE
	for axis in range(3):
		if target_size[axis] > 0.0 and box.size[axis] > 0.00001:
			factor[axis] = target_size[axis] / box.size[axis]
	for child in node.get_children():
		if child is Node3D:
			child.transform = Transform3D(Basis.from_scale(factor), Vector3.ZERO) * child.transform


## Rugs/books are sometimes generated standing upright or tilted in space.
static func lay_flat(node: Node3D) -> void:
	var reference := Vector3.ZERO
	var normals: Array[Vector3] = []
	for item in node.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walker: Node = mi
		while walker != node:
			if walker is Node3D:
				xf = walker.transform * xf
			walker = walker.get_parent()
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var normal := (xf * faces[i + 1] - xf * faces[i]).cross(xf * faces[i + 2] - xf * faces[i])
			normals.append(normal)
			if normal.length_squared() > reference.length_squared():
				reference = normal
	if reference == Vector3.ZERO:
		return
	# The generated front face points toward +Z; keep the printed side visible.
	if reference.z < 0.0:
		reference = -reference
	var average := Vector3.ZERO
	for normal in normals:
		average += normal if normal.dot(reference) >= 0.0 else -normal
	var rotation := Basis(Quaternion(average.normalized(), Vector3.UP))
	for child in node.get_children():
		if child is Node3D:
			child.transform = Transform3D(rotation, Vector3.ZERO) * child.transform
	var box := bounds(node)
	var offset := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	for child in node.get_children():
		if child is Node3D:
			child.position -= offset


## Find actual supporting faces. From below, sample undersides for support columns.
static func support_y(node: Node3D, point: Vector2, ceiling: float, from_below := false) -> float:
	var result := INF if from_below else -INF
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.push_front(node)
	for item in meshes:
		var mi := item as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walker: Node = mi
		while walker != node:
			if walker is Node3D:
				xf = walker.transform * xf
			walker = walker.get_parent()
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a: Vector3 = xf * faces[i]
			var b: Vector3 = xf * faces[i + 1]
			var c: Vector3 = xf * faces[i + 2]
			var normal := (b - a).cross(c - a)
			var minimum_y := 0.15 if from_below else 0.8
			if normal.length_squared() < 0.00000001 or absf(normal.normalized().y) < minimum_y:
				continue
			var hit = Geometry3D.ray_intersects_triangle(Vector3(point.x, ceiling, point.y),
				Vector3.UP if from_below else Vector3.DOWN, a, b, c)
			if hit is Vector3:
				result = minf(result, hit.y) if from_below else maxf(result, hit.y)
	return result


## Representative real vertices near the feet, rather than empty AABB corners.
static func contact_points(node: Node3D) -> Array[Vector3]:
	var box := bounds(node)
	var points: Array[Vector3] = []
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.push_front(node)
	for item in meshes:
		var mi := item as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walker: Node = mi
		while walker != node:
			if walker is Node3D:
				xf = walker.transform * xf
			walker = walker.get_parent()
		for vertex in mi.mesh.get_faces():
			var p: Vector3 = xf * vertex
			if p.y > box.position.y + maxf(0.005, box.size.y * 0.015):
				continue
			if points.is_empty():
				points.assign([p, p, p, p, p])
			if p.x < points[0].x:
				points[0] = p
			if p.x > points[1].x:
				points[1] = p
			if p.z < points[2].z:
				points[2] = p
			if p.z > points[3].z:
				points[3] = p
			if p.y < points[4].y:
				points[4] = p
	return points
