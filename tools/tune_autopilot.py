# -*- coding: utf-8 -*-
"""调自动航行参数：安全上限内取最快。

数学约束（见 _autopilot_desired_speed 注释）：
  sqrt 剖面与蠕行剖面的交点处，减速需求 = 2 x 剖面减速度，
  所以 AUTOPILOT_BRAKE_FRACTION 必须 < 0.5，否则剖面不可行 → 撞地。

取值：
  0.90（错误，a0fde88 引入）→ 刹车距离 8547 m，剖面不可行，直接撞死
  0.35（旧保守值）        → 21978 m，很安全但慢
  **0.46（本次）**        → 16667 m，贴住 0.5 上限，最激进但仍可行

同时提高巡航速度，减少长途飞行时间：
  CRUISE 2000 -> 2600 m/s
  刹车距离 = 2600^2 / (2 * 0.46 * 260) = 28261 m（仍远小于行星间距 12万米级）
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "scripts/ship.gd"
s = io.open(P, encoding="utf-8").read()

CHANGES = [
    ("const AUTOPILOT_BRAKE_FRACTION := 0.35", "const AUTOPILOT_BRAKE_FRACTION := 0.46"),
    ("const AUTOPILOT_CRUISE := 2000.0", "const AUTOPILOT_CRUISE := 2600.0"),
]
for old, new in CHANGES:
    n = s.count(old)
    if n != 1:
        print("警告：%s 出现 %d 次，跳过" % (old[:44], n))
        continue
    s = s.replace(old, new)
    print("  %s -> %s" % (old.strip(), new.strip()))

io.open(P, "w", encoding="utf-8", newline="").write(s)

# 打印新的刹车距离
brk = 260.0
for frac, cruise in [(0.46, 2600.0)]:
    d = cruise * cruise / (2 * frac * brk)
    print("\n新参数：刹车距离 %.0f m（约 %.1f km）" % (d, d / 1000.0))
