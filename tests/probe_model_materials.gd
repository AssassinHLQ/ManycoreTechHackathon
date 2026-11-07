extends SceneTree
# 探针：看一眼刚导入的 glb 在 Godot 里被解析成了什么材质。
#   godot --headless --path . --script res://tests/probe_model_materials.gd -- res://assets/models/black-hole/model.glb

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var argv := OS.get_cmdline_user_args()
	var path := argv[0] if argv.size() > 0 else "res://assets/models/black-hole/model.glb"
	var packed: PackedScene = load(path)
	if packed == null:
		print("加载失败：", path)
		quit(1)
		return
	var root_node: Node = packed.instantiate()
	var meshes := 0
	var tris := 0
	var mins := Vector3(1e18, 1e18, 1e18)
	var maxs := Vector3(-1e18, -1e18, -1e18)
	print("== ", path)
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		meshes += 1
		var mesh: Mesh = mi.mesh
		for surface in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var mat: Material = mi.get_active_material(surface)
			var info := "无材质"
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				info = "Standard albedo=%s emission=%s(%.2f tex=%s) shading=%d unshaded_alpha=%s" % [
					str(sm.albedo_color),
					str(sm.emission_enabled), sm.emission_energy_multiplier,
					sm.emission_texture.resource_path if sm.emission_texture != null else "无",
					sm.shading_mode,
					str(sm.albedo_texture.resource_path if sm.albedo_texture != null else "无")]
			elif mat is BaseMaterial3D:
				info = "BaseMaterial3D shading=%d" % (mat as BaseMaterial3D).shading_mode
			print("  · %-22s surf%d  %s" % [mi.name, surface, info])
		var aabb: AABB = mi.get_aabb()
		mins = mins.min(aabb.position)
		maxs = maxs.max(aabb.position + aabb.size)
	print("网格 %d 个，三角面 %d，局部包围盒 %.0f x %.0f x %.0f" % [
		meshes, tris, maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z])
	quit(0)
