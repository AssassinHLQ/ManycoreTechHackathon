"""把两个空间站源文件转成项目用的 GLB。

Space Station（FBX）：
  · 导入 FBX
  · 烘焙变换到网格（apply transform）
  · 统一成 1 单位 = 1 米，缩放到指定包围盒
  · 原点移到质心（空间站是漂浮物，不放底面）
  · 挂上 5 张 MergedBake PBR 贴图（外链）
  · 导出 GLB（贴图不内嵌，只留 uri）

Space Station 3（blend）：
  · 打开 blend
  · 同样处理三套材质
  · 导出 GLB

用法：
  blender -b --factory-startup -P tools/station_build.py -- <slug>
"""
import os
import sys

import bpy
from mathutils import Vector

ROOT = r"C:\Users\WY157\Desktop\GODOT\_station_src"
OUT_ROOT = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets\models"

# 每个站的目标包围盒最大边（米）。归航站外环约 560 米直径，这两个做远景站，
# 体量要够大才看得见，但也不能盖过主站。
TARGET_SIZE = {
    "space-station": 900.0,
    "space-station-3": 760.0,
}


def log(msg):
    print("[station_build] %s" % msg)


def wipe():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_source(slug):
    src_dir = os.path.join(ROOT, slug, "source")
    name = os.listdir(src_dir)[0]
    path = os.path.join(src_dir, name)
    log("导入 %s" % path)
    if name.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    elif name.lower().endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=path)
    elif name.lower().endswith(".glb") or name.lower().endswith(".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    return name


def collect_meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def apply_transforms():
    """把缩放/旋转烘进网格，根节点保持 identity（README 规矩）。"""
    for obj in collect_meshes():
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
    if collect_meshes():
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(False)


def normalize_size(slug):
    """按现场实测包围盒缩放到 TARGET_SIZE，原点移到质心。"""
    meshes = collect_meshes()
    if not meshes:
        log("⚠ 没有网格")
        return
    lo = Vector((1e18, 1e18, 1e18))
    hi = Vector((-1e18, -1e18, -1e18))
    for obj in meshes:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], world[i])
                hi[i] = max(hi[i], world[i])
    size = hi - lo
    longest = max(size.x, size.y, size.z)
    target = TARGET_SIZE.get(slug, 800.0)
    scale = target / longest if longest > 1e-6 else 1.0
    center = (lo + hi) * 0.5
    log("原始包围盒 %.1f x %.1f x %.1f，最长边 %.1f -> 缩放到 %.1f 米 (×%.6f)"
        % (size.x, size.y, size.z, longest, target, scale))

    # 用一个空物体做父级、施加缩放与居中，然后 apply 到网格
    empty = bpy.data.objects.new("norm", None)
    bpy.context.scene.collection.objects.link(empty)
    empty.scale = (scale, scale, scale)
    empty.location = -center * scale
    for obj in meshes:
        if obj.parent is None:
            obj.parent = empty
    bpy.context.view_layer.update()
    for obj in meshes:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    bpy.data.objects.remove(empty, do_unlink=True)


def report_materials():
    mats = [m for m in bpy.data.materials if m.users > 0]
    log("活动材质 %d 个：%s" % (len(mats), [m.name for m in mats]))


# ── 贴图挂接 ────────────────────────────────────────────────────────
# 两个源资产的材质节点树都是空的（实测 bpy.data.images 只有 0 个 image）：
# 贴图文件就在 textures/ 里，但没被连到材质上。所以这里按命名规则手动接。
#
# space-station（MergedBake 一套 PBR，5 张 4096）：
#   MergedBake_Bake1_PBR_Diffuse.png   -> baseColor
#   MergedBake_Bake1_PBR_Emission.png  -> emission
#   MergedBake_Bake1_PBR_Metalness.png -> metallic
#   MergedBake_Bake1_PBR_Normal.png    -> normal
#   MergedBake_Bake1_PBR_Roughness.png -> roughness
#   两个材质（Main / emitrED）共用同一套烘焙图 —— 本来就是合并烘焙的。
#
# space-station-3（三套材质，各 6 张）：
#   spacestation_main_*        -> spacestation_main
#   spacestation_main2_*       -> spacestation_main2
#   spacestation_smalllights_* -> spacestation_smalllights
#   后缀：_albedo / _emissive / _metallic / _normal / _roughness / _AO

STATION1_MAP = {
    "baseColor": "MergedBake_Bake1_PBR_Diffuse.png",
    "emission": "MergedBake_Bake1_PBR_Emission.png",
    "metallic": "MergedBake_Bake1_PBR_Metalness.png",
    "normal": "MergedBake_Bake1_PBR_Normal.png",
    "roughness": "MergedBake_Bake1_PBR_Roughness.png",
}

STATION3_PREFIX = {
    "spacestation_main": "spacestation_main",
    "spacestation_main2": "spacestation_main2",
    "spacestation_smalllights": "spacestation_smalllights",
}


def _load_image(tex_dir, filename):
    path = os.path.join(tex_dir, filename)
    if not os.path.isfile(path):
        log("  ⚠ 贴图不存在：%s" % path)
        return None
    imgs = [i for i in bpy.data.images if os.path.basename(i.filepath) == filename]
    if imgs:
        return imgs[0]
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = (
        "Non-Color" if ("Normal" in filename or "normal" in filename
                        or "Metalness" in filename or "metallic" in filename
                        or "Roughness" in filename or "roughness" in filename
                        or "_AO" in filename) else "sRGB")
    return img


def _ensure_principled(mat):
    if not mat.use_nodes:
        mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return nt, bsdf


def _wire(nt, bsdf, image, socket_name, is_normal=False):
    if image is None:
        return
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.location = (-600, -200 * len([n for n in nt.nodes if n.type == "TEX_IMAGE"]))
    if is_normal:
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.location = (-300, tex.location.y)
        nt.links.new(tex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    else:
        nt.links.new(tex.outputs["Color"], bsdf.inputs[socket_name])


def wire_station1(tex_dir):
    for mat in bpy.data.materials:
        if mat.users == 0 or mat.name == "Dots Stroke":
            continue
        nt, bsdf = _ensure_principled(mat)
        # 先清掉原来接的 Normal Map（FBX 导入时接了个空贴图的）
        for node in list(nt.nodes):
            if node.type == "NORMAL_MAP":
                nt.nodes.remove(node)
        _wire(nt, bsdf, _load_image(tex_dir, STATION1_MAP["baseColor"]),
              "Base Color")
        _wire(nt, bsdf, _load_image(tex_dir, STATION1_MAP["emission"]),
              "Emission Color")
        _wire(nt, bsdf, _load_image(tex_dir, STATION1_MAP["metallic"]),
              "Metallic")
        _wire(nt, bsdf, _load_image(tex_dir, STATION1_MAP["roughness"]),
              "Roughness")
        _wire(nt, bsdf, _load_image(tex_dir, STATION1_MAP["normal"]),
              "Normal", is_normal=True)
        log("  接好材质 %s" % mat.name)


def wire_station3(tex_dir):
    files = os.listdir(tex_dir)

    def find(prefix, kind):
        for f in files:
            if f.startswith(prefix + "_") and kind in f.lower():
                return f
        return None

    for mat in bpy.data.materials:
        if mat.users == 0 or mat.name == "Dots Stroke":
            continue
        prefix = STATION3_PREFIX.get(mat.name)
        if prefix is None:
            # 名字对不上时按前缀猜
            for cand in STATION3_PREFIX.values():
                if mat.name.startswith(cand):
                    prefix = cand
                    break
        if prefix is None:
            log("  ⚠ 材质 %s 找不到对应贴图前缀" % mat.name)
            continue
        nt, bsdf = _ensure_principled(mat)
        _wire(nt, bsdf, _load_image(tex_dir, find(prefix, "albedo")), "Base Color")
        _wire(nt, bsdf, _load_image(tex_dir, find(prefix, "emissive")), "Emission Color")
        _wire(nt, bsdf, _load_image(tex_dir, find(prefix, "metallic")), "Metallic")
        _wire(nt, bsdf, _load_image(tex_dir, find(prefix, "roughness")), "Roughness")
        _wire(nt, bsdf, _load_image(tex_dir, find(prefix, "normal")), "Normal",
              is_normal=True)
        log("  接好材质 %s（前缀 %s）" % (mat.name, prefix))


def apply_textures(slug):
    tex_dir = os.path.join(ROOT, slug, "textures")
    log("挂贴图：%s" % tex_dir)
    if slug == "space-station":
        wire_station1(tex_dir)
    else:
        wire_station3(tex_dir)
    log("  共载入 %d 张图" % len(bpy.data.images))


def stats():
    tris = 0
    verts = 0
    for obj in collect_meshes():
        me = obj.data
        verts += len(me.vertices)
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
    log("网格 %d 个，顶点 %d，三角面 %d" % (len(collect_meshes()), verts, tris))
    return tris


def export(slug):
    out_dir = os.path.join(OUT_ROOT, slug)
    os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
    out = os.path.join(out_dir, "model.glb")
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_image_format="AUTO",
        export_texture_dir="textures",
        export_apply=True,
        use_selection=False,
        export_yup=True,
    )
    log("导出 %s (%.1f MB)" % (out, os.path.getsize(out) / 1048576.0))


def main():
    argv = sys.argv
    slug = argv[argv.index("--") + 1] if "--" in argv else "space-station"
    wipe()
    name = import_source(slug)
    if not name.lower().endswith(".blend"):
        # blend 里可能自带变换，但一样安全：apply 一次
        pass
    apply_transforms()
    normalize_size(slug)
    apply_textures(slug)
    report_materials()
    tris = stats()
    export(slug)
    log("完成：%s，三角面 %d" % (slug, tris))


main()
