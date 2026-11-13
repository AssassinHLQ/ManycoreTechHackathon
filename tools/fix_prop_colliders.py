# -*- coding: utf-8 -*-
"""重写 _add_prop_colliders：同类道具共用一个 StaticBody3D，上限 34 -> 260。

背景（用户：「资产全都没有碰撞」）：
  旧版每个实例建一个独立 StaticBody3D，为了省物理对象把上限压到 34 个/类。
  但一颗星球单类植被就有 90 个实例，于是六成道具是穿模的。
  改为「共用物理体 + 多个 CollisionShape3D 子节点」后，物理对象数从
  「实例数」降到「道具种类数」（约 20 个），可以把上限放到 260。

⚠ 本脚本用文件方式执行，避免 python -c 经 PowerShell 时双引号被吞掉。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "scripts/planet.gd"
s = io.open(P, encoding="utf-8").read()

START = "const PROP_COLLIDER_CAP := 34"
END = "## 把 prop_queue 里排好的道具落成 MultiMeshInstance3D。"
i = s.find(START)
j = s.find(END)
if i < 0 or j < 0 or j <= i:
    print("anchor not found: i=%d j=%d" % (i, j))
    raise SystemExit(1)

NEW = '''const PROP_COLLIDER_CAP := 260


## 给道具补静态碰撞体。
##
## \\u26a0 2026-11-13 重写（用户：「资产全都没有碰撞」）：
##   旧版每个实例建一个独立 StaticBody3D，为了省物理对象把上限压到 34 个/类 ——
##   但一颗星球单类植被就有 90 个实例，于是**六成道具是穿模的**。
##
##   现在改成「**同类道具共用 1 个 StaticBody3D**，逐个加 CollisionShape3D 子节点」：
##   \\u00b7 物理对象数从「实例数」降到「道具种类数」（约 20 个），开销可以忽略
##   \\u00b7 于是可以把上限放到 260，基本覆盖玩家会走到的全部实例
##   \\u00b7 每个实例仍按自己的位置与朝向摆碰撞形状，互不影响
func _add_prop_colliders(entries: Array, prop_id: String) -> void:
	var limit: float = site_pad_radius * 2.2
	var profile := _prop_collider_profile(prop_id)
	var site_dir: Vector3 = site_direction.normalized()
	# 站点附近的优先（玩家真会走过去），其余按顺序补到上限。
	var picked: Array = []
	var rest: Array = []
	for e in entries:
		var arc: float = acos(clampf((e["dir"] as Vector3).dot(site_dir), -1.0, 1.0)) * radius
		if arc <= limit:
			picked.append(e)
		else:
			rest.append(e)
	for e in rest:
		if picked.size() >= PROP_COLLIDER_CAP:
			break
		picked.append(e)
	if picked.is_empty():
		return
	# 一个物理体承载该类道具的所有碰撞形状。
	var body := StaticBody3D.new()
	body.name = "PropCollision_%s" % prop_id
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for e in picked:
		var dir: Vector3 = e["dir"]
		var size: float = float(e["size"])
		var origin: Vector3 = surface_position(dir, float(e["altitude"]))
		var collision := CollisionShape3D.new()
		# \\u26a0 形状挂在 body 局部空间，所以要把本地方向编进每个形状自己的
		#   transform，不能整体旋转 body（那会把所有实例转到同一朝向）。
		var basis := Basis(Quaternion(Vector3.UP, dir))
		if profile.x < 0.3:
			var shape := CylinderShape3D.new()
			shape.radius = profile.x * size
			shape.height = profile.y * size
			collision.shape = shape
			collision.transform = Transform3D(basis, origin + dir * (profile.y * size * 0.5))
		else:
			var shape := SphereShape3D.new()
			shape.radius = profile.x * size
			collision.shape = shape
			collision.transform = Transform3D(basis, origin + dir * (profile.x * size))
		body.add_child(collision)


'''

s = s[:i] + NEW + s[j:]
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("已重写 _add_prop_colliders：共享物理体 + 上限 34 -> 260")
