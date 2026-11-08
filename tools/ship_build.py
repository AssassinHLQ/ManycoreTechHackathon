# 飞船模型的一键构建：原始 GLB -> 几何修正 + 原始分辨率贴图 + 外链化 -> 成品。
# 用法：
#   python tools/ship_build.py --src <原始.glb> --out-dir <成品目录> [--blender <路径>]
#
# 流程（两步）：
#   1. tools/slim_ship.py（Blender）—— 烘焙变换、修正朝向、原点到底部中心。
#      贴图**不降采样**，Blender 原样保留 4096/2048 的原始 PNG。
#   2. tools/glb_externalize.py（本体）—— 把贴图从 GLB 里抽出来变成独立文件，
#      GLB 只留几何。磁盘上贴图只有一份。
#
# ── 为什么要「外链」而不是把 4K 塞进 GLB ──
#   Godot 的 GLTF 导入器（gltf/embedded_image_handling=1）会把 GLB 内嵌贴图
#   **抽取**成磁盘上的独立文件，材质最终引用的是那些独立文件。
#   也就是说：贴图在 GLB 里存一遍、在磁盘上又存一遍 —— **双份**。
#   4K baseColor 单张 18.6 MB，双份就是 37 MB 白扔，网页版首包直接爆炸。
#   改成外链后磁盘上只有一份，GLB 只剩几百 KB 的几何。
#
# ── 为什么现在能用 4K（以前会被 Godot 撑爆）──
#   旧流程把 4096/2048 压到 1024 并转 JPEG，是因为「四张 4096² PNG 一起导入
#   把 Godot 撑爆」（见 assets/models/README.md）。现在贴图走独立文件、
#   逐张独立导入，峰值内存只剩单张 —— 于是可以恢复 4K 原始画质。
#
# ── 法线贴图保持 PNG ──
#   原始 GLB 里四张图本来就是 PNG，保持无损即可；
#   法线贴图**绝不能**转 JPEG（块效应会破坏法线，产生假高光）。
import argparse
import os
import subprocess
import sys

# Windows 控制台默认 GBK，打印「⇒」这类字符会 UnicodeEncodeError。
# 强制 stdout 走 UTF-8（errors="replace" 兜底，避免非 ASCII 卡死整条流水线）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_externalize import read_glb, build_glb  # noqa: E402

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
MIME_EXT = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}


def image_pixel_size(path):
    """不依赖 PIL 读 PNG/JPEG 尺寸（这里只要宽高，够用了）。"""
    with open(path, "rb") as f:
        head = f.read(32)
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")
        return w, h
    # JPEG：扫 SOFn 标记
    with open(path, "rb") as f:
        data = f.read()
    i = 2
    while i < len(data) - 9:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                      0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            h = int.from_bytes(data[i + 5:i + 7], "big")
            w = int.from_bytes(data[i + 7:i + 9], "big")
            return w, h
        seg = int.from_bytes(data[i + 2:i + 4], "big")
        i += 2 + seg
    return 0, 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="原始 GLB（Sketchfab 下载件）")
    ap.add_argument("--out-dir", required=True, help="成品目录")
    ap.add_argument("--blender", default=r"D:\SOFTWARE\Blender52\blender.exe")
    ap.add_argument("--keep-geometry", action="store_true",
                    help="跳过 Blender 那一步（调试用）")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    work = os.path.join(args.out_dir, "_work")
    os.makedirs(work, exist_ok=True)

    # --- 1. Blender：几何修正 ---
    geom_glb = os.path.join(work, "geometry.glb")
    if args.keep_geometry:
        geom_glb = args.src
        print("=== 步骤 1/2：跳过（--keep-geometry）===")
    else:
        print("=== 步骤 1/2：Blender 修正几何（朝向/原点）===")
        cmd = [args.blender, "--background", "--factory-startup",
               "--python", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                       "slim_ship.py"),
               "--", args.src, geom_glb]
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                              errors="replace")
        for line in proc.stdout.splitlines():
            if any(k in line for k in ("包围盒", "轴语义", "机头", "旋转后",
                                      "最终尺寸", "底部", "已导出")):
                print("   ", line.strip())
        if not os.path.isfile(geom_glb):
            sys.stderr.write(proc.stdout[-3000:])
            sys.stderr.write(proc.stderr[-3000:])
            sys.exit("Blender 步骤失败")

    # --- 2. 外链化：贴图抽成独立文件，GLB 只留几何 ---
    print("\n=== 步骤 2/2：贴图外链化（GLB 只留几何）===")
    gltf, binary = read_glb(geom_glb)

    # 语义名：按材质里各贴图槽的用途反推
    slot = {}
    for mat in gltf.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {})
        for key, sem in (("baseColorTexture", "base_color"),
                         ("metallicRoughnessTexture", "orm")):
            t = pbr.get(key)
            if t is None:
                continue
            src = gltf["textures"][t["index"]].get("source")
            if src is not None:
                slot[src] = sem
        for key, sem in (("normalTexture", "normal"),
                         ("occlusionTexture", "occlusion"),
                         ("emissiveTexture", "emissive")):
            t = mat.get(key)
            if t is None:
                continue
            src = gltf["textures"][t["index"]].get("source")
            if src is not None and src not in slot:
                slot[src] = sem

    tex_dir = os.path.join(args.out_dir, "textures")
    if os.path.isdir(tex_dir):
        for f in os.listdir(tex_dir):
            os.remove(os.path.join(tex_dir, f))
    else:
        os.makedirs(tex_dir, exist_ok=True)

    new_images = []
    drop_bv = set()
    written = []
    # URI 必须是**相对 GLB 所在目录**的路径。贴图放在 textures/ 子目录里
    # （assets/models/README.md 规定的目录结构），所以 uri 要带 textures/ 前缀，
    # 否则 Godot 会去找 res://assets/models/ship-fighter/base_color.png（不存在）。
    for idx, img in enumerate(gltf.get("images", [])):
        bv_index = img.get("bufferView")
        if bv_index is None:
            new_images.append(img)
            continue
        bv = gltf["bufferViews"][bv_index]
        off = bv.get("byteOffset", 0)
        raw = binary[off:off + bv["byteLength"]]
        mime = img.get("mimeType", "application/octet-stream")
        ext = MIME_EXT.get(mime, ".bin")
        sem = slot.get(idx) or os.path.splitext(img.get("name") or "img_%d" % idx)[0]
        fname = sem + ext
        with open(os.path.join(tex_dir, fname), "wb") as f:
            f.write(raw)
        written.append((fname, len(raw), mime))
        new_images.append({"uri": "textures/" + fname, "name": sem})
        drop_bv.add(bv_index)

    # 重建 BIN：把装着贴图字节的 bufferView 挖掉，其余紧凑重排
    old_bvs = gltf.get("bufferViews", [])
    keep = [i for i in range(len(old_bvs)) if i not in drop_bv]
    new_binary = bytearray()
    remap = {}
    keep_entries = []
    for new_i, old_i in enumerate(keep):
        bv = old_bvs[old_i]
        off = bv.get("byteOffset", 0)
        length = bv.get("byteLength", 0)
        remap[old_i] = new_i
        entry = dict(bv)
        entry["byteOffset"] = len(new_binary)
        entry["byteLength"] = length
        new_binary += binary[off:off + length]
        keep_entries.append(entry)
    gltf["bufferViews"] = keep_entries if keep else []

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
    for img in new_images:
        img.pop("bufferView", None)
    gltf["images"] = new_images
    if new_binary:
        gltf["buffers"][0]["byteLength"] = len(new_binary)
    else:
        gltf.pop("buffers", None)

    out_glb = os.path.join(args.out_dir, "model.glb")
    with open(out_glb, "wb") as f:
        f.write(build_glb(gltf, bytes(new_binary)))

    # --- 校验 ---
    print("\n=== 校验 ===")
    check, _ = read_glb(out_glb)
    all_uri = all(i.get("uri") for i in check.get("images", []))
    tris = sum(check["accessors"][p["indices"]]["count"] // 3
               for m in check.get("meshes", []) for p in m.get("primitives", [])
               if "indices" in p)
    print("   贴图全部外链 : %s" % ("是" if all_uri else "否"))
    print("   三角面       : %d" % tris)
    print("   GLB 体积     : %.2f MB（几何）" % (os.path.getsize(out_glb) / 1048576.0))
    for fname, size, mime in written:
        path = os.path.join(tex_dir, fname)
        w, h = image_pixel_size(path)
        print("   贴图 %-14s %6dx%-6d %7.2f MB  %s" % (
            fname, w, h, size / 1048576.0, mime))
    total = sum(s for _, s, _ in written)
    print("   贴图合计     : %.2f MB" % (total / 1048576.0))
    print("\n   下一步：让 Godot 重新导入，然后**手动把每张贴图的**")
    print("   「Mipmaps > Generate」打开 —— 见下方 tools/fix_ship_mipmaps.py")


if __name__ == "__main__":
    main()
