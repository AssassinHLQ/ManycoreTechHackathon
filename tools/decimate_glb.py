# Blender 无头减面：把 GLB 里的网格按比例减面（Decimate COLLAPSE），再写回 GLB。
# 用法：blender.exe -b --python decimate_glb.py -- <ratio> <glb1> <glb2> ...
import bpy
import os
import sys

argv = sys.argv
args = argv[argv.index("--") + 1:] if "--" in argv else []
ratio = float(args[0]) if args else 0.5
paths = args[1:]

print("DECIMATE ratio=%.2f files=%d" % (ratio, len(paths)), flush=True)
ok = 0
fail = 0
for path in paths:
    try:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        before = 0
        after = 0
        for obj in list(bpy.context.scene.objects):
            if obj.type != "MESH":
                continue
            tris = len(obj.data.polygons)
            before += tris
            if tris < 1200:
                continue   # 太小的网格不折腾，避免破坏轮廓
            mod = obj.modifiers.new(name="Decimate", type="DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = ratio
            mod.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_apply(modifier=mod.name)
            after += len(obj.data.polygons)
        size_before = os.path.getsize(path)
        tmp = path + ".tmp.glb"
        bpy.ops.export_scene.gltf(
            filepath=tmp,
            export_format="GLB",
            export_image_format="AUTO",
            export_yup=True,
        )
        os.replace(tmp, path)
        size_after = os.path.getsize(path)
        print("DECIMATED %s  tris %d -> %d  size %.2f -> %.2f MB" % (
            os.path.basename(os.path.dirname(path)), before, after,
            size_before / 1048576.0, size_after / 1048576.0), flush=True)
        ok += 1
    except Exception as exc:
        print("FAILED %s: %s" % (path, exc), flush=True)
        fail += 1
        if os.path.exists(path + ".tmp.glb"):
            os.remove(path + ".tmp.glb")

print("DONE ok=%d fail=%d" % (ok, fail), flush=True)
