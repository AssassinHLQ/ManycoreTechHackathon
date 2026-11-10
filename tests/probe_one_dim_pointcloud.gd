extends SceneTree
# 探针：验证 A Windy Day 点云在 Godot 里的真实情况。
# 用法：godot --headless --path . --script res://tests/probe_one_dim_pointcloud.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in ["res://assets/models/one-dim-star/model.glb",
				 "res://assets/models/_tmp_original_test/model.glb"]:
		print("=== ", path, " ===")
		var packed: PackedScene = load(path)
		if packed == null:
			print("  加载失败")
			continue
		var node := packed.instantiate() as Node3D
		root.add_child(node)
		var meshes := 0
		var total_verts := 0
		var total_prims := 0
		var primitive_modes := {}
		var mn := Vector3(1e18, 1e18, 1e18)
		var mx := Vector3(-1e18, -1e18, -1e18)
		for child in node.find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			var mi := child as MeshInstance3D
			var mesh: Mesh = mi.mesh
			if mesh == null:
				continue
			for s in range(mesh.get_surface_count()):
				total_prims += 1
				var arrays: Array = mesh.surface_get_arrays(s)
				var varr: Variant = arrays[Mesh.ARRAY_VERTEX]
				if varr != null:
					var va: PackedVector3Array = varr
					total_verts += va.size()
					for v in va:
						var w: Vector3 = mi.global_transform * v
						mn = mn.min(w)
						mx = mx.max(w)
				var fmt: int = mesh.surface_get_primitive_type(s)
				primitive_modes[fmt] = primitive_modes.get(fmt, 0) + 1
		print("  MeshInstance3D = %d" % meshes)
		print("  surface = %d" % total_prims)
		print("  顶点合计 = %d" % total_verts)
		print("  图元类型分布 = %s  (0=POINTS,4=TRIANGLES)" % primitive_modes)
		if total_verts > 0:
			print("  包围盒 size = %s" % (mx - mn))
		node.queue_free()
	print("PROBE DONE")
	quit(0)
