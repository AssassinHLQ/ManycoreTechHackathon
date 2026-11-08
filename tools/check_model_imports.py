# 外部模型预算检查：三角面 / 贴图尺寸 / 节点数 / 材质数。
# 用法： python tools/check_model_imports.py [模型目录]
#        不带参数就扫 assets/models/ 下所有模型目录。
#
# 规则见 assets/models/README.md 第二节。贴图**外链**也要算进来 ——
# 只查 GLB 里内嵌的贴图会漏掉一大半（外链之后 GLB 里根本没有图）。
import io
import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")
MANIFEST = os.path.join(MODELS, "LICENSE_MANIFEST.json")

# 贴图预算：主角/近景 ≤ 4096；纯远景剪影 ≤ 512。
# 这里用 4096 作为上限 —— 超过就是「明确超预算」，具体用途由 README 那一栏管。
BUDGET = {"triangles": 150000, "texture_edge": 4096, "nodes": 400, "materials": 24}


def read_glb(path):
    """读 GLB：返回 (gltf_json, bin_bytes)。"""
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
    if gltf is None:
        raise ValueError("GLB 里没有 JSON chunk")
    return gltf, binary


def image_size(path):
    """读 PNG / JPEG 的像素宽高。失败返回 (None, None)。"""
    try:
        from PIL import Image
        with Image.open(path) as im:
            return im.size
    except Exception:
        pass
    try:
        with open(path, "rb") as f:
            head = f.read(32)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            return (int.from_bytes(head[16:20], "big"),
                    int.from_bytes(head[20:24], "big"))
    except Exception:
        pass
    return (None, None)


def triangles(gltf):
    total = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" in prim:
                total += gltf["accessors"][prim["indices"]]["count"] // 3
            else:
                pos = prim.get("attributes", {}).get("POSITION")
                count = gltf["accessors"][pos]["count"] if pos is not None else 0
                mode = prim.get("mode", 4)
                total += count // 3 if mode == 4 else max(count - 2, 0)
    return total


def collect_textures(gltf, binary, model_dir):
    """收集所有贴图：(来源, 路径, 边长)。内嵌与外链都算。"""
    out = []
    views = gltf.get("bufferViews", [])
    for img in gltf.get("images", []):
        uri = img.get("uri")
        if uri:
            if uri.startswith("data:"):
                out.append(("内嵌data", None, None))
                continue
            path = os.path.join(model_dir, uri.replace("/", os.sep))
            size = image_size(path) if os.path.isfile(path) else (None, None)
            edge = max(size) if size and size[0] else None
            out.append((uri, path, edge))
            continue
        bv = img.get("bufferView")
        if bv is None or not binary:
            out.append(("未知", None, None))
            continue
        v = views[bv]
        start = v.get("byteOffset", 0)
        raw = binary[start: start + v.get("byteLength", 0)]
        try:
            from PIL import Image
            with Image.open(io.BytesIO(raw)) as im:
                out.append(("内嵌", None, max(im.size)))
        except Exception:
            out.append(("内嵌", None, None))
    return out


def main(argv):
    if not os.path.isdir(MODELS):
        print("没有 assets/models/ 目录")
        return 1

    with io.open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    # 已接入的模型：条目的 imported 为真。目录名用 imported_slug（没写就用 slug）。
    allowed = set()
    for entry in manifest.get("assets", []):
        if entry.get("imported"):
            allowed.add(entry.get("imported_slug") or entry.get("slug"))

    targets = argv[1:] or sorted(
        d for d in os.listdir(MODELS)
        if os.path.isdir(os.path.join(MODELS, d)) and not d.startswith("_"))
    problems = []
    for slug in targets:
        model_dir = os.path.join(MODELS, slug)
        glb_path = os.path.join(model_dir, "model.glb")
        if not os.path.isfile(glb_path):
            print("[跳过] %s：没有 model.glb" % slug)
            continue
        gltf, binary = read_glb(glb_path)
        tris = triangles(gltf)
        nodes = len(gltf.get("nodes", []))
        mats = len(gltf.get("materials", []))
        textures = collect_textures(gltf, binary, model_dir)
        edges = [e for _, _, e in textures if e]
        max_edge = max(edges) if edges else 0
        print("== %s" % slug)
        print("   三角面 %d / 预算 %d" % (tris, BUDGET["triangles"]))
        print("   节点   %d / 预算 %d" % (nodes, BUDGET["nodes"]))
        print("   材质   %d / 预算 %d" % (mats, BUDGET["materials"]))
        print("   贴图   %d 张，最大边 %d / 预算 %d" % (len(textures), max_edge,
                                                  BUDGET["texture_edge"]))
        for src, path, edge in textures:
            size = ""
            if path and os.path.isfile(path):
                size = "  %.2f MB" % (os.path.getsize(path) / 1048576.0)
            print("      %-28s %s%s" % (src, edge or "?", size))
        if slug not in allowed:
            problems.append("%s：不在 LICENSE_MANIFEST.json 的已导入列表里" % slug)
        if tris > BUDGET["triangles"]:
            problems.append("%s：%d 三角面，超出预算 %d" % (
                slug, tris, BUDGET["triangles"]))
        if max_edge > BUDGET["texture_edge"]:
            problems.append("%s：贴图 %dpx，超出预算 %dpx" % (
                slug, max_edge, BUDGET["texture_edge"]))
        if nodes > BUDGET["nodes"]:
            problems.append("%s：%d 个节点，超出预算 %d" % (
                slug, nodes, BUDGET["nodes"]))
        if mats > BUDGET["materials"]:
            problems.append("%s：%d 个材质，超出预算 %d" % (
                slug, mats, BUDGET["materials"]))

    if problems:
        print("\n=== 超出预算 ===")
        for p in problems:
            print("  ! %s" % p)
        return 1
    print("\n全部模型在预算内。")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
