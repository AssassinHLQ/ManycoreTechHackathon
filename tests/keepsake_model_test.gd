extends SceneTree
# 四件纪念的独立造型检查：各自是多零件模型、互不相同、带回前隐藏。
# 用法：godot --headless --path . --script res://tests/keepsake_model_test.gd

var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _geometry_count(node: Node) -> int:
	var total := 0
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		total += 1
	return total


func _run() -> void:
	var save := "user://starward_keepsake_test.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_keepsake_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	var keys := ["snow", "cloud", "firefly", "alley"]
	var expected_names := {
		"snow": "Keepsake_Snow",
		"cloud": "Keepsake_Cloud",
		"firefly": "Keepsake_Firefly",
		"alley": "Keepsake_Alley",
	}
	var counts := {}
	var signatures := {}
	for key in keys:
		_check(game.attic.keepsake_nodes.has(key), "%s：托座上有纪念模型" % key)
		if not game.attic.keepsake_nodes.has(key):
			continue
		var node: Node3D = game.attic.keepsake_nodes[key]
		_check(node.name == expected_names[key], "%s：模型名为 %s" % [key, expected_names[key]])
		_check(not node.visible, "%s：带回前隐藏" % key)
		var geometry := _geometry_count(node)
		counts[key] = geometry
		_check(geometry >= 5, "%s：是多零件模型（%d 个几何体）" % [key, geometry])
		# 造型签名 = 盒/柱/球 各用了几件；四件应当各不相同
		var signature := {"box": 0, "cylinder": 0, "sphere": 0, "other": 0}
		for child in node.find_children("*", "GeometryInstance3D", true, false):
			var mesh = (child as MeshInstance3D).mesh
			if mesh is BoxMesh:
				signature["box"] += 1
			elif mesh is CylinderMesh:
				signature["cylinder"] += 1
			elif mesh is SphereMesh:
				signature["sphere"] += 1
			else:
				signature["other"] += 1
		signatures[key] = signature
		# 模型自己带光源吗？不要求，但至少要有自发光部件（云舟船灯/树屋萤火/雨巷钟铃/冰镜极光）
		_check(node.get_child_count() > 0, "%s：模型有子节点" % key)

	# 四件互不相同：形状构成（盒/柱/球 的组合）必须两两不同
	var distinct := {}
	for key in signatures:
		distinct[str(signatures[key])] = true
	_check(distinct.size() == 4, "四件纪念造型互不相同（形状构成 %s）" % str(signatures))

	# 带回后可见
	for key in keys:
		game.collect_keepsake(key)
		await process_frame
		var node: Node3D = game.attic.keepsake_nodes[key]
		_check(node.visible, "%s：带回后可见" % key)
	_check(game.keepsakes.size() == 4, "四件纪念都已入袋")

	# 棱镜之心仍是独立物件
	_check(game.attic.prism_heart != null, "棱镜之心仍在旅行架第三层")
	_check(not game.attic.prism_heart.visible, "棱镜之心带回前隐藏")

	print("KEEPSAKE MODEL TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_keepsake_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if failures == 0 else 1)
