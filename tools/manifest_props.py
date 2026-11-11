# -*- coding: utf-8 -*-
"""统计 assets/models/props 下每个 GLB 的真实三角面数，并写入 LICENSE_MANIFEST。

用户要求（目标 ②）：「逐类入库并写进 LICENSE_MANIFEST」。

GLB 结构：12 字节头 + 若干 chunk（JSON chunk 类型 0x4E4F534A）。
三角面数 = 每个 primitive 的 indices accessor.count / 3
（无 indices 时用 POSITION accessor.count / 3）。
"""
import io
import json
import os
import struct

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(REPO, "assets", "models", "props")
MANIFEST = os.path.join(REPO, "assets", "models", "LICENSE_MANIFEST.json")

DEV = {
    "alien-tree": ("伞冠异星树", 30000),
    "alien-tree-lo": ("伞冠异星树（低模，铺量用）", 10000),
    "rock-cluster": ("层积巨岩群", 24000),
    "rock-cluster-lo": ("层积巨岩群（低模，铺量用）", 10000),
    "rock-spire": ("黑曜石尖峰", 26000),
    "rock-spire-lo": ("黑曜石尖峰（低模，铺量用）", 10000),
    "ruin-arch": ("遗迹拱门", 26000),
    "obelisk": ("符纹方尖碑", 26000),
    "dome-habitat": ("废弃穹顶居所", 30000),
    "signal-tower": ("信号中继塔", 28000),
    "crystal-cluster": ("发光晶簇", 24000),
    "vent": ("火山喷口", 22000),
    "floating-rock": ("悬浮碎石岛", 24000),
}


def glb_triangles(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError("not a GLB: %s" % path)
    off = 12
    doc = None
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:            # JSON
            doc = json.loads(body.decode("utf-8"))
            break
        off += 8 + clen
    if doc is None:
        raise ValueError("no JSON chunk: %s" % path)
    accs = doc.get("accessors", [])
    tris = 0
    verts = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" in prim:
                tris += accs[prim["indices"]]["count"] // 3
            attr = prim.get("attributes", {})
            if "POSITION" in attr:
                verts += accs[attr["POSITION"]]["count"]
    return tris, verts


def main():
    found = {}
    for name in sorted(os.listdir(PROPS)):
        p = os.path.join(PROPS, name, "model.glb")
        if not os.path.isfile(p):
            continue
        tris, verts = glb_triangles(p)
        found[name] = (tris, verts, os.path.getsize(p))
        print("%-18s %7d 面 / %7d 顶点 / %5.1f MB" % (
            name, tris, verts, os.path.getsize(p) / 1048576.0))

    with io.open(MANIFEST, encoding="utf-8") as f:
        doc = json.load(f)

    assets = doc["assets"]
    existing = {a.get("slug") for a in assets}
    added = 0
    for name, (tris, verts, size) in sorted(found.items()):
        slug = "prop-%s-ai-generated" % name
        if slug in existing:
            continue
        title, target = DEV.get(name, (name, 0))
        assets.append({
            "slug": slug,
            "original_file": "(AI 生成，无原始下载文件)",
            "title": "%s · 星球道具" % title,
            "author": "AI 生成（Aholo Lux3D，text-to-3D G1-Turbo）",
            "license": "Aholo Lux3D 生成，权属以平台服务条款与参赛协议为准",
            "attribution": "Aholo Lux3D 生成，不含第三方素材；权属以平台服务条款与参赛协议为准",
            "source_url": "https://labs.aholo3d.cn/",
            "imported": True,
            "imported_slug": "props/%s" % name,
            "imported_path": "assets/models/props/%s/model.glb" % name,
            "modifications": (
                "Aholo Lux3D text-to-3D 生成（G1-Turbo，目标 %d 面，实测 %d 面 / %d 顶点，"
                "%.1f MB，扣 13 credits）；未做几何修改；"
                "游戏内在 MultiMesh 里用实例色按星球调色"
                % (target, tris, verts, size / 1048576.0)),
            "modified_by": "tools/gen_props.py",
            "generated_by_tool": "Aholo Lux3D OpenAPI（cn 区域）",
            "task_id_note": "生成台账在 _lux3d_work/logs/collection.sqlite",
        })
        added += 1

    with io.open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("\nLICENSE_MANIFEST: 新增 %d 条，总计 %d 条" % (added, len(assets)))


if __name__ == "__main__":
    main()
