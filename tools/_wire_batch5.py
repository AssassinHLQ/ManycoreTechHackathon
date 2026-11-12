# -*- coding: utf-8 -*-
"""把第五批 18 个资产接进 planet.gd。

① 6 个互动机器 → INTERACTIVE_PROPS（含新类型 med）
   med-station      → med（新）：氧气回满
   oxygen-generator → cargo：氧气 +30
   ore-crusher      → crystal：燃料 +35
   holo-terminal    → relic：扫描记录
   wind-turbine     → vent：上升气流
   landing-beacon   → beacon：补给 + 标记
② 9 个生态装饰 → PROP_MODELS + DETAIL_PROPS_EXTRA（新增第二张细节点缀表）
③ 3 个大型地貌 → LANDFORM_PROPS
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

INTERACTIVE = ["med-station", "oxygen-generator", "ore-crusher",
               "holo-terminal", "wind-turbine", "landing-beacon"]
DECOR = ["crystal-vein", "frozen-pond", "sand-ripple", "alien-mound",
         "lava-drip", "coral-stack", "mushroom-ring", "glass-crater",
         "bone-yard"]
LANDFORM = ["lf-mesa-spire", "lf-dune-sea", "lf-crystal-forest"]

# ═══ ① PROP_MODELS ═══
anchor = '\t"stone-bridge": "res://assets/models/props/stone-bridge/model.glb",'
assert s.count(anchor) == 1, "models anchor"
add = "\n".join('\t"%s": "res://assets/models/props/%s/model.glb",' % (p, p)
                for p in INTERACTIVE + DECOR + LANDFORM)
s = s.replace(anchor, anchor + "\n" + add)

# ═══ ② 上限 ═══
anchor2 = '\t"stone-bridge": 4,'
assert s.count(anchor2) == 1, "cap anchor"
add2 = []
for p in INTERACTIVE:
    add2.append('\t"%s": 3,' % p)
for p in DECOR:
    add2.append('\t"%s": 8,' % p)
for p in LANDFORM:
    add2.append('\t"%s": 2,' % p)
s = s.replace(anchor2, anchor2 + "\n" + "\n".join(add2))

# ═══ ③ INTERACTIVE_PROPS 映射 ═══
old = '\t"signal-beacon": "beacon",\n}'
assert s.count(old) == 1, "interactive anchor"
mapping = [
    ("med-station", "med"), ("oxygen-generator", "cargo"),
    ("ore-crusher", "crystal"), ("holo-terminal", "relic"),
    ("wind-turbine", "vent"), ("landing-beacon", "beacon"),
]
s = s.replace(old, '\t"signal-beacon": "beacon",\n' + "\n".join(
    '\t"%s": "%s",' % (p, k) for p, k in mapping) + "\n}")

# ═══ ④ INTERACTIVE_CHARGES 补 med ═══
old = '\t"beacon": [1, 0.0],\n}'
assert s.count(old) == 1, "charges anchor"
s = s.replace(old, '\t"beacon": [1, 0.0],\n\t"med": [2, 180.0],\n}')

# ═══ ⑤ DETAIL_PROPS_EXTRA 表 ═══
anchor3 = "## 铺量混排：[prop_id, 数量, 尺寸下限, 尺寸上限]"
assert s.count(anchor3) == 1, "mix anchor"
extra = '''## 细节点缀层·第二张表（第五批的「生态专属装饰」）。
##
## 与 DETAIL_PROPS 分开维护：那张是通用件（石堆/苔石/枯木…），
## 这张是**各生物群系专属**的小景（晶脉/冻水洼/沙纹/蚁丘/熔岩滴石/珊瑚堆/
## 蘑菇圈/玻璃化坑/骨骸场）。两张表都会被执行，互不覆盖。
const DETAIL_PROPS_EXTRA := {
	"qinglan": [["mushroom-ring", 3, 2, 3], ["alien-mound", 3, 3, 5]],
	"zheya": [["glass-crater", 3, 3, 5], ["lava-drip", 4, 2, 4]],
	"cangbo": [["frozen-pond", 3, 3, 5], ["crystal-vein", 3, 2, 4]],
	"xuanjing": [["crystal-vein", 4, 3, 5], ["glass-crater", 2, 3, 5]],
	"xuanyuan": [["bone-yard", 3, 3, 5], ["glass-crater", 2, 2, 4]],
	"baiyao": [["frozen-pond", 4, 3, 5], ["crystal-vein", 4, 3, 5]],
	"pansha": [["sand-ripple", 5, 3, 5], ["bone-yard", 2, 3, 5]],
	"taiyuan": [["mushroom-ring", 4, 2, 3], ["alien-mound", 3, 3, 5]],
	"liuwu": [["lava-drip", 5, 2, 4], ["glass-crater", 2, 3, 5]],
	"jianmo": [["crystal-vein", 4, 3, 5], ["glass-crater", 3, 2, 4]],
	"jiangxiao": [["lava-drip", 4, 2, 4], ["sand-ripple", 3, 3, 5]],
	"cangwu": [["mushroom-ring", 4, 2, 3], ["alien-mound", 4, 3, 5]],
	"jinwu": [["sand-ripple", 4, 3, 5], ["glass-crater", 2, 2, 4]],
	"yuheng": [["crystal-vein", 4, 3, 5], ["mushroom-ring", 3, 2, 3]],
	"sue": [["bone-yard", 3, 3, 5], ["glass-crater", 2, 2, 4]],
	"danxia": [["sand-ripple", 4, 3, 5], ["bone-yard", 2, 3, 5]],
	"biluo": [["coral-stack", 5, 2, 4], ["frozen-pond", 2, 3, 5]],
	"youdu": [["frozen-pond", 4, 3, 5], ["crystal-vein", 3, 3, 5]],
	"yaoguang": [["crystal-vein", 5, 3, 5], ["glass-crater", 2, 2, 4]],
	"xuanpu": [["mushroom-ring", 4, 2, 3], ["alien-mound", 3, 3, 5]],
}

'''
s = s.replace(anchor3, extra + anchor3)

# ═══ ⑥ _build_detail_props 同时跑两张表 ═══
old = '''	for entry in DETAIL_PROPS.get(kind, []):
		var pid: String = entry[0]
		if _prop_mesh(pid) == null:
			continue
		for _i in range(int(entry[1])):
			var size: float = rng.randf_range(float(entry[2]), float(entry[3])) * prop_scale
			var axis: Vector3 = perp.rotated(site, rng.randf() * TAU)
			# 0.18~0.9 弧度：绕开平地，但还在「走得到」的范围
			var ang: float = maxf(pad_angle * 1.05, rng.randf_range(0.18, 0.9))
			var dir: Vector3 = site.rotated(axis, ang).normalized()
			if _near_cave(dir, 0.03):
				continue
			_add_prop(pid, dir, size, -1.2 * prop_scale, _prop_tint(), false)'''
assert s.count(old) == 1, "detail loop anchor"
new = '''	for table in [DETAIL_PROPS, DETAIL_PROPS_EXTRA]:
		for entry in table.get(kind, []):
			var pid: String = entry[0]
			if _prop_mesh(pid) == null:
				continue
			for _i in range(int(entry[1])):
				var size: float = rng.randf_range(float(entry[2]), float(entry[3])) * prop_scale
				var axis: Vector3 = perp.rotated(site, rng.randf() * TAU)
				# 0.18~0.9 弧度：绕开平地，但还在「走得到」的范围
				var ang: float = maxf(pad_angle * 1.05, rng.randf_range(0.18, 0.9))
				var dir: Vector3 = site.rotated(axis, ang).normalized()
				if _near_cave(dir, 0.03):
					continue
				_add_prop(pid, dir, size, -1.2 * prop_scale, _prop_tint(), false)'''
s = s.replace(old, new)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("wired batch5: %d interactive / %d decor / %d landform" % (
    len(INTERACTIVE), len(DECOR), len(LANDFORM)))
