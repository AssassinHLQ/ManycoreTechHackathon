# 彩色贴图压缩质量核验：把原图和压缩图逐像素比，量 PSNR / 最大偏差。
# 用法： python tools/check_texture_quality.py <原图> <压缩图>
#
# 为什么需要它：
#   彩色贴图（base color / ORM / 自发光）可以用有损压缩换体积，
#   但「有损」到底损多少必须**量**，不能凭感觉。
#   PSNR 40 dB 以上人眼基本看不出差别；低于 30 dB 会出现明显的色块与描边断裂。
#
# 法线贴图**不能用**这个判据 —— 它要的是法线角度误差，
# 见 tools/check_normal_quality.py。
import sys

import numpy as np
from PIL import Image


def main():
    src_path, cmp_path = sys.argv[1], sys.argv[2]
    a = np.asarray(Image.open(src_path).convert("RGB")).astype(np.float32)
    b = np.asarray(Image.open(cmp_path).convert("RGB")).astype(np.float32)
    if a.shape != b.shape:
        print("尺寸不同 %s vs %s" % (a.shape[:2], b.shape[:2]))
        return 2
    mse = float(np.mean((a - b) ** 2))
    if mse <= 1e-12:
        psnr = float("inf")
    else:
        psnr = 10.0 * float(np.log10(255.0 * 255.0 / mse))
    diff = np.abs(a - b)
    print("PSNR      : %.2f dB" % psnr)
    print("最大偏差  : %.1f / 255" % diff.max())
    print("平均偏差  : %.2f / 255" % diff.mean())
    print("偏差 > 8 的像素占比: %.4f%%" % (float(np.mean(diff.max(axis=-1) > 8)) * 100.0))
    ok = psnr >= 40.0
    print("判定：%s" % ("通过（人眼基本看不出差别）" if ok else "不通过（可见色块/描边断裂）"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
