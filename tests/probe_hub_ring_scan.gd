extends SceneTree
# 探针：沿半径 30 的圆周扫一圈，看哪些角度有碰撞（= 有墙）。
# 用来确认「六扇门之间」真的封上了。
#
#   godot --headless --path . --script res://tests/probe_hub_ring_scan.gd

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_probe_ringscan.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for _i in range(10):
		await process_frame

	var st: Node3D = game.station
	var hub: Node = st.get_node_or_null("StationHub")
	if hub == null:
		print("StationHub 不存在")
		quit(1)
		return
	hub.visible = true

	print("=== 沿半径 30.5 扫一圈：有碰撞=有墙，无碰撞=能穿出去 ===")
	print("  角度    半径30.5   半径29.0   半径27.5")
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var open_at_outer := 0
	var samples := 0
	# 射线起点：枢纽中心、人眼高度。hub 原点在 y=0，人眼 1.6 米。
	var origin_local := Vector3(0.0, 1.6, 0.0)
	for deg in range(0, 360, 3):
		var a := deg_to_rad(float(deg))
		var row := "  %4d " % deg
		for rr in [30.5, 29.0, 27.5]:
			var world: Vector3 = hub.to_global(Vector3(cos(a) * rr, 1.6, sin(a) * rr))
			# 用射线而不是点查询：0.5 米厚的薄墙用 intersect_point 容易漏判
			var ray := PhysicsRayQueryParameters3D.create(hub.to_global(origin_local), world)
			ray.collision_mask = 1
			var res := space.intersect_ray(ray)
			row += "   %s" % ("墙" if not res.is_empty() else "空")
			if rr == 30.5:
				samples += 1
				if res.is_empty():
					open_at_outer += 1
		print(row)
	print("")
	print("半径 30.5 处：%d/%d 个采样点是空的" % [open_at_outer, samples])
	print("（六扇门各占 3.44° 半角，共应约有 6×2×3.44/3 ≈ 14 个采样点是门洞）")
	quit(0)
