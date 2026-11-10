extends SceneTree
# 探针：量归航站枢纽里「门旁补墙」到底建出来没有、位置对不对。
#
#   godot --headless --path . --script res://tests/probe_hub_walls.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_hubwalls.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(10):
		await process_frame

	var st: Node3D = game.station
	if st == null:
		print("归航站没建出来")
		quit(1)
		return

	print("=== 枢纽构件统计 ===")
	var hub: Node = st.get_node_or_null("StationHub")
	if hub == null:
		print("  StationHub 不存在")
		quit(1)
		return

	var meshes := 0
	var bodies := 0
	var shapes := 0
	for node in hub.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	for node in hub.find_children("*", "StaticBody3D", true, false):
		bodies += 1
		for c in node.get_children():
			if c is CollisionShape3D:
				shapes += 1
	print("  MeshInstance3D: %d，StaticBody3D: %d，shape: %d" % [meshes, bodies, shapes])

	# 检查「中央升降梯」标牌还在不在（应该没了）
	var labels := 0
	for node in hub.find_children("*", "Label3D", true, false):
		var lb := node as Label3D
		if lb.text.find("升降梯") >= 0:
			labels += 1
			print("  ⚠ 还有「中央升降梯」标牌：", lb.text)
	print("  「中央升降梯」标牌数量：%d（应为 0）" % labels)

	# 量柱子附近的碰撞：在半径 3~5 之间有没有东西
	print("")
	print("=== 沿 +X 方向从站心往外扫，看哪里被挡住 ===")
	print("  半径   命中?")
	for r in [2.0, 3.0, 3.2, 3.4, 3.6, 4.0, 4.2, 4.5]:
		var world: Vector3 = hub.to_global(Vector3(r, 0.5, 0.0))
		var hit := false
		var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
		var q := PhysicsPointQueryParameters3D.new()
		q.position = world
		q.collision_mask = 1
		var res: Array = space.intersect_point(q, 4)
		hit = res.size() > 0
		print("  %5.1f   %s" % [r, "有碰撞" if hit else "空"])
	quit(0)
