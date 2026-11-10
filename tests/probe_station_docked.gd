extends SceneTree
# 探针：让飞船真的停靠在远景站上，出图看停靠姿势对不对。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/probe_station_docked.gd -- --no-capture

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
	img.save_png("res://captures/docked_%s.png" % label)
	print("saved res://captures/docked_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_probe_docked.json"
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

	var cam := Camera3D.new()
	cam.near = 0.5
	cam.far = 300000.0
	cam.fov = 60.0
	game.add_child(cam)
	cam.current = true

	for i in range(game.distant_stations.size()):
		var st: Node3D = game.distant_stations[i]
		var slug: String = "alpha" if st.name == "DistantStationAlpha" else "beta"
		var port: Vector3 = st.dock_ship_position()

		# 真的把飞船摆到停靠位上，否则图里只有站、看不到「停靠」这回事。
		if game.ship != null:
			game.ship.global_position = port
			game.ship.look_at(st.dock_look_target(), st.dock_up_direction())
			game.ship.visible = true
			game.ship.set_process(false)
			game.ship.set_physics_process(false)
			print("  %s 停泊位 %s，飞船实际 %s，可见=%s，缩放=%s" % [
				slug, str(port), str(game.ship.global_position),
				str(game.ship.visible), str(game.ship.scale)])
			# 船有多大？量一下包围盒，好把镜头对上
			var ship_lo := Vector3(INF, INF, INF)
			var ship_hi := Vector3(-INF, -INF, -INF)
			for node in game.ship.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				if mi.mesh == null:
					continue
				var box: AABB = mi.get_aabb()
				for k in range(8):
					var corner := box.position + Vector3(
						box.size.x if (k & 1) else 0.0,
						box.size.y if (k & 2) else 0.0,
						box.size.z if (k & 4) else 0.0)
					var p: Vector3 = mi.global_transform * corner
					ship_lo = Vector3(minf(ship_lo.x, p.x), minf(ship_lo.y, p.y), minf(ship_lo.z, p.z))
					ship_hi = Vector3(maxf(ship_hi.x, p.x), maxf(ship_hi.y, p.y), maxf(ship_hi.z, p.z))
			print("  飞船包围盒尺寸 %s" % str(ship_hi - ship_lo))

		# 镜头：靠近一点，把飞船框进去（船只有十几米，420 米外就是个点）
		cam.global_position = port + Vector3(60.0, 38.0, 60.0)
		cam.look_at(port, Vector3.UP)
		await _frames(10)
		await _shot("%s_shipdock" % slug)

		# 再拍一张远一点的全身
		cam.global_position = st.global_position + Vector3(1100.0, 620.0, 1100.0)
		cam.look_at(st.global_position, Vector3.UP)
		await _frames(8)
		await _shot("%s_wide" % slug)

	print("DONE")
	quit(0)
