# -*- coding: utf-8 -*-
"""把 planet.gd 的程序化摆件换成 Lux3D 生成的 AI 模型。

原则：
  · 高模（2~3 万面）只当地标，每颗星球少量实例
  · 低模（2 千面级）才拿来铺量
  · MultiMesh 的实例色用来给每颗星球调色（材质开 vertex_color_use_as_albedo），
    这样一套 AI 资产能在 20 颗星球上呈现不同色调
  · 找不到对应 GLB 时自动回退到原来的程序化网格，绝不因为缺资产而崩

本脚本只做「插入新代码 + 重定向两个入口」，原程序化实现全部保留作为回退。
"""
import io

P = r"scripts\planet.gd"
src = io.open(P, encoding="utf-8").read()
orig = src

# ═══════════ 1. 资产表 + 缓存 ═══════════
anchor = "var rock_queue: Dictionary = {}"
assert src.count(anchor) == 1, "rock_queue anchor"
props_decl = '''var rock_queue: Dictionary = {}

## AI 生成道具（Lux3D）的模型路径。
##
## ⚠ 2026-11-11 用户要求：「星球需要更多物体、环境、地形、特殊点，
##   而且不能是程序化的，必须 AI 生成」。
##   所以树、岩石、遗迹、晶体、信号塔这些都是 Lux3D 文生 3D 出来的 GLB。
##
## 命名约定：`-lo` 是低模变体（约 2 千面）用来铺量，无后缀是高模用来当地标。
## 某个 id 缺资产时 `_prop_mesh()` 返回 null，调用方自动回退程序化几何。
const PROP_MODELS := {
	"alien-tree": "res://assets/models/props/alien-tree/model.glb",
	"alien-tree-lo": "res://assets/models/props/alien-tree-lo/model.glb",
	"rock-cluster": "res://assets/models/props/rock-cluster/model.glb",
	"rock-cluster-lo": "res://assets/models/props/rock-cluster-lo/model.glb",
	"rock-spire": "res://assets/models/props/rock-spire/model.glb",
	"rock-spire-lo": "res://assets/models/props/rock-spire-lo/model.glb",
	"ruin-arch": "res://assets/models/props/ruin-arch/model.glb",
	"obelisk": "res://assets/models/props/obelisk/model.glb",
	"dome-habitat": "res://assets/models/props/dome-habitat/model.glb",
	"signal-tower": "res://assets/models/props/signal-tower/model.glb",
	"crystal-cluster": "res://assets/models/props/crystal-cluster/model.glb",
	"vent": "res://assets/models/props/vent/model.glb",
	"floating-rock": "res://assets/models/props/floating-rock/model.glb",
}

## 已加载的 AI 网格缓存（prop_id -> Mesh），同一进程里 20 颗星球共用一份。
static var _prop_mesh_cache := {}

## 待落地的高模地标：prop_id -> Array[Dictionary]（见 _add_prop）
var prop_queue: Dictionary = {}
## 待落地的低模散布：同上
var scatter_prop_queue: Dictionary = {}'''
src = src.replace(anchor, props_decl)


# ═══════════ 2. 载入 AI 网格并归一化 ═══════════
anchor2 = "func _flush_vegetation() -> void:"
assert src.count(anchor2) == 1, "flush anchor"
helpers = '''## 载入一个 AI 道具网格（带缓存）。缺失或损坏时返回 null，调用方回退。
##
## GLB 是场景而不是裸网格，所以实例化一次、取第一个 MeshInstance3D 的 mesh，
## 立刻释放实例 —— mesh 资源本身会被 MultiMesh 持有。
static func _prop_mesh(prop_id: String) -> Mesh:
	if _prop_mesh_cache.has(prop_id):
		return _prop_mesh_cache[prop_id]
	var mesh: Mesh = null
	var path: String = PROP_MODELS.get(prop_id, "")
	if path != "" and ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			var inst = (packed as PackedScene).instantiate()
			if inst != null:
				for mi in inst.find_children("*", "MeshInstance3D", true, false):
					var m: Mesh = (mi as MeshInstance3D).mesh
					if m != null:
						mesh = m
						break
				inst.free()
	_prop_mesh_cache[prop_id] = mesh
	return mesh


## 把 AI 网格包成可被 MultiMesh 实例化的版本：
##   · 复制一份（各星球独立，互不影响材质）
##   · 每个面的材质复制后打开 vertex_color_use_as_albedo，
##     这样 MultiMesh 的实例色能直接给整颗星球的道具调色，
##     而 AI 生成的贴图本身仍然是原样
static func _prop_mesh_for_instancing(prop_id: String) -> Mesh:
	var base: Mesh = _prop_mesh(prop_id)
	if base == null:
		return null
	var copy: Mesh = base.duplicate()
	for s in range(copy.get_surface_count()):
		var mat: Material = copy.surface_get_material(s)
		if mat is StandardMaterial3D:
			var dup: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
			dup.vertex_color_use_as_albedo = true
			copy.surface_set_material(s, dup)
	return copy


## 排入一个 AI 道具（地标）。size 是**世界米数**（道具高度）。
## altitude 是相对地表的抬升（负值=压入地面）。
func _add_prop(prop_id: String, direction: Vector3, size: float,
		altitude := 0.0, tint := Color.WHITE) -> void:
	if _prop_mesh(prop_id) == null:
		return
	if not prop_queue.has(prop_id):
		prop_queue[prop_id] = []
	prop_queue[prop_id].append({
		"dir": direction.normalized(),
		"size": size,
		"altitude": altitude,
		"yaw": rng.randf() * TAU,
		"tint": tint,
	})


## 把 prop_queue 里排好的道具落成 MultiMeshInstance3D。
##
## 关键点：GLB 自己的尺寸是「1 单位高」的不确定值，所以按**包围盒高度**归一化，
## 让 size 参数真正等于世界米数；原点也对齐到模型底面（否则会一半埋进地里）。
func _flush_props() -> void:
	if prop_queue.is_empty():
		return
	for prop_id in prop_queue.keys():
		var entries: Array = prop_queue[prop_id]
		if entries.is_empty():
			continue
		var mesh: Mesh = _prop_mesh_for_instancing(prop_id)
		if mesh == null:
			continue
		var aabb: AABB = mesh.get_aabb()
		var base_h: float = maxf(aabb.size.y, 0.001)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = entries.size()
		for i in range(entries.size()):
			var e: Dictionary = entries[i]
			var dir: Vector3 = e["dir"]
			var k: float = float(e["size"]) / base_h
			var basis := Basis(Quaternion(Vector3.UP, dir))
			basis = basis.rotated(dir, float(e["yaw"]))
			basis = basis.scaled(Vector3.ONE * k)
			# 底面贴地：模型底面在 aabb.position.y*k 处，把它抬回 0
			var origin: Vector3 = surface_position(dir,
				float(e["altitude"]) - aabb.position.y * k)
			mm.set_instance_transform(i, Transform3D(basis, origin))
			mm.set_instance_color(i, e["tint"])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Prop_%s" % prop_id
		instance.multimesh = mm
		instance.visibility_range_end = 2200.0
		add_child(instance)


'''
src = src.replace(anchor2, helpers + anchor2)

# ═══════════ 3. 树 → AI 树 ═══════════
old_tree = '''func _add_tree(direction: Vector3, _collidable := false) -> void:
	var size := rng.randf_range(1.0, 2.25) * prop_scale
	var up := direction.normalized()
	var origin := surface_position(direction, -0.85)
	var transform := Transform3D(Basis(Quaternion(Vector3.UP, up)).scaled(Vector3.ONE * size), origin)
	if rng.randf() < 0.28:
		broad_queue.append(transform)
	else:
		pine_queue.append(transform)'''
new_tree = '''func _add_tree(direction: Vector3, _collidable := false) -> void:
	# ⚠ 2026-11-11：优先用 Lux3D 生成的异星树（AI 资产）。
	#   树高按 prop_scale 放大到 18~40 米，和放大后的星球/建筑一个尺度。
	#   资产缺失时退回下面的程序化树（原逻辑完整保留）。
	var tree_id := "alien-tree-lo" if _prop_mesh("alien-tree-lo") != null else "alien-tree"
	if _prop_mesh(tree_id) != null:
		_add_prop(tree_id, direction, rng.randf_range(18.0, 40.0) * prop_scale / 5.0,
			0.0, _prop_tint())
		return
	var size := rng.randf_range(1.0, 2.25) * prop_scale
	var up := direction.normalized()
	var origin := surface_position(direction, -0.85)
	var transform := Transform3D(Basis(Quaternion(Vector3.UP, up)).scaled(Vector3.ONE * size), origin)
	if rng.randf() < 0.28:
		broad_queue.append(transform)
	else:
		pine_queue.append(transform)'''
assert src.count(old_tree) == 1, "tree anchor"
src = src.replace(old_tree, new_tree)

# _add_tree 后半段（碰撞体）在 AI 分支已 return，保留原代码不动。

# ═══════════ 4. 岩石 → AI 岩石 ═══════════
old_rock = '''func _add_rock(direction: Vector3, size: float, color: Color, altitude: float) -> void:
	size *= prop_scale
	var rotation := Basis.from_euler(Vector3(rng.randf() * PI, rng.randf() * PI, rng.randf() * PI))'''
new_rock = '''func _add_rock(direction: Vector3, size: float, color: Color, altitude: float) -> void:
	size *= prop_scale
	# ⚠ 2026-11-11：优先用 Lux3D 生成的岩石（层积巨岩 / 黑曜石尖峰）。
	#   哪个星球的岩石更「尖」按 kind 区分，和原来的配色意图一致。
	var rock_id := "rock-spire" if _prefers_spires() else "rock-cluster"
	if _prop_mesh(rock_id + "-lo") != null:
		rock_id += "-lo"
	if _prop_mesh(rock_id) != null:
		_add_prop(rock_id, direction, maxf(size, 1.0), altitude, color)
		return
	var rotation := Basis.from_euler(Vector3(rng.randf() * PI, rng.randf() * PI, rng.randf() * PI))'''
assert src.count(old_rock) == 1, "rock anchor"
src = src.replace(old_rock, new_rock)

# ═══════════ 5. 辅助：星球色调 / 尖峰倾向 ═══════════
anchor5 = "func _flush_props() -> void:"
assert src.count(anchor5) == 1
aids = '''## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，
## 让同一套 AI 资产在 20 颗星球上呈现各自的色系（用户：「保留配色，呼应名字」）。
func _prop_tint() -> Color:
	var base: Color = base_color
	# 只在明度/饱和度上做轻微变化，别把 AI 贴图染成一块色板
	var j: float = rng.randf_range(-0.12, 0.18)
	return Color(
		clampf(base.r + j, 0.25, 1.0),
		clampf(base.g + j, 0.25, 1.0),
		clampf(base.b + j, 0.25, 1.0),
		1.0)


## 这颗星球的岩石更适合「尖峰」而不是「圆石堆」吗。
## 晶体/黑曜石/裂隙类用尖峰，其余用层积圆石。
func _prefers_spires() -> bool:
	return kind in ["xuanjing", "jianmo", "youdu", "jiangxiao", "xuanpu"]


'''
src = src.replace(anchor5, aids + anchor5)

# ═══════════ 6. flush 时一起落地 ═══════════
old_flush = '''func _flush_vegetation() -> void:
	var bark := _material(Color("4a352a"))'''
new_flush = '''func _flush_vegetation() -> void:
	# 先把 AI 道具落地（地标 + 可能的低模散布），再补程序化回退部分。
	_flush_props()
	var bark := _material(Color("4a352a"))'''
assert src.count(old_flush) == 1, "flush body anchor"
src = src.replace(old_flush, new_flush)

io.open(P, "w", encoding="utf-8", newline="\n").write(src)
print("planet.gd AI props: %d -> %d chars" % (len(orig), len(src)))
