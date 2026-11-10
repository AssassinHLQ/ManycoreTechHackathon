extends SceneTree
# 探针：诊断一维星全量版为什么渲染全黑。
# 用法：godot --headless --path . --script res://tests/probe_onedim_black.gd
#
# 逐项排除：
#   1. 模型能不能加载、有多少 mesh
#   2. mesh 的 AABB 是否合理（不是 0 或 NaN）
#   3. 材质是否换成了点云着色器
#   4. 相机看过去是否在 AABB 范围内

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/models/one-dim-star/model.glb")
	if packed == null:
		print("FAIL: 加载失败")
		quit(1)
		return
	var node := packed.instantiate() as Node3D
	root.add_child(node)
	await process_frame

	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	print("MeshInstance3D = %d" % meshes.size())

	var mn := Vector3(1e18, 1e18, 1e18)
	var mx := Vector3(-1e18, -1e18, -1e18)
	var zero_aabb := 0
	var total_vis := 0
	for child in meshes:
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			print("  ⚠ %s mesh 为 null" % mi.name)
			continue
		var aabb: AABB = mi.get_aabb()
		var sz := aabb.size
		if sz.length() < 0.0001:
			zero_aabb += 1
		if mi.visible:
			total_vis += 1
		var w := mi.global_transform * aabb
		mn = mn.min(w.position)
		mx = mx.max(w.position + w.size)
	print("  AABB 为 0 的 mesh = %d" % zero_aabb)
	print("  可见 mesh = %d" % total_vis)
	print("  世界包围盒 min=%s" % mn)
	print("  世界包围盒 max=%s" % mx)
	print("  尺寸 = %s  中心 = %s" % [mx - mn, (mn + mx) * 0.5])

	# 看第一个 mesh 的材质
	var first := meshes[0] as MeshInstance3D
	var mm: Mesh = first.mesh
	print("")
	print("第一个 mesh: surfaces = %d" % mm.get_surface_count())
	print("  图元类型 = %d (0=POINTS)" % mm.surface_get_primitive_type(0))
	var m: Material = mm.surface_get_material(0)
	print("  材质 = %s" % (m.get_class() if m else "null"))
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		print("  shader = %s" % (sm.shader.resource_path if sm.shader else "null"))
		print("  brightness = %s" % sm.get_shader_parameter("brightness"))

	var arrays: Array = mm.surface_get_arrays(0)
	var varr: Variant = arrays[Mesh.ARRAY_VERTEX]
	var carr: Variant = arrays[Mesh.ARRAY_COLOR]
	print("  顶点数 = %d" % ((varr as PackedVector3Array).size() if varr != null else -1))
	print("  颜色数 = %d" % ((carr as PackedColorArray).size() if carr != null else -1))
	if carr != null:
		var ca: PackedColorArray = carr
		if ca.size() > 0:
			print("  前 3 色 = %s %s %s" % [ca[0], ca[1], ca[2]])

	print("BLACK DIAG DONE")
	quit(0)
