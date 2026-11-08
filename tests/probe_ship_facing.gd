extends SceneTree
# 探针：把飞船模型放在空白场景里，沿 6 个轴向各拍一张，直观看机头朝哪。
# 用法：godot --path . --script res://tests/probe_ship_facing.gd
#
# 为什么需要它：
#   飞船模型来自外部 GLB，原始是 Y-up（机头 -Y、机顶 +Z），
#   靠 tools/slim_ship.py 绕 X 轴 +90° 转成 Godot 的 Z-up（机头 -Z、机顶 +Y）。
#   但「机头在哪」只能靠**几何 + 眼睛**判定，不能靠注释断言 ——
#   注释说机头在 -Z，模型实际却转了 90°，玩家看到的就会是反的。
#
# 本探针刻意复刻 scripts/ship.gd 的 _build_external_model() 变换链，
#   然后绕**模型自身**的六个轴向拍图：拍到尖头的那张就是机头方向。

const VIEW_DIST := 9.0

var _model: Node3D
var _camera: Camera3D


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-20000, -20000))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://captures/facing_%s.png" % name)
	print("saved res://captures/facing_%s.png" % name)


func _run() -> void:
	var packed: PackedScene = load("res://assets/models/ship-fighter/model.glb")
	if packed == null:
		print("加载失败")
		quit(1)
		return

	var holder := Node3D.new()
	holder.name = "Holder"
	root.add_child(holder)

	var model := packed.instantiate() as Node3D
	# 和 scripts/ship.gd 的 SHIP_MODEL_ROTATION 一致（现在是零 —— 朝向已烘焙进 GLB）
	model.rotation = Vector3.ZERO
	holder.add_child(model)
	_model = model

	# 让模型居中，并把尺度拉到和游戏里一致（机长 6.5 m）
	# 注意：Godot 的 glTF 导入器会把 glTF 的 Y-up 转成 Z-up，所以这里的
	# 局部包围盒已经是 **Godot 坐标**：X=翼展、Y=机高、Z=机长。
	# （旧版本按 Y-up 解读，导致缩放算错、相机贴脸拍。）
	var bounds := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var rel := Transform3D.IDENTITY
			var walker: Node = mi
			while walker != null and walker != model:
				rel = (walker as Node3D).transform * rel
				walker = walker.get_parent()
			if walker == model:
				rel = model.transform * rel
			var box: AABB = rel * mi.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		for child in node.get_children():
			stack.append(child)
	var factor := 6.5 / bounds.size.z
	holder.scale = Vector3.ONE * factor
	print("包围盒 = %s  缩放 = %.3f" % [bounds.size, factor])

	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 200.0
	_camera.fov = 50.0
	root.add_child(_camera)
	_camera.current = true

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-1.0, -0.6, 0.0)
	key.light_energy = 2.2
	root.add_child(key)

	# 沿**模型自身**（即 Godot 里的 holder）的六个轴向拍。
	# holder 的 -Z 就是「游戏里飞船的前进方向」（Godot 约定：-Z 为前）。
	var views := {
		"minus_z": Vector3(0, 0, -1),   # 从机头前方看过去 —— 应该看到尖头
		"plus_z": Vector3(0, 0, 1),    # 从机尾后方看过去
		"minus_y": Vector3(0, -1, 0),   # 从机顶往下看
		"plus_y": Vector3(0, 1, 0),    # 从机底往上看
		"minus_x": Vector3(-1, 0, 0),   # 左侧
		"plus_x": Vector3(1, 0, 0),    # 右侧
	}
	for key_name in views:
		var dir: Vector3 = views[key_name]
		_camera.global_position = dir * VIEW_DIST
		_camera.look_at(Vector3.ZERO, Vector3.UP)
		await _frames(6)
		await _shot(key_name)

	print("FACING PROBE COMPLETE")
	quit(0)
