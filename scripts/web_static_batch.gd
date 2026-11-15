extends RefCounted
## Static authored landmarks only. Gameplay anchors and collision nodes stay intact.
static func apply(planet: Node3D, enabled := OS.has_feature("web")) -> void:
	if not enabled:
		return
	for landmark in planet.find_children("Architecture_*", "Node3D", true, false):
		if landmark.has_meta("web_batched"):
			continue
		var inverse: Transform3D = landmark.global_transform.affine_inverse()
		var buckets := {}
		var sources := 0
		var triangles := 0
		for node in landmark.find_children("*", "MeshInstance3D", true, false):
			if not node.visible or node.mesh == null or node.get_child_count() > 0 or node.skin != null:
				continue
			var transform: Transform3D = inverse * node.global_transform
			var scale: Vector3 = transform.basis.get_scale()
			if absf(scale.x - scale.y) > 0.0001 or absf(scale.y - scale.z) > 0.0001:
				continue
			var valid := true
			for surface in range(node.mesh.get_surface_count()):
				var material: Material = node.get_active_material(surface)
				if not material is StandardMaterial3D or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					valid = false
			if not valid:
				continue
			var center: Vector3 = (transform * node.mesh.get_aabb()).get_center()
			var chunk := Vector3i(floori(center.x / 24.0), floori(center.y / 24.0), floori(center.z / 24.0))
			for surface in range(node.mesh.get_surface_count()):
				var material: Material = node.get_active_material(surface)
				var key := str(material.get_instance_id()) + str(chunk) + str(node.cast_shadow) + str(node.layers)
				if not buckets.has(key):
					var tool := SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					tool.set_material(material)
					buckets[key] = [tool, node.cast_shadow, node.layers]
				var mesh: Mesh = node.mesh
				var arrays: Array = mesh.surface_get_arrays(surface)
				var indices = arrays[Mesh.ARRAY_INDEX]
				triangles += (indices.size() if indices is PackedInt32Array and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
				if not indices is PackedInt32Array or indices.is_empty():
					var indexed := SurfaceTool.new()
					indexed.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
					indexed.index()
					mesh = indexed.commit()
					buckets[key][0].append_from(mesh, 0, transform)
				else:
					buckets[key][0].append_from(mesh, surface, transform)
			node.visible = false
			sources += 1
		var output_triangles := 0
		for bucket in buckets.values():
			var node := MeshInstance3D.new()
			node.name = "WebStaticBatch"
			node.mesh = bucket[0].commit()
			node.cast_shadow = bucket[1]
			node.layers = bucket[2]
			landmark.add_child(node)
			output_triangles += node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
		landmark.set_meta("web_batched", {"sources": sources, "batches": buckets.size(), "triangles": triangles, "output_triangles": output_triangles})
