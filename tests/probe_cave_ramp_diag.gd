extends SceneTree
# 诊断：Lux3D 星球上洞穴螺旋坡道为什么撑不住玩家。
#   godot --headless --path . --script res://tests/probe_cave_ramp_diag.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_cave_diag.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for _i in range(20):
		await physics_frame

	var home = game.home
	var cave: Node3D = home.find_child("Cave_Qinglan", true, false)
	if cave == null:
		print("没有 Cave_Qinglan")
		quit(1)
		return
	print("cave 本地位置 = %s（长度 %.1f）" % [str(cave.position), cave.position.length()])
	print("cave_direction 在表面高度 = %.1f" % home.terrain_height(home.cave_direction))
	print("surface_position 长度 = %.1f" % home.surface_position(home.cave_direction).length())
	print("site_height = %.1f / radius = %.0f" % [float(home.site_height), float(home.radius)])

	for sample in [24, 64, 104, 144]:
		var t := float(sample) / 160.0
		var angle := PI * 0.5 - 0.30 + 0.36 * 40.0 * t
		var expected_y := lerpf(-0.2, -12.85, t)
		game.player.reparent(home, false)
		game.player.global_position = cave.global_transform * Vector3(
			cos(angle) * 8.4, expected_y + 1.2, sin(angle) * 8.4)
		game.player.velocity = Vector3.ZERO
		for _i in range(45):
			await physics_frame
		var local: Vector3 = cave.global_transform.affine_inverse() * game.player.global_position
		var radial: float = game.player.global_position.length()
		print("  sample %3d: 期望 y=%7.2f  实际 y=%7.2f  差 %6.2f  on_floor=%s  半径=%.1f" % [
			sample, expected_y, local.y, local.y - expected_y,
			str(game.player.is_on_floor()), radial])

	quit(0)
