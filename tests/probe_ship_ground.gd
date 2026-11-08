extends SceneTree
# 探针：量飞船模型相对**地面**的高度，以及座舱相机在船体里的位置。
# 用法：godot --headless --path . --script res://tests/probe_ship_ground.gd
#
# 为什么需要它：
#   飞船模型换过朝向（机头从 -X 修正到 -Z），旧版 SHIP_MODEL_GROUND_SINK=0.96
#   是照着**旧朝向**的模型调的。换完朝向，模型底面相对船体原点的高度变了，
#   硬编码的下压量就不再对 —— 船会悬空或者陷进地里。
#   这里量出「船体原点离模型底面多少米」，让下压量可以按几何算出来。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/models/ship-fighter/model.glb")
	if packed == null:
		print("加载失败")
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "Holder"
	model.rotation = Vector3.ZERO
	holder.add_child(model)
	root.add_child(holder)

	# 和 scripts/ship.gd 的 _build_external_model() 同样算包围盒
	var bounds := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var rel := Transform3D.IDENTITY
			var walker: Node = mi
			while walker != null and walker != model:
				rel = (walker as Node3D).transform * rel
				walker = walker.get_parent()
			if walker == model:
				rel = model.transform * rel
			var box: AABB = rel * mi.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		for child in node.get_children():
			stack.append(child)

	print("模型局部包围盒 position = ", bounds.position)
	print("模型局部包围盒 size     = ", bounds.size)

	var factor := 6.5 / absf(bounds.size.z)
	print("缩放 factor = %.4f" % factor)
	print("缩放后 翼展X=%.3f 机高Y=%.3f 机长Z=%.3f" % [
		absf(bounds.size.x) * factor, absf(bounds.size.y) * factor, absf(bounds.size.z) * factor])
	print("缩放后 底面 y = %.4f（模型自身坐标）" % (bounds.position.y * factor))

	# ship.gd 里 holder.position.y = -bounds.position.y * factor - GROUND_SINK
	# 船体原点在地面上方的距离 = land() 给的 surface_position(normal, 2.3) 的 2.3 m
	# 模型底面相对船体原点 = bounds.position.y*factor + holder.position.y = -GROUND_SINK
	# 所以底面离地高度 = 2.3 - GROUND_SINK
	print("")
	print("=== 落地高度 ===")
	for sink in [0.0, 0.96, 1.5, 2.3]:
		print("  GROUND_SINK=%.2f → 底面离地 %.2f m" % [sink, 2.3 - sink])
	print("  要让底面贴地，GROUND_SINK 应为 2.30")
	print("  （注意 land() 用 surface_position(normal, 2.3)，即船体原点离地 2.3 m）")

	quit(0)
