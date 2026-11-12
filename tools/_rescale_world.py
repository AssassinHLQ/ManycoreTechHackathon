"""「星球全部加大」：半径 ×3 → ×5，同时把轨道拉开、黑洞外移。

为什么必须一起改轨道：
  实测现有 20 颗星球在 ×3 时，最紧的一对（瑶光→硫坞）轨道只差 1000 米，
  而半径和 1620 米 —— 本来就重叠了，只是靠轨道高度差和相位错开没撞上。
  半径再放大到 ×5、×6 只会更糟，所以轨道必须重新铺开。

新轨道：从 2640 均匀铺到 16000（设计值，实际 ×10 = 26400 ~ 160000）
  · 相邻轨道差 700 设计值 = 7000 米
  · 最大半径和 = (430 + 340) × 5 = 3850 米 → 安全余量 3150 米
  · 最外层 160000 米 < 相机 far 400000 ✓
  · 自动驾驶 4000 m/s 到最外层约 40 秒 ✓
黑洞位置同步 ×10 → ×20，留在星系外围。
"""
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

MAIN = Path(__file__).resolve().parent.parent / "scripts" / "main.gd"

# id -> 新设计轨道
NEW_ORBIT = {
    "qinglan": 2640.0,
    "jinwu": 3400.0,
    "baiyao": 4100.0,
    "jiangxiao": 4800.0,
    "youdu": 5500.0,
    "xuanjing": 6200.0,
    "zheya": 6900.0,
    "sue": 7600.0,
    "pansha": 8300.0,
    "cangwu": 9000.0,
    "taiyuan": 9700.0,
    "cangbo": 10400.0,
    "danxia": 11100.0,
    "yaoguang": 11800.0,
    "liuwu": 12500.0,
    "yuheng": 13200.0,
    "xuanyuan": 13900.0,
    "biluo": 14600.0,
    "jianmo": 15300.0,
    "xuanpu": 16000.0,
}


def main() -> None:
    text = MAIN.read_text(encoding="utf-8", errors="replace")
    original = text

    # 1) 半径倍数 3.0 -> 5.0
    text = text.replace(
        "const PLANET_RADIUS_SCALE := 3.0",
        "const PLANET_RADIUS_SCALE := 5.0",
    )

    # 2) 黑洞位置外移 10 -> 20
    text = text.replace(
        "const BH_POSITION_SCALE := 10.0",
        "const BH_POSITION_SCALE := 20.0",
    )

    # 3) 逐颗换轨道：在同一段定义里把 "orbit": <旧> 换成新值
    for pid, new_orbit in NEW_ORBIT.items():
        pat = re.compile(
            r'("id": "%s", "name": "[^"]+",\s*\n\s*'
            r'"radius": [\d.]+ \* PLANET_RADIUS_SCALE, "orbit": )([\d.]+)' % re.escape(pid)
        )
        m = pat.search(text)
        if not m:
            print("没匹配到", pid)
            continue
        old = m.group(2)
        text = text[:m.start(2)] + ("%.1f" % new_orbit) + text[m.end(2):]
        print("  %-10s 轨道 %.0f -> %.0f" % (pid, float(old), new_orbit))

    MAIN.write_text(text, encoding="utf-8", newline="")
    print("\n写入完成，改动:%s" % ("是" if text != original else "否"))


if __name__ == "__main__":
    main()
