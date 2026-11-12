# -*- coding: utf-8 -*-
"""给 gen_props.py 追加 3 个资产：crystal-cluster-lo / vent-lo / stone-bridge。

- crystal-cluster-lo、vent-lo：铺量用低模（1 万面），
  用来把 _add_crystal / _add_spout 这两处**程序化**摆件也换成 AI 资产，
  这样才真正满足用户「不能是程序化的，必须 AI 生成」。
- stone-bridge：目标 ② 里点名的「桥」。

成本：3 × 13 = 39 credits（余额 2689 → 2650，红线 1000 仍有余量）。
"""
import io

p = r"tools\gen_props.py"
s = io.open(p, encoding="utf-8").read()
o = s

# ── PROPS 尾部追加 3 条 ──
anchor = '''    ("rock-spire-lo",  10000,
     "sharp faceted obsidian spire, low detail"),
]'''
if anchor in s and "crystal-cluster-lo" not in s:
    s = s.replace(anchor, '''    ("rock-spire-lo",  10000,
     "sharp faceted obsidian spire, low detail"),
    ("crystal-cluster-lo",  10000,
     "cluster of tall glowing crystal shards growing from stone, low detail "
     "silhouette only"),
    ("vent-lo",  10000,
     "volcanic fumarole vent, cracked crater rim with ash crust, low detail "
     "silhouette only"),
    ("stone-bridge",  26000,
     "ancient stone bridge spanning a chasm, two thick pillars, cracked carved "
     "deck with low side walls, weathered alien ruin"),
]''')
else:
    print("PROPS 追加跳过（已存在或锚点变了）")

# ── DEV_NAMES 追加中文名 ──
anchor2 = '''    "floating-rock": "\u60ac\u6d6e\u788e\u77f3\u5c9b",
}'''
assert s.count(anchor2) == 1, "DEV_NAMES anchor"
s = s.replace(anchor2, '''    "floating-rock": "\u60ac\u6d6e\u788e\u77f3\u5c9b",
    "alien-tree-lo": "\u4f1e\u51a0\u5f02\u661f\u6811\uff08\u4f4e\u6a21\uff09",
    "rock-cluster-lo": "\u5c42\u79ef\u5de8\u5ca9\u7fa4\uff08\u4f4e\u6a21\uff09",
    "rock-spire-lo": "\u9ed1\u66dc\u77f3\u5c16\u5cf0\uff08\u4f4e\u6a21\uff09",
    "crystal-cluster-lo": "\u53d1\u5149\u6676\u7c07\uff08\u4f4e\u6a21\uff09",
    "vent-lo": "\u706b\u5c71\u55b7\u53e3\uff08\u4f4e\u6a21\uff09",
    "stone-bridge": "\u53e4\u77f3\u6865",
}''')

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("gen_props.py updated:", o != s)
