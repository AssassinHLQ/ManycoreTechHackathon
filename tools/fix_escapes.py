# -*- coding: utf-8 -*-
"""清理注释里误留的 \\uXXXX 转义字面量。"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "scripts/planet.gd"
s = io.open(P, encoding="utf-8").read()

before = s
s = s.replace("\\u26a0", "\u26a0")
s = s.replace("\\u00b7", "\u00b7")
s = s.replace("\\u2014", "\u2014")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("变化:", before != s)
print("剩余反斜杠转义:", s.count("\\u26a0") + s.count("\\u00b7"))
