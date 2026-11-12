# -*- coding: utf-8 -*-
"""A：可交互道具有「次数 + 冷却再生」。

用户 2026-11-12：「ABC 顺序来做」。
A = 给交互加采集次数/冷却的资源循环（采完变暗，过一会儿长回来）。

设计：
  · 每个交互点有 charges（晶簇 3 次、货舱 2 次、喷口/遗迹 1 次）
  · 采到 0 → 该实例的 MultiMesh 颜色调暗（视觉上「采空了」），进入冷却
  · 冷却结束 → 次数长回来、颜色恢复（资源循环，不是一次性消耗）
  · 需要把「交互点 → MultiMesh 实例节点 + 实例下标」的映射建起来，
    才能在运行时单独改某一个实例的颜色
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ═══ 1. 每次采集的充能数（按 prop_id）═══
old = 'const INTERACTIVE_PROPS := {'
assert s.count(old) == 1
new = '''## \u6bcf\u4e2a\u4ea4\u4e92\u70b9\u7684\u5145\u80fd\u6570\u4e0e\u51b7\u5374\u79d2\u6570\u3002
##
## charges = \u80fd\u91c7\u51e0\u6b21\uff1bcooldown = \u91c7\u7a7a\u540e\u591a\u5c11\u79d2\u957f\u56de\u6765\u3002
## \u300c\u77ff\u8109\u578b\u300d\u7684\u4e1c\u897f\u80fd\u53cd\u590d\u91c7\uff0c\u300c\u4e00\u6b21\u6027\u300d\u7684\uff08\u9057\u8ff9\u626b\u63cf\u3001\u55b7\u53e3\uff09\u53ea\u7ed9 1\u3002
const INTERACTIVE_CHARGES := {
	"crystal": [3, 90.0],
	"cargo": [2, 150.0],
	"vent": [1, 120.0],
	"relic": [1, 0.0],
	"beacon": [1, 0.0],
}


const INTERACTIVE_PROPS := {'''
s = s.replace(old, new)

# ═══ 2. spot 结构加字段 ═══
old = '''	var ikind := String(INTERACTIVE_PROPS.get(prop_id, ""))
	if ikind != "":
		interactive_spots.append({
			"id": prop_id,
			"kind": ikind,
			"dir": ndir,
			"size": size,
			"altitude": altitude,
			"used": false,
		})'''
assert s.count(old) == 1, "spot append anchor"
new = '''	var ikind := String(INTERACTIVE_PROPS.get(prop_id, ""))
	if ikind != "":
		var cfg: Array = INTERACTIVE_CHARGES.get(ikind, [1, 0.0])
		var spot_index: int = interactive_spots.size()
		interactive_spots.append({
			"id": prop_id,
			"kind": ikind,
			"dir": ndir,
			"size": size,
			"altitude": altitude,
			"used": false,
			"charges": int(cfg[0]),
			"max_charges": int(cfg[0]),
			"cooldown": float(cfg[1]),
			"ready_at": 0,
			"scanned": false,
			"tint": tint,
			"node": null,
			"mi": -1,
		})
		# \u8ba9 _flush_props \u5efa\u7acb\u300c\u4ea4\u4e92\u70b9 \u2192 MultiMesh \u5b9e\u4f8b\u300d\u7684\u6620\u5c04\uff0c
		# \u5426\u5219\u6ca1\u529e\u6cd5\u5728\u8fd0\u884c\u65f6\u5355\u72ec\u628a\u67d0\u4e00\u4e2a\u5b9e\u4f8b\u8c03\u6697\u3002
		(prop_queue[prop_id] as Array)[-1]["spot"] = spot_index'''
s = s.replace(old, new)

# ═══ 3. _flush_props 建立映射 ═══
old = '''			mm.set_instance_transform(i, Transform3D(basis, origin))
			mm.set_instance_color(i, e["tint"])'''
assert s.count(old) == 1, "flush anchor"
new = '''			mm.set_instance_transform(i, Transform3D(basis, origin))
			mm.set_instance_color(i, e["tint"])
			# \u4ea4\u4e92\u70b9\u5efa\u7acb\u5230\u5b9e\u4f8b\u7684\u6620\u5c04\uff08\u4f9b\u91c7\u7a7a\u540e\u8c03\u6697\u7528\uff09
			if e.has("spot"):
				var si: int = int(e["spot"])
				if si >= 0 and si < interactive_spots.size():
					(interactive_spots[si] as Dictionary)["node"] = instance
					(interactive_spots[si] as Dictionary)["mi"] = i'''
s = s.replace(old, new)

# ═══ 4. nearest_interactive：采空且未冷却的不算可交互 ═══
old = '''		var spot: Dictionary = interactive_spots[i]
		if bool(spot["used"]):
			continue'''
assert s.count(old) == 1, "nearest filter anchor"
new = '''		var spot: Dictionary = interactive_spots[i]
		if bool(spot["used"]):
			continue
		if int(spot["charges"]) <= 0:
			continue          # \u91c7\u7a7a\u4e86\uff0c\u7b49\u51b7\u5374'''
s = s.replace(old, new)

# ═══ 5. consume_interactive 改成扣次数 + 调暗 + 冷却 ═══
old = '''## \u6807\u8bb0\u67d0\u4e2a\u4ea4\u4e92\u70b9\u5df2\u7528\u6389\uff08\u91c7\u96c6/\u62c6\u89e3\u8fc7\u5c31\u4e0d\u80fd\u518d\u91c7\uff09\u3002
func consume_interactive(index: int) -> void:
	if index >= 0 and index < interactive_spots.size():
		(interactive_spots[index] as Dictionary)["used"] = true'''
assert s.count(old) == 1, "consume anchor"
new = '''## \u6263\u4e00\u6b21\u6b21\u6570\u3002\u6263\u5230 0 \u5c31\u628a\u8be5\u5b9e\u4f8b\u8c03\u6697\u5e76\u8fdb\u5165\u51b7\u5374\uff0c\u51b7\u5374\u5b8c\u81ea\u52a8\u957f\u56de\u6765\u3002
##
## \u8fd4\u56de\u5269\u4f59\u6b21\u6570\uff080 = \u521a\u91c7\u7a7a\uff09\u3002
func consume_interactive(index: int) -> int:
	if index < 0 or index >= interactive_spots.size():
		return 0
	var spot: Dictionary = interactive_spots[index]
	var left: int = maxi(int(spot["charges"]) - 1, 0)
	spot["charges"] = left
	if left <= 0:
		_set_spot_dim(spot, true)
		var cd: float = float(spot["cooldown"])
		if cd <= 0.0:
			spot["used"] = true      # \u4e00\u6b21\u6027\u7684\uff08\u9057\u8ff9/\u55b7\u53e3\uff09\u76f4\u63a5\u4f5c\u5e9f
		else:
			spot["ready_at"] = Time.get_ticks_msec() / 1000.0 + cd
	return left


## \u628a\u67d0\u4e2a\u4ea4\u4e92\u5b9e\u4f8b\u7684\u989c\u8272\u8c03\u6697 / \u6062\u590d\uff08\u91c7\u7a7a\u7684\u76f4\u89c2\u53cd\u9988\uff09\u3002
func _set_spot_dim(spot: Dictionary, dim: bool) -> void:
	var node = spot.get("node")
	var mi: int = int(spot.get("mi", -1))
	if node == null or not is_instance_valid(node) or mi < 0:
		return
	var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
	if mm == null or mi >= mm.instance_count:
		return
	var tint: Color = spot["tint"]
	if dim:
		mm.set_instance_color(mi, Color(tint.r * 0.22, tint.g * 0.22, tint.b * 0.22, tint.a))
	else:
		mm.set_instance_color(mi, tint)


## \u51b7\u5374\u5230\u671f\u7684\u4ea4\u4e92\u70b9\u91cd\u65b0\u5145\u80fd\uff08\u5728 _process \u91cc\u8c03\uff09\u3002
func _refresh_interactive_charges() -> void:
	if interactive_spots.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	for i in range(interactive_spots.size()):
		var spot: Dictionary = interactive_spots[i]
		if bool(spot["used"]) or int(spot["charges"]) > 0:
			continue
		if now < float(spot["ready_at"]):
			continue
		spot["charges"] = int(spot["max_charges"])
		_set_spot_dim(spot, false)


## \u67d0\u9897\u661f\u7403\u7684\u9057\u8ff9\u626b\u63cf\u8fdb\u5ea6\uff1a[\u5df2\u626b, \u603b\u6570]\u3002
func relic_progress() -> Array:
	var total := 0
	var done := 0
	for spot in interactive_spots:
		if String(spot["kind"]) != "relic":
			continue
		total += 1
		if bool(spot["scanned"]):
			done += 1
	return [done, total]'''
s = s.replace(old, new)

# ═══ 6. _process 里刷新冷却 ═══
old = '''		_update_orbit()
		_update_water()'''
assert s.count(old) == 1, "process anchor"
new = '''		_update_orbit()
		_update_water()
		_refresh_interactive_charges()'''
s = s.replace(old, new)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("A: charges + cooldown added:", o != s)
