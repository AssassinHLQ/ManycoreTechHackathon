# 把 GLB 里内嵌的贴图抽成独立文件，并让 GLB 改用 uri 外链引用。
# 用法： python tools/glb_externalize.py <输入.glb> <输出.glb> <贴图输出目录>
#
# 为什么需要它：
#   Godot 的 GLTF 导入器会把 GLB 内嵌贴图**抽取**成磁盘上的独立文件
#   （import 设置 gltf/embedded_image_handling=1），材质最终引用的是那些独立文件。
#   也就是说：同一份贴图既在 GLB 里存了一遍，又在磁盘上存了一遍 —— 双份。
#   贴图从 1024 升到 4096 之后，baseColor 单张就是 18.6 MB PNG，双份就是 37 MB 白扔。
#
#   所以正确做法是让 GLB 只留几何，贴图走 uri 外链，磁盘上只有一份。
#   本脚本字节级搬运贴图（不重新编码），保证画质无损。
#
# 关键实现细节：外链化之后，装着贴图字节的那几个 bufferView 要从 GLB 里**真正删掉**，
#   连同它们占的 BIN 区间一起挖掉，剩下的 bufferView 重新紧凑排布并修正 byteOffset，
#   否则贴图数据仍然留在 GLB 里，等于没省。
import json
import os
import struct
import sys

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942

MIME_EXT = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}
# GLB 里 images 没有语义名时，按材质里各贴图槽的用途反推名字。
SLOT_NAMES = {
    "baseColorTexture": "base_color",
    "metallicRoughnessTexture": "orm",
    "normalTexture": "normal",
    "occlusionTexture": "occlusion",
    "emissiveTexture": "emissive",
}


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("不是 GLB（magic=%x）" % magic)
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
    """重新封装 GLB：JSON chunk + BIN chunk，各 4 字节对齐。"""
    json_bytes = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    bin_bytes = binary + b"\x00" * ((-len(binary)) % 4)

    total = 12 + 8 + len(json_bytes) + (8 + len(bin_bytes) if bin_bytes else 0)
    out = bytearray()
    out += struct.pack("<III", GLB_MAGIC, 2, total)
    out += struct.pack("<II", len(json_bytes), JSON_CHUNK)
    out += json_bytes
    if bin_bytes:
        out += struct.pack("<II", len(bin_bytes), BIN_CHUNK)
        out += bin_bytes
    return bytes(out)


def slot_names_for_images(gltf):
    """返回 {image_index: 语义名}，按材质里各贴图槽的用途反推。"""
    names = {}
    for mat in gltf.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {})
        slots = {}
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            t = pbr.get(key)
            if t is None:
                continue
            src = gltf["textures"][t["index"]].get("source")
            if src is not None:
                slots[src] = SLOT_NAMES[key]
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            t = mat.get(key)
            if t is None:
                continue
            src = gltf["textures"][t["index"]].get("source")
            if src is not None and src not in slots:
                slots[src] = SLOT_NAMES[key]
        names.update(slots)
    return names


def main():
    if len(sys.argv) < 4:
        sys.exit("用法: glb_externalize.py <输入.glb> <输出.glb> <贴图输出目录> [uri前缀]")
    src_path, dst_path, tex_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    # 第 4 个参数：写进 GLB 的 uri 前缀。
    # 贴图放在 GLB 同级的 textures/ 子目录时传 "textures/" —— Godot 按 GLB 所在目录
    # 解析相对 uri，不传的话它会在模型旁边再生成一份 model_*.png（等于双份）。
    uri_prefix = sys.argv[4] if len(sys.argv) > 4 else ""

    gltf, binary = read_glb(src_path)
    os.makedirs(tex_dir, exist_ok=True)
    slot = slot_names_for_images(gltf)

    # --- 1. 抽出贴图字节，记下要丢弃的 bufferView ---
    images = gltf.get("images", [])
    new_images = []
    drop_bv = set()
    used_names = {}
    for idx, img in enumerate(images):
        bv_index = img.get("bufferView")
        if bv_index is None:
            new_images.append(img)      # 本来就是外链
            continue
        bv = gltf["bufferViews"][bv_index]
        off = bv.get("byteOffset", 0)
        raw = binary[off:off + bv["byteLength"]]
        mime = img.get("mimeType", "application/octet-stream")
        ext = MIME_EXT.get(mime, ".bin")
        base = slot.get(idx) or os.path.splitext(img.get("name") or "image_%d" % idx)[0]
        # 多套材质共用同一槽位时，语义名会撞（三个材质都叫 base_color）。
        # 撞了就用 image 自己的名字做前缀，避免后写的把先写的覆盖掉。
        if base in used_names:
            own = os.path.splitext(img.get("name") or "")[0]
            base = "%s_%s" % (own, base) if own else "%s_%d" % (base, idx)
            # 再撞就加序号兜底
            suffix = 2
            unique = base
            while unique in used_names:
                unique = "%s_%d" % (base, suffix)
                suffix += 1
            base = unique
        used_names[base] = idx
        fname = base + ext
        with open(os.path.join(tex_dir, fname), "wb") as f:
            f.write(raw)
        print("  image[%d] %-12s %-12s %9d 字节 -> %s" % (
            idx, img.get("name") or "-", mime, len(raw), fname))
        new_images.append({"uri": uri_prefix + fname, "name": base})
        drop_bv.add(bv_index)

    # --- 2. 重建 BIN ---
    #
    # ⚠ 历史教训（2026-11-10，两次翻车）：
    #   ① 早期版本照抄 byteLength，Godot 报「buffer view size was smaller than
    #      the minimum required size」—— 因为几何 bufferView 常常是**多个 accessor
    #      共用一块连续区间**，单个 bufferView 的 byteLength 只覆盖它自己那份；
    #   ② 后来想「挖掉贴图区间、其余紧凑重排」，但重排时必须同步改所有
    #      bufferView 的 byteOffset —— 漏改就整片数据错位。
    #
    #   现在改成**不重排**：几何 bufferView 一律原样保留（byteOffset / byteLength /
    #   byteStride / target 全部照抄），只把贴图占的那几段字节**原地清零**。
    #   贴图数据因此不再占体积（Godot 读的是外链文件），而几何偏移完全不动，
    #   不可能错位。代价是 BIN 里留了点零，可以被 gzip 压掉。
    old_bvs = gltf.get("bufferViews", [])
    new_binary = bytearray(binary)
    for bv_index in drop_bv:
        bv = old_bvs[bv_index]
        off = bv.get("byteOffset", 0)
        length = bv.get("byteLength", 0)
        new_binary[off:off + length] = b"\x00" * length
    keep_entries = [dict(bv) for bv in old_bvs]
    remap = {i: i for i in range(len(old_bvs))}
    # 不重排：所有 bufferView 原样保留（贴图那几段已被清零）。
    gltf["bufferViews"] = keep_entries

    # --- 3. 访问器 / 稀疏访问 / 镜像器 的 bufferView 索引重映射 ---
    for acc in gltf.get("accessors", []):
        bv = acc.get("bufferView")
        if bv is not None and bv in remap:
            acc["bufferView"] = remap[bv]
        sparse = acc.get("sparse")
        if sparse:
            for part in ("indices", "values"):
                idx = sparse.get(part, {}).get("bufferView")
                if idx is not None and idx in remap:
                    sparse[part]["bufferView"] = remap[idx]
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            idx = prim.get("indices")
            if idx is not None:
                acc = gltf["accessors"][idx]
                bv = acc.get("bufferView")
                if bv is not None and bv in remap:
                    acc["bufferView"] = remap[bv]
            for attr, acc_index in (prim.get("attributes") or {}).items():
                acc = gltf["accessors"][acc_index]
                bv = acc.get("bufferView")
                if bv is not None and bv in remap:
                    acc["bufferView"] = remap[bv]
    for skin in gltf.get("skins", []):
        for key in ("inverseBindMatrices",):
            idx = skin.get(key)
            if idx is not None:
                acc = gltf["accessors"][idx]
                bv = acc.get("bufferView")
                if bv is not None and bv in remap:
                    acc["bufferView"] = remap[bv]
    for img in new_images:
        img.pop("bufferView", None)

    gltf["images"] = new_images
    if not new_binary:
        gltf.pop("buffers", None)
    else:
        gltf["buffers"][0]["byteLength"] = len(new_binary)

    with open(dst_path, "wb") as f:
        f.write(build_glb(gltf, bytes(new_binary)))
    print("已写出 %s (%d 字节)，贴图 %d 字节" % (
        dst_path, os.path.getsize(dst_path),
        sum(os.path.getsize(os.path.join(tex_dir, f))
            for f in os.listdir(tex_dir))))


if __name__ == "__main__":
    main()
