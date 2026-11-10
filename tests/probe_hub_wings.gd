extends SceneTree
# 探针：专门拍「门框旁边」的补墙，确认缝隙堵上了。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/probe_hub_wings.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("res://captures/hubwing_%s.png" % label)
	print("saved res://captures/hubwing_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_probe_hubwing.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.hud.visible = false
	game.set_process(false)

	var st: Node3D = game.station
	var hub: Node = st.get_node_or_null("StationHub")
	if hub == null:
		print("StationHub 不存在")
		quit(1)
		return
	hub.visible = true

	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 20000.0
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	await _frames(4)

	# 站在枢纽中心偏一点，朝 A 门方向看它的右侧（门框与间隔墙之间）
	var eye_h := 1.6
	for entry in [[0.0, "doorA"], [60.0, "doorB"]]:
		var base_deg: float = entry[0]
		var label: String = entry[1]
		var a := deg_to_rad(base_deg)
		# 站在半径 12 处，朝门的方向看
		cam.global_position = hub.to_global(Vector3(cos(a) * 12.0, eye_h, sin(a) * 12.0))
		cam.look_at(hub.to_global(Vector3(cos(a) * 30.0, eye_h, sin(a) * 30.0)), Vector3.UP)
		await _frames(6)
		await _shot("%s_center" % label)

		# 稍微偏向门框右侧，看缝隙
		var off := deg_to_rad(10.0)
		var a2 := a + off
		cam.global_position = hub.to_global(Vector3(cos(a) * 12.0, eye_h, sin(a) * 12.0))
		cam.look_at(hub.to_global(Vector3(cos(a2) * 30.0, eye_h, sin(a2) * 30.0)), Vector3.UP)
		await _frames(6)
		await _shot("%s_right" % label)

	print("DONE")
	quit(0)
