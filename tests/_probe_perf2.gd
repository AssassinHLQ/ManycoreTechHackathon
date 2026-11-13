extends SceneTree
# 验证：进游戏后是否还卡死 / 显存是否还爆。
# 打点：加载完、start_game 后逐帧观察帧时间与内存。

var game
var _frames_seen := 0
var _worst_frame := 0.0
var _sum_frame := 0.0
var _last_tick := 0


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _mb(b: int) -> String:
	return "%.0f MB" % (float(b) / 1048576.0)


func _run() -> void:
	var save_path := "user://starward_perf2.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	print("=== PERF CHECK ===")
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()
	print("  after world_ready: static=%s" % _mb(OS.get_static_memory_usage()))

	var deadline := Time.get_ticks_msec() + 180000
	while game.planets.size() < 20 and Time.get_ticks_msec() < deadline:
		await process_frame
	print("  after 20 planets: static=%s peak=%s" % [
		_mb(OS.get_static_memory_usage()), _mb(OS.get_static_memory_peak_usage())])

	# 进游戏
	game.start_game()
	await _frames(10)
	print("  after start_game: static=%s" % _mb(OS.get_static_memory_usage()))

	# 观察 240 帧的帧时间
	_last_tick = Time.get_ticks_usec()
	for i in range(240):
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - _last_tick) / 1000.0
		_last_tick = now
		_frames_seen += 1
		_sum_frame += dt
		if dt > _worst_frame:
			_worst_frame = dt

	print("  frames=%d  avg=%.2f ms  worst=%.2f ms" % [
		_frames_seen, _sum_frame / float(maxi(1, _frames_seen)), _worst_frame])
	print("  final static=%s peak=%s" % [
		_mb(OS.get_static_memory_usage()), _mb(OS.get_static_memory_peak_usage())])

	# 飞船是否还在正常位置、有没有立刻死
	print("  ship exists=%s  hull=%.1f  state=%s" % [
		str(game.ship != null), game.ship.hull if game.ship != null else -1.0, game.state])

	print("PERF DONE")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
