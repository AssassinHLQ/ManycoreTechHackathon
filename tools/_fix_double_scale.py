import io

# ══════════ 1. planet.gd：去掉 cave_mouth_radius 的重复缩放 ══════════
p = r"scripts\planet.gd"
s = io.open(p, encoding="utf-8").read()
o = s

old = """	distance *= prop_scale
	cave_mouth_radius *= prop_scale
	cave_direction = (site_direction + tangent * (distance / radius)).normalized()
	cave_hole_angle = cave_mouth_radius / radius"""
new = """	# ⚠ cave_mouth_radius **不要**在这里乘 prop_scale。
	#   它是 underground.gd 的**局部单位**（shaft_radius = 本值 + 0.6），
	#   而 underground 整棵子树已经由 _prop_parent 乘了一次 prop_scale。
	#   这里再乘一次 = 缩放两次 → 世界竖井半径 253 米，而洞口只有 57 米，
	#   会变成「小洞口下面一个巨大洞厅」的穿帮。
	#   世界尺度的洞口角只在这里算一次：
	#     洞口世界半径 = cave_mouth_radius * prop_scale（+ 下面 _build_lux3d_surface 的余量）
	distance *= prop_scale
	cave_direction = (site_direction + tangent * (distance / radius)).normalized()
	cave_hole_angle = (cave_mouth_radius * prop_scale) / radius"""
assert s.count(old) == 1, "setup_cave anchor"
s = s.replace(old, new)

# 洞口余量那块也要用世界尺度
old2 = """	if cave_enabled:
		var rim_extra: float = 1.5 * prop_scale
		cave_hole_angle = (cave_mouth_radius + rim_extra) / radius"""
new2 = """	if cave_enabled:
		# 世界尺度算：洞体世界半径 = cave_mouth_radius * prop_scale
		# （underground 的竖井 + 0.6 局部 ≈ +3 世界米，这里一并算进余量）
		var rim_extra: float = 1.5 * prop_scale
		cave_hole_angle = ((cave_mouth_radius + 0.6) * prop_scale + rim_extra) / radius"""
assert s.count(old2) == 1, "rim anchor"
s = s.replace(old2, new2)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("planet.gd double-scale fixed:", o != s)


# ══════════ 2. smoke_test.gd：坡道半径用局部值，不要再乘缩放 ══════════
p2 = r"tests\smoke_test.gd"
t = io.open(p2, encoding="utf-8").read()
to = t
old3 = """	var ramp_radius: float = cave.global_transform.basis.get_scale().x * (game.home.cave_mouth_radius - 1.6)"""
new3 = """	# 注意：下面的 Ve"ctor3(...) 是 **cave 局部坐标**，cave.global_transform
	# 已经带上了 ×prop_scale 的缩放，所以这里**不能**再乘一次。
	# cave_mouth_radius 本身就是局部单位（underground.gd 里 shaft_radius = 本值 + 0.6，
	# ramp_radius = shaft_radius - 2.2 = 本值 - 1.6）。
	var ramp_radius: float = game.home.cave_mouth_radius - 1.6"""
new3 = new3.replace("Ve\"ctor3", "Vector3")
assert t.count(old3) == 1, "smoke ramp_radius anchor"
t = t.replace(old3, new3)
io.open(p2, "w", encoding="utf-8", newline="\n").write(t)
print("smoke_test ramp_radius fixed:", to != t)
