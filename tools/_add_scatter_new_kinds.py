# -*- coding: utf-8 -*-
"""给后 10 颗 Lux3D 星球补上铺量摆件。

实测：jiangxiao~xuanpu 这 10 颗只有地标（16~32 个实例），没有铺量的树/岩石，
因为 _build_landscape 的 match kind 只写了前 10 颗，新 kind 落到无 case 分支
→ `_add_tree`/`_add_rock` 一次都没调用。

按各自设定补上（只用走 AI 资产的 _add_tree / _add_rock；
程序化的 _add_crystal / _add_spout 不再用于铺量 —— 它们已经由 PLANET_PROPS 的
AI 晶簇/喷口地标承担）：
  绛霄 赤铁矿红沙 / 铁锈雾      → 岩石为主
  苍梧 墨绿林海 / 翡翠高地      → 树为主
  金乌 焦金沙海 / 灼白盐盘      → 岩石
  玉衡 玉青平原 / 石英脉        → 岩疏 + 少量树
  素娥 素白月壤 / 静默石桩      → 岩石
  丹霞 丹红条纹岩层 / 彩色阶地  → 岩石
  碧落 碧空浅海 / 环礁          → 岩石稀疏
  幽都 幽蓝玄岩 / 冷光冰川      → 岩石 + 少量树
  瑶光 青白晶原 / 耀眼镜面      → 岩石为主（晶簇在地标层）
  玄圃 暗紫岩台 / 幽绿苔原      → 树 + 岩石
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ── 1. count 表加上新 kind ──
old = """		"liuwu": count = 110
		"jianmo": count = 90"""
new = """		"liuwu": count = 110
		"jianmo": count = 90
		# 后 10 颗 Lux3D 星球：按设定给不同密度
		"cangwu": count = 160
		"xuanpu": count = 150
		"youdu": count = 130
		"jiangxiao": count = 130
		"danxia": count = 140
		"yaoguang": count = 120
		"jinwu": count = 120
		"sue": count = 110
		"yuheng": count = 110
		"biluo": count = 90"""
assert s.count(old) == 1, "count anchor"
s = s.replace(old, new)

# ── 2. 循环里的 match 加新 case ──
old2 = """			"jianmo":
				if i % 3 == 0:
					_add_crystal(direction, Color("9b7fd0"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.2), Color("241f2b"), 0.0)"""
new2 = """			"jianmo":
				if i % 3 == 0:
					_add_crystal(direction, Color("9b7fd0"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.2), Color("241f2b"), 0.0)
			# ── 后 10 颗 Lux3D 星球：只用 AI 资产的树/岩石铺量 ──
			"cangwu":
				if i % 4 != 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.6, 5.0), base_color.lightened(0.12), 0.0)
			"xuanpu":
				if i % 3 != 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.4, 4.6), base_color.lightened(0.10), 0.0)
			"youdu":
				if i % 6 == 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.6, 6.0), Color("2a3550"), 0.0)
			"jiangxiao":
				_add_rock(direction, rng.randf_range(1.8, 6.4), Color("7a3b2a"), 0.0)
			"danxia":
				_add_rock(direction, rng.randf_range(2.0, 7.0), Color("8c4a35"), 0.0)
			"jinwu":
				_add_rock(direction, rng.randf_range(1.8, 6.0), Color("b09050"), 0.0)
			"sue":
				_add_rock(direction, rng.randf_range(1.4, 5.2), Color("cfd4d8"), 0.0)
			"yuheng":
				if i % 7 == 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.4, 5.0), Color("9fb6a8"), 0.0)
			"yaoguang":
				_add_rock(direction, rng.randf_range(1.6, 6.2), Color("c8dcea"), 0.0)
			"biluo":
				_add_rock(direction, rng.randf_range(1.2, 4.0), Color("a8c8d0"), -1.0)"""
assert s.count(old2) == 1, "match anchor"
s = s.replace(old2, new2)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("scatter for new kinds:", o != s)
