extends SceneTree
# 探针：把飞船 GLB 单独放进一个空场景，用**正交相机**拍正后视图 / 侧视图，
# 叠上尾焰起点的十字准星。正交投影下像素↔米是线性的，可以直接量出喷口圆心。
# 用法（窗口模式）：Godot_v4.7.1-stable_win64_console.exe --path . --script res://tests/_capture_nozzle_ortho.gd

const TARGET_L := 70.0
const SINK := 11.5
const ShipScript := preload("res://scripts/ship.gd")

var cam: Camera3D
var scene: Node3D


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-4000, -4000))
		DisplayServer.window_set_size(Vector2i(1600, 1000))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://captures/%s.png" % name)
		print("  saved %s.png (%dx%d)" % [name, img.get_width(), img.get_height()])


func _crosshair(parent: Node3D, at: Vector3, color: Color, arm: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	for horizontal in [true, false]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(arm * 2.0, 0.25, 0.25) if horizontal else Vector3(0.25, arm * 2.0, 0.25)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = at
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	scene = Node3D.new()
	root.add_child(scene)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	scene.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 40, 0)
	sun.light_energy = 1.4
	scene.add_child(sun)

	var packed: PackedScene = load("res://assets/models/ship-fighter/model.glb")
	var model := packed.instantiate() as Node3D
	var holder := Node3D.new()
	holder.add_child(model)
	scene.add_child(holder)

	# 复刻 ship.gd 的换算：先量原始 AABB，再缩放到 70 m、底面贴 y=-SINK
	var bounds := AABB()
	var first := true
	var stack: Array = [model]
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
		for ch in node.get_children():
			stack.append(ch)
	var center := bounds.get_center()
	var factor: float = TARGET_L / bounds.size.z
	holder.scale = Vector3.ONE * factor
	holder.position = Vector3(-center.x * factor, -bounds.position.y * factor - SINK, -center.z * factor)
	print("model factor=%.3f  hull local y [%.2f, %.2f]" % [
		factor, -SINK, bounds.size.y * factor - SINK])

	# 直接读 ship.gd 的喷口表（14 m 坐标 × 5，再前移 EXHAUST_PLUME_FORWARD_RATIO·L）
	var nozzles: Array = []
	for v in ShipScript.EXHAUST_NOZZLES:
		nozzles.append((v as Vector3) * (TARGET_L / 14.0))
	for i in range(nozzles.size()):
		var n: Vector3 = nozzles[i]
		n.z -= TARGET_L * ShipScript.EXHAUST_PLUME_FORWARD_RATIO
		nozzles[i] = n
		print("  crosshair[%d] at %s" % [i, str(n)])
		_crosshair(scene, n, Color(1, 0.92, 0.1), 4.0)
		# 参考架：喷口圆心 + 半径 2 m 的「口」字，方便看是否同心
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(0.2, 1.0, 0.4)
		ring_mat.no_depth_test = true
		for k in range(4):
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var r := 2.2
			bm.size = Vector3(r * 2, 0.16, 0.16) if k < 2 else Vector3(0.16, r * 2, 0.16)
			bar.mesh = bm
			bar.material_override = ring_mat
			bar.position = n + (Vector3(0, r, 0) if k == 1 else (Vector3(0, -r, 0) if k == 3 else Vector3.ZERO))
			if k < 2:
				bar.position.x += 0.0
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			scene.add_child(bar)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	cam.current = true

	# 正后视图（沿 -Z 看）：覆盖 y -16..16，x ±25.6
	cam.size = 32.0
	cam.global_position = Vector3(0, -3.0, 120)
	cam.look_at(Vector3(0, -3.0, 0), Vector3.UP)
	await _frames(8)
	await _shot("nozzle_ortho_back")

	# 侧视图（沿 -X 看）：覆盖 z ±32，y -20..20
	cam.size = 40.0
	cam.global_position = Vector3(120, -3.0, 0)
	cam.look_at(Vector3(0, -3.0, 0), Vector3.UP)
	await _frames(8)
	await _shot("nozzle_ortho_side")

	print("ORTHO DONE")
	quit(0)
