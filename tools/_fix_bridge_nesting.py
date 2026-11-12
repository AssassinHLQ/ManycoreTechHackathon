# -*- coding: utf-8 -*-
"""修正上一步把 stone-bridge 插错层级的问题。

错误结果：["rock-cluster", 1, 80, 120, false, ["stone-bridge", ...]]
正确结果：[..., ["rock-cluster", 1, 80, 120, false], ["stone-bridge", ...]]
"""
import io
import re

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# 把 `false, ["stone-bridge", 1, 90, 150, false]]` 修成
#     `false], ["stone-bridge", 1, 90, 150, false]]`
bad = 'false, ["stone-bridge", 1, 90, 150, false]]'
good = 'false], ["stone-bridge", 1, 90, 150, false]]'
n = s.count(bad)
assert n == 5, "expected 5 broken bridge entries, found %d" % n
s = s.replace(bad, good)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("bridge nesting fixed (%d entries)" % n)
