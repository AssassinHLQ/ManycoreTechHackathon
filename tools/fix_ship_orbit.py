# -*- coding: utf-8 -*-
"""第三人称跟随距离随飞船尺寸放大。

飞船从 14 m 放到 70 m（对齐星球 ×5 尺度）后，原来的
orbit_distance = 11.5 m 会让相机落在机身内部（船本身就有 70 m 长）。
按同一比例 11.5 x 5 = 57.5 m，滚轮范围 4.5~30 同步放大到 22~150。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "scripts/ship.gd"
s = io.open(P, encoding="utf-8").read()

PAIRS = [
    ("var orbit_distance := 11.5", "var orbit_distance := 58.0"),
    ("var orbit_distance_target := 11.5", "var orbit_distance_target := 58.0"),
    ("clampf(orbit_distance_target * 0.88, 4.5, 30.0)",
     "clampf(orbit_distance_target * 0.88, 22.0, 150.0)"),
    ("clampf(orbit_distance_target * 1.12, 4.5, 30.0)",
     "clampf(orbit_distance_target * 1.12, 22.0, 150.0)"),
]
for old, new in PAIRS:
    n = s.count(old)
    if n != 1:
        print("警告：%s 出现 %d 次" % (old[:46], n))
        continue
    s = s.replace(old, new)
    print("  %s  ==>  %s" % (old.strip(), new.strip()))

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("\n完成：跟随距离 58 m，滚轮 22~150 m")
