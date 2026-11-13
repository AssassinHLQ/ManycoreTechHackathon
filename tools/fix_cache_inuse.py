# -*- coding: utf-8 -*-
"""步骤 C 修正版：淘汰时只卸「没有星球在用」的网格。

第一版把上限设成 48，但 PROP_MODELS 有 **180 种道具**，20 颗星球基本会用到全部。
于是缓存不断把「正在用」的网格淘汰掉，而 MultiMesh 仍持有它 ——
下次请求重新载入一份新的 Mesh，旧的还在，**变成两份，内存不降反升**
（实测 1786 MB -> 2000 MB）。

修正：维护一个「在用」表，淘汰时跳过在用条目。
  · 在用的网格不会被卸载（不会重复载入，不会黑模）
  · 不在用的（只被 _prop_mesh 试探过、没落成 MultiMesh 的）会被清掉
  · 这样上限 48 是安全的：它只约束「闲置条目」，不会造成抖动
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "scripts/planet.gd"
s = io.open(P, encoding="utf-8").read()
orig = s
ok = []


def sub(old, new, label):
    global s
    n = s.count(old)
    if n != 1:
        print("  [跳过] %s：锚点 %d 次" % (label, n))
        return
    s = s.replace(old, new)
    ok.append(label)
    print("  [完成] %s" % label)


# 1) 增加「在用」表
sub(
    "## LRU 顺序：队尾最新。淘汰时从队首摘。\nstatic var _prop_cache_order: Array = []\n",
    "## LRU 顺序：队尾最新。淘汰时从队首摘。\nstatic var _prop_cache_order: Array = []\n"
    "## 「正在使用」的 prop_id -> 引用它的星球数。\n"
    "## 淘汰时必须跳过这些：它们的 Mesh 被 MultiMesh 持有，卸载只会导致\n"
    "## 下次重新载入一份新的，而旧的仍然活着 —— 内存不降反升。\n"
    "static var _prop_in_use := {}\n",
    "增加 _prop_in_use 表",
)

# 2) 重写淘汰函数：跳过在用条目
OLD_TOUCH = """static func _prop_cache_touch(prop_id: String) -> void:
	_prop_cache_order.erase(prop_id)
	_prop_cache_order.append(prop_id)
	while _prop_cache_order.size() > PROP_CACHE_LIMIT:
		var oldest: String = String(_prop_cache_order.pop_front())
		if oldest != prop_id:
			_prop_mesh_cache.erase(oldest)
"""
NEW_TOUCH = """static func _prop_cache_touch(prop_id: String) -> void:
	_prop_cache_order.erase(prop_id)
	_prop_cache_order.append(prop_id)
	if _prop_cache_order.size() <= PROP_CACHE_LIMIT:
		return
	# 只淘汰「没有任何星球在用」的条目。
	# 在用条目若被淘汰，下次请求会重新载入一份新 Mesh，而旧的仍被 MultiMesh
	# 持有 —— 反而变成两份，内存不降反升（实测踩过：1786 MB -> 2000 MB）。
	var excess: int = _prop_cache_order.size() - PROP_CACHE_LIMIT
	var survivors: Array = []
	for key in _prop_cache_order:
		var k: String = String(key)
		if excess > 0 and k != prop_id and not _prop_in_use.has(k):
			_prop_mesh_cache.erase(k)
			excess -= 1
		else:
			survivors.append(k)
	_prop_cache_order = survivors


## 标记某个 prop_id 已经落成 MultiMesh（正被某颗星球使用）。
## 由 _flush_props 在把 mesh 交给 MultiMesh 之后调用。
static func _prop_mark_in_use(prop_id: String) -> void:
	_prop_in_use[prop_id] = int(_prop_in_use.get(prop_id, 0)) + 1
"""
sub(OLD_TOUCH, NEW_TOUCH, "淘汰函数跳过在用条目 + 增加 _prop_mark_in_use")

# 3) 在 MultiMesh 挂上 mesh 后登记在用
sub(
    "\t\tinstance.multimesh = mm\n",
    "\t\tinstance.multimesh = mm\n"
    "\t\t# 这个 mesh 从此被本星球的 MultiMesh 持有，不能再被 LRU 淘汰\n"
    "\t\t_prop_mark_in_use(prop_id)\n",
    "_flush_props 登记在用",
)

if s != orig:
    io.open(P, "w", encoding="utf-8", newline="").write(s)
print("\n完成 %d / 3 项" % len(ok))
