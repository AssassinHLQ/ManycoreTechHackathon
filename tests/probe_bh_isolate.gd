extends SceneTree
# 探针：近距离逐层隔离，找出「静止可见的角状块 / 三角块」出自哪一层壳。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/probe_bh_isolate.gd -- --no-capture

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
	img.save_png("res://captures/bh_iso_%s.png" % label)
	print("saved res://captures/bh_iso_%s.png" % label)


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_probe_bh_iso.json"
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

	var target: Node3D = game.gargantua
	if target == null:
		print("卡冈图雅没建出来")
		quit(1)
		return
	var center: Vector3 = target.global_position
	var cam := Camera3D.new()
	cam.near = 1.0
	cam.far = 200000.0
	cam.fov = 70.0
	game.add_child(cam)
	cam.current = true
	# 用户截图那种「盘面铺满屏」的近距离
	cam.global_position = center + Vector3(
		cos(deg_to_rad(30.0)) * cos(deg_to_rad(35.0)) * 800.0,
		sin(deg_to_rad(30.0)) * 800.0,
		cos(deg_to_rad(30.0)) * sin(deg_to_rad(35.0)) * 800.0)
	cam.look_at(center, Vector3.UP)
	await _frames(8)

	# 收集所有 (节点, surface, 材质名)
	var entries: Array = []
	for node in target.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for surface in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(surface)
			var nm := "?"
			if mat != null:
				nm = str(mat.resource_name) if mat.resource_name != "" else mat.get_class()
				if mat is ShaderMaterial:
					var sh: Shader = (mat as ShaderMaterial).shader
					nm += " [%s]" % (sh.resource_path.get_file() if sh != null else "shader")
			entries.append({"node": mi, "surface": surface, "name": nm})

	print("=== 图层清单 ===")
	for i in range(entries.size()):
		print("  [%d] %s  surf%d  ->  %s" % [
			i, (entries[i]["node"] as Node).name, int(entries[i]["surface"]), entries[i]["name"]])

	# 逐层单独显示
	for i in range(entries.size()):
		var only: MeshInstance3D = entries[i]["node"]
		var only_surface: int = int(entries[i]["surface"])
		for node2 in target.find_children("*", "MeshInstance3D", true, false):
			var mi2 := node2 as MeshInstance3D
			var keep_node: bool = (mi2 == only)
			for s in range(mi2.mesh.get_surface_count()):
				if keep_node and s == only_surface:
					mi2.set_surface_override_material(s, mi2.mesh.surface_get_material(s))
					continue
				# 其它面全部抹掉
				var blank := StandardMaterial3D.new()
				blank.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				blank.albedo_color = Color(0, 0, 0, 0)
				blank.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mi2.set_surface_override_material(s, blank)
		await _frames(6)
		await _shot("%02d_%s_s%d" % [i, (only.name as String).replace(" ", "_"), only_surface])

	print("DONE")
	quit(0)
