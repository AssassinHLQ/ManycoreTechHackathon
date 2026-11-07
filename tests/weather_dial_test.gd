extends SceneTree
# 黄铜天气旋钮：四档轮换、窗外小景切换、指针转动。
# 用法：godot --headless --path . --script res://tests/weather_dial_test.gd

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
	var save := "user://starward_weather_test.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_weather_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.enter_attic()
	await physics_frame

	var attic = game.attic
	_check(attic.WEATHER_ORDER.size() == 4, "旋钮共四档")
	_check(attic.weather_roots.size() == 4, "窗外有四套天候小景")
	_check(attic.dial_index == 0, "初始停在第一档")
	_check(attic.current_weather() == "cloud", "第一档是云海（原作顺序）")
	_check(attic.weather_title() == "云海", "第一档标题为云海")
	_check(attic.dial_pointer != null, "指针已建造")
	_check(attic.dial_anchor() != null, "旋钮有交互锚点")

	# 只有当前那一套可见
	for key in attic.WEATHER_ORDER:
		var root_node: Node3D = attic.weather_roots[key]
		_check(root_node.visible == (key == "cloud"), "云海档位只显示 %s" % key)

	# 轮换顺序：云海 → 萤火森林 → 雨巷 → 雪夜 → 回到云海
	var expected := [["firefly", "萤火森林"], ["alley", "雨巷"], ["snow", "雪夜"], ["cloud", "云海"]]
	for pair in expected:
		var result: Dictionary = attic.cycle_dial()
		_check(String(result["key"]) == String(pair[0]), "轮换到 %s" % pair[0])
		_check(String(result["title"]) == String(pair[1]), "标题为 %s" % pair[1])
		# 可见性跟随
		var visible_count := 0
		for key in attic.WEATHER_ORDER:
			if (attic.weather_roots[key] as Node3D).visible:
				visible_count += 1
		_check(visible_count == 1, "%s 档位只显示一套小景" % pair[0])
		_check((attic.weather_roots[pair[0]] as Node3D).visible, "%s 的小景可见" % pair[0])

	# 指针角度与档位一致
	var pointer_angle: float = attic.dial_pointer.rotation.z
	var expect_angle: float = -TAU * float(attic.dial_index) / 4.0
	_check(absf(pointer_angle - expect_angle) < 0.001, "指针角度跟随档位")

	# 走真实交互路径：站在旋钮前按 E
	var dial: Node3D = attic.dial_anchor()
	var before: int = attic.dial_index
	game.player.global_position = dial.global_position
	await physics_frame
	game._interact()
	await physics_frame
	_check(attic.dial_index == (before + 1) % 4, "站在旋钮前按 E 会拨一档")

	# 站在门前不应被旋钮抢走（门仍可用）
	var door_entry: Dictionary = attic.doors[0]
	game.player.global_position = (door_entry["anchor"] as Node3D).global_position
	await physics_frame
	_check(game.near_attic_door() == door_entry["key"], "离开旋钮后门前识别仍正常")

	game.leave_attic()
	await physics_frame
	print("WEATHER DIAL TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_weather_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if failures == 0 else 1)
