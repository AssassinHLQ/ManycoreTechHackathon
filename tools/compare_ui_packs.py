# -*- coding: utf-8 -*-
"""把两个候选 UI 包拼成对比图，放在游戏本身的深色底上。

用法： python compare_ui_packs.py <包A目录> <包A标题> <包B目录> <包B标题> <输出png>
"""
import os
import sys
from PIL import Image, ImageDraw

BG = (4, 16, 26)
GRID = (26, 74, 82)
LABEL = (150, 205, 205)
HEAD = (240, 214, 160)

CELL_W, CELL_H = 240, 130
PAD = 14
COLS = 6


def collect(root, exts=(".png", ".jpg")):
    out = []
    for dirpath, _, names in os.walk(root):
        for n in sorted(names):
            if n.lower().endswith(exts):
                # 跳过预览图/说明图（太大，不是素材）
                if n.lower() in ("preview.png", "sample.png", "elements.png"):
                    continue
                out.append(os.path.join(dirpath, n))
    return out


def panel(title, files, width):
    """返回 (图像, 高度)"""
    rows = (len(files) + COLS - 1) // COLS
    h = 46 + rows * (CELL_H + PAD) + PAD
    img = Image.new("RGBA", (width, h), BG + (255,))
    d = ImageDraw.Draw(img)
    d.text((PAD, 12), "%s  (%d files)" % (title, len(files)), fill=HEAD + (255,))

    for idx, path in enumerate(files):
        im = Image.open(path)
        if im.mode != "RGBA":
            im = im.convert("RGBA")
        cx = PAD + (idx % COLS) * (CELL_W + PAD)
        cy = 46 + (idx // COLS) * (CELL_H + PAD)
        scale = min((CELL_W - 8) / im.width, (CELL_H - 8) / im.height, 1.0)
        if scale < 1.0:
            im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))),
                           Image.LANCZOS)
        ox = cx + (CELL_W - im.width) // 2
        oy = cy + (CELL_H - im.height) // 2
        img.alpha_composite(im, (ox, oy))
        d.rectangle([cx, cy, cx + CELL_W - 1, cy + CELL_H - 1], outline=GRID + (255,), width=1)
        d.text((cx + 4, cy + CELL_H - 13), os.path.basename(path)[:30], fill=LABEL + (255,))
    return img, h


def main():
    a_dir, a_title, b_dir, b_title, out = sys.argv[1:6]
    fa = collect(a_dir)
    fb = collect(b_dir)
    print("A: %s -> %d 个" % (a_title, len(fa)))
    print("B: %s -> %d 个" % (b_title, len(fb)))

    W = COLS * (CELL_W + PAD) + PAD
    pa, ha = panel(a_title, fa, W)
    pb, hb = panel(b_title, fb, W)

    sheet = Image.new("RGBA", (W, ha + hb), BG + (255,))
    sheet.alpha_composite(pa, (0, 0))
    sheet.alpha_composite(pb, (0, ha))
    sheet.save(out)
    print("\n写出 %s (%d x %d)" % (out, sheet.width, sheet.height))

    # 尺寸清单，方便判断能不能九宫格
    print("\n=== 尺寸（宽 x 高）===")
    for label, files in ((a_title, fa), (b_title, fb)):
        print("-- %s" % label)
        for p in files:
            im = Image.open(p)
            print("   %-34s %4d x %-4d" % (os.path.basename(p), im.width, im.height))


main()
