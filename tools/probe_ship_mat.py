# 探针：报告材质里每个贴图接在哪个槽位上（base color / normal / ORM…）。
# 用法： blender --background --python probe_ship_mat.py -- <输入.glb>
import bpy
import sys

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else argv
src = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

print("=== MATERIAL SLOTS ===")
for m in bpy.data.materials:
    print("MATERIAL %s  use_nodes=%s" % (m.name, m.use_nodes))
    if not m.use_nodes:
        continue
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE":
            img = n.image
            # 找出这个贴图连到哪个 Principled 输入
            targets = []
            for out in n.outputs:
                for link in out.links:
                    for inp in link.to_node.inputs:
                        targets.append("%s.%s" % (link.to_node.name, inp.name))
            print("  TEX_IMAGE name=%-12s image=%-10s size=%dx%d -> %s" % (
                n.name, img.name if img else "?",
                img.size[0] if img else 0, img.size[1] if img else 0,
                targets or "(未连接)"))
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            print("  PRINCIPLED inputs:")
            for inp in n.inputs:
                v = ""
                if inp.type == "RGBA" and not inp.is_linked:
                    try:
                        v = " = %s" % (tuple(round(x, 3) for x in inp.default_value),)
                    except Exception:
                        v = ""
                elif inp.is_linked:
                    v = " <- linked"
                print("    %-24s %s" % (inp.name, v))

print("=== IMAGE FILE PATHS ===")
for img in bpy.data.images:
    print("  %-12s %dx%d filepath=%s" % (img.name, img.size[0], img.size[1], img.filepath))
