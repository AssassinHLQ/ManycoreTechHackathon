# 从 GLB 里把内嵌贴图原样抽出来（字节级，不重新编码）。
# 用法： python tools/extract_glb_textures.py <模型.glb> <输出目录>
#
# 为什么需要它：Blender 在 D 盘、不是每次都在 PATH 上，
# 而「这个 GLB 内嵌了哪些图、什么分辨率」用不着 3D 引擎也能问出来。
import json
import os
import struct
import sys


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("不是 GLB（magic=%x）" % magic)
    offset, gltf, binary = 12, None, b""
    while offset < min(length, len(data)):
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif chunk_type == 0x004E4942:
            binary = chunk
        offset += 8 + chunk_len + (-chunk_len % 4)
    return gltf, binary


def main():
    path = sys.argv[1]
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    gltf, binary = read_glb(path)

    # 贴图槽位 -> 语义名。GLB 里没有语义名时按材质里的实际用途反推。
    for i, img in enumerate(gltf.get("images", [])):
        bv_index = img.get("bufferView")
        if bv_index is None:
            print("[%d] %s  外链 uri=%s（不处理）" % (i, img.get("name"), img.get("uri")))
            continue
        bv = gltf["bufferViews"][bv_index]
        off = bv.get("byteOffset", 0)
        raw = binary[off:off + bv["byteLength"]]
        mime = img.get("mimeType", "application/octet-stream")
        ext = {"image/png": ".png", "image/jpeg": ".jpg"}.get(mime, ".bin")
        name = img.get("name") or ("image_%d" % i)
        dst = os.path.join(outdir, "%s%s" % (name, ext))
        with open(dst, "wb") as f:
            f.write(raw)
        print("[%d] %-10s %-12s %9d 字节 -> %s" % (i, name, mime, len(raw), dst))


if __name__ == "__main__":
    main()
