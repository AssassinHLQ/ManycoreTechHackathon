# -*- coding: utf-8 -*-
"""目标 ③④：
  ③ 按星球类型布置 AI 道具组合 + 特殊地标（每颗星球看起来不一样）
  ④ 地形起伏加强（LUX_RELIEF_BOOST），且必须在「高度查询 / 可视网格 / 平地基准」
     三处同步应用，否则又会变成卡死那个老问题。

关键约束（写在这里免得以后踩）：`terrain_height()` 是着陆、行走、碰撞、建筑定位
的唯一真源。任何对高度的改动都必须同时改：
    · _sample_lux_height()      —— 高度查询
    · _displace_lux_mesh_to_pad() 的 smooth_r —— 可视网格 conform 目标
    · site_raw（平地基准 site_height 的来源）
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ══════════════ ④-1 起伏加强系数 ══════════════
old = "func _sample_lux_height(dir: Vector3) -> float:"
assert s.count(old) == 1
s = s.replace(old, """## 地形起伏加强系数（目标 ④「地形也要更多 AI 生成细节，更强的起伏」）。
##
## Lux3D 给的星球模型本身起伏就比程序化强（半径比 4~5 倍），但中值滤波 +
## conform=1.0 之后被抹平了一部分，站在地上看只剩缓坡。
## 这里把「相对设计半径的偏离量」放大，山更高、盆地更深，而球体本身不变。
##
## ⚠ 必须与可视网格、平地基准同步（见文件顶部与本函数的调用点），
##   否则可视面与碰撞面再次分离，玩家会被卡住 —— 那是 2026-11-11 修过一轮的老问题。
const LUX_RELIEF_BOOST := 1.25

## 少数「以水/冰/平原为主」的星球保持较平的起伏，否则海面与冰架会碎成山脊。
const LUX_RELIEF_FLAT_KINDS := ["cangbo", "biluo", "jinwu", "yuheng"]

func _lift_lux(h: float) -> float:
	if radius <= 0.0:
		return h
	if kind in LUX_RELIEF_FLAT_KINDS:
		return radius + (h - radius) * 1.06
	return radius + (h - radius) * LUX_RELIEF_BOOST


func _sample_lux_height(dir: Vector3) -> float:
	return _lift_lux(_sample_lux_map(_lux_height_map, dir))""")

# ══════════════ ④-2 可视网格 conform 也走同一个加强 ══════════════
old = """				var smooth_r: float = _sample_lux_map(_lux_height_map, dir)"""
assert s.count(old) == 1, "smooth_r anchor"
s = s.replace(old, """				# 必须用 _lift_lux 包一层：可视网格 conform 的目标就是
				# terrain_height()，两边不一致玩家就会陷进地里 / 浮在空中。
				var smooth_r: float = _lift_lux(_sample_lux_map(_lux_height_map, dir))""")

# ══════════════ ④-3 平地基准 site_raw 也要加强 ══════════════
old = """	var site_raw: float = _sample_lux_map(map, site_direction.normalized())"""
assert s.count(old) == 1, "site_raw anchor"
s = s.replace(old, """	# 平地基准也要走 _lift_lux：terrain_height() 在站点附近会把高度混合成
	# site_height（= 本值），少了这一步整个基地会比周围地形低一截或高一块。
	var site_raw: float = _lift_lux(_sample_lux_map(map, site_direction.normalized()))""")

# ══════════════ ③-1 星球 → 道具组合表 ══════════════
old = "const PROP_MODELS := {"
assert s.count(old) == 1, "PROP_MODELS anchor"
s = s.replace(old, """## 每颗星球的 AI 道具组合：kind → [prop_id, 数量, 尺寸下限, 尺寸上限, 是否靠基地, 悬浮?]
##
## ⚠ 2026-11-11 目标 ③「按星球类型与 prop_scale 布置更多物体、环境与特殊地标」。
##   组合依据是每颗星球的设定文字（见 main.gd 的 description）：
##     青岚=雾松林+石砌村舍+旧观测塔 → 树密、遗迹拱门、方尖碑、穹顶
##     赭崖=盐碱裂谷+间歇喷泉+断裂观测环 → 喷口、尖峰、中继塔
##     悬晶=环站残骸+磁性矿石+低空碎片 → 晶簇、悬浮石、中继塔
##     缄默=黑曜石暗面+静默门阵 → 方尖碑阵、黑曜石尖峰
##     瑶光=耀眼晶脊+朝下的镜面 → 晶簇极密、尖峰、悬浮石
##   尺寸单位是「设计米数」，运行时会再乘 prop_scale。
const PLANET_PROPS := {
	"qinglan": [["ruin-arch", 3, 34, 52, true], ["obelisk", 4, 40, 70, false],
		["dome-habitat", 2, 34, 50, true], ["rock-cluster", 6, 20, 40, false]],
	"zheya": [["vent", 8, 24, 44, false], ["rock-spire", 10, 30, 70, false],
		["signal-tower", 3, 46, 80, true], ["ruin-arch", 2, 30, 46, false]],
	"cangbo": [["crystal-cluster", 10, 20, 44, false], ["dome-habitat", 3, 30, 46, true],
		["floating-rock", 5, 26, 50, false]],
	"xuanjing": [["crystal-cluster", 12, 22, 50, false], ["floating-rock", 8, 26, 54, false],
		["signal-tower", 3, 44, 76, true]],
	"xuanyuan": [["obelisk", 8, 46, 90, true], ["ruin-arch", 3, 36, 58, false],
		["rock-spire", 6, 34, 76, false]],
	"baiyao": [["rock-spire", 12, 32, 78, false], ["crystal-cluster", 8, 22, 46, false],
		["dome-habitat", 2, 30, 44, true]],
	"pansha": [["rock-spire", 14, 34, 86, false], ["ruin-arch", 3, 32, 52, false],
		["rock-cluster", 10, 22, 46, false]],
	"taiyuan": [["ruin-arch", 4, 32, 54, false], ["rock-cluster", 10, 20, 42, false],
		["dome-habitat", 2, 30, 44, true]],
	"liuwu": [["vent", 10, 26, 48, false], ["dome-habitat", 3, 32, 48, true],
		["signal-tower", 2, 44, 72, false], ["rock-cluster", 6, 20, 38, false]],
	"jianmo": [["obelisk", 12, 44, 92, false], ["rock-spire", 10, 32, 74, false],
		["floating-rock", 5, 24, 48, false]],
	"jiangxiao": [["rock-spire", 10, 30, 68, false], ["vent", 5, 22, 42, false],
		["ruin-arch", 2, 30, 48, false]],
	"cangwu": [["ruin-arch", 3, 32, 52, true], ["rock-cluster", 8, 20, 40, false],
		["obelisk", 3, 40, 66, false]],
	"jinwu": [["rock-cluster", 12, 22, 46, false], ["obelisk", 5, 42, 74, false],
		["vent", 4, 22, 40, false]],
	"yuheng": [["crystal-cluster", 10, 22, 46, false], ["obelisk", 4, 38, 64, false],
		["rock-cluster", 8, 20, 38, false]],
	"sue": [["obelisk", 10, 40, 76, false], ["rock-cluster", 10, 20, 40, false],
		["floating-rock", 4, 24, 46, false]],
	"danxia": [["rock-cluster", 12, 22, 48, false], ["rock-spire", 8, 30, 66, false],
		["ruin-arch", 2, 30, 48, false]],
	"biluo": [["crystal-cluster", 8, 20, 40, false], ["floating-rock", 6, 24, 46, false],
		["dome-habitat", 3, 30, 44, true]],
	"youdu": [["crystal-cluster", 12, 22, 48, false], ["rock-spire", 8, 30, 68, false],
		["alien-tree", 4, 16, 30, false]],
	"yaoguang": [["crystal-cluster", 14, 24, 54, false], ["rock-spire", 8, 30, 70, false],
		["floating-rock", 6, 24, 48, false]],
	"xuanpu": [["alien-tree", 8, 16, 32, false], ["crystal-cluster", 8, 20, 42, false],
		["rock-cluster", 8, 20, 38, false]],
}

## 会「悬浮」的道具：放置时抬高，做成浮空岛/浮石。
const PROP_FLOATING := ["floating-rock"]

const PROP_MODELS := {""")

# ══════════════ ③-2 布置函数 ══════════════
old = "## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，"
assert s.count(old) == 1, "tint anchor"
s = s.replace(old, """## 在星球上挑一个放道具的方向。
## near_site = true 时贴着基地外围（玩家一眼能看到），否则全球散布，
## 两种情况都避开基地平地本身和洞口。
func _pick_prop_direction(near_site: bool) -> Vector3:
	var site: Vector3 = site_direction.normalized()
	var pad_angle: float = site_pad_radius / radius
	for _attempt in range(28):
		var dir: Vector3
		if near_site:
			var perp: Vector3 = site.cross(Vector3.FORWARD)
			if perp.length_squared() < 0.01:
				perp = site.cross(Vector3.RIGHT)
			perp = perp.normalized()
			var axis: Vector3 = perp.rotated(site, rng.randf() * TAU)
			var ang: float = pad_angle * rng.randf_range(1.2, 3.2)
			dir = site.rotated(axis, ang).normalized()
		else:
			dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1),
				rng.randf_range(-1, 1))
			if dir.length_squared() < 0.001:
				continue
			dir = dir.normalized()
		var arc: float = acos(clampf(dir.dot(site), -1.0, 1.0))
		if arc < pad_angle * 0.95:
			continue                      # 别压在基地平地上
		if _near_cave(dir, 0.06):
			continue                      # 别堵洞口
		return dir
	return Vector3.ZERO


## 按 kind 布置这一颗星球的 AI 地标（目标 ③）。
##
## 与铺量的树/岩石分开：这里是「少而大、能认出来」的地标，
## 每颗星球的组合不同，所以 20 颗星球各有各的地貌性格。
func _build_landmark_props() -> void:
	var table: Array = PLANET_PROPS.get(kind, [])
	if table.is_empty():
		return
	for entry in table:
		var prop_id: String = entry[0]
		if _prop_mesh(prop_id) == null:
			continue
		var count: int = int(entry[1])
		var size_min: float = float(entry[2]) * prop_scale
		var size_max: float = float(entry[3]) * prop_scale
		var near: bool = bool(entry[4])
		var floating: bool = PROP_FLOATING.has(prop_id)
		for _i in range(count):
			var dir := _pick_prop_direction(near)
			if dir == Vector3.ZERO:
				continue
			var size := rng.randf_range(size_min, size_max)
			# 悬浮的抬高到半空；其余底部微沉入地表，避免悬空缝。
			var altitude: float = size * 0.35 if floating else -size * 0.04
			_add_prop(prop_id, dir, size, altitude, _prop_tint(), false)


## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，""")

# ══════════════ ③-3 _add_prop 增加 respect_cap 参数 ══════════════
old = """func _add_prop(prop_id: String, direction: Vector3, size: float,
		altitude := 0.0, tint := Color.WHITE) -> void:"""
assert s.count(old) == 1, "add_prop sig"
s = s.replace(old, """func _add_prop(prop_id: String, direction: Vector3, size: float,
		altitude := 0.0, tint := Color.WHITE, respect_cap := true) -> void:""")

old = """	var cap: int = int(PROP_INSTANCE_CAP.get(prop_id, 20))
	if (prop_queue[prop_id] as Array).size() >= cap:
		return"""
assert s.count(old) == 1, "cap body"
s = s.replace(old, """	# 地标（respect_cap=false）由 PLANET_PROPS 精确控制数量，不受铺量限额约束。
	if respect_cap:
		var cap: int = int(PROP_INSTANCE_CAP.get(prop_id, 20))
		if (prop_queue[prop_id] as Array).size() >= cap:
			return""")

# ══════════════ ③-4 _ready 里调用 ══════════════
old = """	_build_ground_scatter()"""
assert s.count(old) == 1, "scatter call"
s = s.replace(old, """	_build_ground_scatter()
	# 目标 ③：按星球类型布置 AI 地标（少而大，和铺量的树/岩石分工不同）
	_build_landmark_props()""")

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("planet.gd props+lift: %d -> %d chars" % (len(o), len(s)))
