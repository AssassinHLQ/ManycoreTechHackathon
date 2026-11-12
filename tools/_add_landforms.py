# -*- coding: utf-8 -*-
"""目标 ④「地形也要更多 AI 生成细节，更强的起伏 / 大型地貌特征」——全部零额度。

两条手段：
  A. 起伏加强分级：实测缄默 -9%/+8%、丹霞 -5%/+4% 够戏剧性，
     但幽都/瑶光只有 ±2~4%，看着平。按 kind 给不同 boost：
       水体/冰原（沧波、碧落）      1.06  ← 保持平，否则海面碎成山脊
       常规岩石星球                1.35
       最平的几颗（幽都/瑶光/素娥/玉衡/丹霞）1.55  ← 让它们也有山
  B. 大型地貌件：把已生成的 AI 资产放大到 300~800 米当地貌地标（零额度）。
     用 floating-rock 当悬空巨岩、rock-spire 当千米石柱、rock-cluster 当整座山丘。

⚠ 起伏加强必须三处同步（高度查询 / 可视网格 / 平地基准），这里的 _lift_lux 已经
   是唯一入口，分级改造只改 _lift_lux 内部，不会破坏同步。
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ═══════════ A. 起伏分级 ═══════════
old = """const LUX_RELIEF_BOOST := 1.25

## 少数「以水/冰/平原为主」的星球保持较平的起伏，否则海面与冰架会碎成山脊。
const LUX_RELIEF_FLAT_KINDS := ["cangbo", "biluo", "jinwu", "yuheng"]

func _lift_lux(h: float) -> float:
	if radius <= 0.0:
		return h
	if kind in LUX_RELIEF_FLAT_KINDS:
		return radius + (h - radius) * 1.06
	return radius + (h - radius) * LUX_RELIEF_BOOST"""
new = """const LUX_RELIEF_BOOST := 1.35

## 少数「以水/冰/平原为主」的星球保持较平的起伏，否则海面与冰架会碎成山脊。
const LUX_RELIEF_FLAT_KINDS := ["cangbo", "biluo"]

## 实测起伏最小的几颗（高度表只有 ±2~4%），单独提高加强系数，
## 让它们也有能看的地形层次。实测值见 tests/probe_relief_budget.gd。
const LUX_RELIEF_BOLD_KINDS := ["youdu", "yaoguang", "sue", "yuheng", "danxia", "xuanpu"]
const LUX_RELIEF_BOLD := 1.55

func _lift_lux(h: float) -> float:
	if radius <= 0.0:
		return h
	if kind in LUX_RELIEF_FLAT_KINDS:
		return radius + (h - radius) * 1.06
	if kind in LUX_RELIEF_BOLD_KINDS:
		return radius + (h - radius) * LUX_RELIEF_BOLD
	return radius + (h - radius) * LUX_RELIEF_BOOST"""
assert s.count(old) == 1, "boost anchor"
s = s.replace(old, new)

# ═══════════ B. 大型地貌件表 ═══════════
old2 = "## 会「悬浮」的道具：放置时抬高，做成浮空岛/浮石。"
assert s.count(old2) == 1, "floating const"
s = s.replace(old2, """## 大型地貌件（目标 ④「大型地貌特征」）。
##
## 复用已生成的 AI 资产、放大到 300~800 米世界高度，做成从轨道上就能看见的地标：
##   floating-rock  → 悬空巨岩（科幻感强）
##   rock-spire     → 千米石柱 / 侵蚀塔
##   rock-cluster   → 整座山丘群
##   crystal-cluster→ 巨型晶脉
## 尺寸是「设计米数」，运行时 × prop_scale。
## ⚠ 这一条**完全零额度**：只是把已有 GLB 放大，不新增生成。
const LANDFORM_PROPS := {
	"qinglan": [["rock-cluster", 1, 90, 130, false]],
	"zheya": [["rock-spire", 2, 110, 190, false], ["rock-cluster", 1, 80, 120, false]],
	"cangbo": [["floating-rock", 2, 100, 170, false]],
	"xuanjing": [["floating-rock", 3, 90, 160, false], ["rock-spire", 1, 100, 150, false]],
	"xuanyuan": [["rock-spire", 2, 130, 220, false]],
	"baiyao": [["rock-spire", 2, 110, 200, false]],
	"pansha": [["rock-spire", 3, 120, 220, false]],
	"taiyuan": [["rock-cluster", 2, 85, 130, false]],
	"liuwu": [["rock-spire", 1, 110, 170, false], ["rock-cluster", 1, 80, 120, false]],
	"jianmo": [["rock-spire", 3, 130, 230, false], ["floating-rock", 1, 100, 150, false]],
	"jiangxiao": [["rock-spire", 2, 110, 190, false]],
	"cangwu": [["rock-cluster", 2, 85, 135, false]],
	"jinwu": [["rock-cluster", 2, 80, 125, false]],
	"yuheng": [["crystal-cluster", 2, 90, 150, false]],
	"sue": [["rock-spire", 2, 100, 170, false]],
	"danxia": [["rock-cluster", 2, 90, 140, false], ["rock-spire", 1, 110, 180, false]],
	"biluo": [["floating-rock", 2, 95, 160, false]],
	"youdu": [["crystal-cluster", 2, 95, 160, false], ["rock-spire", 1, 110, 180, false]],
	"yaoguang": [["crystal-cluster", 3, 100, 170, false], ["floating-rock", 1, 95, 150, false]],
	"xuanpu": [["rock-cluster", 1, 90, 140, false], ["crystal-cluster", 1, 90, 140, false]],
}

## 会「悬浮」的道具：放置时抬高，做成浮空岛/浮石。""")

# ═══════════ B-2 布置地貌件 ═══════════
old3 = """	# 地标是在 _build_landscape 之后才排进队列的，所以必须在这里补一次 flush
	# （_flush_props 内部有 _flushed_prop_ids 去重，铺量那批不会重复实例化）。
	_flush_props()"""
assert s.count(old3) == 1, "landmark tail"
s = s.replace(old3, """	# 目标 ④：大型地貌件（把已有资产放大，零额度）
	_build_landform_props()
	# 地标与地貌件都是在 _build_landscape 之后才排进队列的，所以必须在这里补 flush
	# （_flush_props 内部有 _flushed_prop_ids 去重，铺量那批不会重复实例化）。
	_flush_props()""")

old4 = """## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，"""
assert s.count(old4) == 1, "tint2"
s = s.replace(old4, """## 布置大型地貌件（目标 ④）。复用已有 AI 资产放大，零额度消耗。
func _build_landform_props() -> void:
	var table: Array = LANDFORM_PROPS.get(kind, [])
	if table.is_empty():
		return
	for entry in table:
		var prop_id: String = entry[0]
		if _prop_mesh(prop_id) == null:
			continue
		var count: int = int(entry[1])
		var size_min: float = float(entry[2]) * prop_scale
		var size_max: float = float(entry[3]) * prop_scale
		var floating: bool = PROP_FLOATING.has(prop_id)
		for _i in range(count):
			# 地貌件放得远一点，别压住基地
			var dir := _pick_prop_direction(false)
			if dir == Vector3.ZERO:
				continue
			var size := rng.randf_range(size_min, size_max)
			var altitude: float = size * 0.45 if floating else -size * 0.05
			_add_prop(prop_id, dir, size, altitude, _prop_tint(), false)


## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，""")

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("relief tiers + landforms:", o != s)
