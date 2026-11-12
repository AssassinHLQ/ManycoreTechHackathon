# -*- coding: utf-8 -*-
"""把 harvest 里所有包拼成一张大总览，每个包占一块，一眼看全。

像素图按整数倍 nearest 放大；矢量/大图按比例缩小。
每个包只取前 N 张，避免 381 个文件刷爆画面。
"""
import io
import os
import sys
from PIL import Image, ImageDraw

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = os.path.join("_uipkgs", "harvest")
OUT = os.path.join("_uipkgs", "harvest_sheet.png")

BG = (4, 16, 26)
GRID = (26, 74, 82)
LABEL = (150, 205, 205)
HEAD = (240, 214, 160)

CELL_W, CELL_H = 130, 78
PAD = 10
COLS = 10
PER_PACK = 20


def pack_files(d):
    out = []
    for dp, _, fs in os.walk(d):
        for n in sorted(fs):
            if n.lower().endswith((".png", ".jpg", ".jpeg")):
                p = os.path.join(dp, n)
                try:
                    if os.path.getsize(p) > 3 * 1024 * 1024:
                        continue
                except OSError:
                    continue
                out.append(p)
    # 优先挑根目录/靠前的
    out.sort(key=lambda p: (p.count(os.sep), len(p)))
    return out


def main():
    packs = [d for d in sorted(os.listdir(ROOT)) if os.path.isdir(os.path.join(ROOT, d))]
    chosen = []
    for d in packs:
        fs = pack_files(os.path.join(ROOT, d))
        if fs:
            chosen.append((d, fs[:PER_PACK], len(fs)))

    if not chosen:
        print("没有可用包")
        return

    # 版面：每包一行起，按 COLS 排
    blocks = []
    for name, fs, total in chosen:
        rows = max(1, (len(fs) + COLS - 1) // COLS)
        blocks.append((name, fs, total, rows))

    total_h = PAD
    for _, _, _, rows in blocks:
        total_h += 26 + rows * (CELL_H + PAD)

    W = COLS * (CELL_W + PAD) + PAD
    sheet = Image.new("RGBA", (W, total_h + PAD), BG + (255,))
    d = ImageDraw.Draw(sheet)

    y = PAD
    for name, fs, total, rows in blocks:
        d.text((PAD, y + 4), "%s  (%d 张，展示前 %d)" % (name, total, len(fs)),
               fill=HEAD + (255,))
        y += 26
        for idx, p in enumerate(fs):
            try:
                im = Image.open(p).convert("RGBA")
            except Exception:
                continue
            cx = PAD + (idx % COLS) * (CELL_W + PAD)
            cy = y + (idx // COLS) * (CELL_H + PAD)
            mx = (CELL_W - 8) / max(1, im.width)
            my = (CELL_H - 8) / max(1, im.height)
            if mx >= 2 and my >= 2:
                k = max(1, min(int(mx), int(my), 6))
                im = im.resize((im.width * k, im.height * k), Image.NEAREST)
            elif mx < 1 or my < 1:
                s = min(mx, my)
                im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
            ox = cx + (CELL_W - im.width) // 2
            oy = cy + (CELL_H - im.height) // 2
            sheet.alpha_composite(im, (ox, oy))
            d.rectangle([cx, cy, cx + CELL_W - 1, cy + CELL_H - 1], outline=GRID + (255,), width=1)
            d.text((cx + 2, cy + CELL_H - 11), os.path.basename(p)[:20], fill=LABEL + (255,))
        y += rows * (CELL_H + PAD)

    sheet.save(OUT)
    print("写出 %s  (%d x %d)" % (OUT, sheet.width, sheet.height))
    for name, fs, total, _ in blocks:
        print("  %-40s %4d 张" % (name, total))


main()
