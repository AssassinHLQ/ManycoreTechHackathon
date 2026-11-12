"""批量压缩 assets/models 下所有 GLB 的内部贴图（递归遍历）。

为什么需要：
  之前只压了外部 png，但 GLB 内部还内嵌一份更重的贴图：
  167 个 glb 合计 1156 MB，其中贴图占 731 MB（约 63%）。
  星球模型每个 200k+ 面 + 2048² 贴图，贴图占 50~59%。

策略（按文件大小自适应）：
  文件 > 8 MB  → 贴图降到 512（远看为主，屏幕占比小）
  文件 ≤ 8 MB  → 贴图降到 1024（近看也用）
  法线贴图一律保持 PNG 无损，其余转 JPEG q88

用法：
  python compress_glb_all.py [--dry]
"""
import io
import json
import os
import struct
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from PIL import Image

ROOT = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets\models"
BIG_BYTES = 8 * 1024 * 1024
DRY = "--dry" in sys.argv


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] == b"PK\x03\x04":
        import zipfile
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            glb = next((n for n in z.namelist() if n.lower().endswith(".glb")), None)
            if glb is None:
                raise ValueError("zip has no glb")
            data = z.read(glb)
    if data[:4] != b"glTF":
        raise ValueError("not a GLB")
    chunks = []
    off = 12
    while off + 8 <= len(data):
        clen, ctype = struct.unpack("<I4s", data[off:off + 8])
        chunks.append([ctype, data[off + 8:off + 8 + clen]])
        off += 8 + clen + ((4 - clen % 4) % 4)
    js = json.loads(chunks[0][1].decode("utf-8"))
    bin_data = b""
    for ctype, payload in chunks[1:]:
        if ctype.startswith(b"BIN"):
            bin_data = payload
            break
    return js, bin_data


def write_glb(path, js, bin_data):
    jb = json.dumps(js, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    bb = bin_data + b"\x00" * ((4 - len(bin_data) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(jb) + 8 + len(bb)))
        f.write(struct.pack("<I4s", len(jb), b"JSON"))
        f.write(jb)
        f.write(struct.pack("<I4s", len(bb), b"BIN\x00"))
        f.write(bb)


def normal_indices(js):
    idx = set()
    for mat in js.get("materials", []):
        for key in ("normalTexture", "occlusionTexture"):
            t = mat.get(key)
            if not t:
                continue
            ti = t.get("index")
            texs = js.get("textures", [])
            if ti is not None and ti < len(texs):
                src = texs[ti].get("source")
                if src is not None:
                    idx.add(src)
    return idx


def compress_one(path, max_size):
    js, bin_data = read_glb(path)
    images = js.get("images", [])
    if not images:
        return None
    normals = normal_indices(js)
    image_bv = {}
    for i, im in enumerate(images):
        bv = im.get("bufferView")
        if bv is not None:
            image_bv[bv] = i
    bvs = js.get("bufferViews", [])
    new_bin = bytearray()
    changed = False
    for bi, bv in enumerate(bvs):
        old_off = bv.get("byteOffset", 0)
        raw = bin_data[old_off:old_off + bv["byteLength"]]
        if bi in image_bv:
            ii = image_bv[bi]
            is_norm = ii in normals
            try:
                im = Image.open(io.BytesIO(raw))
                w, h = im.size
                if max(w, h) > max_size:
                    k = max_size / float(max(w, h))
                    im = im.resize((max(1, int(w * k)), max(1, int(h * k))),
                                   Image.LANCZOS)
                    changed = True
                out = io.BytesIO()
                if is_norm:
                    if im.mode not in ("RGB", "RGBA", "L"):
                        im = im.convert("RGB")
                    im.save(out, format="PNG", optimize=True)
                    images[ii]["mimeType"] = "image/png"
                else:
                    if im.mode not in ("RGB", "L"):
                        im = im.convert("RGB")
                    im.save(out, format="JPEG", quality=88, optimize=True)
                    images[ii]["mimeType"] = "image/jpeg"
                new_raw = out.getvalue()
                if len(new_raw) < len(raw):
                    changed = True
            except Exception:
                new_raw = raw
        else:
            new_raw = raw
        while len(new_bin) % 4:
            new_bin.append(0)
        bv["byteOffset"] = len(new_bin)
        bv["byteLength"] = len(new_raw)
        new_bin.extend(new_raw)
    while len(new_bin) % 4:
        new_bin.append(0)
    if not changed:
        return None
    js["buffers"] = [{"byteLength": len(new_bin)}]
    return js, bytes(new_bin)


def main():
    targets = []
    for dirpath, _d, files in os.walk(ROOT):
        for fn in files:
            if fn.endswith(".glb"):
                targets.append(os.path.join(dirpath, fn))
    targets.sort(key=lambda p: -os.path.getsize(p))
    print("找到 %d 个 glb" % len(targets))
    tb = ta = 0
    n_ok = 0
    for p in targets:
        before = os.path.getsize(p)
        if before < 500 * 1024:
            continue
        max_size = 512 if before > BIG_BYTES else 1024
        rel = p.replace(ROOT + os.sep, "")
        if DRY:
            print("  [dry] %-58s %6.1f MB  target=%d" % (rel[:58], before / 1048576, max_size))
            continue
        try:
            r = compress_one(p, max_size)
            if r is None:
                continue
            js, new_bin = r
            tmp = p + ".tmp"
            write_glb(tmp, js, new_bin)
            after = os.path.getsize(tmp)
            if after >= before:
                os.remove(tmp)
                continue
            os.replace(tmp, p)
            imp = p + ".import"
            if os.path.isfile(imp):
                os.remove(imp)
            n_ok += 1
            tb += before
            ta += after
            print("  %-56s %6.1f -> %5.1f MB" % (rel[:56], before / 1048576, after / 1048576),
                  flush=True)
        except Exception as exc:
            if os.path.exists(p + ".tmp"):
                os.remove(p + ".tmp")
            print("  [FAIL] %-50s %s" % (rel[:50], str(exc)[:60]))
    if tb:
        print("\n压了 %d 个，%.0f MB -> %.0f MB（省 %.0f%%）" % (
            n_ok, tb / 1048576, ta / 1048576, (1 - ta / float(tb)) * 100))


if __name__ == "__main__":
    main()
