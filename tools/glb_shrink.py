"""把外部化后的 GLB 里「已被清零的贴图区间」真正裁掉，只保留几何。

为什么需要：
  glb_externalize.py 为了不破坏 accessor 偏移，只把贴图字节**原地清零**，
  所以 BIN 长度不变（86 MB），但内容大半是零。Godot 读的时候没问题，
  可是仓库里躺着 86 MB 的文件很丑（虽然 gzip 后只有 3.5 MB）。

  ⚠ 直接裁会破坏后面所有 bufferView 的 byteOffset —— 所以这里做**完整重映射**：
    · 只保留非贴图 bufferView
    · 重新紧凑排布，同步改每个 bufferView 的 byteOffset
    · accessor 的 bufferView 索引也一起重映射
  任何一步漏改都会让 Godot 报「buffer view size was smaller than ...」。

用法：
  python tools/glb_shrink.py <输入.glb> <输出.glb>
"""
import json
import struct
import sys

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("不是 GLB")
    offset, gltf, binary = 12, None, b""
    while offset < min(length, len(data)):
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + chunk_len]
        if chunk_type == JSON_CHUNK:
            gltf = json.loads(chunk.decode("utf-8"))
        elif chunk_type == BIN_CHUNK:
            binary = chunk
        offset += 8 + chunk_len + (-chunk_len % 4)
    return gltf, binary


def build_glb(gltf, binary):
    js = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    out = bytearray()
    total = 12 + 8 + len(js) + (8 + len(binary) if binary else 0)
    out += struct.pack("<III", GLB_MAGIC, 2, total)
    out += struct.pack("<II", len(js), JSON_CHUNK)
    out += js
    if binary:
        bin_ = binary + b"\x00" * ((-len(binary)) % 4)
        out += struct.pack("<II", len(bin_), BIN_CHUNK)
        out += bin_
    return bytes(out)


def is_all_zero(seg):
    return not any(seg)


def main():
    if len(sys.argv) < 3:
        sys.exit("用法: glb_shrink.py <输入.glb> <输出.glb>")
    src, dst = sys.argv[1], sys.argv[2]
    gltf, binary = read_glb(src)
    old_bvs = gltf.get("bufferViews", [])

    # 哪些 bufferView 是纯零（贴图那段被清零的）？这些可以整个丢掉。
    drop = set()
    for i, bv in enumerate(old_bvs):
        off = bv.get("byteOffset", 0)
        length = bv.get("byteLength", 0)
        if length > 0 and is_all_zero(binary[off:off + length]):
            drop.add(i)
    # 被 accessor 引用的不能丢（几何哪怕全零也是数据）
    referenced = set()
    for acc in gltf.get("accessors", []):
        bv = acc.get("bufferView")
        if bv is not None:
            referenced.add(bv)
        sparse = acc.get("sparse") or {}
        for part in ("indices", "values"):
            idx = sparse.get(part, {}).get("bufferView")
            if idx is not None:
                referenced.add(idx)
    drop -= referenced
    if not drop:
        print("没有可裁掉的区间，直接复制")
        with open(dst, "wb") as f:
            f.write(build_glb(gltf, binary))
        return

    # 重新紧凑排布
    keep = [i for i in range(len(old_bvs)) if i not in drop]
    new_binary = bytearray()
    remap = {}
    entries = []
    for new_i, old_i in enumerate(keep):
        bv = old_bvs[old_i]
        off = bv.get("byteOffset", 0)
        length = bv.get("byteLength", 0)
        remap[old_i] = new_i
        entry = dict(bv)
        entry["byteOffset"] = len(new_binary)
        new_binary += binary[off:off + length]
        entries.append(entry)
    gltf["bufferViews"] = entries

    # 重映射所有引用
    for acc in gltf.get("accessors", []):
        bv = acc.get("bufferView")
        if bv is not None and bv in remap:
            acc["bufferView"] = remap[bv]
        sparse = acc.get("sparse") or {}
        for part in ("indices", "values"):
            idx = sparse.get(part, {}).get("bufferView")
            if idx is not None and idx in remap:
                sparse[part]["bufferView"] = remap[idx]
    for img in gltf.get("images", []):
        bv = img.get("bufferView")
        if bv is not None and bv in remap:
            img["bufferView"] = remap[bv]
    if "buffers" in gltf and gltf["buffers"]:
        gltf["buffers"][0]["byteLength"] = len(new_binary)

    with open(dst, "wb") as f:
        f.write(build_glb(gltf, bytes(new_binary)))
    print("裁掉 %d 个零区间：%d 字节 -> %d 字节（%.1f MB -> %.1f MB）" % (
        len(drop), len(binary), len(new_binary),
        len(binary) / 1048576.0, len(new_binary) / 1048576.0))


if __name__ == "__main__":
    main()
