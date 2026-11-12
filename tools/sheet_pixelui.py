# -*- coding: utf-8 -*-
"""拼 Pixel UI Sci-Fi Free 的总览图。

这包是**像素画风**，每张图都很小（几十像素），必须按整数倍放大看，
否则缩在格子里什么都看不见。所以这里按 nearest 放大 3~6 倍再贴。
"""
import io
import json
import os
import sys
from PIL import Image, ImageDraw

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

BASE = os.path.join("_uipkgs", "pixelui", "godot-pixel-ui-scifi-free-main", "addons", "pixel_ui_scifi")
OUT = os.path.join("_uipkgs", "pixelui_sheet.png")

BG = (4, 16, 26)
GRID = (26, 74, 82)
LABEL = (150, 205, 205)
HEAD = (240, 214, 160)

CELL_W, CELL_H = 200, 110
PAD = 12
COLS = 7


def collect(sub, exts=(".png",)):
    d = os.path.join(BASE, sub)
    if not os.path.isdir(d):
        return []
    return [os.path.join(d, n) for n in sorted(os.listdir(d)) if n.lower().endswith(exts)]


def section(title, files, img, y0):
    draw_target = ImageDraw.Draw(img)
    rows = max(1, (len(files) + COLS - 1) // COLS)
    draw_target.text((PAD, y0 + 6), "%s  (%d)" % (title, len(files)), fill=HEAD + (255,))
    for idx, p in enumerate(files):
        im = Image.open(p).convert("RGBA")
        cx = PAD + (idx % COLS) * (CELL_W + PAD)
        cy = y0 + 30 + (idx // COLS) * (CELL_H + PAD)
        # 像素图：整数倍放大，nearest 保持锐利
        mx = (CELL_W - 10) / max(1, im.width)
        my = (CELL_H - 10) / max(1, im.height)
        k = max(1, min(int(mx), int(my), 8))
        if k > 1:
            im = im.resize((im.width * k, im.height * k), Image.NEAREST)
        ox = cx + (CELL_W - im.width) // 2
        oy = cy + (CELL_H - im.height) // 2
        img.alpha_composite(im, (ox, oy))
        draw_target.rectangle([cx, cy, cx + CELL_W - 1, cy + CELL_H - 1],
                              outline=GRID + (255,), width=1)
        nm = os.path.basename(p).replace(".png", "")
        draw_target.text((cx + 3, cy + CELL_H - 12), "%s  %dx%d" % (nm, Image.open(p).width, Image.open(p).height),
                         fill=LABEL + (255,))
    return 30 + rows * (CELL_H + PAD)


def main():
    groups = [
        ("themes/cyan · 主题控件", collect(os.path.join("themes", "cyan"))),
        ("icons · 图标", collect("icons")),
        ("bars · 血条填充", collect("bars")),
        ("hud + cursor", collect("hud") + collect(".")),
    ]
    # 只统计总高度
    total_h = PAD
    for _, files in groups:
        rows = max(1, (len(files) + COLS - 1) // COLS)
        total_h += 30 + rows * (CELL_H + PAD)

    W = COLS * (CELL_W + PAD) + PAD
    sheet = Image.new("RGBA", (W, total_h + PAD), BG + (255,))
    d = ImageDraw.Draw(sheet)

    y = PAD
    for title, files in groups:
        if not files:
            continue
        used = section(title, files, sheet, y)
        y += used

    sheet.save(OUT)
    print("写出 %s  (%d x %d)" % (OUT, sheet.width, sheet.height))
    for title, files in groups:
        print("  %-24s %d" % (title, len(files)))


main()
