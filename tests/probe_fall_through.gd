extends SceneTree
# 复现「掉进星球里面」：玩家放下后是否穿过地形碰撞。
#
#   godot --headless --path . --script res://tests/probe_fall_through.gd
#
# 输出：每颗被检星球的
#   · 玩家到球心的距离 vs terrain_height（低于它 = 陷进地里）
#   · on_floor 状态
#   · 地形碰撞体的面数（0 就说明碰撞压根没建）

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _check_planet(p) -> void:
	var site: Vector3 = p.site_direction.normalized()
	var th: float = p.terrain_height(site)
	var spawn: Vector3 = p.global_position + p.surface_position(site, 6.0)
	game.player.reparent(p, false)
	game.player.global_transform = Transform3D(
		Basis(Quaternion(Vector3.UP, site)), spawn)
	game.player.velocity = Vector3.ZERO
	await _frames(120)
	var rel: Vector3 = p.global_transform.affine_inverse() * game.player.global_position
	var dist: float = rel.length()
	# 地形碰撞体面数
	var faces := 0
	for b in p.find_children("*", "StaticBody3D", true, false):
		for c in (b as StaticBody3D).find_children("*", "CollisionShape3D", true, false):
			var sh = (c as CollisionShape3D).shape
			if sh is ConcavePolygonShape3D:
				faces += (sh as ConcavePolygonShape3D).get_faces().size() / 3
	print("%-10s 地形高 %7.1f  玩家距心 %7.1f  差值 %+7.1f  on_floor=%-5s 地形碰撞面 %d" % [
		p.planet_id, th, dist, dist - th, str(game.player.is_on_floor()), faces])


func _run() -> void:
	var save := "user://starward_fall.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(6)
	game.start_game()
	await _frames(20)
	for i in range(1200):
		await process_frame
		if game.planets.size() >= 20:
			break
	await _frames(10)

	print("=== 落地检查（放置后 120 物理帧）===")
	print("%-10s %s" % ["星球", "结果"])
	for idx in [0, 2, 15, 19]:
		await _check_planet(game.planets[idx])
	print("")
	print("判读：差值应该 ≈ +3~6（站在地表上方），on_floor=true。")
	print("      差值明显为负 = 陷进地里 / 掉进星球。")

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
