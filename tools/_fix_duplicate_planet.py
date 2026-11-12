# -*- coding: utf-8 -*-
"""修复「渐进式建场把母星建了两遍」的 bug。

问题：_build_planets(home_only) 的跳过条件写成
    if home_only and definition.id != "qinglan": continue
第一遍 home_only=true 只建 qinglan（1 颗）；
第二遍 home_only=false 时**这个条件对所有星球都为假** → 连 qinglan 再建一遍
→ planets.size() = 21，数组里 qinglan 出现两次（重影、双份建筑/道具），
冒烟测试三项结构性断言翻红：
    twenty explorable bodies created / twenty planetary signals / distinct gravity

修法：记住已经建过哪些 id，第二遍跳过它们。这样无论调用几次都不会重复。
"""
import io

P = r"scripts\main.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ── 1. 新增已建集合 ──
old = "var planets: Array = []"
assert s.count(old) == 1, "planets decl"
s = s.replace(old, """var planets: Array = []
## 已经建过的行星 id。
## ⚠ 2026-11-11 修「母星被建两遍」：_build_planets 分两段调用
## （先 home_only=true 建母星、world_ready 后再建其余），
## 旧版第二段用 `if home_only and id != "qinglan"` 判断，
## home_only=false 时对**所有**星球都成立 → qinglan 被建了第二次，
## planets.size() 变成 21、数组里有两个 qinglan（重影 + 双份建筑/道具）。
## 现在改成按 id 去重，调用几次都不会重复。
var built_planet_ids: Dictionary = {}""")

# ── 2. 跳过条件改成「已建过就跳过」 ──
old2 = """		# 第一段只建母星：其余 19 颗留到 world_ready 之后再补，
		# 否则菜单要等 44 秒才出得来（见本函数头部的说明）。
		if home_only and definition.id != "qinglan":
			continue"""
new2 = """		# 第一段只建母星：其余 19 颗留到 world_ready 之后再补，
		# 否则菜单要等 44 秒才出得来（见本函数头部的说明）。
		if home_only and definition.id != "qinglan":
			continue
		# 已经建过就跳过 —— 第二段（home_only=false）不能把母星再建一遍。
		if built_planet_ids.has(definition.id):
			continue"""
assert s.count(old2) == 1, "skip anchor"
s = s.replace(old2, new2)

# ── 3. 建完记入集合 ──
old3 = """		add_child(planet)
		planets.append(planet)
		if planet.planet_id == "qinglan":
			home = planet"""
new3 = """		add_child(planet)
		planets.append(planet)
		built_planet_ids[planet.planet_id] = true
		if planet.planet_id == "qinglan":
			home = planet"""
assert s.count(old3) == 1, "append anchor"
s = s.replace(old3, new3)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("duplicate planet fixed:", o != s)
