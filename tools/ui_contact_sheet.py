# -*- coding: utf-8 -*-
"""把 Kenney / Wenrexa 两个 UI 包拼成总览图，放在游戏本身的深色底上。

为什么要拼：包里是 33 个独立 PNG，逐个看没法判断整体气质。拼到游戏配色的
底色上（近黑深蓝 #04101A）才看得出「贴到本项目里是什么样子」。
"""
import os
from PIL import Image

SRC = os.path.join("_uipkgs", "wenrexa", "PNG")
OUT = os.path.join("_uipkgs", "wenrexa_contact_sheet.png")

BG = (4, 16, 26)          # 与 HUD 面板 rgba(0.015,0.028,0.047) 同色
GRID = (26, 74, 82)       # 分隔线，接近 HUD 的 border #4c9b9a 但压暗
LABEL = (140, 200, 200)
PAD = 18
CELL_W, CELL_H = 300, 150

files = sorted(f for f in os.listdir(SRC) if f.lower().endswith(".png"))
print("共 %d 个 PNG" % len(files))

# 先量尺寸
info = []
for f in files:
    im = Image.open(os.path.join(SRC, f)).convert("RGBA")
    info.append((f, im))
    print("  %-18s %4d x %-4d" % (f, im.width, im.height))

COLS = 6
ROWS = (len(info) + COLS - 1) // COLS
W = COLS * (CELL_W + PAD) + PAD
H = ROWS * (CELL_H + PAD) + PAD

sheet = Image.new("RGBA", (W, H), BG + (255,))

for idx, (name, im) in enumerate(info):
    cx = PAD + (idx % COLS) * (CELL_W + PAD)
    cy = PAD + (idx // COLS) * (CELL_H + PAD)

    # 等比缩到格子里，留边
    scale = min((CELL_W - 8) / im.width, (CELL_H - 8) / im.height, 1.0)
    if im.width > CELL_W - 8 or im.height > CELL_H - 8:
        im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))),
                       Image.LANCZOS)

    ox = cx + (CELL_W - im.width) // 2
    oy = cy + (CELL_H - im.height) // 2
    sheet.alpha_composite(im, (ox, oy))

    # 格子边框
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    d.rectangle([cx, cy, cx + CELL_W - 1, cy + CELL_H - 1], outline=GRID + (255,), width=1)
    d.text((cx + 5, cy + CELL_H - 14), name.replace(".png", ""), fill=LABEL + (255,))

sheet.save(OUT)
print("\n写出 %s  (%d x %d)" % (OUT, W, H))
