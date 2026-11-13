# -*- coding: utf-8 -*-
"""修 toggle_third_person 里硬编码的 orbit_distance = 13.0。

飞船放到 70 m 后，13 m 的跟随距离会落进机身内部，
导致「第三人称相机看向飞船」这条断言失败（DOT 0.85 < 0.9）。
改成按机长推导：0.83 x 机长（14 m 时约 11.6 m，70 m 时约 58 m），
这样以后改机长不用再动这里。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "scripts/ship.gd"
s = io.open(P, encoding="utf-8").read()

OLD = """		orbit_yaw = PI
		orbit_pitch = 0.28
		orbit_distance = 13.0
		orbit_distance_target = 13.0"""
NEW = """		orbit_yaw = PI
		orbit_pitch = 0.28
		# \u26a0 2026-11-13：这里原来硬编码 13.0。飞船放大到 70 m 后，
		#   13 m 的距离会让相机落进机身内部。改为按机长推导：
		#   14 m 机长时约 11.6 m（与旧值接近），70 m 时约 58 m。
		var start_dist: float = ship_model_length * 0.83 if ship_model_length > 0.01 else 11.6
		orbit_distance = start_dist
		orbit_distance_target = start_dist"""

n = s.count(OLD)
if n != 1:
    print("锚点出现 %d 次，未修改" % n)
    raise SystemExit(1)
s = s.replace(OLD, NEW)
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("toggle_third_person 的 13.0 改为 ship_model_length * 0.83")
