extends SceneTree

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
	var test_save := "user://starward_settings_test.json"
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_settings_game.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	var s = game.settings
	_check(s != null, "settings service exists")
	if s == null:
		quit(1)
		return
	s.save_path = test_save
	s.set_quality("low")
	_check(int(s.values.msaa) == 0 and int(s.values.grass) == 0, "low preset turns off MSAA and thins grass")
	s.set_shadows(0)
	_check(not game.key_light.shadow_enabled, "shadows can be disabled at runtime")
	var ranged: Array = s.ranged_nodes
	_check(not ranged.is_empty(), "distance-culled nodes were collected")
	if not ranged.is_empty():
		var base_range: float = ranged[0][1]
		s.set_view_distance(0)
		_check(ranged[0][0].visibility_range_end < base_range, "view distance scales culled nodes")
	var scatter = null
	for node in game.home.find_children("*", "MultiMeshInstance3D", true, false):
		if node.is_in_group("ground_scatter"):
			scatter = node
			break
	_check(scatter != null, "ground scatter is tagged")
	if scatter != null:
		s.set_grass(0)
		_check(scatter.multimesh.visible_instance_count < scatter.multimesh.instance_count, "grass density reduces visible instances")
	s.set_msaa(2)
	_check(game.get_viewport().msaa_3d == Viewport.MSAA_4X, "MSAA applies to the viewport")
	s.set_sky_detail(0)
	_check(int(s.values.sky_detail) == 0 and int(game.sky_material.get_shader_parameter("sky_detail")) == 0, "sky detail 0 reaches the sky shader")
	s.set_sky_detail(3)
	_check(int(s.values.sky_detail) == 3 and int(game.sky_material.get_shader_parameter("sky_detail")) == 3, "sky detail 3 reaches the sky shader")
	s.set_sky_detail(9)
	_check(int(s.values.sky_detail) == 3, "sky detail is clamped into 0..3")
	_check(str(s.values.quality) == "custom", "changing sky detail alone marks the quality preset custom")
	s.set_quality("low")
	_check(int(s.values.sky_detail) == 0, "the low preset drops the sky detail as well")
	s.set_quality("high")
	_check(int(s.values.sky_detail) == 3, "the high preset lifts the sky detail")
	_check(int(game.sky_material.get_shader_parameter("sky_detail")) == 3, "the preset's sky detail reaches the sky shader")
	s.set_fps_limit(60)
	_check(Engine.max_fps == 60, "frame cap applies")
	s.set_fps_limit(144)
	_check(Engine.max_fps == 144, "high-refresh frame caps apply")
	s.set_sensitivity(1.8)
	_check(is_equal_approx(s.sensitivity_multiplier(), 1.8), "mouse sensitivity applies to walking and flight")
	s.set_view_distance(2)
	s.save_settings()
	var saved_view: int = int(s.values.view_distance)
	s.values.view_distance = 0
	s.load_settings()
	_check(int(s.values.view_distance) == saved_view, "settings persist to disk")
	s.reset_defaults()
	_check(int(s.values.view_distance) == 1 and int(s.values.msaa) == 1, "restore defaults works")
	_check(int(s.values.sky_detail) == 3, "restore defaults restores the sky detail tier")
	Engine.max_fps = 0
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("SETTINGS TEST COMPLETE: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
