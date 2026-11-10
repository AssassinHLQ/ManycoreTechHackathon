extends SceneTree
# 对比探针：同一颗点云，**不改材质** vs **换成点云着色器**，各出一张图。
# 用法：godot --path . --no-capture --script res://tests/probe_shader_vs_default.gd
#
# 为什么需要它：
#   已经确认模型数据完全正常（AABB ±1.09、150 mesh 可见、顶点色存在），
#   但换成 one_dim_star.gd 的着色器后渲染全黑，而不换材质是白色能看见。
#   说明问题**在着色器本身**，不在模型。
#   这个探针把两种路径并排出图，一次看清。

const OffWin := preload("res://scripts/offscreen_window.gd")

var cam: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://captures/compare_%s.png" % name)
	print("saved res://captures/compare_%s.png" % name)


func _run() -> void:
	await OffWin.apply(self)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.06)
	env.environment = e
	root.add_child(env)

	cam = Camera3D.new()
	cam.near = 0.01
	cam.far = 1000.0
	cam.fov = 45.0
	root.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 0.3, 4.0)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	# ── A：原样加载，不改材质 ──
	var a := (load("res://assets/models/one-dim-star/model.glb") as PackedScene).instantiate() as Node3D
	root.add_child(a)
	await _frames(4)
	await _shot("a_default")
	a.queue_free()
	await _frames(2)

	# ── B：换成点云着色器 ──
	var b := (load("res://assets/models/one-dim-star/model.glb") as PackedScene).instantiate() as Node3D
	root.add_child(b)
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/one_dim_star.gdshader")
	shader_mat.set_shader_parameter("brightness", 2.6)
	var n := 0
	for child in b.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			mi.mesh.surface_set_material(s, shader_mat)
			n += 1
	print("替换材质 surface 数 = %d" % n)
	await _frames(4)
	await _shot("b_shader")
	b.queue_free()
	await _frames(2)

	# ── C：换成「不加混合」的简单着色器版本，验证是不是 blend_add 的问题 ──
	var c := (load("res://assets/models/one-dim-star/model.glb") as PackedScene).instantiate() as Node3D
	root.add_child(c)
	var plain := StandardMaterial3D.new()
	plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plain.vertex_color_use_as_albedo = true
	for child in c.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			mi.mesh.surface_set_material(s, plain)
	await _frames(4)
	await _shot("c_vertexcolor")
	c.queue_free()

	print("COMPARE DONE")
	quit(0)
