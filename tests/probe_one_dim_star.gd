extends SceneTree
# 探针：验证一维星（真实点云资产）的「远看有、靠近散」与材质修补。
# 用法：godot --headless --path . --script res://tests/probe_one_dim_star.gd

var game
var failures := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS  ", msg)
	else:
		failures += 1
		print("FAIL  ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_onedim.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(10):
		await physics_frame

	var star = game.one_dim_star
	_check(star != null, "one_dim_star exists")

	# 不污染现有契约
	_check(game.planets.size() == 10, "planets still 10 (star is decorative, not explorable)")
	_check(game.anomalies.size() == 16, "anomalies still 16 (no scannable signal)")

	# 点云结构
	var model: Node3D = star.model
	_check(model != null, "point-cloud model loaded")
	var meshes: Array = star._meshes
	_check(meshes.size() == 150, "150 point-cloud meshes (%d)" % meshes.size())
	_check(star.TARGET_RADIUS > 100.0, "scaled up to a visible radius")

	# 材质：必须是点云着色器（它负责输出顶点色）。
	# ⚠ 不能用「BaseMaterial3D.vertex_color_use_as_albedo」判 ——
	#   现在用的是 ShaderMaterial，那个属性根本不存在。
	#   （第一版断言就是这么写的，换材质后误报 0/0。）
	var mat_ok := 0
	var checked := 0
	for mi in meshes:
		var mm: Mesh = (mi as MeshInstance3D).mesh
		if mm == null:
			continue
		var m: Material = mm.surface_get_material(0)
		checked += 1
		if m is ShaderMaterial:
			var sm := m as ShaderMaterial
			if sm.shader != null and sm.shader.resource_path.ends_with("one_dim_star.gdshader"):
				mat_ok += 1
		if checked >= 5:
			break
	_check(checked > 0 and mat_ok == checked,
		"every surface uses the point-cloud shader (%d/%d)" % [mat_ok, checked])

	# 远看：全部可见
	var far: Vector3 = star.global_position + Vector3(0, 0, 2000.0)
	game.player.global_position = far
	game.ship.global_position = far
	star._process(0.016)
	var vis_far := _visible_count(meshes)
	print("   距离 %.0f m 时可见 mesh = %d / %d" % [
		star.global_position.distance_to(game.player.global_position), vis_far, meshes.size()])
	_check(vis_far == meshes.size(), "far away: the whole point cloud is visible")

	# 靠近：减少
	var mid: Vector3 = star.global_position + Vector3(0, 0, 260.0)
	game.player.global_position = mid
	game.ship.global_position = mid
	star._process(0.016)
	var vis_mid := _visible_count(meshes)
	print("   距离 %.0f m 时可见 mesh = %d / %d" % [
		star.global_position.distance_to(game.player.global_position), vis_mid, meshes.size()])
	_check(vis_mid < meshes.size(), "closer: the cloud starts dissolving")
	_check(vis_mid > 0, "closer: still partly visible")

	# 贴脸：全消失
	var near: Vector3 = star.global_position + Vector3(0, 0, 60.0)
	game.player.global_position = near
	game.ship.global_position = near
	star._process(0.016)
	var vis_near := _visible_count(meshes)
	print("   距离 %.0f m 时可见 mesh = %d / %d" % [
		star.global_position.distance_to(game.player.global_position), vis_near, meshes.size()])
	_check(vis_near == 0, "very close: the star cannot be observed at all")

	# 退回去恢复
	game.player.global_position = far
	game.ship.global_position = far
	star._process(0.016)
	_check(_visible_count(meshes) == meshes.size(), "moving back out: the star reappears")

	print("\nONE DIM STAR PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)


func _visible_count(meshes: Array) -> int:
	var n := 0
	for mi in meshes:
		if (mi as MeshInstance3D).visible:
			n += 1
	return n
