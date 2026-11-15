extends Node
## Opt-in diagnostics only: --profile-runtime. Never enabled in normal play.
var game
var timer := 0.0

func _process(delta: float) -> void:
	timer += delta
	if timer < 2.0:
		return
	timer = 0.0
	if OS.has_feature("web"):
		var command = JavaScriptBridge.eval("window.__godotPerfCommand || ''")
		JavaScriptBridge.eval("window.__godotPerfCommand = ''")
		match str(command):
			"low", "medium", "high": game.settings.set_quality(str(command))
			"no_shadows": game.key_light.shadow_enabled = false
			"no_msaa": game.get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			"scale70": game.get_viewport().scaling_3d_scale = 0.7
			"sky0": game.apply_sky_detail(0)
			"freeze_orbits":
				for planet in game.planets: planet.set_physics_process(false)
			"hide_props":
				game.home._prop_root.visible = false
			"pocket_cloud", "pocket_firefly", "pocket_alley", "pocket_snow":
				game.enter_pocket(str(command).trim_prefix("pocket_"))
			"leave_pocket": game.leave_pocket()
	var sample := {"state": game.state,
		"render_scale": game.get_viewport().scaling_3d_scale,
		"viewport": str(game.get_viewport().get_visible_rect().size),
		"canvas_pixels": str(game.get_window().size),
		"light_budget": ProjectSettings.get_setting_with_override("rendering/limits/opengl/max_renderable_lights"),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"physics_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)}
	print("RUNTIME PERF ", JSON.stringify(sample))
