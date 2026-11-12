"""把飞船系统面板加宽，修掉右侧数值被切断的问题。

现象（用户截图）：推进剂数值显示成「1.0T」，右边被面板边缘切掉了。
根因：面板宽度 = offset_right(352) - offset_left(24) = 328 px，
      而右侧数值标签从 x=180 起、宽 150 → 到 330，已经越过面板右边缘 328。
      「1.0T」其实是「1.0T…」被裁掉的残片。

修法：
  · 面板右边界 352 → 404（宽 380 px）
  · 数值标签起点 180 → 196，宽度 150 → 176，右端落在 372 < 380 ✓
  · 进度条宽度 306 → 348，跟着面板一起放宽
  · 子系统状态灯、圆盘、说明文字的相对位置不变（都在左侧）
"""
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HUD = Path(__file__).resolve().parent.parent / "scripts" / "hud.gd"


def main() -> None:
    t = HUD.read_text(encoding="utf-8", errors="replace")
    before = t
    n = 0

    # 1) 面板右边加宽 352 -> 404
    t2 = t.replace("status_panel.offset_right = 352",
                   "status_panel.offset_right = 404", 1)
    if t2 != t:
        t = t2
        n += 1
        print("✓ 面板宽度 328 -> 380")

    # 2) 进度条 306 -> 348（三处：bar_a / bar_b / 其它 306 宽的条）
    t2 = t.replace("Rect2(16, 60, 306, 7)", "Rect2(16, 60, 348, 7)")
    t2 = t2.replace("Rect2(16, 110, 306, 7)", "Rect2(16, 110, 348, 7)")
    if t2 != t:
        t = t2
        n += 1
        print("✓ 进度条 306 -> 348")

    # 3) 右侧数值标签：起点 180 -> 196，宽度 150 -> 176
    t2 = t.replace("Rect2(180, r0_y(), 150, 20)", "Rect2(196, r0_y(), 176, 20)")
    t2 = t2.replace("Rect2(180, r1_y(), 150, 20)", "Rect2(196, r1_y(), 176, 20)")
    if t2 != t:
        t = t2
        n += 1
        print("✓ 数值标签右移并加宽")

    # 4) 数值标签右对齐，避免长短不一时跳动
    if "bar_a_value.horizontal_alignment" not in t:
        anchor = 'status_panel.add_theme_stylebox_override("panel", status_style)'
        add = ('\tbar_a_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT\n'
               '\tbar_b_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT\n')
        # 位置：插在 bar_b_value 定义之后更稳妥，这里放在面板样式设置前
        t = t.replace(anchor, add + anchor, 1)
        n += 1
        print("✓ 数值右对齐")

    HUD.write_text(t, encoding="utf-8", newline="")
    print("共 %d 处改动%s" % (n, "" if t != before else "（无变化）"))


if __name__ == "__main__":
    main()
