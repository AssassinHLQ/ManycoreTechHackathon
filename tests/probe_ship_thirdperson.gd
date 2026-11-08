extends SceneTree
# 探针：核对「第三人称不包含主角」。
# 用法：godot --headless --path . --script res://tests/probe_ship_thirdperson.gd
#
# 为什么需要它：
#   玩家节点不是「空壳」—— 它带着自己的 Camera3D 和提灯（SpotLight3D）。
#   登船时只设了 player.visible = false，但：
#     · Camera3D 是 current=false 时不渲染，visible=false 也不影响它；
#     · 提灯是光源，GeometryInstance3D 之外的 Light3D **不受 visible 影响**；
#     · 玩家的碰撞胶囊是 Shape3D，也不渲染。
#   所以「看不见主角」这件事**不能靠眼睛看**，得逐项核对。

var game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := "user://starward_tp_probe.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(8):
		await physics_frame

	var failures := 0
	var ship = game.ship
	var player = game.player

	print("=== 登船前 ===")
	print("  player.visible = ", player.visible)
	print("  player.camera.current = ", player.camera.current)
	print("  玩家在船上的相对位置 = ", player.global_position - ship.global_position)

	# 登船
	game.state = "ship"
	player.visible = false
	ship.camera.current = true

	print("\n=== 登船后（座舱）===")
	print("  player.visible = ", player.visible)
	print("  ship.camera.current = ", ship.camera.current)
	print("  player.camera.current = ", player.camera.current)
	# 玩家提灯：在船上时不该照亮周围
	print("  玩家提灯 lamp.visible = ", player.lamp.visible)
	# 玩家身上有没有会被渲染的网格
	# 关键：**人本身没有身体模型** —— 玩家节点只是碰撞胶囊 + 相机 + 提灯。
	# 那些网格全都挂在 player.camera 底下，是烤棉花糖的道具（树枝 + 棉花糖 + 火光）。
	# 判据：网格是不是在 Camera3D 下面 —— 在的话就是道具，不是主角身体。
	var body_meshes := 0
	for node in player.find_children("*", "MeshInstance3D", true, false):
		var under_camera := false
		var p: Node = node.get_parent()
		while p != null and p != player:
			if p is Camera3D:
				under_camera = true
				break
			p = p.get_parent()
		if not under_camera:
			body_meshes += 1
			print("    ★ 主角身体网格: ", node.get_path())
	print("  玩家身上的 MeshInstance3D = %d（其中主角身体 = %d，其余是烤棉花糖道具）" % [
		player.find_children("*", "MeshInstance3D", true, false).size(), body_meshes])

	if player.visible:
		failures += 1
		print("  ! 玩家节点仍然可见")
	if player.camera.current:
		failures += 1
		print("  ! 玩家相机仍然是 current")
	if body_meshes > 0:
		failures += 1
		print("  ! 玩家身上有 %d 个**身体**网格会被渲染" % body_meshes)
	else:
		print("  玩家没有身体模型（只有碰撞胶囊 + 相机 + 提灯）→ 第三人称里不会出现主角 ✓")

	# ── 第三人称 ──
	print("\n=== 切到第三人称 ===")
	var ok: bool = ship.toggle_third_person()
	print("  toggle 返回 = ", ok)
	print("  third_person = ", ship.third_person)
	print("  相机局部位置 = ", ship.camera.position)
	print("  相机距船心 = %.2f m" % ship.camera.position.length())
	print("  相机 fov = %.1f" % ship.camera.fov)
	# 相机必须在船外（不能还在座舱里）
	if ship.camera.position.length() < 5.0:
		failures += 1
		print("  ! 第三人称相机还在船体里")
	# 相机朝向必须指向船心
	var to_center: Vector3 = (-ship.camera.position).normalized()
	var cam_forward: Vector3 = -ship.camera.global_transform.basis.z.normalized()
	if to_center.dot(cam_forward) < 0.9:
		failures += 1
		print("  ! 相机没有看向船心（点积 %.3f）" % to_center.dot(cam_forward))
	else:
		print("  相机朝向船心 ✓（点积 %.3f）" % to_center.dot(cam_forward))
	# 玩家依旧不可见
	if player.visible:
		failures += 1
		print("  ! 第三人称时玩家又可见了")

	# 回到座舱
	ship.toggle_third_person()
	print("\n=== 切回座舱 ===")
	print("  third_person = ", ship.third_person)
	print("  相机局部位置 = ", ship.camera.position)
	if ship.camera.position.length() > 3.0:
		failures += 1
		print("  ! 相机没有回到座舱")

	print("\nTHIRD PERSON PROBE: %d failure(s)" % failures)
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	quit(0 if failures == 0 else 1)
