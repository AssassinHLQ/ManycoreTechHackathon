extends SceneTree
# 五颗次天体的地标取证截图：每颗一张远景 + 一张中景。
# 用法：godot --position 20000,20000 --path . --script res://tests/capture_secondary.gd

var game
var review_camera: Camera3D


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://captures/" + name + ".png"
	var result := image.save_png(path)
	print("CAPTURE ", path, " -> ", error_string(result))


func _run() -> void:
	var capture_save := "user://starward_capture_secondary.json"
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = capture_save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.start_game()
	await _frames(20)
	game.hud.menu.visible = false
	game.hud.toast.visible = false
	game.hud.visible = false

	review_camera = Camera3D.new()
	review_camera.near = 0.5
	review_camera.far = 60000.0
	review_camera.fov = 55.0
	game.add_child(review_camera)
	review_camera.current = true
	game.state = "capture"

	var targets := [
		["baiyao", "白曜星"],
		["pansha", "磐砂星"],
		["taiyuan", "苔垣星"],
		["liuwu", "硫坞星"],
		["jianmo", "缄默星"],
	]
	for entry in targets:
		var planet = null
		for candidate in game.planets:
			if candidate.planet_id == entry[0]:
				planet = candidate
				break
		if planet == null:
			print("MISSING PLANET ", entry[0])
			continue
		var arch = planet.find_child("Architecture_*", true, false)
		var focus: Vector3 = arch.global_position if arch != null else planet.global_position
		var up: Vector3 = (focus - planet.global_position).normalized()
		var side: Vector3 = up.cross(Vector3.FORWARD).normalized()
		if side.length_squared() < 0.01:
			side = up.cross(Vector3.RIGHT).normalized()

		# 远景：整颗星球与地标剪影
		review_camera.global_position = focus + up * (planet.radius * 1.5) + side * (planet.radius * 1.7)
		review_camera.look_at(focus, up)
		await _frames(10)
		await _capture("secondary_%s_far" % entry[0])

		# 中景：地标本体
		review_camera.global_position = focus + up * 46.0 + side * 58.0
		review_camera.look_at(focus + up * 8.0, up)
		await _frames(10)
		await _capture("secondary_%s_near" % entry[0])

	print("SECONDARY CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(capture_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_save))
	quit(0)
