# -*- coding: utf-8 -*-
"""第六批资产规格（66 个）—— 交给持有额度的协作 agent 生成。

用法（对方 agent）：
    1. 把这些条目并入 tools/gen_props.py 的 PROPS 列表（格式一致）
    2. python tools/gen_props.py --only <id1>,<id2>,...
    3. 生成完按「生成后处理」小节收尾（⚠ 降采样后必须删 model.glb 缓存）

预算：66 × 13 = 858 credits（g1-turbo 单价 13），2000 额度用掉不到一半。

设计原则：**只补当前 114 个资产没覆盖的空缺**，不重复已有内容。
  已有：20 个 lm-* 签名地标 / 96 个通用件与 lo 变体 / 15 个大地貌 /
        18 个互动机器 / 25 个装饰 / 6 个基础建筑件
  还没覆盖：星球上没有生物、洞穴里没有专属陈设、植被形态单一、
            每颗星球只有一个地标、建筑无法拼接
"""
import io

TAIL = "no ground plane, no pedestal, no base, no text, no backdrop"

# ── A. 外星生物（12）：星球上现在一只活物都没有 ──
CREATURES = [
    ("creature-grazer", 26000,
     "alien grazing beast, four thick legs, low heavy body with a ridged back "
     "and a small blunt head lowered to feed"),
    ("creature-glider", 24000,
     "alien gliding creature, wide thin membrane wings stretched between long "
     "finger bones, small streamlined body, perched with wings folded up"),
    ("creature-beetle-swarm", 24000,
     "cluster of large alien beetles, three chitinous oval bodies with ridged "
     "carapaces and short antennae gathered on the ground"),
    ("creature-tall-walker", 28000,
     "tall alien walker, slender three metre legs, compact body and a long "
     "narrow head on a curved neck"),
    ("creature-burrower", 26000,
     "alien burrowing creature, armoured segmented body emerging from a mound "
     "with two broad digging claws"),
    ("creature-crystal-crawler", 26000,
     "crystal shelled crawler, low six legged body covered in translucent "
     "faceted plates with faint inner glow"),
    ("creature-glow-jelly", 24000,
     "floating glow jelly, translucent bell with long trailing tendrils, "
     "hovering above the ground"),
    ("creature-pack-hound", 26000,
     "alien pack hound, lean quadruped with a narrow wedge head, raised "
     "shoulder spines and a whip tail"),
    ("creature-ruin-guardian", 30000,
     "ancient ruin guardian construct, tall faceted stone body with a hollow "
     "glowing chest core and segmented arms"),
    ("creature-spore-drifter", 22000,
     "spore drifter organism, rounded puffed body trailing thin filaments, "
     "floating low over the ground"),
    ("creature-ice-herd", 26000,
     "ice adapted herd beast, shaggy pale body with broad flat feet and curved "
     "brow horns"),
    ("creature-lava-mite", 22000,
     "lava mite, small squat creature with a cracked glowing carapace and "
     "short stiff legs"),
]

# ── B. 洞穴陈设（12）：地下世界现在是空的 ──
CAVE = [
    ("cave-stalagmite", 22000,
     "cave stalagmite, tall tapered mineral column rising from a cave floor "
     "with rippled flowstone surface"),
    ("cave-stalactite", 22000,
     "cave stalactite cluster, several downward tapering mineral spikes "
     "hanging from a rock ceiling"),
    ("cave-crystal-cluster", 24000,
     "underground crystal cluster, large pale crystals growing out of wet cave "
     "rock with glowing tips"),
    ("cave-mine-cart", 26000,
     "abandoned mine cart, rusted metal box on four iron wheels with a broken "
     "handle and ore spilling over the rim"),
    ("cave-elevator", 28000,
     "cave lift platform, square metal cage with guide rails and a hanging "
     "cable, open front"),
    ("cave-lantern", 20000,
     "mining lantern on a post, caged glass lamp with a warm glowing core "
     "mounted on a bent iron stake"),
    ("cave-altar", 26000,
     "underground stone altar, squat carved block with a shallow basin and "
     "faint spiral etching"),
    ("cave-pillar", 24000,
     "cave pillar, thick natural rock column connecting floor and ceiling with "
     "eroded fluted sides"),
    ("cave-lake-stone", 22000,
     "underground lake stones, cluster of smooth wet boulders in shallow dark "
     "water with pale mineral rims"),
    ("cave-bridge", 26000,
     "natural cave bridge, narrow stone span across a chasm with rough broken "
     "edges"),
    ("cave-fossil-wall", 24000,
     "fossil bearing cave wall, slab of layered rock with large embedded bone "
     "shapes and shell impressions"),
    ("cave-rail", 22000,
     "mine rail track, short curved length of narrow gauge track with wooden "
     "sleepers and rusted spikes"),
]

# ── C. 每颗星球第二个签名地标（20 个）──
# 当前每球只有 1 个 lm-* 地标，远看还认得出，走近就只剩通用件。
LANDMARK2 = [
    ("lm2-qinglan", 26000,
     "weathered stone watchpost, three storey square tower with a shingled "
     "roof and a wooden signal platform on top"),
    ("lm2-zheya", 26000,
     "salt crusted survey mast, leaning lattice tower with a rusted drum "
     "antenna and frayed guy wires"),
    ("lm2-cangbo", 26000,
     "ice core drilling rig, braced derrick over a bored shaft with a coiled "
     "cable spool and heated control hut"),
    ("lm2-xuanjing", 26000,
     "orbital debris shrine, ring of bent hull plates arranged upright around "
     "a fused engine core"),
    ("lm2-xuanyuan", 26000,
     "black stone causeway, raised road of polished slabs leading into a "
     "narrow gap between two rock walls"),
    ("lm2-baiyao", 24000,
     "frozen geode arch, split crystal geode forming a natural doorway with "
     "pale blue interior facets"),
    ("lm2-pansha", 24000,
     "buried caravan frame, half exposed skeletal wagon frame and cargo boxes "
     "under a dune lip"),
    ("lm2-taiyuan", 24000,
     "overgrown garden terrace, stepped stone planting beds with tangled "
     "frosted shrubs"),
    ("lm2-liuwu", 26000,
     "collapsed gantry crane, toppled steel crane lying across a loading bay "
     "with snapped cables"),
    ("lm2-jianmo", 24000,
     "silent bell tower, open stone tower holding a huge cracked bell on a "
     "rusted yoke"),
    ("lm2-jiangxiao", 26000,
     "open pit mine head, timber framed shaft mouth with a winch drum and "
     "spoil heap"),
    ("lm2-cangwu", 26000,
     "hollow giant stump, enormous felled tree base with a carved doorway and "
     "climbing roots"),
    ("lm2-jinwu", 24000,
     "dry salt well, stone rimmed well in cracked salt crust with a broken "
     "windlass"),
    ("lm2-yuheng", 24000,
     "quartz cutting floor, terraced stone yard with embedded white veins and "
     "a stone saw frame"),
    ("lm2-sue", 24000,
     "crater observatory ring, low circular wall of dressed stones around a "
     "shallow bowl with marker posts"),
    ("lm2-danxia", 26000,
     "striped rock bridge, thick banded sandstone arch spanning a gully with "
     "stepped abutments"),
    ("lm2-biluo", 24000,
     "tidal shrine, low white coral platform with a shallow reflecting basin "
     "and bone wind chimes"),
    ("lm2-youdu", 26000,
     "ice cave mouth, blue frozen overhang framing a dark opening with "
     "hanging icicle teeth"),
    ("lm2-yaoguang", 26000,
     "mirror shard monument, tall thin mirrored slab tilted on a crystal "
     "plinth reflecting the ground"),
    ("lm2-xuanpu", 24000,
     "moss terrace altar, low stone platform covered in glowing green moss "
     "with crude offering stones"),
]

# ── D. 植被补充（12）：现在只有树/蘑菇/棘丛/枯树四种形态 ──
PLANTS = [
    ("fern-cluster", 18000,
     "alien fern cluster, arching fronds with fine divided leaflets rising "
     "from a central crown"),
    ("vine-drape", 18000,
     "hanging vine drape, dense curtain of thin vines with small leaves "
     "falling from a rock lip"),
    ("moss-mat", 16000,
     "moss mat patch, low dense cushion of soft moss with tiny pale cups"),
    ("spore-pod", 18000,
     "spore pod plant, bulbous hollow pods on thin stalks with split seams "
     "leaking fine dust"),
    ("giant-fungus", 22000,
     "giant fungus, massive curved cap on a thick fibrous stalk with shelf "
     "growths climbing up"),
    ("grass-plume", 16000,
     "feather grass plume, tall thin stalks topped with pale waving plumes"),
    ("reed-stand", 18000,
     "reed stand, tight cluster of hollow pale reeds with narrow blade leaves"),
    ("bulb-plant", 18000,
     "bulb plant, fat translucent bulb with three wide fleshy leaves splayed "
     "outward"),
    ("thorn-vine", 18000,
     "thorn vine tangle, woody climbing stems covered in long pale thorns"),
    ("canopy-shrub", 20000,
     "umbrella canopy shrub, flat disc of foliage held on a single short trunk"),
    ("lichen-rock", 16000,
     "lichen covered rock, low boulder encrusted with flat grey and orange "
     "lichen crusts"),
    ("seed-head", 16000,
     "dry seed head plant, branching skeleton of dry stems holding small "
     "clusters of seed capsules"),
]

# ── E. 模块化建筑件（10）：现在建筑是整块的，拼不起来 ──
MODULES = [
    ("mod-doorframe", 22000,
     "modular doorway frame, rectangular stone lintel and two jambs sized for "
     "a wall opening"),
    ("mod-railing", 20000,
     "modular railing section, three posts joined by two horizontal rails"),
    ("mod-stairs", 22000,
     "modular stair flight, eight straight stone steps between two low "
     "side walls"),
    ("mod-tower-top", 22000,
     "modular tower roof, conical shingled cap with an overhanging eave ring"),
    ("mod-platform", 20000,
     "modular platform slab, square stone deck with a raised edge lip"),
    ("mod-archway", 22000,
     "modular archway, single wide stone arch span with voussoir blocks"),
    ("mod-window-panel", 18000,
     "modular window panel, square frame with a grid of narrow light slots"),
    ("mod-ladder", 18000,
     "modular ladder, two vertical rails with eight evenly spaced rungs"),
    ("mod-pipe-run", 20000,
     "modular pipe run, three parallel conduits with flange joints and a "
     "support bracket"),
    ("mod-signage", 18000,
     "modular sign board, weathered rectangular plate on two short posts with "
     "blank face"),
]

GROUPS = [
    ("A 外星生物", CREATURES),
    ("B 洞穴陈设", CAVE),
    ("C 第二地标", LANDMARK2),
    ("D 植被补充", PLANTS),
    ("E 模块化建筑件", MODULES),
]


def main():
    total = sum(len(g[1]) for g in GROUPS)
    print("批次六：%d 个资产，%d credits（单价 13）\n" % (total, total * 13))
    for name, items in GROUPS:
        print("%s：%d 个" % (name, len(items)))
    # 输出可直接粘进 gen_props.py 的代码块
    out = []
    for name, items in GROUPS:
        out.append("\n# ── %s ──" % name)
        for pid, faces, desc in items:
            out.append('    ("%s", %d,\n     "%s, %s"),' % (pid, faces, desc, TAIL))
    print("\n=== 可直接并入 gen_props.py 的 PROPS 条目 ===")
    print("\n".join(out))


if __name__ == "__main__":
    main()
