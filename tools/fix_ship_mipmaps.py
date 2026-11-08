# 修 3D 贴图的 Godot 导入设置：开 Mipmaps、用 VRAM 压缩、关掉 detect_3d。
# 用法： python tools/fix_ship_mipmaps.py [贴图目录...]
#
# 为什么需要它：
#   Godot 的纹理导入默认 **不开 mipmap**（detect_3d/compress_to=1 的意思是
#   「检测到只在 2D 用就按 2D 处理」）。对 3D 里的贴图来说这是错的：
#   没有 mipmap，远处看过去会**闪烁**（aliasing），而且显存里只有一张全分辨率图。
#   旧版飞船贴图（model_Image_*.jpg）是手动开着 mipmap 导入的，
#   换成外链的新贴图后重新导入就丢了 —— 于是要补上这一刀。
#
#   compress/mode=2（VRAM Compressed）是这里的关键：
#     mode=0（Lossless）会把 4096² 的 PNG **原样**塞进 .ctex，一张就是 11.9 MB；
#     mode=2 走 BC1/BC3 之类，4096² 压到 8 MB（带 mip 链约 10.7 MB）。
#     实测：3 MB 的 WebP 源用 mode=0 导入，出来的 .ctex 仍然是 9.9 MB ——
#     无损容器会把有损压缩的收益**全部吃掉**。所以要省体积必须用 mode=2。
#     网页版的 export preset 本来也是 texture_format/s3tc_bptc=true，
#     用 mode=2 正好对上。
import os
import re
import sys

DEFAULT_DIRS = [
    os.path.join("assets", "models", "ship-fighter", "textures"),
]

# 每张贴图在**导入时**的尺寸上限（0 = 不限）。
# 源 PNG 保持原始分辨率（仓库里留的是可再加工的母版），
# 真正进 pck 的是这个上限 —— 也就是玩家下载的体积。
#
# 为什么 normal / orm 要降一档（实测数据）：
#   4096² 的 normal 在 s3tc 下是 10.67 MB，2048² 只要 2.67 MB，省 8 MB。
#   但法线贴图每像素只存了 xy 两个自由度，z 是重建出来的，
#   而且它画的是**粗糙的蒙皮起伏**，不是精细涂装 ——
#   放到 2048² 后和 4096² 在游戏里的画面**看不出差别**（截图逐帧比过）。
#   base_color 不同：那是涂装、编号 EXO、铆钉、蒙皮划痕，
#   4096² 一眼就能看出比 1024² 清楚得多，所以它保持 4096。
#   orm 是粗糙度/金属度/遮蔽，属低频信息，1024² 足够。
SIZE_LIMITS = {
    "base_color": 0,
    "normal": 2048,
    "orm": 1024,
    "emissive": 0,
}


def fix(path: str) -> bool:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    original = text
    text = re.sub(r"mipmaps/generate=false", "mipmaps/generate=true", text)
    text = re.sub(r"detect_3d/compress_to=1", "detect_3d/compress_to=0", text)
    # compress/mode: 0 = Lossless, 1 = Lossy, 2 = VRAM Compressed, 3 = VRAM Uncompressed
    text = re.sub(r"compress/mode=0", "compress/mode=2", text)
    # 按文件名套用尺寸上限。
    # 注意：文件名是 `base_color.png.import`，去掉后缀 `.import` 后
    # 还要再去掉贴图本身的扩展名，才轮到 `base_color`。
    stem = os.path.basename(path)
    if stem.endswith(".import"):
        stem = stem[: -len(".import")]
    stem = os.path.splitext(stem)[0]
    limit = SIZE_LIMITS.get(stem)
    if limit is not None:
        text = re.sub(r"process/size_limit=\d+", "process/size_limit=%d" % limit, text)
    if text != original:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        return True
    return False


def main():
    dirs = sys.argv[1:] or DEFAULT_DIRS
    changed = 0
    checked = 0
    for d in dirs:
        if not os.path.isdir(d):
            print("跳过（目录不存在）: %s" % d)
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".import"):
                continue
            path = os.path.join(d, name)
            checked += 1
            if fix(path):
                changed += 1
                print("  已修正 %s" % path)
            else:
                print("  已符合   %s" % path)
    print("检查 %d 个导入文件，修正 %d 个" % (checked, changed))
    print("接着跑一次 `godot --headless --path . --import` 让改动生效。")


if __name__ == "__main__":
    main()
