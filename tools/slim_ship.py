# 把飞船 GLB 瘦身并转成 Godot 友好的朝向。
# 用法： blender --background --python slim_ship.py -- <输入.glb> <输出.glb>
#
# 做四件事：
#   1. 4K 贴图降到 1024，PNG 转 JPEG（原文件单张 4096² 解码 50MB，四张一起导入会把 Godot 撑爆）
#   2. 把根节点的缩放/旋转烘焙进网格（assets/models/README.md 的硬要求）
#   3. 修正朝向：原模型是 Y-up（机头 -Y、机顶 +Z），转成 Godot 的 Z-up（机头 -Z、机顶 +Y）
#   4. 原点摆到船体底部中心（落地物件约定）
#
# 朝向推导（实测包围盒与俯视/侧视渲染确认）：
#   原模型 size = (1.910, 1.378, 0.450)  长轴 X 为翼展，Y 为机长，Z 为机高
#   绕 X 轴 +90°： Y->Z, Z->-Y
#   结果：机头(-Y) -> -Z（Godot 前向），机顶(+Z) -> +Y（Godot 上）✔
import bpy
import sys
import os
import math
from mathutils import Vector

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    sys.exit("需要参数: <输入.glb> <输出.glb>")

src, dst = argv[0], argv[1]
MAX_TEX = 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    sys.exit("没有导入到网格")


def world_bounds(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for corner in o.bound_box:
            p = o.matrix_world @ Vector(corner)
            for i in range(3):
                mn[i] = min(mn[i], p[i])
                mx[i] = max(mx[i], p[i])
    return mn, mx


# --- 1. 贴图降采样 ---
for img in list(bpy.data.images):
    if img.size[0] == 0:
        continue
    w, h = img.size
    if max(w, h) <= MAX_TEX:
        continue
    scale = MAX_TEX / float(max(w, h))
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    img.scale(nw, nh)
    print("贴图 %s: %dx%d -> %dx%d" % (img.name, w, h, nw, nh))

# --- 2. 解除父子并烘焙变换 ---
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
for o in meshes:
    if o.parent is not None:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

mn, mx = world_bounds(meshes)
size = mx - mn
print("原始包围盒 size = (%.3f, %.3f, %.3f)" % (size.x, size.y, size.z))

# --- 3. 朝向修正：绕 X 轴 +90° ---
for o in meshes:
    o.rotation_mode = "XYZ"
    o.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

# --- 4. 原点到底部中心 ---
mn2, mx2 = world_bounds(meshes)
offset = Vector((
    (mn2.x + mx2.x) * 0.5,
    mn2.y,                    # 底部
    (mn2.z + mx2.z) * 0.5,
))
for o in meshes:
    o.location -= offset
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

mn3, mx3 = world_bounds(meshes)
final = mx3 - mn3
print("最终尺寸 (X宽, Y高, Z长) = (%.3f, %.3f, %.3f)" % (final.x, final.y, final.z))
print("底部 y = %.4f （应为 0）" % mn3.y)

# --- 5. 导出 ---
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_image_format="JPEG",
    export_jpeg_quality=88,
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_yup=True,
)
print("已导出:", dst, os.path.getsize(dst), "字节")
