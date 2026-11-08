# 飞船 GLB 的几何处理：把根节点变换烘焙进网格、修正朝向、原点摆到底部中心。
# 用法： blender --background --python slim_ship.py -- <输入.glb> <输出.glb>
#
# 只做**几何**三件事（贴图不在这里处理，见 tools/ship_build.py）：
#   1. 把根节点的缩放/旋转烘焙进网格（assets/models/README.md 的硬要求）
#   2. 修正朝向：Godot 约定机头 -Z、机顶 +Y、翼展 X
#   3. 原点摆到船体底部中心（落地物件约定）
#
# ── 朝向怎么定的（2026-11-08 实测，不是照抄注释）──
#   旧版本注释写「原模型 Y-up，机头 -Y、机顶 +Z，绕 X 轴 +90° 即可」——
#   **这是错的**。用 tests/probe_ship_facing.gd 六向截图复核后实测：
#   原始 GLB 在 Blender 里的世界包围盒 = (1.910, 1.378, 0.450)
#     X = 1.910 = **机长**
#     Y = 1.378 = **翼展**
#     Z = 0.450 = **机高**
#   而且端面切片密度显示 **-X 端是尖的（43 顶点）**、+X 端是平的（2025 顶点），
#   也就是 **机头在 -X**，不是注释里说的 -Y。
#   旧脚本只绕 X 轴 +90°，那只会把「机顶朝上」解决掉，
#   **机头仍然留在 -X** —— 机身是横着的，和 Godot 的前进方向差 90°。
#   （游戏里表现为：飞船侧着飞，摄像机在座舱里看到的却是机腹侧面。）
#
#   本脚本改成**自己量、自己算**：
#     - 用端面切片密度找出机头轴与机头端
#     - 用包围盒找出机长轴、翼展轴、机高轴
#     - 构造目标基底（机头 -Z、机顶 +Y），算出旋转矩阵直接作用在网格数据上
#   这样不再依赖任何「注释里的轴向」——换模型也不用改脚本。
#
# 顺带把朝向这件事变成**可验证的**：脚本最后会打印
# 「最终尺寸 (X宽, Y高, Z长)」与「机头端切片密度」，
# 由 tests/probe_ship_facing.gd 的六向截图做最终确认。
import bpy
import sys
import os
import math
from mathutils import Vector, Matrix

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    sys.exit("需要参数: <输入.glb> <输出.glb>")

src, dst = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    sys.exit("没有导入到网格")


def world_bounds(objs):
    """世界包围盒。**直接遍历顶点**，不用 o.bound_box ——
    后者在 mesh.transform() 之后是陈旧缓存，会让「底部 y = 0」的断言失效
    （实测踩过：缓存值让原点偏移算错，底部停在 0.4624）。"""
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        mw = o.matrix_world
        for v in o.data.vertices:
            p = mw @ v.co
            for i in range(3):
                mn[i] = min(mn[i], p[i])
                mx[i] = max(mx[i], p[i])
    return mn, mx


def axis_profile(objs, axis):
    """沿 axis 两端各取 8% 厚度内的顶点数。少的一端 = 更尖 = 机头端。"""
    mn, mx = world_bounds(objs)
    lo, hi = mn[axis], mx[axis]
    band = (hi - lo) * 0.08
    neg = pos = 0
    for o in objs:
        mw = o.matrix_world
        for v in o.data.vertices:
            c = (mw @ v.co)[axis]
            if c <= lo + band:
                neg += 1
            elif c >= hi - band:
                pos += 1
    return neg, pos


# --- 1. 解除父子并烘焙变换 ---
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
print("烘焙后包围盒 size = (%.3f, %.3f, %.3f)" % (size.x, size.y, size.z))

# --- 2. 实测判定各轴语义 ---
axes = sorted(range(3), key=lambda a: size[a], reverse=True)
length_axis = axes[0]      # 最长 = 机长
height_axis = axes[2]      # 最短 = 机高
span_axis = axes[1]        # 中间 = 翼展
print("轴语义：机长=%s 翼展=%s 机高=%s" % (
    "XYZ"[length_axis], "XYZ"[span_axis], "XYZ"[height_axis]))

# 机头：机长轴上更尖的那一端
neg, pos = axis_profile(meshes, length_axis)
head_is_neg = neg < pos
print("机头端切片：-%s=%d / +%s=%d ⇒ 机头在 %s%s" % (
    "XYZ"[length_axis], neg, "XYZ"[length_axis], pos,
    "-" if head_is_neg else "+", "XYZ"[length_axis]))

# 机顶：Blender 的 glTF 导入器把 glTF 的 +Y(上) 映射到 Blender 的 +Z，
# 所以烘焙后「机顶」在 +Z 方向。取反只在模型本身上下颠倒时才会发生，
# 这里按 +Z 处理，最后由六向截图复核。
up_vector = Vector((0.0, 0.0, 1.0))
head_vector = Vector((0.0, 0.0, 0.0))
head_vector[length_axis] = -1.0 if head_is_neg else 1.0

# --- 3. 构造旋转：把 (head, up) 映射到 **导出后 Godot 里**的 (-Z, +Y) ---
# ⚠ 坐标系陷阱（实测踩过两轮）：
#   Blender 是 Z-up，glTF/Godot 是 Y-up。Blender 导出 glTF 时（export_yup=True）
#   会做一次转换 M: (x, y, z) -> (x, z, -y)；Godot 导入 glTF 时**不再转**
#   （两者都是 Y-up，前向都是 -Z）。
#   所以「Blender 里摆好」不等于「Godot 里摆好」，必须把 M 算进去。
#   推导：想要 Godot 里 head=-Z、up=+Y、span=+X，
#         反推 Blender 里必须是 head=+Y、up=+Z、span=+X：
#           M(e_y) = -e_z  ⇒ Blender +Y → Godot -Z ✔（机头朝前）
#           M(e_z) = +e_y  ⇒ Blender +Z → Godot +Y ✔（机顶朝上）
#           M(e_x) = +e_x  ⇒ Blender +X → Godot +X ✔（翼展不变）
#   下面用 Blender 空间的基底表达这个目标。
target_back = Vector((0.0, -1.0, 0.0))   # Blender: 尾方向 = -Y（机头在 +Y）
target_up = Vector((0.0, 0.0, 1.0))      # Blender: 机顶 = +Z
# 右手系里 right = up × back（列向量）
target_right = target_up.cross(target_back).normalized()

back_s = -head_vector                   # 源：机头指向 head_vector，尾方向相反
up_s = up_vector
# 源基底：right = up × back
right_s = up_s.cross(back_s)
if right_s.length < 1e-6:
    sys.exit("源 up 与 head 平行，无法构造基底（模型可能上下颠倒）")
right_s.normalize()
# 再正交化 up：up = back × right
up_s = back_s.cross(right_s).normalized()

def basis_cols(right, up, back):
    """列向量拼成的 3x3 矩阵：第 0 列=right, 1=up, 2=back。"""
    return Matrix((
        (right.x, up.x, back.x),
        (right.y, up.y, back.y),
        (right.z, up.z, back.z),
    ))


B_s = basis_cols(right_s, up_s, back_s)
B_t = basis_cols(target_right, target_up, target_back)
R3 = B_t @ B_s.transposed()
# Mesh.transform() 要求 4x4
R = R3.to_4x4()
print("旋转矩阵 R =")
for row in R3:
    print("   (%+.4f, %+.4f, %+.4f)" % (row[0], row[1], row[2]))

for o in meshes:
    o.data.transform(R)
    o.data.update()

mn2, mx2 = world_bounds(meshes)
s2 = mx2 - mn2
print("旋转后 size (Blender X,Y,Z) = (%.3f, %.3f, %.3f)" % (s2.x, s2.y, s2.z))

# 校验必须用 **导出后 Godot 空间** 的语义来判，否则会看错轴。
# 导出时 Blender 会做 M: (x,y,z) -> (x,z,-y)（Y-up），
# 所以 Godot 里的尺寸 = (Blender.x, Blender.z, Blender.y)。
g_x, g_y, g_z = s2.x, s2.z, s2.y
print("Godot 空间 size (翼展X, 机高Y, 机长Z) = (%.3f, %.3f, %.3f)" % (g_x, g_y, g_z))
print("  机高应是最小的 %.3f → %s" % (
    min(g_x, g_y, g_z), "对" if abs(g_y - min(g_x, g_y, g_z)) < 1e-4 else "错"))
print("  机长应是最大的 %.3f → %s" % (
    max(g_x, g_y, g_z), "对" if abs(g_z - max(g_x, g_y, g_z)) < 1e-4 else "错"))
# 机头：Blender 里机头在 +Y，导出 M 后 +Y -> -Z，所以 Godot 里机头在 -Z。
head_neg = 0
head_pos = 0
band = s2.y * 0.08
for o in meshes:
    mw = o.matrix_world
    for v in o.data.vertices:
        c = (mw @ v.co).y
        if c <= mn2.y + band:
            head_neg += 1
        elif c >= mx2.y - band:
            head_pos += 1
print("  机头应在 Blender +Y（导出后即 Godot -Z）：+Y 端=%d / -Y 端=%d → %s" % (
    head_pos, head_neg, "对" if head_pos < head_neg else "错"))

# --- 4. 原点到底部中心 ---
# ⚠ 同样要把导出转换 M 算进去：
#   Godot 里「底部」= Y 最小；M 把 Blender 的 -Z 映射到 Godot 的 -Y。
#   所以在 Blender 里要让模型**底部**贴到 z=0 的镜像位置 ——
#   即把 Blender 的 z 范围挪到「底部 = 0」是不对的，M 之后 Godot 的 y 会翻转。
#   直接推：Godot 原点要求 Godot y=0 是底部 ⇒ M 后 Blender 的 z 应该是**最大值**侧？
#   M: (x,y,z) -> (x,z,-y)。Godot y = Blender z。Godot 要 y>=0（底部在 0，往上为正）
#   ⇒ Blender z >= 0，即 Blender 的 z 最小值应为 0。
#   Blender z 最小 = 底部（Blender Z-up，-Z 是下）✔ 正好一致。
mn2, mx2 = world_bounds(meshes)
offset = Vector((
    (mn2.x + mx2.x) * 0.5,   # X 居中（翼展方向）
    (mn2.y + mx2.y) * 0.5,   # Y 居中（机长方向）
    mn2.z,                   # Z 最小 = 底部 → Blender z=0 ⇒ Godot y=0
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
print("最终尺寸 (Blender X,Y,Z) = (%.3f, %.3f, %.3f)" % (final.x, final.y, final.z))
print("最终尺寸 (Godot 翼展X,机高Y,机长Z) = (%.3f, %.3f, %.3f)" % (
    final.x, final.z, final.y))
print("Blender 底部 z = %.4f （应为 0 ⇒ Godot 底部 y = 0）" % mn3.z)

# --- 5. 导出（贴图随后由 tools/ship_build.py 换成原始分辨率并外链）---
# Blender 5.x 的 export_image_format 枚举是 ('AUTO','JPEG','WEBP','NONE')，没有 PNG。
# 这里用 AUTO：贴图是 PNG 就保持 PNG，是 JPEG 就保持 JPEG。
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_image_format="AUTO",
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_yup=True,
)
print("已导出:", dst, os.path.getsize(dst), "字节")
