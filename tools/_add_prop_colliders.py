# -*- coding: utf-8 -*-
"""给 AI 道具补静态碰撞体（只给站点附近，控制数量）。

背景：把 _add_tree / _add_rock 改成走 AI 道具后提前 return，
原来的 StaticBody3D + CylinderShape3D 不再创建，于是
「near-site trees and buildings create static colliders」翻红
（玩家能直接穿过 AI 树/岩石）。

做法：在 _flush_props 落实例时，对**离站点 2.2 倍平地半径以内**的实例
补一个近似碰撞体（树/塔类用竖直胶囊，岩石类用球）。远处的纯装饰不加，
否则一颗星球 180 个 StaticBody 太贵。
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ── 道具分类：用什么碰撞体 ──
old = "## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，"
assert s.count(old) == 1, "anchor tint"
s = s.replace(old, """## 某个道具该用什么近似碰撞体。
## 竖直细长的（树/塔/方尖碑/晶簇）用胶囊，块状的（岩石/穹顶）用球。
## 返回 Vector2(半径系数, 高度系数)，都是相对「道具高度 size」的比例。
func _prop_collider_profile(prop_id: String) -> Vector2:
	if prop_id.contains("tree") or prop_id.contains("tower") \\
			or prop_id.contains("obelisk") or prop_id.contains("spire") \\
			or prop_id.contains("crystal"):
		return Vector2(0.16, 0.92)   # 细高：半径 16% 高度
	return Vector2(0.42, 0.62)       # 块状：半径 42% 高度


## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，""")

# ── _flush_props 里补碰撞体 ──
old2 = """		var instance := MultiMeshInstance3D.new()
		instance.name = "Prop_%s" % prop_id
		instance.multimesh = mm
		instance.visibility_range_end = 2200.0
		add_child(instance)"""
new2 = """		var instance := MultiMeshInstance3D.new()
		instance.name = "Prop_%s" % prop_id
		instance.multimesh = mm
		instance.visibility_range_end = 2200.0
		add_child(instance)
		_add_prop_colliders(entries, prop_id)"""
assert s.count(old2) == 1, "flush anchor"
s = s.replace(old2, new2)

# ── 新增 _add_prop_colliders ──
old3 = """## 把 prop_queue 里排好的道具落成 MultiMeshInstance3D。"""
assert s.count(old3) == 1, "helper head anchor"
s = s.replace(old3, """## 给站点附近的道具补静态碰撞体。
##
## 为什么只补站点附近：一颗星球有 ~180 个道具实例，全加 StaticBody3D 太贵
## （每个都是独立物理对象）。玩家真正会走进去的只有基地周围那一片，
## 远处的高山巨石纯属背景，穿过去也没人发现。
## 半径 = 2.2 倍平地半径，正好覆盖「看得清细节」的范围。
func _add_prop_colliders(entries: Array, prop_id: String) -> void:
	var limit: float = site_pad_radius * 2.2
	var profile := _prop_collider_profile(prop_id)
	for e in entries:
		var dir: Vector3 = e["dir"]
		var size: float = float(e["size"])
		var origin: Vector3 = surface_position(dir,
			float(e["altitude"]) - size * 0.0)
		# 站点的角距离（用地表弧长近似）
		if acos(clampf(dir.dot(site_direction.normalized()), -1.0, 1.0)) * radius > limit:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), origin)
		var collision := CollisionShape3D.new()
		if profile.x < 0.3:
			var shape := CylinderShape3D.new()
			shape.radius = profile.x * size
			shape.height = profile.y * size
			collision.shape = shape
			collision.position.y = profile.y * size * 0.5
		else:
			var shape := SphereShape3D.new()
			shape.radius = profile.x * size
			collision.shape = shape
			collision.position.y = profile.x * size
		body.add_child(collision)
		add_child(body)


## 把 prop_queue 里排好的道具落成 MultiMeshInstance3D。""")

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("prop colliders added:", o != s)
