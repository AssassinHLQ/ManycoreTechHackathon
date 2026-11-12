# -*- coding: utf-8 -*-
"""把最后两处程序化摆件（_add_crystal / _add_spout）也换成 AI 资产。

用户要求「不能是程序化的，必须 AI 生成」。planet.gd 里还剩：
  · _add_crystal() —— 13 处调用，直接手搓 ArrayMesh 晶簇
  · _add_spout()   —— 1 处调用，手搓喷气孔
现在改成：优先用 Lux3D 的 crystal-cluster-lo / vent-lo（1 万面低模，铺量用），
缺失时回退原程序化实现（原代码一行不删）。

另外把目标 ② 点名的「桥」stone-bridge 加进有裂谷/沟槽设定的星球地貌表。
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ═══════════ 1. 资产表补三条 ═══════════
old = '\t"crystal-cluster": "res://assets/models/props/crystal-cluster/model.glb",'
assert s.count(old) == 1, "crystal model anchor"
s = s.replace(old, old + '''
\t"crystal-cluster-lo": "res://assets/models/props/crystal-cluster-lo/model.glb",
\t"vent-lo": "res://assets/models/props/vent-lo/model.glb",
\t"stone-bridge": "res://assets/models/props/stone-bridge/model.glb",''')

# ═══════════ 2. 限额表 ═══════════
old = '\t"crystal-cluster": 10,'
assert s.count(old) == 1, "crystal cap anchor"
s = s.replace(old, '''\t"crystal-cluster": 10,
\t"crystal-cluster-lo": 70,
\t"vent-lo": 60,
\t"stone-bridge": 4,''')

# ═══════════ 3. _add_crystal 走 AI ═══════════
old = """func _add_crystal(direction: Vector3, color: Color, altitude: float) -> void:
	var root := _prop_parent(direction, altitude)"""
assert s.count(old) == 1, "add_crystal anchor"
s = s.replace(old, """func _add_crystal(direction: Vector3, color: Color, altitude: float) -> void:
	# \u26a0 2026-11-11 \u7528\u6237\uff1a\u300c\u4e0d\u80fd\u662f\u7a0b\u5e8f\u5316\u7684\uff0c\u5fc5\u987b AI \u751f\u6210\u300d\u3002
	#   \u4f18\u5148\u7528 Lux3D \u7684\u53d1\u5149\u6676\u7c07\uff08\u4f4e\u6a21\u53d8\u4f53\u94fa\u91cf\u7528\uff09\uff0c\u7f3a\u5931\u65f6\u56de\u9000\u4e0b\u9762\u7684\u7a0b\u5e8f\u5316\u6676\u7c07\u3002
	if _prop_mesh("crystal-cluster-lo") != null:
		_add_prop("crystal-cluster-lo", direction,
			rng.randf_range(16.0, 34.0) * prop_scale, altitude, color)
		return
	var root := _prop_parent(direction, altitude)""")

# ═══════════ 4. _add_spout 走 AI ═══════════
old = """func _add_spout(direction: Vector3) -> void:
	var root := _prop_parent(direction, -1.0)"""
assert s.count(old) == 1, "add_spout anchor"
s = s.replace(old, """func _add_spout(direction: Vector3) -> void:
	# \u540c _add_crystal\uff1a\u4f18\u5148 AI \u55b7\u53e3\uff08\u4f4e\u6a21\u53d8\u4f53\uff09\uff0c\u7f3a\u5931\u65f6\u56de\u9000\u7a0b\u5e8f\u5316\u3002
	if _prop_mesh("vent-lo") != null:
		_add_prop("vent-lo", direction,
			rng.randf_range(14.0, 28.0) * prop_scale, -1.0 * prop_scale, _prop_tint())
		return
	var root := _prop_parent(direction, -1.0)""")

# ═══════════ 5. 桥加进有裂谷/沟槽设定的星球 ═══════════
BRIDGE = ', ["stone-bridge", 1, 90, 150, false]'
for kind in ["zheya", "liuwu", "danxia", "jianmo", "xuanyuan"]:
    # 精确整行替换，避免字符串搜索错位
    lines = s.split("\n")
    hit = None
    for i, ln in enumerate(lines):
        if ln.startswith('\t"%s": [[' % kind) and "LANDFORM" not in ln:
            hit = i
    assert hit is not None, "landform line for %s" % kind
    ln = lines[hit]
    if "stone-bridge" in ln:
        continue
    # 行以 "]]," 结尾 → 改成 ', ["stone-bridge", ...]],'
    assert ln.endswith("]],"), "unexpected landform line %s: %s" % (kind, ln)
    lines[hit] = ln[:-3] + BRIDGE + "]],"
    s = "\n".join(lines)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("crystal/spout -> AI, bridge added:", o != s)
