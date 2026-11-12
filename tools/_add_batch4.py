# -*- coding: utf-8 -*-
"""第四批：36 个资产（互动物品 12 + 通用装饰 16 + 大型地貌 8）。

用户 2026-11-12：「限制降低到 300」—— 额度红线从 1000 降到 300，
可用额度从 61 变成 735，可以继续生成。

36 x 13 = 468 credits（g1-turbo 单价 13），完成后余额约 567，仍高于 300 红线。
"""
import io

P = r"tools\gen_props.py"
s = io.open(P, encoding="utf-8").read()
o = s

TAIL = "no ground plane, no pedestal, no base, no text, no backdrop"

INTERACTIVE = [
    ("power-cell", 24000,
     "stacked power cell module, three ribbed cylindrical batteries in a metal "
     "frame with glowing indicator strips"),
    ("control-console", 26000,
     "freestanding control console, angled panel with rows of small buttons "
     "and a blank dark screen on a single pedestal"),
    ("stasis-pod", 26000,
     "upright stasis pod, frosted glass cylinder with a metal base and hinged "
     "clamp ring, interior faintly lit"),
    ("signal-beacon", 24000,
     "signal beacon post, slender mast with a pyramidal lamp head and three "
     "small antenna rods"),
    ("mining-rig", 28000,
     "small mining rig, drill head mounted on a tripod frame with hydraulic "
     "arms and a hopper bin"),
    ("fuel-tank", 24000,
     "fuel storage tank, horizontal capsule tank on two saddle stands with a "
     "valve wheel and pipe stub"),
    ("holo-slab", 26000,
     "holographic slab, upright dark glass panel in a rough stone frame with "
     "faint concentric etchings"),
    ("supply-crate", 22000,
     "supply crate, reinforced box with hinged lid, corner brackets and a "
     "stenciled stripe"),
    ("pipe-cluster", 22000,
     "cluster of industrial pipes, three bent conduits with flanges and a "
     "junction valve box"),
    ("comm-dish", 24000,
     "communication dish, small parabolic dish on a braced tripod mount with "
     "a feed horn at the focus"),
    ("thermal-stack", 24000,
     "thermal exhaust stack, tall vent tower with louvered slats and a rusted "
     "flare crown"),
    ("databank", 24000,
     "data bank terminal, squat cabinet with a slanted screen and two rows of "
     "small status lights"),
]

DECOR = [
    ("bone-fossil", 22000,
     "exposed fossil bones, curved rib cage half buried in rock with a spine "
     "segment and scattered vertebrae"),
    ("stone-cairn", 18000,
     "stacked stone cairn, five flat rocks balanced into a tapering pile, "
     "weathered and lichen speckled"),
    ("mossy-boulder", 18000,
     "large mossy boulder, rounded rock with thick green moss patches and "
     "small ferns at its base"),
    ("icicle-cluster", 18000,
     "cluster of icicles, hanging frozen spikes of different lengths under a "
     "broken rock lip"),
    ("dune-grass", 16000,
     "dry dune grass tufts, sparse clumps of thin pale blades bent by wind"),
    ("ore-scrap", 18000,
     "heap of ore scrap, angular metallic chunks and slag lumps mixed together"),
    ("rail-segment", 20000,
     "broken rail segment, short length of rusted track with two sleepers and "
     "bent spikes"),
    ("banner-pole", 20000,
     "tattered banner pole, leaning metal pole with a torn cloth strip hanging "
     "from the crossbar"),
    ("rope-coil", 16000,
     "coiled rope on the ground, thick weathered line wound into a loose ring "
     "beside a wooden peg"),
    ("plank-walkway", 20000,
     "short plank walkway, two narrow boards laid across support blocks with "
     "worn edges"),
    ("gravel-pile", 16000,
     "pile of loose gravel and small stones, scattered rubble mound with mixed "
     "grain sizes"),
    ("rusted-hull", 24000,
     "rusted hull plate fragment, torn curved metal panel with rivets and a "
     "few missing sections"),
    ("glass-shards", 18000,
     "heap of broken glass shards, sharp translucent fragments piled in a "
     "shallow scatter"),
    ("twisted-metal", 22000,
     "twisted metal wreckage, bent beams and sheared plate tangled into a "
     "low heap"),
    ("dead-shrub", 18000,
     "small dead shrub, dry brittle twigs with a few clinging curled leaves"),
    ("bleached-log", 18000,
     "sun bleached fallen log, cracked white wood trunk lying on its side with "
     "broken branch stubs"),
]

LANDFORM = [
    ("lf-crater-rim", 26000,
     "crater rim ridge, raised circular ridge of ejected rock around a shallow "
     "bowl, radial fractures on the outer slope"),
    ("lf-dry-riverbed", 26000,
     "dry riverbed channel, winding bed of rounded stones between low banks "
     "with undercut edges"),
    ("lf-glacier-wall", 26000,
     "glacier ice wall, tall blue frozen face with vertical fracture lines and "
     "a moraine of debris at its foot"),
    ("lf-boulder-field", 26000,
     "field of scattered boulders, dozens of rounded rocks of mixed sizes "
     "strewn across open ground"),
    ("lf-cliff-terraces", 26000,
     "stepped cliff terraces, three stacked rock ledges with flat tops and "
     "rubble slopes between them"),
    ("lf-sinkhole", 26000,
     "sinkhole depression, collapsed circular pit with cracked overhanging rim "
     "and rubble on the floor"),
    ("lf-lava-flow", 24000,
     "hardened lava flow, ropy black basalt surface with cracked cooled crust "
     "and a raised channel"),
    ("lf-salt-flat", 24000,
     "salt crust expanse, cracked polygonal white crust plates lifting at the "
     "seams"),
]


def fmt(items):
    return "\n".join('    ("%s", %d,\n     "%s, %s"),' % (pid, f, d, TAIL)
                     for pid, f, d in items)


idx = s.rfind("PROPS += [")
assert idx > 0, "no anchor"
block = ("\n# \u2500\u2500 \u7b2c\u56db\u6279\uff1a\u4e92\u52a8\u7269\u54c1 + \u901a\u7528\u88c5\u9970 + \u5927\u578b\u5730\u8c8c "
         "(36 \u4e2a) \u2500\u2500\n"
         "PROPS += [\n" + fmt(INTERACTIVE) + "\n]\n\n"
         "PROPS += [\n" + fmt(DECOR) + "\n]\n\n"
         "PROPS += [\n" + fmt(LANDFORM) + "\n]\n")
s = s[:idx] + block + s[idx:]

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
total = len(INTERACTIVE) + len(DECOR) + len(LANDFORM)
print("added %d assets (interactive %d / decor %d / landform %d)" % (
    total, len(INTERACTIVE), len(DECOR), len(LANDFORM)))
