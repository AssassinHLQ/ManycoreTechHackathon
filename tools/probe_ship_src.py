# 探针：读原始飞船 GLB，报告贴图分辨率、网格/材质统计。
# 用法： blender --background --python probe_ship_src.py -- <输入.glb>
import bpy
import sys
from mathutils import Vector

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    sys.exit("需要参数: <输入.glb>")

src = argv[0]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

print("=== IMAGES ===")
for img in sorted(bpy.data.images, key=lambda i: i.name):
    print("  %-28s %dx%d  size=%s  source=%s" % (
        img.name, img.size[0], img.size[1], img.file_format, img.source))

print("=== MATERIALS ===")
for m in bpy.data.materials:
    print("  %s" % m.name)

print("=== MESHES ===")
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
total_tris = 0
for o in meshes:
    tris = len(o.data.loop_triangles) if o.data.loop_triangles else 0
    if not tris:
        o.data.calc_loop_triangles()
        tris = len(o.data.loop_triangles)
    total_tris += tris
    print("  %-24s verts=%-6d tris=%-6d mat=%s" % (
        o.name, len(o.data.vertices), tris,
        [ms.name for ms in o.data.materials]))
print("  TOTAL tris = %d" % total_tris)

mn = Vector((1e9, 1e9, 1e9))
mx = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    for corner in o.bound_box:
        p = o.matrix_world @ Vector(corner)
        for i in range(3):
            mn[i] = min(mn[i], p[i])
            mx[i] = max(mx[i], p[i])
size = mx - mn
print("=== BOUNDS size = (%.4f, %.4f, %.4f) ===" % (size.x, size.y, size.z))
print("=== NODES ===")
for o in bpy.data.objects:
    print("  %-24s type=%-8s parent=%s scale=%s rot=%s" % (
        o.name, o.type, o.parent.name if o.parent else "-",
        tuple(round(v, 4) for v in o.scale), tuple(round(v, 4) for v in o.rotation_euler)))
