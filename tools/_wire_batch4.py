# -*- coding: utf-8 -*-
"""把第四批 36 个资产接进 planet.gd。

① 12 个互动物品 → INTERACTIVE_PROPS（映射到已有的 4 种效果）
   power-cell / fuel-tank        → crystal（补喷气燃料 +35）
   supply-crate / mining-rig / pipe-cluster → cargo（补氧气 +30）
   thermal-stack                 → vent（上升气流）
   control-console / stasis-pod / holo-slab / databank / comm-dish / signal-beacon
                                 → relic（扫描记录）
② 16 个通用装饰 → PROP_MODELS + 上限，并新增 DETAIL_PROPS 细节点缀层
③ 8 个大型地貌 → LANDFORM_PROPS
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

INTERACTIVE = ["power-cell", "control-console", "stasis-pod", "signal-beacon",
               "mining-rig", "fuel-tank", "holo-slab", "supply-crate",
               "pipe-cluster", "comm-dish", "thermal-stack", "databank"]
DECOR = ["bone-fossil", "stone-cairn", "mossy-boulder", "icicle-cluster",
         "dune-grass", "ore-scrap", "rail-segment", "banner-pole",
         "rope-coil", "plank-walkway", "gravel-pile", "rusted-hull",
         "glass-shards", "twisted-metal", "dead-shrub", "bleached-log"]
LANDFORM = ["lf-crater-rim", "lf-dry-riverbed", "lf-glacier-wall",
            "lf-boulder-field", "lf-cliff-terraces", "lf-sinkhole",
            "lf-lava-flow", "lf-salt-flat"]

# ═══════════ ① PROP_MODELS ═══════════
anchor = '\t"stone-bridge": "res://assets/models/props/stone-bridge/model.glb",'
assert s.count(anchor) == 1, "models anchor"
add = "\n".join('\t"%s": "res://assets/models/props/%s/model.glb",' % (p, p)
                for p in INTERACTIVE + DECOR + LANDFORM)
s = s.replace(anchor, anchor + "\n" + add)

# ═══════════ ② 实例上限 ═══════════
anchor2 = '\t"stone-bridge": 4,'
assert s.count(anchor2) == 1, "cap anchor"
add2 = []
for p in INTERACTIVE:
    add2.append('\t"%s": 4,' % p)
for p in DECOR:
    add2.append('\t"%s": 10,' % p)
for p in LANDFORM:
    add2.append('\t"%s": 2,' % p)
s = s.replace(anchor2, anchor2 + "\n" + "\n".join(add2))

# ═══════════ ③ INTERACTIVE_PROPS 映射 ═══════════
old = '\t"rubble-wall": "relic",\n}'
assert s.count(old) == 1, "interactive table anchor"
mapping = [
    ("power-cell", "crystal"), ("fuel-tank", "crystal"),
    ("supply-crate", "cargo"), ("mining-rig", "cargo"),
    ("pipe-cluster", "cargo"), ("thermal-stack", "vent"),
    ("control-console", "relic"), ("stasis-pod", "relic"),
    ("holo-slab", "relic"), ("databank", "relic"),
    ("comm-dish", "relic"), ("signal-beacon", "relic"),
]
new = '\t"rubble-wall": "relic",\n' + "\n".join(
    '\t"%s": "%s",' % (p, k) for p, k in mapping) + "\n}"
s = s.replace(old, new)

# ═══════════ ④ DETAIL_PROPS 细节点缀层 ═══════════
anchor3 = "## 铺量混排：[prop_id, 数量, 尺寸下限, 尺寸上限]"
assert s.count(anchor3) == 1, "mix table anchor"
detail = '''## 细节点缀层：中距离的小物件，给「走出基地那一段」加视觉信息。
##
## 和 SCATTER_MIX（整球铺量、控总量）分工：
##   SCATTER_MIX 负责「远看有东西」，这一层负责「走近有细节」。
## 位置在站点 0.18~0.9 弧度（约 360~1800 米），不压平地、不堵楼梯。
const DETAIL_PROPS := {
	"qinglan": [["stone-cairn", 4, 2, 3], ["mossy-boulder", 6, 2, 4], ["bleached-log", 5, 3, 6], ["rope-coil", 3, 1, 2]],
	"zheya": [["ore-scrap", 6, 2, 4], ["rusted-hull", 4, 3, 6], ["gravel-pile", 6, 2, 3], ["dead-shrub", 5, 2, 3]],
	"cangbo": [["icicle-cluster", 6, 2, 4], ["stone-cairn", 4, 2, 3], ["gravel-pile", 5, 2, 3]],
	"xuanjing": [["glass-shards", 6, 2, 3], ["twisted-metal", 5, 3, 5], ["ore-scrap", 5, 2, 4]],
	"xuanyuan": [["bone-fossil", 4, 3, 6], ["stone-cairn", 5, 2, 3], ["gravel-pile", 5, 2, 3]],
	"baiyao": [["icicle-cluster", 8, 2, 4], ["stone-cairn", 3, 2, 3]],
	"pansha": [["dune-grass", 8, 1, 2], ["bleached-log", 5, 3, 6], ["gravel-pile", 5, 2, 3]],
	"taiyuan": [["dead-shrub", 7, 2, 3], ["stone-cairn", 4, 2, 3], ["rope-coil", 3, 1, 2]],
	"liuwu": [["rusted-hull", 5, 3, 6], ["pipe-cluster", 4, 2, 4], ["ore-scrap", 5, 2, 4]],
	"jianmo": [["glass-shards", 5, 2, 3], ["stone-cairn", 5, 2, 3]],
	"jiangxiao": [["ore-scrap", 6, 2, 4], ["gravel-pile", 6, 2, 3], ["rusted-hull", 3, 3, 5]],
	"cangwu": [["mossy-boulder", 6, 2, 4], ["bleached-log", 5, 3, 6], ["dead-shrub", 5, 2, 3]],
	"jinwu": [["gravel-pile", 7, 2, 3], ["bleached-log", 4, 3, 6], ["dune-grass", 5, 1, 2]],
	"yuheng": [["mossy-boulder", 5, 2, 4], ["glass-shards", 5, 2, 3], ["stone-cairn", 4, 2, 3]],
	"sue": [["gravel-pile", 7, 2, 3], ["stone-cairn", 5, 2, 3], ["bone-fossil", 3, 3, 6]],
	"danxia": [["gravel-pile", 6, 2, 3], ["ore-scrap", 5, 2, 4], ["dune-grass", 4, 1, 2]],
	"biluo": [["glass-shards", 6, 2, 3], ["mossy-boulder", 4, 2, 4], ["rope-coil", 3, 1, 2]],
	"youdu": [["icicle-cluster", 7, 2, 4], ["glass-shards", 4, 2, 3], ["stone-cairn", 3, 2, 3]],
	"yaoguang": [["glass-shards", 7, 2, 3], ["stone-cairn", 4, 2, 3], ["icicle-cluster", 4, 2, 4]],
	"xuanpu": [["mossy-boulder", 5, 2, 4], ["dead-shrub", 6, 2, 3], ["rope-coil", 3, 1, 2]],
}

'''
s = s.replace(anchor3, detail + anchor3)

# ═══════════ ⑤ 布置函数 ═══════════
anchor4 = "## 互动种子：保证每颗星球都有四种互动可用。"
assert s.count(anchor4) == 1, "seed fn anchor"
fn = '''## 细节点缀层布置（见 DETAIL_PROPS）。
func _build_detail_props() -> void:
\tvar site: Vector3 = site_direction.normalized()
\tvar perp: Vector3 = site.cross(Vector3.FORWARD)
\tif perp.length_squared() < 0.01:
\t\tperp = site.cross(Vector3.RIGHT)
\tperp = perp.normalized()
\tvar pad_angle: float = site_pad_radius / maxf(radius, 1.0)
\tfor entry in DETAIL_PROPS.get(kind, []):
\t\tvar pid: String = entry[0]
\t\tif _prop_mesh(pid) == null:
\t\t\tcontinue
\t\tfor _i in range(int(entry[1])):
\t\t\tvar size: float = rng.randf_range(float(entry[2]), float(entry[3])) * prop_scale
\t\t\tvar axis: Vector3 = perp.rotated(site, rng.randf() * TAU)
\t\t\t# 0.18~0.9 弧度：绕开平地，但还在「走得到」的范围
\t\t\tvar ang: float = maxf(pad_angle * 1.05, rng.randf_range(0.18, 0.9))
\t\t\tvar dir: Vector3 = site.rotated(axis, ang).normalized()
\t\t\tif _near_cave(dir, 0.03):
\t\t\t\tcontinue
\t\t\t_add_prop(pid, dir, size, -1.2 * prop_scale, _prop_tint(), false)


'''
s = s.replace(anchor4, fn + anchor4)

# 调用：放在基地点缀之后
old_call = "\t# 互动种子：保证每颗星球都有晶簇/货舱/喷口可用\n\t_build_interactive_seeds()"
assert s.count(old_call) == 1, "call anchor"
s = s.replace(old_call, old_call + "\n\t# 细节点缀层：走出去那一段的小物件\n\t_build_detail_props()")

# ═══════════ ⑥ LANDFORM_PROPS 补 8 条 ═══════════
LF_ADD = {
    "qinglan": '["lf-boulder-field", 1, 26, 40, false]',
    "zheya": '["lf-lava-flow", 1, 28, 46, false]',
    "cangbo": '["lf-glacier-wall", 1, 28, 46, false]',
    "xuanjing": '["lf-sinkhole", 1, 28, 44, false]',
    "xuanyuan": '["lf-crater-rim", 1, 26, 42, false]',
    "baiyao": '["lf-glacier-wall", 1, 28, 46, false]',
    "pansha": '["lf-dry-riverbed", 1, 26, 42, false]',
    "taiyuan": '["lf-crater-rim", 1, 26, 40, false]',
    "liuwu": '["lf-lava-flow", 1, 28, 46, false]',
    "jianmo": '["lf-crater-rim", 1, 26, 42, false]',
    "jiangxiao": '["lf-cliff-terraces", 1, 28, 46, false]',
    "cangwu": '["lf-sinkhole", 1, 26, 42, false]',
    "jinwu": '["lf-salt-flat", 1, 26, 42, false]',
    "yuheng": '["lf-cliff-terraces", 1, 26, 44, false]',
    "sue": '["lf-boulder-field", 1, 26, 40, false]',
    "danxia": '["lf-cliff-terraces", 1, 28, 46, false]',
    "biluo": '["lf-salt-flat", 1, 26, 40, false]',
    "youdu": '["lf-glacier-wall", 1, 28, 46, false]',
    "yaoguang": '["lf-crater-rim", 1, 26, 42, false]',
    "xuanpu": '["lf-dry-riverbed", 1, 26, 40, false]',
}
lines = s.split("\n")
lf_start = None
for i, ln in enumerate(lines):
    if "const LANDFORM_PROPS" in ln:
        lf_start = i
        break
assert lf_start is not None, "LANDFORM_PROPS not found"
lf_end = lf_start
while lf_end < len(lines) and lines[lf_end].strip() != "}":
    lf_end += 1
for k, entry in LF_ADD.items():
    hit = None
    for i in range(lf_start, lf_end):
        if lines[i].startswith('\t"%s": [[' % k):
            hit = i
            break
    assert hit is not None, "landform row %s" % k
    # 行可能是多行写法（首行不以 ]], 结尾），往后扫到真正收尾的那一行
    tail = hit
    guard = 0
    while tail < lf_end and not lines[tail].rstrip().endswith("]],"):
        tail += 1
        guard += 1
        assert guard < 8, "row %s 找不到结尾" % k
    row = lines[tail].rstrip()
    assert row.endswith("]],"), "unexpected row %s: %r" % (k, row)
    cr = lines[tail][len(row):]
    lines[tail] = row[:-3] + ", " + entry + "]]," + cr
s = "\n".join(lines)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("wired: %d interactive / %d decor / %d landform" % (
    len(INTERACTIVE), len(DECOR), len(LANDFORM)))
