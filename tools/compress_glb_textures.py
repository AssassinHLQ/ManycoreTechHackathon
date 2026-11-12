"""压缩 GLB 内部的贴图：2048 PNG → 1024 JPEG（法线保持 PNG）。

为什么需要：
  Lux3D 产出的每个道具都有 3 张 2048² PNG，贴图占文件体积 95%。
  一个茶壶 6.25 MB 里 5.94 MB 是贴图，而它在阁楼里只占屏幕上几十像素。
  降到 1024 + JPEG 后通常能压到 0.8 MB 左右，观感几乎无差。

做法（纯 GLB 重打包，不重算几何）：
  1. 解析 GLB 的 JSON chunk + BIN chunk
  2. 找出所有 image（PNG），按用途分类：
       · 法线贴图（normalTexture 引用）→ PNG 保持无损，只降分辨率
       · 其余（baseColor / metallicRoughness / emissive）→ JPEG q88
  3. 重新排列 bufferViews，重建 BIN，写回 GLB

依赖：Pillow（已在运行环境里）
"""
import io
import json
import os
import struct
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from PIL import Image


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    # ⚠ 兼容 G1-Turbo：它返回的是 ZIP 包，但文件被命名为 .glb。
    #   （G1 返回真 GLB，Turbo 返回 ZIP —— 同一个 output_path 参数两种格式都可能出现）
    if data[:4] == b"PK\x03\x04":
        import zipfile
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            names = z.namelist()
            glb_name = next((n for n in names if n.lower().endswith(".glb")), None)
            if glb_name is None:
                raise ValueError("ZIP 里没有 glb: " + ", ".join(names[:5]))
            data = z.read(glb_name)
    magic, ver, total = struct.unpack("<4sII", data[0:12])
    if magic != b"glTF":
        raise ValueError("not a GLB: " + path)
    chunks = []
    off = 12
    while off + 8 <= len(data):
        clen, ctype = struct.unpack("<I4s", data[off:off + 8])
        payload = data[off + 8:off + 8 + clen]
        chunks.append([ctype, payload])
        # ⚠ 每个 chunk 按 4 字节对齐补齐，补齐字节**不属于** payload
        pad = (4 - clen % 4) % 4
        off += 8 + clen + pad
    if not chunks:
        raise ValueError("no chunks: " + path)
    js = json.loads(chunks[0][1].decode("utf-8"))
    bin_data = b""
    for ctype, payload in chunks[1:]:
        if ctype == b"BIN\x00" or ctype == b"BIN ":
            bin_data = payload
            break
    return js, bin_data


def write_glb(path, js, bin_data):
    jb = json.dumps(js, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    bb = bin_data + b"\x00" * ((4 - len(bin_data) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(jb), b"JSON"))
        f.write(jb)
        f.write(struct.pack("<I4s", len(bb), b"BIN\x00"))
        f.write(bb)


def normal_image_indices(js):
    """哪些 image 是法线贴图（不能有损压缩）。"""
    idx = set()
    for mat in js.get("materials", []):
        nt = mat.get("normalTexture")
        if not nt:
            continue
        tex_i = nt.get("index")
        texs = js.get("textures", [])
        if tex_i is not None and tex_i < len(texs):
            src = texs[tex_i].get("source")
            if src is not None:
                idx.add(src)
    return idx


def compress(src_path, dst_path, max_size=1024, quality=88):
    js, bin_data = read_glb(src_path)
    normal_idx = normal_image_indices(js)

    images = js.get("images", [])
    if not images:
        print("  (无贴图，跳过)")
        return False

    new_bin = bytearray()
    kept_buffers = []  # (旧 bufferView index, 新 offset, 新长度)

    # 先复制所有非图片的 bufferView
    image_bv = {}
    for i, im in enumerate(images):
        bv = im.get("bufferView")
        if bv is not None:
            image_bv[bv] = i

    bvs = js.get("bufferViews", [])
    remap = {}
    order = list(range(len(bvs)))
    for bi in order:
        bv = bvs[bi]
        old_off = bv.get("byteOffset", 0)
        old_len = bv["byteLength"]
        raw = bin_data[old_off:old_off + old_len]

        if bi in image_bv:
            ii = image_bv[bi]
            is_normal = ii in normal_idx
            try:
                im = Image.open(io.BytesIO(raw))
                w, h = im.size
                if max(w, h) > max_size:
                    k = max_size / float(max(w, h))
                    im = im.resize((max(1, int(w * k)), max(1, int(h * k))),
                                   Image.LANCZOS)
                out = io.BytesIO()
                if is_normal:
                    if im.mode not in ("RGB", "RGBA"):
                        im = im.convert("RGB")
                    im.save(out, format="PNG", optimize=True)
                else:
                    im = im.convert("RGB")
                    im.save(out, format="JPEG", quality=quality, optimize=True)
                new_raw = out.getvalue()
                images[ii]["mimeType"] = "image/png" if is_normal else "image/jpeg"
                # name 里带 Normal 的也当法线，避免误判
            except Exception as exc:
                print("    图%d 处理失败，保留原样: %s" % (ii, exc))
                new_raw = raw
        else:
            new_raw = raw

        # 4 字节对齐
        while len(new_bin) % 4:
            new_bin.append(0)
        bv["byteOffset"] = len(new_bin)
        bv["byteLength"] = len(new_raw)
        new_bin.extend(new_raw)
        remap[bi] = bi

    while len(new_bin) % 4:
        new_bin.append(0)

    js["buffers"] = [{"byteLength": len(new_bin)}]
    js["bufferViews"] = bvs
    write_glb(dst_path, js, bytes(new_bin))
    return True


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else \
        r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets\models\props\attic"
    max_size = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
    total_before = 0
    total_after = 0
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if not f.endswith(".glb"):
                continue
            p = os.path.join(d, f)
            before = os.path.getsize(p)
            if before < 100 * 1024:
                continue
            tmp = p + ".tmp"
            print("%-18s %6.2f MB" % (name, before / 1048576), end=" -> ", flush=True)
            try:
                if compress(p, tmp, max_size=max_size):
                    os.replace(tmp, p)
                else:
                    os.remove(tmp)
                after = os.path.getsize(p)
                total_before += before
                total_after += after
                print("%6.2f MB  (省 %.0f%%)" % (after / 1048576,
                                                (1 - after / float(before)) * 100))
            except Exception as exc:
                if os.path.exists(tmp):
                    os.remove(tmp)
                print("失败: %s" % exc)
    if total_before:
        print("\n合计 %.1f MB -> %.1f MB（省 %.0f%%）" % (
            total_before / 1048576, total_after / 1048576,
            (1 - total_after / float(total_before)) * 100))


if __name__ == "__main__":
    main()
