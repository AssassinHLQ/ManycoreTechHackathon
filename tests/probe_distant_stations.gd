extends SceneTree
# 探针：给两座远景空间站出图，确认接得对不对、朝向和体量合不合适。
#
# 窗口纪律（AGENTS.md）：运行时把窗口挪到屏幕外 + 命令行带 --no-capture。
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/probe_distant_stations.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("res://captures/station_%s.png" % label)
	print("saved res://captures/station_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_probe_stations.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(30)
	game.hud.visible = false
	game.set_process(false)
	game.state = "capture"

	print("=== 远景空间站清单 ===")
	for holder in game.distant_stations:
		var meshes := 0
		var tris := 0
		for node in holder.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			meshes += 1
			for s in range(mi.mesh.get_surface_count()):
				tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
		print("  %-22s pos=%s  网格=%d  三角≈%d" % [
			holder.name, str(holder.global_position), meshes, tris])

	var cam := Camera3D.new()
	cam.near = 1.0
	cam.far = 200000.0
	cam.fov = 60.0
	game.add_child(cam)
	cam.current = true

	# 每座站拍三个距离
	for i in range(game.distant_stations.size()):
		var holder: Node3D = game.distant_stations[i]
		var center: Vector3 = holder.global_position
		var slug: String = "unknown"
		if holder.name == "DistantStationAlpha":
			slug = "alpha"
		elif holder.name == "DistantStationBeta":
			slug = "beta"
		for spec in [["near", 900.0, 18.0], ["mid", 1800.0, 22.0], ["far", 3200.0, 26.0]]:
			var dist: float = spec[1]
			var pitch := deg_to_rad(float(spec[2]))
			var yaw := deg_to_rad(40.0)
			cam.global_position = center + Vector3(
				cos(pitch) * cos(yaw) * dist,
				sin(pitch) * dist,
				cos(pitch) * sin(yaw) * dist)
			cam.look_at(center, Vector3.UP)
			await _frames(10)
			await _shot("%s_%s" % [slug, spec[0]])

	print("DONE")
	quit(0)
