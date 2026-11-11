extends SceneTree
# 诊断：沧波星那圈硬边和方块穿插到底是谁画出来的。
#   godot --headless --path . --script res://tests/probe_water_artifact.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_water_diag.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(4):
		await process_frame

	var p = game.planets[2]   # cangbo
	print("=== %s ===" % p.planet_id)
	print("  radius              = %.1f" % float(p.radius))
	print("  lux_model_path      = %s" % p.lux_model_path)
	print("  _lux_height_ready   = %s" % str(p._lux_height_ready))
	var peak := 0.0
	var low := INF
	for h in p._lux_height_map:
		peak = maxf(peak, h)
		low = minf(low, h)
	print("  高度表范围          = %.1f .. %.1f（ratio %.3f）" % [low, peak, peak / maxf(low, 1.0)])
	print("  water_shell         = %s" % ("有" if p.water_shell != null else "无"))
	print("  atmosphere          = %s" % ("有" if p.atmosphere != null else "无"))
	if p.atmosphere != null and p.atmosphere.mesh is SphereMesh:
		print("  大气层球半径        = %.1f（%.3f × radius）" % [
			(p.atmosphere.mesh as SphereMesh).radius,
			(p.atmosphere.mesh as SphereMesh).radius / float(p.radius)])
	if p.clouds != null and p.clouds.mesh is SphereMesh:
		print("  云层球半径          = %.1f（%.3f × radius）" % [
			(p.clouds.mesh as SphereMesh).radius,
			(p.clouds.mesh as SphereMesh).radius / float(p.radius)])
	print("")
	print("=== 所有 MeshInstance3D 子节点 ===")
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var r := -1.0
		if m.mesh is SphereMesh:
			r = (m.mesh as SphereMesh).radius
		elif m.mesh != null:
			r = m.mesh.get_aabb().size.length() * 0.5
		print("  %-24s 半径/包围≈%9.1f  可见=%s  材质=%s" % [
			m.name, r, str(m.visible),
			"Shader" if m.material_override is ShaderMaterial else
			("Std" if m.material_override is StandardMaterial3D else "无")])
	quit(0)
