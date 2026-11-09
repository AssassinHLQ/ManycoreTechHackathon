extends SceneTree
# 探针：为什么 3000 处 1600 速还能逃？量一下它的实际轨迹。
#
#   godot --headless --path . --script res://tests/probe_bh_traj.gd

var game
var ship


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_bh_traj.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	ship = game.ship
	var hole: Vector3 = game.gargantua.global_position

	print("=== 3000 处 1600 速的轨迹 ===")
	print("  捕获圈 BH_FORCE_CAPTURE = %.0f" % ship.BH_FORCE_CAPTURE)
	print("  秒    距离      速度      是否在捕获圈内")
	ship.global_position = hole + Vector3(0.0, 3000.0, 0.0)
	ship.velocity = Vector3(1600.0, 0.0, 0.0)
	ship.bh_orbit_age = 0.0
	ship.bh_captured = false
	var dt := 1.0 / 60.0
	var closest := INF
	var closest_t := 0.0
	var captured_at := -1.0
	for i in range(3600):
		var g: Vector3 = ship._black_hole_pull(dt)
		ship.velocity += g * dt
		ship.global_position += ship.velocity * dt
		var d: float = ship.global_position.distance_to(hole)
		if d < closest:
			closest = d
			closest_t = float(i) * dt
		if d <= ship.BH_FORCE_CAPTURE and captured_at < 0.0:
			captured_at = float(i) * dt
		if i % 30 == 0 and i <= 300:
			print("  %4.1f  %8.1f  %8.1f    %s" % [
				float(i) * dt, d, ship.velocity.length(),
				"是" if d <= ship.BH_FORCE_CAPTURE else "否"])
	print("")
	print("  最近距离 = %.1f（发生在 %.2f 秒）" % [closest, closest_t])
	print("  首次进入捕获圈 = %s" % ("没进过" if captured_at < 0.0 else "%.2f 秒" % captured_at))
	print("  => 捕获圈半径 %.0f，最近只到 %.0f，所以判定从未触发" % [
		ship.BH_FORCE_CAPTURE, closest])
	quit(0)
