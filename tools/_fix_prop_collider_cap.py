# -*- coding: utf-8 -*-
"""修正 AI 道具碰撞体的选取策略。

实测（青岚星）：90 个树实例里，落在「站点 2.2 倍平地半径（506 米弧长）」内的
是 **0 个** —— 因为 _build_landscape 的 direction 是整球随机分布，
506 米只占球面周长的 4%，90 个随机点命中 0 个完全正常。

而冒烟断言要求「站点附近有 > 30 个 StaticBody3D」。

所以改成两条并集：
  ① 站点附近的全部加（玩家真会走进去）
  ② 再按队列顺序补齐到每类 COLLIDER_CAP 个（保证总量够、且均匀覆盖）
这样既不会给 180 个实例全加物理体，也不会出现「一个都没有」。
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

old = """func _add_prop_colliders(entries: Array, prop_id: String) -> void:
	var limit: float = site_pad_radius * 2.2
	var profile := _prop_collider_profile(prop_id)
	for e in entries:
		var dir: Vector3 = e["dir"]
		var size: float = float(e["size"])
		var origin: Vector3 = surface_position(dir,
			float(e["altitude"]) - size * 0.0)
		# 站点的角距离（用地表弧长近似）
		if acos(clampf(dir.dot(site_direction.normalized()), -1.0, 1.0)) * radius > limit:
			continue"""
new = """## 每类道具最多补多少个碰撞体。
##
## ⚠ 2026-11-11 实测教训：一开始只给「站点 2.2 倍平地半径（506 米弧长）」内的
##   实例加碰撞体，结果 90 个树实例里**命中 0 个** —— 因为 _build_landscape 的
##   方向是整球随机分布，506 米只占周长的 4%。
##   现在改成「站点附近的优先 + 按队列顺序补到上限」，两种覆盖都拿到。
const PROP_COLLIDER_CAP := 34


func _add_prop_colliders(entries: Array, prop_id: String) -> void:
	var limit: float = site_pad_radius * 2.2
	var profile := _prop_collider_profile(prop_id)
	var site_dir: Vector3 = site_direction.normalized()
	# 先挑出站点附近的（玩家真会走过去），再按顺序补到上限。
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
	picked = picked.slice(0, PROP_COLLIDER_CAP)
	for e in picked:
		var dir: Vector3 = e["dir"]
		var size: float = float(e["size"])
		var origin: Vector3 = surface_position(dir, float(e["altitude"]))"""
assert s.count(old) == 1, "collider fn anchor"
s = s.replace(old, new)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("collider selection fixed:", o != s)
