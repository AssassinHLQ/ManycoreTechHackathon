"""给「星球放大」算一组安全的 (半径倍数, 轨道倍数)。

约束：
  · 目标：星球明显变大（用户要求「全部加大」）
  · 相邻轨道差 > 两颗半径和 + 安全余量
  · 最外层轨道 × 相机 far（40 万米）之内，且自动驾驶能在合理时间内到达
"""
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

MAIN = Path(__file__).resolve().parent.parent / "scripts" / "main.gd"
PAT = re.compile(
    r'"id": "(\w+)", "name": "([^"]+)",\s*\n\s*'
    r'"radius": ([\d.]+) \* PLANET_RADIUS_SCALE, "orbit": ([\d.]+) \* ORBIT_SCALE'
)


def main() -> None:
    text = MAIN.read_text(encoding="utf-8", errors="replace")
    planets = [(m.group(1), m.group(2), float(m.group(3)), float(m.group(4)))
               for m in PAT.finditer(text)]
    if not planets:
        raise SystemExit("没解析到行星定义")

    print("候选组合（安全余量 ≥ 2000 米）：")
    print("  半径×  轨道×   最紧余量     最远轨道      百公里用时@4000m/s")
    for rs in (4, 5, 6, 7):
        for os_ in (10, 12, 14, 16, 18, 20):
            srt = sorted(planets, key=lambda x: x[3])
            worst = None
            for a, b in zip(srt, srt[1:]):
                gap = (b[3] - a[3]) * os_
                rsum = (b[2] + a[2]) * rs
                margin = gap - rsum
                if worst is None or margin < worst[0]:
                    worst = (margin, a[1], b[1])
            outermost = max(p[3] for p in planets) * os_
            if worst[0] < 2000:
                continue
            print("  ×%-3d  ×%-3d  %+9.0f  %11.0f   %6.1f 秒" % (
                rs, os_, worst[0], outermost, outermost / 4000.0))
    print()
    print("参考：现在 ×3 / ×10 的最紧余量是负的（已互相重叠，靠轨道高度错开）")
    print("最远轨道要小于相机 far 400000，且自动驾驶 4000 m/s 下不宜超过 60 秒")


if __name__ == "__main__":
    main()
