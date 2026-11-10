"""清理 Sketchfab 导出里的冗余节点缩放与动画。

用法:
    python tools/flatten_glb_scale.py <输入.glb> <输出.glb>

⚠ 2026-11-10 重要修正（本工具第一版搞反了，害得星球渲染全黑）:
    A Windy Day 的顶点数据**本来就是最终尺寸**（所有 POSITION accessor
    的 min/max 都在 ±1.09 量级），而 node 上挂着一个 scale=1e-10 的父节点。
    第一版误以为「顶点是 1e-10 大小、要靠父节点放大」，
    于是把 1e-10 乘进了顶点 —— 结果模型被缩成 1e-10，屏幕上是一个点，
    而 min/max 还是 ±1.09，两者对不上，Godot 视锥剔除直接把它剔掉了。
    **正确做法是反过来的：顶点不动，只把那个错误的 scale 删掉。**

    这类数据要**先量再动手**：读一遍所有 POSITION accessor 的 min/max，
    跟 1 比一比，就知道顶点到底是「已经很大」还是「真的很小」。

同时清理:
    - 节点上的 scale / matrix（Sketchfab 常见的冗余变换）
    - animations（它是那些 1e-10 缩放的关键帧，留着会在运行时把模型缩回去）

不做的事:
    - **不动顶点数据**（见上）
    - 不处理蒙皮（有 skins 直接拒绝）
"""
import json
import os
import struct
import sys


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _ver, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("不是 GLB")
    off, gltf, binary = 12, None, b""
    while off < min(length, len(data)):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binary = chunk
        off += 8 + clen + (-clen % 4)
    return gltf, binary


def build_glb(gltf, binary):
    jb = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    jb += b"\x20" * ((4 - len(jb) % 4) % 4)
    bb = binary + b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(jb), 0x4E4F534A) + jb
    out += struct.pack("<II", len(bb), 0x004E4942) + bb
    return bytes(out)


def position_extent(gltf):
    """量所有 POSITION accessor 的 min/max 范围，用来判断顶点是否已经是最终尺寸。"""
    lo = float("inf")
    hi = float("-inf")
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            pa = prim.get("attributes", {}).get("POSITION")
            if pa is None:
                continue
            acc = gltf["accessors"][pa]
            if "min" in acc:
                lo = min(lo, min(acc["min"]))
            if "max" in acc:
                hi = max(hi, max(acc["max"]))
    return lo, hi


def main():
    src, out = sys.argv[1], sys.argv[2]
    parent = os.path.dirname(out)
    if parent:
        os.makedirs(parent, exist_ok=True)

    gltf, binary = read_glb(src)
    if gltf.get("skins"):
        print("模型带 skin，本工具不处理，退出")
        sys.exit(1)

    lo, hi = position_extent(gltf)
    print("顶点范围 = [%.4f, %.4f]" % (lo, hi))
    if abs(hi) < 1e-3 and abs(lo) < 1e-3:
        print("⚠ 顶点确实很小（< 1e-3），这个模型的情况和 A Windy Day 不同，")
        print("  本工具**不**做烘焙（那会改变尺寸）；请先确认期望尺寸再处理。")
    else:
        print("顶点已是正常尺寸 → 只删节点上的冗余缩放，**不动顶点**")

    # ── 1. 删节点上的 scale / matrix ──
    cleared = 0
    for n in gltf.get("nodes", []):
        if n.pop("scale", None) is not None:
            cleared += 1
        if n.pop("matrix", None) is not None:
            cleared += 1
    print("清掉 %d 处节点变换" % cleared)

    # ── 2. 删动画（它们是那些缩放的关键帧）──
    anim_count = len(gltf.get("animations", []))
    if anim_count:
        gltf.pop("animations", None)
        print("删除 %d 段动画（其关键帧就是刚删掉的缩放）" % anim_count)

    with open(out, "wb") as f:
        f.write(build_glb(gltf, binary))

    print("%s  %.2f MB → %s  %.2f MB" % (
        os.path.basename(src), os.path.getsize(src) / 1048576.0,
        os.path.basename(out), os.path.getsize(out) / 1048576.0))


if __name__ == "__main__":
    main()
