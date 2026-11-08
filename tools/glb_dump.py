# 不依赖 Blender，直接读 GLB 的 JSON chunk，打印贴图/材质/网格结构。
# 用法： python tools/glb_dump.py <模型.glb> [--images]
#
# 为什么需要它：Blender 装在 D 盘、不是每次都在 PATH 上，
# 而「这个 GLB 到底把贴图内嵌了还是外链、分辨率多少」这个问题用不着 3D 引擎。
import json
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
    want_images = "--images" in sys.argv
    gltf, binary = read_glb(path)
    print("asset      :", gltf.get("asset"))
    print("extensions :", list((gltf.get("extensionsUsed") or [])))
    print("BIN 字节数 :", len(binary))

    print("\n=== IMAGES ===")
    for i, img in enumerate(gltf.get("images", [])):
        buf = img.get("bufferView")
        mime = img.get("mimeType")
        size = None
        if buf is not None:
            bv = gltf["bufferViews"][buf]
            size = bv.get("byteLength")
        print("  [%d] name=%-14s mime=%-12s bufferView=%s bytes=%s uri=%s" % (
            i, img.get("name"), mime, buf, size, img.get("uri")))

    print("\n=== SAMPLERS/TEXTURES ===")
    for i, tex in enumerate(gltf.get("textures", [])):
        src = tex.get("source")
        name = gltf["images"][src].get("name") if src is not None and src < len(gltf.get("images", [])) else None
        print("  [%d] source=%s name=%s sampler=%s" % (i, src, name, tex.get("sampler")))

    print("\n=== MATERIALS ===")
    for i, mat in enumerate(gltf.get("materials", [])):
        print("  [%d] %s" % (i, mat.get("name")))
        pbr = mat.get("pbrMetallicRoughness", {})
        bc = pbr.get("baseColorTexture")
        if bc is not None:
            print("      baseColorTexture -> %s (tex %s, uv %s)" % (
                gltf["images"][gltf["textures"][bc["index"]]["source"]].get("name"),
                bc["index"], bc.get("texCoord", 0)))
        mr = pbr.get("metallicRoughnessTexture")
        if mr is not None:
            print("      metallicRoughnessTexture -> %s (tex %s)" % (
                gltf["images"][gltf["textures"][mr["index"]]["source"]].get("name"),
                mr["index"]))
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            t = mat.get(key)
            if t is not None:
                print("      %s -> %s (tex %s)" % (
                    key, gltf["images"][gltf["textures"][t["index"]]["source"]].get("name"),
                    t["index"]))
        print("      baseColorFactor=%s metallic=%s roughness=%s" % (
            pbr.get("baseColorFactor"), pbr.get("metallicFactor"), pbr.get("roughnessFactor")))

    print("\n=== MESHES ===")
    total = 0
    for i, mesh in enumerate(gltf.get("meshes", [])):
        tris = 0
        prims = mesh.get("primitives", [])
        for prim in prims:
            idx = prim.get("indices")
            if idx is not None:
                tris += gltf["accessors"][idx]["count"] // 3
        total += tris
        print("  [%d] %-28s prims=%d tris=%d" % (i, mesh.get("name"), len(prims), tris))
    print("  TOTAL tris = %d" % total)

    print("\n=== NODES ===")
    for i, node in enumerate(gltf.get("nodes", [])):
        print("  [%d] %-44s mesh=%s children=%s t=%s r=%s s=%s" % (
            i, (node.get("name") or "")[:44], node.get("mesh"), node.get("children"),
            node.get("translation"), node.get("rotation"), node.get("scale")))

    if want_images:
        print("\n=== IMAGE BYTES (每张前 24 字节) ===")
        for i, img in enumerate(gltf.get("images", [])):
            buf = img.get("bufferView")
            if buf is None:
                continue
            bv = gltf["bufferViews"][buf]
            off = bv.get("byteOffset", 0)
            data = binary[off:off + 24]
            print("  [%d] %-14s %s" % (i, img.get("name"), data[:24].hex()))


if __name__ == "__main__":
    main()
