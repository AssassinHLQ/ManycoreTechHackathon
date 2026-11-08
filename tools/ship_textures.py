# 给 GLB 里指定语义名的贴图换文件（或删掉某张贴图的引用）。
# 用法： python tools/ship_textures.py --glb <model.glb> --out <新.glb> [--drop emissive] [--replace emissive=path]
#
# 为什么需要它：
#   删掉一张贴在 Godot 侧要改 material，但 **GLB 里的贴图引用也得同步去掉** ——
#   不然导出时 Godot 仍会把那张图打进 pck，白占体积。
#   飞船的 emissive 就是这种情况：原始贴图整张是黑的（实测最大值 2/255，
#   非零像素只有 10398 个），视觉上完全不发光，却要占 2.67 MB 的 pck 空间。
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_externalize import read_glb, build_glb  # noqa: E402

SLOT_KEYS = ("baseColorTexture", "metallicRoughnessTexture", "normalTexture",
             "occlusionTexture", "emissiveTexture")


def slot_of_image(gltf, image_index):
    """反查这张图接在材质的哪个槽上。"""
    for mat in gltf.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {})
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            t = pbr.get(key)
            if t is not None:
                src = gltf["textures"][t["index"]].get("source")
                if src == image_index:
                    return key
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            t = mat.get(key)
            if t is not None:
                src = gltf["textures"][t["index"]].get("source")
                if src == image_index:
                    return key
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--drop", action="append", default=[],
                    help="要删掉的贴图语义名（可重复）")
    ap.add_argument("--replace", action="append", default=[],
                    help="语义名=新文件路径（可重复）")
    args = ap.parse_args()

    gltf, binary = read_glb(args.glb)
    drops = set(args.drop)
    replacements = {}
    for item in args.replace:
        key, _, path = item.partition("=")
        replacements[key] = path

    # 建立 语义名 -> image index 的映射
    sem_to_img = {}
    for idx, img in enumerate(gltf.get("images", [])):
        name = img.get("name")
        if name:
            sem_to_img.setdefault(name, idx)

    dropped_images = set()
    for sem in drops:
        idx = sem_to_img.get(sem)
        if idx is None:
            print("找不到贴图 %s，跳过" % sem)
            continue
        dropped_images.add(idx)
        # 把材质里引用它的槽删掉
        for mat in gltf.get("materials", []):
            pbr = mat.get("pbrMetallicRoughness", {})
            for key in SLOT_KEYS:
                holder = pbr if key in ("baseColorTexture", "metallicRoughnessTexture") else mat
                t = holder.get(key)
                if t is None:
                    continue
                src = gltf["textures"][t["index"]].get("source")
                if src == idx:
                    del holder[key]
                    print("  从材质移除 %s 槽（贴图 %s）" % (key, sem))
            if "emissiveFactor" in mat and sem == "emissive":
                del mat["emissiveFactor"]

    # 替换
    for sem, path in replacements.items():
        idx = sem_to_img.get(sem)
        if idx is None:
            print("找不到贴图 %s，跳过替换" % sem)
            continue
        with open(path, "rb") as f:
            raw = f.read()
        # 找它对应的 bufferView，把字节换掉
        bv_index = gltf["images"][idx].get("bufferView")
        if bv_index is None:
            print("  %s 是外链贴图，请直接改 uri" % sem)
            continue
        bv = gltf["bufferViews"][bv_index]
        old_len = bv["byteLength"]
        off = bv.get("byteOffset", 0)
        binary = binary[:off] + raw + binary[off + old_len:]
        bv["byteLength"] = len(raw)
        # 后面所有 bufferView 的 offset 要挪
        for other in gltf["bufferViews"]:
            o_off = other.get("byteOffset", 0)
            if o_off > off:
                other["byteOffset"] = o_off + (len(raw) - old_len)
        gltf["buffers"][0]["byteLength"] = len(binary)
        print("  %s 换成 %s（%d 字节）" % (sem, path, len(raw)))

    # 删掉 images / textures 里对应的项，并重映射索引
    if dropped_images:
        keep_images = [i for i in range(len(gltf["images"])) if i not in dropped_images]
        remap = {old: new for new, old in enumerate(keep_images)}
        gltf["images"] = [gltf["images"][i] for i in keep_images]
        keep_textures = []
        tex_remap = {}
        for ti, tex in enumerate(gltf["textures"]):
            src = tex.get("source")
            if src in dropped_images:
                tex_remap[ti] = None
                continue
            new_tex = dict(tex)
            if src is not None:
                new_tex["source"] = remap[src]
            keep_textures.append(new_tex)
            tex_remap[ti] = len(keep_textures) - 1
        gltf["textures"] = keep_textures
        # 材质里指向被删贴图的 texture 索引要重映射
        for mat in gltf.get("materials", []):
            pbr = mat.get("pbrMetallicRoughness", {})
            for key in SLOT_KEYS:
                holder = pbr if key in ("baseColorTexture", "metallicRoughnessTexture") else mat
                t = holder.get(key)
                if t is not None:
                    t["index"] = tex_remap[t["index"]]
        print("  删掉 %d 张贴图" % len(dropped_images))

    with open(args.out, "wb") as f:
        f.write(build_glb(gltf, binary))
    print("已写出 %s（%d 字节）" % (args.out, os.path.getsize(args.out)))


if __name__ == "__main__":
    main()
