# -*- coding: utf-8 -*-
"""列出 20 颗星球的 id / 名字 / 描述，用来按星球类型配道具。"""
import io
import re

s = io.open(r"scripts\main.gd", encoding="utf-8").read()
pat = re.compile(r'"id":\s*"([a-z]+)",\s*"name":\s*"([^"]+)"')
desc = re.compile(r'"description":\s*"([^"]+)"')
rows = []
for m in pat.finditer(s):
    pid, name = m.group(1), m.group(2)
    tail = s[m.end(): m.end() + 1200]
    d = desc.search(tail)
    rows.append((pid, name, d.group(1) if d else "-"))
for pid, name, d in rows:
    print("%-10s %-6s %s" % (pid, name, d))
print("\n合计 %d 条" % len(rows))
