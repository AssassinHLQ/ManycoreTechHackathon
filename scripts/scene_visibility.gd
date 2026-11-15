extends RefCounted
## Screen-sized detail budgets for Web's comparatively expensive draw submission.
## Terrain and large silhouettes remain visible at astronomical distances.
static func apply(root: Node, enabled := OS.has_feature("web")) -> void:
	if not enabled:
		return
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if node.visibility_range_end > 0.0 or node is MultiMeshInstance3D:
			continue
		if node is MeshInstance3D and node.mesh != null:
			var size: float = (node.global_transform * node.get_aabb()).size.length()
			if size >= 800.0:
				continue
			node.visibility_range_end = maxf(120.0, size * 24.0)
		elif node is Label3D:
			node.visibility_range_end = 1400.0
