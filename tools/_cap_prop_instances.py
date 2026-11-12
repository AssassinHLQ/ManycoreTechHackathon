# -*- coding: utf-8 -*-
"""修正 AI 道具的实例数量，避免面数爆炸。

实测（青岚星）：350 棵高模树 × 34468 面 = 1206 万面，加上岩石共 1403 万面，
一帧都渲染不动。原因：`_add_tree` / `_add_rock` 的调用次数是「铺量」级
（每球 120~350 次），而 Lux3D 的模型是 2~3 万面的高模。

策略：
  · 有低模变体（*-lo，1 万面）→ 用它铺量，但**限额**（每类 ≤ 90 个）
  · 只有高模 → 当成**地标**，每类 ≤ 18 个
  · 超额的调用直接丢弃（不排进队列），这样既不会爆炸也不会写一堆 if
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ── 每类道具的实例上限 ──
old = """const PROP_MODELS := {"""
new = """## 每类 AI 道具的实例上限（防止面数爆炸）。
##
## ⚠ 2026-11-11 实测：青岚星 350 棵高模树 × 34468 面 = 1206 万面，
##   单星球合计 1403 万面 —— 完全渲染不动。
##   Lux3D 的模型是 2~3 万面的「高模」，只能当地标；
##   低模变体（*-lo，1 万面）才能拿来铺量，且每类仍要限额。
const PROP_INSTANCE_CAP := {
	"alien-tree": 18,
	"alien-tree-lo": 90,
	"rock-cluster": 18,
	"rock-cluster-lo": 90,
	"rock-spire": 18,
	"rock-spire-lo": 90,
	"ruin-arch": 6,
	"obelisk": 8,
	"dome-habitat": 4,
	"signal-tower": 4,
	"crystal-cluster": 10,
	"vent": 8,
	"floating-rock": 8,
}

const PROP_MODELS := {"""
assert s.count(old) == 1
s = s.replace(old, new)

# ── _add_prop 里做限额 ──
old2 = """	if _prop_mesh(prop_id) == null:
		return
	if not prop_queue.has(prop_id):
		prop_queue[prop_id] = []
	prop_queue[prop_id].append({"""
new2 = """	if _prop_mesh(prop_id) == null:
		return
	if not prop_queue.has(prop_id):
		prop_queue[prop_id] = []
	# 限额：超过上限的调用直接丢弃，避免面数爆炸（见 PROP_INSTANCE_CAP 的说明）。
	var cap: int = int(PROP_INSTANCE_CAP.get(prop_id, 20))
	if (prop_queue[prop_id] as Array).size() >= cap:
		return
	prop_queue[prop_id].append({"""
assert s.count(old2) == 1
s = s.replace(old2, new2)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("instance caps added:", o != s)
