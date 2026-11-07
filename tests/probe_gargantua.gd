extends SceneTree
# 探针：从远、中、近三个距离拍卡冈图雅，用来定比例与发光强度。
#   godot --path . --script res://tests/probe_gargantua.gd

var game


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("res://captures/probe_%s.png" % name)
	print("saved res://captures/probe_%s.png" % name)


func _run() -> void:
	var save := "user://starward_probe_gargantua.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(20)
	game.hud.visible = false
	game.set_process(false)

	var target: Node3D = game.gargantua
	if target == null:
		print("卡冈图雅没有建出来")
		quit(1)
		return
	var center: Vector3 = target.global_position
	print("卡冈图雅位置 = ", center, "  距原点 %.0f" % center.length())
	var tris := 0
	for node in target.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			tris += ((idx as PackedInt32Array).size() / 3) if idx != null and (idx as PackedInt32Array).size() > 0 \
				else ((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
	print("卡冈图雅三角面 = %d，发光材质 %d 个" % [tris, game.gargantua_glow_materials.size()])

	var cam := Camera3D.new()
	cam.near = 1.0
	cam.far = 200000.0
	cam.fov = 60.0
	game.add_child(cam)
	cam.current = true
	game.state = "capture"

	# 发光对照：同一个机位，试几种发光处理
	#   用法：-- 2.6 shadow 0.0     （shadow = 把发光壳压成黑，看黑洞阴影能不能露出来）
	var argv := OS.get_cmdline_user_args()
	var variants: Array[String] = []
	for a in argv:
		variants.append(a)
	if variants.is_empty():
		variants = ["2.6"]

	for spec in [
		[Vector3(2600.0, 900.0, 2600.0), 60.0, "gargantua_far"],
		[Vector3(-3000.0, 2200.0, 3200.0), 55.0, "gargantua_mid"],
		[Vector3(-600.0, 260.0, 760.0), 55.0, "gargantua_near"],
		# 贴近平面的低仰角特写：作者那张预览就是这个构图（盘的近侧从眼前掠过、
		# 远侧被透镜效果拉到上方）。同一件资产，视角不同读起来完全两样。
		[Vector3(-1500.0, 120.0, 1500.0), 55.0, "gargantua_low"],
	]:
		var offset: Vector3 = spec[0]
		cam.global_position = center + offset
		cam.look_at(center, Vector3.UP)
		cam.fov = spec[1]
		await _frames(10)
		for value in variants:
			var shadow := value == "shadow"
			var dark_index := -1
			var warm := value.begins_with("tint:")
			var amber := value.begins_with("amber:")
			var warmtex := value.begins_with("warmtex:")
			var energy := 1.6
			if warm:
				energy = float(value.substr(5))
			if amber:
				energy = float(value.substr(6))
			if warmtex:
				energy = float(value.substr(8))
			if value.begins_with("dark:"):
				dark_index = int(value.substr(5))
			var warm_tint := Color(1.0, 0.80, 0.52)
			for i in range(game.gargantua_glow_materials.size()):
				var material: StandardMaterial3D = game.gargantua_glow_materials[i]
				if dark_index == i:
					material.emission_energy_multiplier = 0.0
					material.albedo_color = Color(0, 0, 0)
				elif dark_index >= 0:
					material.emission_energy_multiplier = 1.6
					material.albedo_color = Color(1, 1, 1)
				else:
					material.emission_energy_multiplier = 0.0 if shadow else energy
					material.emission = warm_tint if (warm or amber or warmtex) else Color(1, 1, 1)
					if shadow:
						material.albedo_color = Color(0, 0, 0)
					elif amber:
						# 摘掉反照率贴图，只留暖色自发光
						material.albedo_color = warm_tint
						material.albedo_texture = null
					elif warmtex:
						# 折中：**保留**反照率贴图（保住盘面的层次），只把颜色相乘成暖色
						material.albedo_color = warm_tint
					else:
						material.albedo_color = Color(1, 1, 1)
			await _frames(3)
			# 标签要带上处理方式，否则 dark/amber/warmtex 都会写成 "e<数值>" 互相覆盖
			# （这个坑真踩过：warmtex 那两档把之前的对照图覆盖掉了）
			var tag := ""
			if shadow:
				tag = "shadow"
			elif dark_index >= 0:
				tag = "dark%d" % dark_index
			elif amber:
				tag = "amber%s" % String.num(energy, 2).replace(".", "_")
			elif warmtex:
				tag = "warmtex%s" % String.num(energy, 2).replace(".", "_")
			elif warm:
				tag = "tint%s" % String.num(energy, 2).replace(".", "_")
			else:
				tag = "origin%s" % String.num(energy, 2).replace(".", "_")
			await _shot("%s_%s" % [spec[2], tag])

	quit(0)
