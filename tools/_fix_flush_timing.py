# -*- coding: utf-8 -*-
"""修「地标排进队列却没落地」。

时序问题：
  _ready → _build_landscape() → _flush_vegetation() → _flush_props()   ← 这时只排了铺量的树/岩石
        → ... → _build_ground_scatter() → _build_landmark_props()      ← 地标这时才进队列

于是 ruin-arch / obelisk / dome-habitat 全部停在 queue 里没被实例化
（实测：青岚星只落地 2 个 Prop 节点，地标一个都没有）。

修法：
  ① _flush_props 记下已经 flush 过的 prop_id，重复调用时跳过（否则铺量那批会重复实例化）
  ② _build_landmark_props 末尾再调一次 _flush_props
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ① 已 flush 集合
old = "## 待落地的低模散布：同上\nvar scatter_prop_queue: Dictionary = {}"
assert s.count(old) == 1, "queue decl"
s = s.replace(old, """## 待落地的低模散布：同上
var scatter_prop_queue: Dictionary = {}
## 已经 flush 过的 prop_id。_flush_props 可能被调用两次
## （铺量在 _build_landscape 里 flush、地标在 _build_landmark_props 里再 flush），
## 没有这个集合会把铺量那批重复实例化一遍。
var _flushed_prop_ids: Dictionary = {}""")

# ② flush 跳过已处理的
old2 = """	for prop_id in prop_queue.keys():
		var entries: Array = prop_queue[prop_id]
		if entries.is_empty():
			continue"""
assert s.count(old2) == 1, "flush loop"
s = s.replace(old2, """	for prop_id in prop_queue.keys():
		var entries: Array = prop_queue[prop_id]
		if entries.is_empty():
			continue
		if _flushed_prop_ids.has(prop_id):
			continue
		_flushed_prop_ids[prop_id] = true""")

# ③ 地标建完再 flush
old3 = """			var altitude: float = size * 0.35 if floating else -size * 0.04
			_add_prop(prop_id, dir, size, altitude, _prop_tint(), false)"""
assert s.count(old3) == 1, "landmark tail"
s = s.replace(old3, """			var altitude: float = size * 0.35 if floating else -size * 0.04
			_add_prop(prop_id, dir, size, altitude, _prop_tint(), false)
	# 地标是在 _build_landscape 之后才排进队列的，所以必须在这里补一次 flush
	# （_flush_props 内部有 _flushed_prop_ids 去重，铺量那批不会重复实例化）。
	_flush_props()""")

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("flush timing fixed:", o != s)
