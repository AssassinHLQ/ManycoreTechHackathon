extends SceneTree
# 量「启动到可操作」耗时：建场时间 + start_game 到玩家落地。
# 用法：godot --headless --path . --script res://tests/_probe_boot_time.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var save := "user://probe_boot.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	var t_inst := Time.get_ticks_msec()
	if not game.world_ready:
		await game.world_ready_finished
	var t_world := Time.get_ticks_msec()
	game.start_game()
	var frames := 0
	while frames < 600 and game.state != "walk":
		await process_frame
		frames += 1
	for i in range(10):
		await physics_frame
	var t_play := Time.get_ticks_msec()
	var pdist: float = game.player.global_position.distance_to(game.ship.global_position)
	print("=== BOOT TIME ===")
	print("  load scene   %6d ms" % (t_inst - t0))
	print("  world ready  %6d ms" % (t_world - t_inst))
	print("  start_game -> walk  %6d ms (%d frames)" % [t_play - t_world, frames])
	print("  total playable %6d ms" % (t_play - t0))
	print("  planets = %d" % game.planets.size())
	print("  remote areas ready = %s" % game.world_areas_ready)
	print("  player->ship = %.2f m (board radius 8)" % pdist)
	game.state = "ship"
	await process_frame
	var stream_start := Time.get_ticks_msec()
	var max_frame_ms := 0.0
	var max_frame_stage := ""
	while game.world_build_remaining:
		var frame_start := Time.get_ticks_usec()
		var stage := "areas"
		if game.world_areas_ready:
			stage = "finalize" if game.planets.size() >= 20 else "planet %d" % game.planets.size()
		await process_frame
		var frame_ms := (Time.get_ticks_usec() - frame_start) / 1000.0
		if frame_ms > max_frame_ms:
			max_frame_ms = frame_ms
			max_frame_stage = stage
	print("=== STREAM TIME ===")
	print("  remote areas ready = %s" % game.world_areas_ready)
	print("  planets after stream = %d" % game.planets.size())
	print("  stream duration = %d ms" % (Time.get_ticks_msec() - stream_start))
	print("  max process_frame wait = %.1f ms" % max_frame_ms)
	print("  max frame stage = %s" % max_frame_stage)
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0)
