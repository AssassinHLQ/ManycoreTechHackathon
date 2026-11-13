# -*- coding: utf-8 -*-
"""压缩 assets 下的贴图，**保持原扩展名不变**。

⚠ 为什么必须保持扩展名（2026-11-13 踩到的严重 bug）：
   上一版脚本把 png 转成 jpg 并改名，但 GLB 里的 image.uri 写死是
   "textures/base_color.png"。改名之后 GLB 找不到贴图，
   飞船/归航站/青岚星地面全部变成褐色裸模。
   所以这版**只降分辨率 + 优化，不改名**。

策略：
  · 最长边 > 1024 的降到 1024
  · PNG 仍存为 PNG（optimize=True），JPG 仍存为 JPG（quality=88）
  · 小于 0.9 MB 的跳过
  · 不动 .import（Godot 会因文件 md5 变化自动重导）
"""
import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from PIL import Image

ROOT = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets"
MIN_BYTES = 900 * 1024
TARGET_MAX = 1024
DRY = "--dry" in sys.argv


def process(path):
    before = os.path.getsize(path)
    if before < MIN_BYTES:
        return None
    ext = os.path.splitext(path)[1].lower()
    try:
        im = Image.open(path)
    except Exception as exc:
        return ("skip", path, before, before, str(exc)[:40])
    w, h = im.size
    longest = max(w, h)
    if longest <= TARGET_MAX:
        return None
    k = TARGET_MAX / float(longest)
    nw, nh = max(1, int(w * k)), max(1, int(h * k))
    try:
        im2 = im.resize((nw, nh), Image.LANCZOS)
        out = io.BytesIO()
        if ext in (".jpg", ".jpeg"):
            if im2.mode not in ("RGB", "L"):
                im2 = im2.convert("RGB")
            im2.save(out, format="JPEG", quality=88, optimize=True)
        else:
            # PNG：保留 alpha，保持 PNG 格式（**不改名**）
            if im2.mode not in ("RGB", "RGBA", "L", "LA", "P"):
                im2 = im2.convert("RGBA")
            im2.save(out, format="PNG", optimize=True)
    except Exception as exc:
        return ("skip", path, before, before, str(exc)[:40])

    data = out.getvalue()
    if len(data) >= before:
        return None
    if not DRY:
        with open(path, "wb") as f:
            f.write(data)
    return ("ok", path, before, len(data), "%dx%d -> %dx%d" % (w, h, nw, nh))


def main():
    files = []
    for dirpath, _d, filenames in os.walk(ROOT):
        for fn in filenames:
            if fn.lower().endswith((".png", ".jpg", ".jpeg")):
                files.append(os.path.join(dirpath, fn))
    files.sort()
    tb = ta = 0
    ok = 0
    for p in files:
        r = process(p)
        if r is None:
            continue
        kind, path, before, after, note = r
        if kind == "skip":
            print("  [skip] %-46s %s" % (os.path.basename(path)[:46], note))
            continue
        ok += 1
        tb += before
        ta += after
        print("  %-50s %6.1f -> %5.1f MB  %s" % (
            path.replace(ROOT + os.sep, "")[:50], before / 1048576,
            after / 1048576, note), flush=True)
    print("\n处理 %d 个，%.0f MB -> %.0f MB（省 %.0f%%）" % (
        ok, tb / 1048576, ta / 1048576,
        (1 - ta / float(max(1, tb))) * 100))


if __name__ == "__main__":
    main()
