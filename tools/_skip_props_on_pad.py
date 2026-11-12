# -*- coding: utf-8 -*-
"""散布摆件不要长在基地平地上。

实测：沧波星散布了 40 个 AI 晶簇 + 23 个喷口 + 90 个岩石，其中一个正好落在
潮汐站的台阶路径上，把玩家堵住 → walk_test「tide station stairs are climbable」翻红。

`_build_landscape` 的随机方向只避开了洞口，没有避开建筑站点。
而 `terrain_height` 在 pad_angle 内会把地形压平，本来就不该在上面长东西
（平地上冒出树/晶簇也难看）。这里统一跳过基地平地及外扩 10%。
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

old = """		if _near_cave(direction, 0.03):
			continue"""
assert s.count(old) == 1, "cave skip anchor"
s = s.replace(old, """		if _near_cave(direction, 0.03):
			continue
		# 基地平地上不长任何东西：那块地形被压平了，长树/晶簇既难看又会堵路
		# （实测：沧波星一个晶簇落在潮汐站台阶上，玩家走不进去）。
		if acos(clampf(direction.dot(site_direction.normalized()), -1.0, 1.0)) \\
				< (site_pad_radius / maxf(radius, 1.0)) * 1.1:
			continue""")

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("pad skip added:", o != s)
