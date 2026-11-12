import io

PP = r"scripts\planet.gd"
AP = r"scripts\architecture.gd"


def load(p):
    with io.open(p, encoding="utf-8") as f:
        return f.read()


def save(p, s):
    with io.open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


# ══════════════════════ planet.gd ══════════════════════
src = load(PP)
orig_len = len(src)

# ── 1. 统一的物件缩放系数 ──
old = """	if radius > 0.0 and terrain_reference_radius > 0.0:
		site_pad_radius *= radius / terrain_reference_radius"""
new = """	if radius > 0.0 and terrain_reference_radius > 0.0:
		prop_scale = radius / terrain_reference_radius
		site_pad_radius *= prop_scale"""
assert src.count(old) == 1, "pad scale anchor"
src = src.replace(old, new)

# 声明 prop_scale
old = "var terrain_reference_radius := 0.0"
new = """var terrain_reference_radius := 0.0
## 地面物件的统一缩放系数 = 实际半径 / 设计半径（现在 = 5）。
##
## ⚠ 2026-11-11 用户：「为什么每个星球就一个星球在，没有东西」。
##   星球半径 ×5 之后，只有 `site_pad_radius` 跟着放大了（46 → 230 米），
##   而建筑、熔岩柱、晶体、树、岩石的尺寸**全是绝对米数**没动：
##     观测塔 13 米高，搁在半径 2000 米的星球上 = 地球上一根 40 米长的针；
##     全星球 170 棵树，平均 15 万平方米一棵。
##   结果从驾驶舱看下去，每颗星球都是一颗光球，上面什么都没有。
##   这里统一乘上 5：建筑变 20~65 米、树变 18~40 米，从空中一眼就能看见。
var prop_scale := 1.0"""
assert src.count(old) == 1, "terrain_reference_radius anchor"
src = src.replace(old, new)

# ── 2. 道具根节点带缩放 ──
old = "func _surface_parent(direction: Vector3, altitude: float) -> Node3D:"
assert src.count(old) == 1
# 在它前面插入 _prop_parent
helper = '''## 和 `_surface_parent` 一样，但把整棵子树按 `prop_scale` 放大。
##
## 只给**户外摆件**用（建筑、熔岩柱、晶体、喷口、遗迹、落点岛）。
## 洞穴内部（underground.gd）故意不用它 —— 那是给人走的手工空间，
## 保持人类尺度才对。
func _prop_parent(direction: Vector3, altitude: float) -> Node3D:
	var root := _surface_parent(direction, altitude)
	if root != null and not is_equal_approx(prop_scale, 1.0):
		root.scale = Vector3.ONE * prop_scale
	return root


'''
src = src.replace(old, helper + old)

# 把摆件构造里的 _surface_parent 调用换成 _prop_parent
for lineno_hint, old_call in [
    ("_add_basalt", "\tvar root := _surface_parent(direction, 0.0)\n\tvar height := rng.randf_range(6.0, 24.0)"),
    ("_add_crystal", "\tvar root := _surface_parent(direction, altitude)\n\tvar height := rng.randf_range(6.0, 18.0)"),
    ("_add_spout", "\tvar root := _surface_parent(direction, -1.0)"),
    ("_add_landing_island", "\tvar root := _surface_parent(Vector3.UP, -2.5)"),
    ("_add_home_ruin", "\tvar root := _surface_parent(direction, 0.0)"),
    ("_add_eye_spires", "\tvar root := _surface_parent(direction, 0.0)"),
]:
    if old_call in src:
        src = src.replace(old_call, old_call.replace("_surface_parent(", "_prop_parent("), 1)
    else:
        print("WARN: 没找到 %s 的 _surface_parent 调用" % lineno_hint)

# ── 3. 树 / 岩石尺寸跟着放大 ──
old = "\tvar size := rng.randf_range(1.0, 2.25)\n\tvar up := direction.normalized()"
assert src.count(old) == 1, "tree size anchor"
src = src.replace(old,
                  "\tvar size := rng.randf_range(1.0, 2.25) * prop_scale\n"
                  "\tvar up := direction.normalized()")

old = """func _add_rock(direction: Vector3, size: float, color: Color, altitude: float) -> void:
	var rotation := Basis.from_euler(Vector3(rng.randf() * PI, rng.randf() * PI, rng.randf() * PI))"""
assert src.count(old) == 1, "rock anchor"
src = src.replace(old,
                  """func _add_rock(direction: Vector3, size: float, color: Color, altitude: float) -> void:
	size *= prop_scale
	var rotation := Basis.from_euler(Vector3(rng.randf() * PI, rng.randf() * PI, rng.randf() * PI))""")

# ── 4. 摆件数量适度增加（尺寸 ×5 已经解决"看得见"，数量 ×2 解决"看着丰富"）──
old = "\tvar count := 170\n\tmatch kind:\n\t\t\"zheya\": count = 140"
assert src.count(old) == 1, "landscape count anchor"
src = src.replace(old,
                  "\tvar count := 170\n"
                  "\t# ⚠ 星球放大 5 倍后表面积 ×25，物件数量也翻倍，否则空旷得像荒星。\n"
                  "\t#   没有再乘 5：每棵树都带一个 StaticBody3D 碰撞体，\n"
                  "\t#   20 颗星球 × 850 个碰撞体太贵，×2 已经足够看出层次。\n"
                  "\tcount *= 2\n"
                  "\tmatch kind:\n\t\t\"zheya\": count = 140")

# ── 5. 可视网格完全贴合高度表（eliminates 视觉/碰撞不一致）──
old = "\tvar conform := 0.95"
assert src.count(old) == 1, "conform anchor"
src = src.replace(old,
                  "\t# ⚠ 2026-11-11 从 0.95 提到 1.0。\n"
                  "\t#   0.95 意味着每个顶点仍保留 5% 的原始 GLB 起伏，\n"
                  "\t#   而碰撞/地形查询只认 `terrain_height` —— 两份表面差几十米，\n"
                  "\t#   玩家就会「看着在地上、实际陷在碰撞面里」，走两步被卡死。\n"
                  "\t#   1.0 = 可视网格完全落在 terrain_height 上，三份数据真正同源。\n"
                  "\tvar conform := 1.0")

# ── 6. Lux3D 碰撞球面分辨率 128×64 → 384×192 ──
old = """	sphere.radial_segments = 256 if cave_enabled else 128
	sphere.rings = 128 if cave_enabled else 64"""
assert src.count(old) == 2, "resolution anchor count = %d" % src.count(old)
src = src.replace(old, """	# ⚠ 2026-11-11 分辨率从 128×64（cave 256×128）提到 384×192。
	#
	#   这是「地形把人物卡死」的根因：Lux3D 的高度表本身是 96×192 格
	#   （半径 2000 米时每格约 65 米），而旧碰撞球面在赤道只有 128 格
	#   = **每格 98 米**，比高度表本身还粗 —— 采样不足导致碰撞面在地下
	#   切出一条条几十米宽的大折面，玩家走在折面棱上就被卡住。
	#   现在的 384×192（每格约 32 米）是高度表的 2 倍过采样，能完整表达它。
	sphere.radial_segments = 384
	sphere.rings = 192""")

save(PP, src)
print("planet.gd: %d -> %d 字符" % (orig_len, len(src)))

# ══════════════════════ architecture.gd ══════════════════════
a = load(AP)
a_orig = len(a)

old = "\tvar root: Node3D = planet._surface_parent(direction, altitude)"
assert a.count(old) == 1, "architecture root anchor"
a = a.replace(old, "\tvar root: Node3D = planet._prop_parent(direction, altitude)")

old = "## 程序化地标建筑。所有尺寸均为米，不随星球半径整体缩放。"
assert a.count(old) == 1
a = a.replace(old, """## 程序化地标建筑。所有尺寸均按「半径 400 米」的设计尺度写成米。
##
## ⚠ 2026-11-11 改：整棵子树现在由 `planet._prop_parent()` 按
##   `radius / 400` 统一放大（现在 ×5），所以这里的数字**不用动** ——
##   写 13 米的观测塔，在半径 2000 米的星球上就是 65 米高。""")

save(AP, a)
print("architecture.gd: %d -> %d 字符" % (a_orig, len(a)))
