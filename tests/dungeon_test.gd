extends SceneTree
# 镜牢回廊（骨架）：进入、房间推进、归途门、通关结算与最佳纪录。
# 用法：godot --headless --path . --script res://tests/dungeon_test.gd

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


func _run() -> void:
	var save := "user://starward_dungeon_test.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_dungeon_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame

	# --- 原作段位：S 无瑕（无伤且 7 分钟内）/ A 稳镜（受击≤2 且 10 分钟内）/ B 初净 ---
	_check(game.progress.dungeon_rank(300.0, 0) == "S", "无伤且 5 分钟：S 无瑕")
	_check(game.progress.dungeon_rank(500.0, 2) == "A", "受击 2 次且 8 分钟：A 稳镜")
	_check(game.progress.dungeon_rank(700.0, 2) == "B", "超过 10 分钟：B 初净")
	_check(game.progress.dungeon_rank(100.0, 3) == "B", "受击超过 2 次：B 初净")
	_check(game.progress.dungeon_rank(300.0, 0, false) == "B", "中途退出只记 B")
	_check(game.progress.dungeon_rank_name("S") == "无瑕", "S 段位名为无瑕")
	_check(game.progress.dungeon_rank_name("A") == "稳镜", "A 段位名为稳镜")
	_check(game.progress.dungeon_rank_name("B") == "初净", "B 段位名为初净")
	_check(game.progress.time_text(83.0) == "01:23", "时间文本格式 01:23")

	# --- 世界与房间 ---
	_check(game.attic_worlds.world_node("dungeon") != null, "镜牢世界已建造")
	_check(game.attic_worlds.dungeon_room_count() == 6, "镜牢共 6 间房")
	_check(game.attic_worlds.dungeon_room_kind(0) == "combat", "第 1 间是镜室")
	_check(game.attic_worlds.dungeon_room_kind(1) == "boon", "第 2 间是静镜室")
	_check(game.attic_worlds.dungeon_room_kind(5) == "boss", "第 6 间是镜心内厅")

	game.enter_attic()
	await physics_frame
	game.enter_pocket("mirror")
	await physics_frame

	# --- 镜牢门 ---
	var gate = game.attic_worlds.dungeon_gate_anchor()
	_check(gate != null, "镜界里有镜牢门")
	if gate != null:
		game.player.global_position = (gate as Node3D).global_position
		await physics_frame
		_check(game.near_dungeon_gate(), "站在镜牢门前能识别")
		game._interact()
		await physics_frame
		_check(game.pocket_key == "dungeon" and game.dungeon_active, "按 E 进入镜牢")
		_check(game.player.get_parent() == game.attic_worlds.world_node("dungeon"),
			"玩家已挂到镜牢世界下")
		_check(game.dungeon_room == 0, "进入时在第 1 间")
		_check(game.progress.is_unlocked("dungeon_first"), "首次进入解锁成就「镜牢初探」")

	# --- 房间推进 ---
	for i in range(game.attic_worlds.dungeon_room_count()):
		var anchor = game.attic_worlds.dungeon_room_anchor(i)
		_check(anchor != null, "第 %d 间有房间锚点" % (i + 1))
		if anchor == null:
			continue
		game.player.global_position = (anchor as Node3D).global_position
		game._update_dungeon(0.016)
		await physics_frame
		_check(game.dungeon_room == i, "走到第 %d 间时房号正确" % (i + 1))

	# --- 抵达尽头：结算 ---
	var finish = game.attic_worlds.dungeon_finish_anchor()
	_check(finish != null, "镜心内厅有终点锚点")
	if finish != null:
		game.player.global_position = (finish as Node3D).global_position
		game._update_dungeon(0.016)
		await physics_frame
		_check(not game.dungeon_active, "抵达尽头后镜牢状态结束")
		_check(int(game.progress.dungeon.get("clears", 0)) == 1, "记录了一次通关")
		_check(float(game.progress.dungeon.get("best_seconds", 0.0)) >= 0.0, "记录了最好用时")
		_check(String(game.progress.dungeon.get("best_rank", "")) != "", "记录了最好评价")
		_check(game.progress.is_unlocked("dungeon_clear"), "解锁成就「走到尽头」")
		_check(game.pocket_key == "mirror", "结算后回到镜界")

	# --- 归途门：中途可以退出 ---
	if gate != null:
		game.player.global_position = (gate as Node3D).global_position
		await physics_frame
		game._interact()
		await physics_frame
		_check(game.pocket_key == "dungeon", "可以再次进入镜牢")
		var ret = game.attic_worlds.return_anchor("dungeon")
		_check(ret != null, "镜牢入口有归途门")
		if ret != null:
			game.player.global_position = (ret as Node3D).global_position
			await physics_frame
			_check(game.near_pocket_return(), "站在归途门前能识别")
			game.leave_pocket()
			await physics_frame
			_check(game.pocket_key == "mirror", "从归途门出来回到镜界")
			_check(not game.dungeon_active, "中途退出后镜牢状态结束")

	# --- 最快纪录只被更快的一次刷新 ---
	# 先清掉前面那次「瞬移通关」留下的极短纪录，否则 45 秒也刷不掉 0.03 秒
	game.progress.dungeon = {}
	game.progress.record_dungeon(120.0, 6, true)
	var quicker: Dictionary = game.progress.record_dungeon(45.0, 6, true, 0, 0)
	_check(bool(quicker["is_best"]), "更快的一次会刷新纪录")
	_check(String(quicker["best_rank"]) == "S", "最好评价更新为 S")
	var slower: Dictionary = game.progress.record_dungeon(160.0, 6, true)
	_check(not bool(slower["is_best"]), "更慢的一次不刷新纪录")
	_check(String(slower["best_rank"]) == "S", "最好评价保持 S")

	game.leave_pocket()
	await physics_frame
	game.leave_attic()
	await physics_frame
	print("DUNGEON TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_dungeon_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if failures == 0 else 1)
