"""点云抽稀：从 GLB 的 POINTS 图元里均匀采样，只保留一部分点。

用法:
    python tools/decimate_pointcloud.py <输入.glb> <输出.glb> --ratio 0.2

为什么要它:
    A Windy Day 有 205 万个点、55 MB 原始数据，Godot 导入后让 pck 涨 42.58 MB。
    点云的视觉密度有饱和点 —— 屏幕上同一片像素里堆 20 个点和堆 5 个点
    看起来差不多，但文件大小差 4 倍。所以抽稀是**性价比最高**的压缩手段。

    ⚠ 和三角面减面不同：减面会破坏形状，点云抽稀只是变稀疏，
      形状与颜色分布都保留。

结构特点（实测 A Windy Day）:
    400 个 accessor，只有 4 个 bufferView：
      bufferView[0] 被 150 个 POSITION 共享（stride 12）
      bufferView[1] 被 150 个 COLOR_0 共享（stride 16）
      bufferView[2]/[3] 里有另外 100 个 accessor（未被 primitive 引用）
    **同一个 bufferView 里塞了 150 个 accessor 的数据**，所以必须
    按 accessor 的 byteOffset 逐段抽稀，不能整个 bufferView 一起切
    （一起切会破坏各段的对齐和顺序）。

做法:
    1. 对每个 POINTS primitive，按 (POSITION accessor) 决定保留哪些点索引
    2. 把同一 mesh 的所有属性按**同一组索引**抽稀（颜色要跟位置对齐）
    3. 重建 buffer：点云数据全新建，未被引用的旧 accessor 直接丢弃
"""
import json
import os
import random
import struct
import sys

TYPE_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
COMP = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2),
        5122: ("h", 2), 5121: ("B", 1), 5120: ("b", 1)}


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


def elem_layout(gltf, acc_index):
    """返回 (ncomp, struct_format, size)。
    ⚠ 不读 byteStride —— 点云数据在 bufferView 里是**紧密连续**的：
      同一个 bufferView 里 150 个 accessor 首尾相接，
      每个 accessor 内部 stride 就是 ncomp*size。读 bufferView 的 stride
      会把别的 accessor 的数据也读进来。
    """
    acc = gltf["accessors"][acc_index]
    ncomp = TYPE_N[acc["type"]]
    fmt, size = COMP[acc["componentType"]]
    return ncomp, fmt, size


def acc_base_offset(gltf, acc_index):
    acc = gltf["accessors"][acc_index]
    bv = gltf["bufferViews"][acc["bufferView"]]
    return bv.get("byteOffset", 0) + acc.get("byteOffset", 0)


def main():
    src, out = sys.argv[1], sys.argv[2]
    ratio = 0.2
    if "--ratio" in sys.argv:
        ratio = float(sys.argv[sys.argv.index("--ratio") + 1])
    seed = 20261110
    if "--seed" in sys.argv:
        seed = int(sys.argv[sys.argv.index("--seed") + 1])

    parent = os.path.dirname(out)
    if parent:
        os.makedirs(parent, exist_ok=True)

    gltf, binary = read_glb(src)
    rng = random.Random(seed)

    new_bin = bytearray()
    new_bvs = []
    new_accessors = []

    def add_blob(blob: bytes) -> int:
        off = len(new_bin)
        new_bin.extend(blob)
        while len(new_bin) % 4:
            new_bin.append(0)
        bvi = len(new_bvs)
        new_bvs.append({"buffer": 0, "byteOffset": off, "byteLength": len(blob)})
        return bvi

    total_before = 0
    total_after = 0
    # 旧 accessor 索引 -> 新 accessor 索引
    acc_map = {}

    for mi, mesh in enumerate(gltf.get("meshes", [])):
        for prim in mesh.get("primitives", []):
            if prim.get("mode", 4) != 0:
                print("⚠ 发现非 POINTS 图元，本脚本只处理点云")
                sys.exit(1)
            attrs = prim.get("attributes", {})
            pos_acc = attrs.get("POSITION")
            if pos_acc is None:
                continue
            if pos_acc in acc_map:
                # 这个 mesh 的 POSITION 已经处理过（共享 accessor），
                # 那就按同一组索引处理其它属性
                continue

            # 决定保留哪些点
            ncomp, fmt, size = elem_layout(gltf, pos_acc)
            count = gltf["accessors"][pos_acc]["count"]
            total_before += count
            keep_n = max(1, int(count * ratio))
            keep_idx = sorted(rng.sample(range(count), keep_n))
            total_after += keep_n

            # 同一个 mesh 的所有属性都用这组索引
            for name, acc_idx in attrs.items():
                nc, f, sz = elem_layout(gltf, acc_idx)
                base = acc_base_offset(gltf, acc_idx)
                rec = struct.Struct("<" + f * nc)
                parts = []
                xs = []
                ys = []
                zs = []
                for i in keep_idx:
                    vals = rec.unpack_from(binary, base + i * sz)
                    parts.append(rec.pack(*vals))
                    if name == "POSITION":
                        xs.append(vals[0])
                        ys.append(vals[1])
                        zs.append(vals[2])
                blob = b"".join(parts)
                bvi = add_blob(blob)
                new_acc = {
                    "bufferView": bvi,
                    "componentType": gltf["accessors"][acc_idx]["componentType"],
                    "count": keep_n,
                    "type": gltf["accessors"][acc_idx]["type"],
                }
                if name == "POSITION":
                    new_acc["min"] = [min(xs), min(ys), min(zs)]
                    new_acc["max"] = [max(xs), max(ys), max(zs)]
                acc_map[acc_idx] = len(new_accessors)
                new_accessors.append(new_acc)

    # 重映射 primitive 里的 accessor 索引
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            for name, old in list(prim.get("attributes", {}).items()):
                if old in acc_map:
                    prim["attributes"][name] = acc_map[old]
            if "indices" in prim and prim["indices"] in acc_map:
                prim["indices"] = acc_map[prim["indices"]]

    # ⚠ 关键：原文件带 1 个 animations（50 条 scale 通道），
    # 它的 sampler 引用的正是那 100 个「未被 primitive 引用」的 accessor。
    # 抽稀后这些 accessor 不再存在，动画会指向越界索引 →
    # Godot 报 "Index p_accessor_index = 300 is out of bounds"。
    #
    # 而且这个动画**本来就是要丢的**：它是那堆 1e-10 缩放的呼吸动画，
    # 我们已经把缩放烘焙进顶点、节点变换全打平，
    # 再播这个动画会把模型重新缩到 1e-10（等于把星缩成看不见的点）。
    # 所以这里直接删掉整段 animations，并把它引用到的 accessor 一并丢弃。
    anim_count = len(gltf.get("animations", []))
    if anim_count:
        gltf.pop("animations", None)
        print("删除 %d 段动画（它们是已烘焙掉的 1e-10 缩放关键帧）" % anim_count)

    gltf["accessors"] = new_accessors
    gltf["bufferViews"] = new_bvs
    gltf["buffers"] = [{"byteLength": len(new_bin)}]

    with open(out, "wb") as f:
        f.write(build_glb(gltf, bytes(new_bin)))

    print("点云抽稀：%d → %d 点（ratio=%.2f）" % (total_before, total_after, ratio))
    print("%s  %.2f MB → %s  %.2f MB（省 %.0f%%）" % (
        os.path.basename(src), os.path.getsize(src) / 1048576.0,
        os.path.basename(out), os.path.getsize(out) / 1048576.0,
        100.0 * (1 - os.path.getsize(out) / os.path.getsize(src))))


if __name__ == "__main__":
    main()
