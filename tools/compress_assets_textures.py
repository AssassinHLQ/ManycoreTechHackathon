"""批量压缩 assets 下的贴图（保留法线图为 PNG）。

为什么：Web 导出 index.pck 已到 919 MB，玩家根本下载不动。
实测 assets 下 148 个 >1MB 的 png 合计 610 MB，其中 6 张是 4096²，
最大的 space-station/textures/normal.png 单张 68.8 MB。

策略：
  · 4096 → 2048，2048 → 1024（贴图在游戏里从没占到那么大的屏幕面积）
  · 法线贴图（文件名含 normal/nor）保持 PNG 无损，其余转 JPEG q88
  · 已小于等于目标尺寸且 < 1MB 的跳过

⚠ 这个脚本会**覆盖源文件**。运行前先 git commit，出问题能回滚。
"""
import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from PIL import Image

ROOT = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets"
MIN_BYTES = 900 * 1024        # 小于 0.9 MB 的不动
TARGET_MAX = 1024             # 目标最长边
NORMAL_MAX = 1024             # 法线也用同样分辨率，但保持 PNG


def is_normal(path):
    low = path.lower()
    return ("normal" in low) or ("_nor" in low) or ("nor_" in low) or ("/nor" in low)


def is_albedo_like(path):
    """颜色贴图 → JPEG 有损；其余（ORM/metallic/roughness）也走 JPEG。"""
    return not is_normal(path)


def process(path):
    before = os.path.getsize(path)
    if before < MIN_BYTES:
        return None
    try:
        im = Image.open(path)
    except Exception as exc:
        return ("skip", path, before, before, "open failed: %s" % exc)
    w, h = im.size
    longest = max(w, h)
    if longest <= TARGET_MAX:
        return None
    k = TARGET_MAX / float(longest)
    nw, nh = max(1, int(w * k)), max(1, int(h * k))
    try:
        im2 = im.resize((nw, nh), Image.LANCZOS)
    except Exception as exc:
        return ("skip", path, before, before, "resize failed: %s" % exc)

    out = io.BytesIO()
    normal = is_normal(path)
    try:
        if normal:
            if im2.mode not in ("RGB", "RGBA", "L"):
                im2 = im2.convert("RGB")
            im2.save(out, format="PNG", optimize=True)
            new_ext = ".png"
        else:
            if im2.mode not in ("RGB", "L"):
                im2 = im2.convert("RGB")
            im2.save(out, format="JPEG", quality=88, optimize=True)
            new_ext = ".jpg"
    except Exception as exc:
        return ("skip", path, before, before, "save failed: %s" % exc)

    data = out.getvalue()
    if len(data) >= before:
        return None

    # 扩展名变化时要连 .import 一起清掉，让 Godot 重新导入
    if new_ext != os.path.splitext(path)[1].lower():
        base = os.path.splitext(path)[0]
        new_path = base + new_ext
        os.replace_new = None
        with open(new_path, "wb") as f:
            f.write(data)
        os.remove(path)
        imp = path + ".import"
        if os.path.isfile(imp):
            os.remove(imp)
        return ("jpg", new_path, before, len(data), "%dx%d -> %dx%d" % (w, h, nw, nh))
    else:
        with open(path, "wb") as f:
            f.write(data)
        return ("png", path, before, len(data), "%dx%d -> %dx%d" % (w, h, nw, nh))


def main():
    files = []
    for dirpath, _dirnames, filenames in os.walk(ROOT):
        for fn in filenames:
            if fn.lower().endswith((".png", ".jpg")):
                files.append(os.path.join(dirpath, fn))
    files.sort()
    total_before = 0
    total_after = 0
    changed = 0
    for p in files:
        r = process(p)
        if r is None:
            continue
        kind, path, before, after, note = r
        if kind == "skip":
            print("  [skip] %s  (%s)" % (os.path.basename(path), note))
            continue
        changed += 1
        total_before += before
        total_after += after
        print("  %-42s %6.1f -> %5.1f MB  %s" % (
            path.replace(ROOT + os.sep, "")[:42], before / 1048576,
            after / 1048576, note))
    print("\n处理 %d 个文件，%.0f MB -> %.0f MB（省 %.0f%%）" % (
        changed, total_before / 1048576, total_after / 1048576,
        (1 - total_after / float(max(1, total_before))) * 100))


if __name__ == "__main__":
    main()
