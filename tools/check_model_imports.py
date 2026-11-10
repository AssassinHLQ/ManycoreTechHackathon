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
EXPORT_PRESETS = os.path.join(ROOT, "export_presets.cfg")

# 贴图预算：主角/近景 ≤ 4096；纯远景剪影 ≤ 512。
# 这里用 4096 作为上限 —— 超过就是「明确超预算」，具体用途由 README 那一栏管。
BUDGET = {"triangles": 150000, "texture_edge": 4096, "nodes": 400, "materials": 24}


def excluded_from_export():
    """读 export_presets.cfg 的 exclude_filter，返回被排除的路径前缀集合。

    为什么需要它：
      预算（三角面 ≤ 150k 等）管的是**进游戏/进包**的模型。
      但 `assets/models/` 里可以放**母版资产** —— 比如 Lux3D 生成的高面数星球，
      留着备用或做下游烘焙的源，**明确排除出导出**，不占 pck。
      这类资产不该按「进包预算」判红，否则检查器会一直报错，
      真出问题的时候反而没人看。
    """
    prefixes = set()
    if not os.path.isfile(EXPORT_PRESETS):
        return prefixes
    with io.open(EXPORT_PRESETS, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("exclude_filter"):
                continue
            _, _, value = line.partition("=")
            for part in value.strip().strip('"').split(","):
                part = part.strip()
                # 只看 assets/models/ 下的排除项，转成相对 MODELS 的 slug
                marker = "assets/models/"
                if marker in part:
                    slug = part.split(marker, 1)[1].split("/")[0]
                    if slug:
                        prefixes.add(slug)
    return prefixes


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
    """统计三角面数。**POINTS 图元不算三角面。**

    ⚠ glTF 的 primitive.mode 决定图元类型：
        0=POINTS  1=LINES  2=LINE_LOOP  3=LINE_STRIP  4=TRIANGLES
        5=TRIANGLE_STRIP  6=TRIANGLE_FAN
      一维星（A Windy Day）是 **150 个 mode=0 的 POINTS 图元、205 万个点、零三角面**。
      旧版把「没有 indices」的 primitive 一律按 (count-2) 算三角形，
      于是 205 万个点被当成 205 万三角面 → 报「超出预算 13 倍」，
      而实际上它对 GPU 的光栅化开销远小于同数量的三角面。
      这里按 mode 分开算：只有三角形类图元才计入面数。
    """
    total = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            mode = prim.get("mode", 4)
            pos = prim.get("attributes", {}).get("POSITION")
            vcount = gltf["accessors"][pos]["count"] if pos is not None else 0
            idx = prim.get("indices")
            icount = gltf["accessors"][idx]["count"] if idx is not None else vcount
            if mode == 4:            # TRIANGLES
                total += icount // 3
            elif mode == 5:          # TRIANGLE_STRIP
                total += max(icount - 2, 0)
            elif mode == 6:          # TRIANGLE_FAN
                total += max(icount - 2, 0)
            # POINTS / LINES / LINE_LOOP / LINE_STRIP 不计入三角面
    return total


def primitive_stats(gltf):
    """返回 {mode: 图元数} 和 {mode: 顶点数}，用来在报告里区分点云/线/三角面。"""
    prim_count = {}
    vert_count = {}
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            mode = prim.get("mode", 4)
            pos = prim.get("attributes", {}).get("POSITION")
            vcount = gltf["accessors"][pos]["count"] if pos is not None else 0
            prim_count[mode] = prim_count.get(mode, 0) + 1
            vert_count[mode] = vert_count.get(mode, 0) + vcount
    return prim_count, vert_count


MODE_NAMES = {0: "POINTS", 1: "LINES", 2: "LINE_LOOP", 3: "LINE_STRIP",
              4: "TRIANGLES", 5: "TRIANGLE_STRIP", 6: "TRIANGLE_FAN"}


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
    excluded_slugs = excluded_from_export()
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
        # 母版资产：明确排除出导出的，不按「进包预算」判红（见 excluded_from_export）
        is_master = slug in excluded_slugs
        tag = "  【母版·不进包】" if is_master else ""
        print("== %s%s" % (slug, tag))
        # 点云/线这类非三角面图元要单独报，否则「0 三角面」看起来像空模型
        prim_count, vert_count = primitive_stats(gltf)
        non_tri = {m: n for m, n in prim_count.items() if m != 4}
        if non_tri:
            parts = ["%s×%d（%d 顶点）" % (MODE_NAMES.get(m, str(m)), n, vert_count.get(m, 0))
                     for m, n in sorted(non_tri.items())]
            print("   图元   %s  ← 非三角面图元，不计入三角面预算" % "、".join(parts))
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
        if is_master:
            # 母版只查许可闸门；面数/贴图只是记录，不判红。
            continue
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
