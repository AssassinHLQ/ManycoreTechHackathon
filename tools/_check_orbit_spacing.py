"""算一下星球放大到不同倍数时，相邻轨道会不会互相重叠。

判据：两颗行星的轨道半径差 > 两者半径和，就不可能相撞。
（轨道高度和相位能让它们错开，但那样太依赖运气，不适合当基准。）
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
    planets = [(m.group(2), float(m.group(3)), float(m.group(4)))
               for m in PAT.finditer(text)]
    print("行星数 =", len(planets))
    if not planets:
        return
    for scale in (3, 4, 5, 6, 7):
        srt = sorted(planets, key=lambda x: x[2])
        worst = None
        for a, b in zip(srt, srt[1:]):
            orbit_gap = (b[2] - a[2]) * 10.0
            radius_sum = (b[1] + a[1]) * scale
            margin = orbit_gap - radius_sum
            if worst is None or margin < worst[0]:
                worst = (margin, a[0], b[0], orbit_gap, radius_sum)
        flag = "危险" if worst[0] < 0 else ("偏紧" if worst[0] < 1500 else "OK")
        print("  ×%d : 最紧一对 %s→%s  轨道差 %.0f  半径和 %.0f  → 余量 %+.0f  [%s]" % (
            scale, worst[1], worst[2], worst[3], worst[4], worst[0], flag))


if __name__ == "__main__":
    main()
