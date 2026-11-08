# 法线贴图压缩质量核验：把原图和压缩图都解回法线向量，量角度误差。
# 用法： python tools/check_normal_quality.py <原图.png> <压缩图>
#
# 为什么需要它：
#   法线贴图存的是 RGB = (x,y,z) 的方向，**不能**用普通图片的「视觉无损」标准来判断。
#   法线对压缩噪声极其敏感：一点点偏差就会在金属高光上变成假高光（像爬虫的亮点）。
#   所以必须量「解压后的法线与原法线的夹角」。
#   判据：绝大多数像素的夹角 < 2°（视觉无差），最大 < 8°（不会出破面）。
import sys

import numpy as np
from PIL import Image


def to_normals(rgb):
    """RGB -> 单位法线向量 (H, W, 3)。"""
    arr = np.asarray(rgb).astype(np.float32) / 255.0
    v = arr * 2.0 - 1.0
    norm = np.linalg.norm(v, axis=-1, keepdims=True)
    norm[norm < 1e-6] = 1e-6
    return v / norm


def main():
    src_path, cmp_path = sys.argv[1], sys.argv[2]
    a = Image.open(src_path).convert("RGB")
    b = Image.open(cmp_path).convert("RGB")
    if a.size != b.size:
        print("尺寸不同 %s vs %s —— 不能逐像素比较" % (a.size, b.size))
        return 2
    na = to_normals(a)
    nb = to_normals(b)
    dot = np.clip(np.sum(na * nb, axis=-1), -1.0, 1.0)
    angle = np.degrees(np.arccos(dot))
    print("像素数 %d" % angle.size)
    for t in (0.5, 1.0, 2.0, 3.0, 5.0, 8.0):
        pct = float(np.mean(angle < t)) * 100.0
        print("  夹角 < %4.1f° 的像素占比: %6.2f%%" % (t, pct))
    print("  平均夹角 %.3f°  中位数 %.3f°  99分位 %.3f°  最大 %.2f°" % (
        angle.mean(), np.median(angle),
        np.percentile(angle, 99), angle.max()))
    ok = np.mean(angle < 2.0) > 99.0 and angle.max() < 8.0
    print("判定：%s" % ("通过（可用于法线贴图）" if ok else "不通过（法线会有可见假高光）"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
