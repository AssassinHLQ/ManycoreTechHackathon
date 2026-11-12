# -*- coding: utf-8 -*-
"""把道具贴图降到 1024²，压掉显存。

背景：Lux3D 输出的 GLB 带 2048² 贴图，Godot 的 .import 里 compress/mode=0（无损、
非 VRAM 压缩）+ vram_texture=false，于是每张 2048² RGBA8 在显存里约 16 MB。
16 个道具时约 0.5 GB 还能吃；再生成 36 个就变成 52 个道具 × 2 张 ≈ 1.6 GB —— 会爆。

道具在屏幕上最大也就占几十个像素高度（玩家走到跟前时才有细节需求），
1024² 完全够用，显存直接砍到 1/4。

⚠ 只改 assets/models/props 下的贴图，不碰星球/UI —— 那些可能需要无损。
⚠ 不修改源 PNG 之外的东西；改完需要重新 `godot --import`。
"""
import io
import os
import sys

PROPS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     "assets", "models", "props")
LIMIT = 1024


def main():
    try:
        from PIL import Image
    except ImportError:
        print("需要 Pillow：python -m pip install pillow")
        return 1

    changed = 0
    saved_bytes = 0
    for name in sorted(os.listdir(PROPS)):
        d = os.path.join(PROPS, name)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.lower().endswith(".png"):
                continue
            p = os.path.join(d, fn)
            try:
                im = Image.open(p)
            except Exception as e:
                print("跳过 %s/%s：%s" % (name, fn, e))
                continue
            w, h = im.size
            if max(w, h) <= LIMIT:
                continue
            before = os.path.getsize(p)
            im = im.convert("RGB") if im.mode in ("RGBA", "P") and fn.startswith("model_0") else im
            scale = LIMIT / float(max(w, h))
            im = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
            im.save(p, optimize=True)
            after = os.path.getsize(p)
            saved_bytes += max(0, before - after)
            changed += 1
            print("%-22s %-12s %dx%d -> %dx%d  %.1f -> %.1f MB" % (
                name, fn, w, h, im.width, im.height, before / 1048576.0, after / 1048576.0))

    print("\n降采样 %d 张，省下 %.0f MB（尺寸 1/4 → 显存约 1/4）" % (
        changed, saved_bytes / 1048576.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
