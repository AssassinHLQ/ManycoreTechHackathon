extends SceneTree
# 验证：飞船多阶段降落落稳后，机腹是否真的贴地（不再陷进地形）。
# 用法：godot --headless --path . --script res://tests/_probe_ship_ground.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://probe_ship_ground.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	var ShipScript = load("res://scripts/ship.gd")
	var sink: float = ShipScript.SHIP_MODEL_GROUND_SINK
	var rest: float = ShipScript.LANDING_REST_ALT
	print("=== 常量 ===")
	print("  SHIP_MODEL_GROUND_SINK = %.2f m   LANDING_REST_ALT = %.2f m" % [sink, rest])

	var home = game.home
	var normal := Vector3.UP

	# 实际走一遍多阶段降落（和 _verify_landing_stages.gd 同一套流程）
	game.state = "ship"
	game.ship.landed = false
	game.ship.land_phase = 0
	game.ship.global_position = home.global_position + home.surface_position(normal, 20.0)
	game.ship.velocity = Vector3.ZERO
	game.ship.try_land()
	var frames := 0
	while frames < 900 and not game.ship.landed:
		game.ship._physics_process(1.0 / 60.0)
		frames += 1
	print("=== 降落 ===")
	print("  landed = %s，用了 %d 帧（%.1f 秒）" % [
		str(game.ship.landed), frames, frames / 60.0])

	# landed 分支每帧会用 LANDING_REST_ALT 重钉位置，再推一帧读最终值
	game.ship._physics_process(1.0 / 60.0)
	var dir: Vector3 = (game.ship.global_position - home.global_position).normalized()
	var terrain: float = home.terrain_height(dir)
	var altitude: float = game.ship.global_position.distance_to(home.global_position) - terrain
	var belly: float = altitude - sink
	print("=== 落稳后实测 ===")
	print("  船体原点离地 = %.2f m（期望 %.2f）" % [altitude, rest])
	print("  机腹相对地表 = %+.2f m（0=贴地，负数=陷地）" % belly)
	print("  对照旧常量 2.3：机腹 = %+.2f m" % (2.3 - sink))

	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
