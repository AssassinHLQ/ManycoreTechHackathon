extends SceneTree
# 探针：把卡冈图雅按层拆开，一次只显示一层，定位「曲线不光滑」到底出在哪一层。
#
# 用途（2026-11-08 查「吸积盘曲线不光滑」时留下的）：
#   这件资产是两个网格、六个 surface 叠在一起（center / blackoutside /
#   light1 / light2 / light3 / distortion + ring / ring2）。出问题时得先知道
#   是哪一层在捣乱 —— 逐层单独拍一张，一眼就能看出来。
#
#   godot --path . --script res://tests/probe_gargantua_layers.gd
#   输出：res://captures/layer_00_all.png 与 layer_NN_<网格>_s<面数>.png

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
	img.save_png("res://captures/layer_%s.png" % name)
	print("saved res://captures/layer_%s.png" % name)


func _run() -> void:
	var save := "user://starward_probe_layers.json"
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
	var cam := Camera3D.new()
	cam.near = 1.0
	cam.far = 200000.0
	cam.fov = 55.0
	game.add_child(cam)
	cam.current = true
	game.state = "capture"

	# 收集所有网格节点，按材质分组
	var layers: Array = []
	for node in target.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var label := "%s_s%d" % [mi.name, mi.mesh.get_surface_count()]
		layers.append({"node": mi, "label": label})

	# 先拍一张全部可见的
	cam.global_position = center + Vector3(-3000.0, 2200.0, 3200.0)
	cam.look_at(center, Vector3.UP)
	await _frames(10)
	await _shot("00_all")

	# 逐层：只显示这一层，其余隐藏
	for i in range(layers.size()):
		for j in range(layers.size()):
			var mi2: MeshInstance3D = layers[j]["node"]
			mi2.visible = (i == j)
		await _frames(6)
		await _shot("%02d_%s" % [i + 1, String(layers[i]["label"]).replace("/", "-")])

	# 复原
	for j in range(layers.size()):
		(layers[j]["node"] as MeshInstance3D).visible = true
	print("DONE")
	quit(0)
