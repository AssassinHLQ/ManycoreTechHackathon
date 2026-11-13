# -*- coding: utf-8 -*-
"""批量用 Lux3D 生成星球道具资产。

用法（在仓库根目录）：
    python tools/gen_props.py            # 生成全部缺失的
    python tools/gen_props.py --only tree,ruin-arch
    python tools/gen_props.py --list

每个资产：assets/models/props/<id>/model.glb
已存在 model.glb 的会跳过（可断点续跑）。
"""
import argparse
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILL = os.path.join(os.environ["USERPROFILE"], ".dsh", "skills", "aholo-lux3d")
CLIENT = os.path.join(SKILL, "core", "runtime", "lux3d_client.py")
CREDS = os.path.join(os.environ["USERPROFILE"], ".dsh", "credentials", "lux3d-cn.env")
OUT_ROOT = os.path.join(REPO, "assets", "models", "props")

# 统一要求：单一物体、无底座、中性色（方便按星球调色）、PBR。
TAIL = ("desaturated neutral tones so it can be recoloured per planet, "
        "game-ready environment prop, single isolated object, "
        "no ground plane, no pedestal, no base, no text, no backdrop")

PROPS = [
    # ── 植物 ─────────────────────────────────────────────
    ("alien-tree", 30000,
     "alien umbrella tree, tall slender pale trunk branching high into a wide "
     "flat mushroom-shaped canopy of overlapping plates"),
    # ── 岩石地形 ─────────────────────────────────────────
    ("rock-cluster", 24000,
     "cluster of large weathered boulders, layered sedimentary strata, rounded "
     "eroded edges, three to five interlocking stones of different sizes"),
    ("rock-spire", 26000,
     "tall sharp obsidian rock spire, faceted volcanic shard column, jagged "
     "vertical ridges, broken fractured top"),
    # ── 遗迹 / 人造 ───────────────────────────────────────
    ("ruin-arch", 26000,
     "ancient stone archway ruin, weathered carved blocks, half collapsed "
     "lintel, thin alien glyph bands cut into the pillars"),
    ("obelisk", 26000,
     "slender monolithic obelisk of dark stone, tapered four-sided shaft, "
     "glowing etched runes running vertically, small stepped plinth top"),
    ("dome-habitat", 30000,
     "small abandoned dome habitat, ribbed geodesic shell of pale panels, "
     "one open hatch doorway, antenna stub on top, weathered seams"),
    ("signal-tower", 28000,
     "tall thin signal relay tower, lattice truss mast with three horizontal "
     "ring platforms, small dish and blinking beacon at the summit"),
    # ── 特殊点 ───────────────────────────────────────────
    ("crystal-cluster", 24000,
     "cluster of tall glowing crystal shards growing from stone, sharp "
     "hexagonal prisms at varied angles, translucent interior"),
    ("vent", 22000,
     "volcanic fumarole vent, cracked rock crater rim with glowing fissures "
     "and ash crust, small chimney of fused stone"),
    ("floating-rock", 24000,
     "levitating fractured rock island, layered stone chunk with hanging "
     "stalactites underneath, slight tilt, broken edges"),
]

# ── 低模变体：专门用来「铺量」（MultiMesh 实例化） ──
# 高模一个 2~3 万面，铺几百个会直接把显卡干掉；这些控制在 2 千面左右，
# 只保留剪影和主要结构，贴图仍然是 Lux3D 生成的。

# ── 第二批：每星球专属地标 + 通用环境物件 + 大地貌件 ──
# 用户 2026-11-12：「怎么才 39，太少了」。
# 36 个 × 13 credits = 468，花完余额 2182（1000 红线下方仍有余量）。
PROPS += [
    ("lm-qinglan", 30000,
     "stone village cluster, three small round stone houses with slate roofs beside one tall slender observatory tower with open arch windows, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-zheya", 28000,
     "broken ring observation station, half collapsed circular steel gantry tilted on a salt flat, snapped trusses and a dangling platform, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-cangbo", 26000,
     "polar research station on ice, ribbed dome habitat raised on four legs with a wind turbine and a fenced instrument yard, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-xuanjing", 28000,
     "crashed orbital ring segment, torn curved metal hull arc half buried in rock, exposed ribs and broken window strips, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-xuanyuan", 26000,
     "colossal black monolith gate, two towering polished slabs facing each other with a dark void between, thin glowing seam lines, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-baiyao", 26000,
     "forest of ice spires, translucent blue crystal towers of varied height clustered on a chalk plain, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-pansha", 26000,
     "field of tall eroded hoodoo pillars in a sand basin, mushroom-capped sandstone columns of different heights, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-taiyuan", 26000,
     "low stone wall labyrinth, mossy dry stone walls forming a spiral maze on a grassy flat, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-liuwu", 28000,
     "abandoned starship drydock, skeletal steel gantry frame with docking clamps and a fallen crane arm, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-jianmo", 26000,
     "row of tall dark monoliths arranged in an arc, smooth obsidian standing stones of slightly different heights, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-jiangxiao", 26000,
     "red iron mesa plateau with layered horizontal cliffs and a deep mine cut into one face, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-cangwu", 28000,
     "giant emerald trees grove, huge buttressed trunks with wide layered canopies, mossy root fans, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-jinwu", 24000,
     "white salt pan with cracked polygonal crust and a dead beacon tower leaning at its edge, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-yuheng", 24000,
     "quartz vein outcrop, a giant milky white crystal seam splitting a rock terrace, sharp protruding veins, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-sue", 24000,
     "ring of pale stone posts around a shallow crater, evenly spaced square monolith stubs on bare regolith, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-danxia", 26000,
     "striped sandstone terraces, stepped layered rock fins in red and ochre bands rising in tiers, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-biluo", 24000,
     "white coral atoll ring around a shallow lagoon, low broken reef rim with a few raised coral heads, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-youdu", 26000,
     "glacier tongue of blue ice spilling from a dark rock cleft, glowing interior lights deep inside the ice, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-yaoguang", 26000,
     "vast crystal spine ridge, mirrored facets pointing downward from an arching crystal formation, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm-xuanpu", 24000,
     "dark violet rock terrace with glowing green moss patches creeping over stepped slabs, no ground plane, no pedestal, no base, no text, no backdrop"),
]

PROPS += [
    ("alien-mushroom", 20000,
     "cluster of glowing alien mushrooms, tall thin stems with wide luminous caps of different sizes, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("dead-tree", 20000,
     "bare twisted dead tree, skeletal branching trunk with no leaves, weathered bleached wood, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("thorn-shrub", 18000,
     "low alien thorn shrub, dense tangle of spiky gray-green branches with small hard leaves, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("crystal-flora", 18000,
     "small crystal plants, thin faceted translucent shards growing in a low cluster like grass, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("ice-spike", 18000,
     "cluster of sharp ice shards, translucent splintered frozen spikes of varied height, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("dune-arch", 22000,
     "weathered sandstone arch, a single curved eroded rock bridge with a narrow opening underneath, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cargo-pod", 20000,
     "crashed cargo container pod, dented rectangular hull half sunk in soil, one hatch torn open, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("antenna-mast", 22000,
     "small relay antenna mast, thin lattice pole with three short crossbars and a small dish, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("stone-idol", 22000,
     "weathered stone idol statue, squat carved figure with a blank oval face and folded arms, heavily eroded, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("rubble-wall", 20000,
     "broken stone wall segment, collapsed masonry with missing blocks and rubble at the base, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lava-boulder", 18000,
     "porous volcanic boulder cluster, dark pitted rock chunks with sharp fracture faces, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("geyser-basin", 20000,
     "small geyser basin, shallow mineral terrace pool with a raised sinter rim and steam vent, no ground plane, no pedestal, no base, no text, no backdrop"),
]

PROPS += [
    ("lf-canyon-wall", 26000,
     "sheer canyon wall, tall vertical stratified cliff face with eroded vertical fluting and a talus slope at the base, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-natural-arch", 24000,
     "massive natural rock arch, thick weathered stone bridge spanning a wide gap, smooth eroded underside, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-mesa-plateau", 24000,
     "flat topped mesa plateau, steep layered cliffs rising to a broad flat summit with a ragged rim, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-ridge-spine", 24000,
     "jagged mountain ridge spine, a long row of sharp rock peaks along a single crest line with eroded gullies, no ground plane, no pedestal, no base, no text, no backdrop"),
]

# 第三批：8 个低模变体，专供铺量混排
PROPS += [
    ("alien-mushroom-lo", 10000,
     "cluster of glowing alien mushrooms, thin stems with wide luminous caps, low detail silhouette only, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("dead-tree-lo", 10000,
     "bare twisted dead tree, skeletal branching trunk, low detail silhouette only, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("thorn-shrub-lo", 10000,
     "low alien thorn shrub, dense spiky branches, low detail silhouette only, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("crystal-flora-lo", 10000,
     "small crystal shards growing in a low cluster like grass, low detail silhouette only, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("ice-spike-lo", 10000,
     "cluster of sharp ice shards of varied height, low detail silhouette only, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lava-boulder-lo", 10000,
     "porous volcanic boulder chunks, low detail silhouette only, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("dune-arch-lo", 10000,
     "weathered sandstone arch with a narrow opening underneath, low detail silhouette only, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cargo-pod-lo", 10000,
     "crashed cargo container pod half sunk in soil, low detail silhouette only, no ground plane, no pedestal, no base, no text, no backdrop"),
]

# ── 第四批：互动物品 + 通用装饰 + 大型地貌 (36 个) ──
PROPS += [
    ("power-cell", 24000,
     "stacked power cell module, three ribbed cylindrical batteries in a metal frame with glowing indicator strips, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("control-console", 26000,
     "freestanding control console, angled panel with rows of small buttons and a blank dark screen on a single pedestal, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("stasis-pod", 26000,
     "upright stasis pod, frosted glass cylinder with a metal base and hinged clamp ring, interior faintly lit, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("signal-beacon", 24000,
     "signal beacon post, slender mast with a pyramidal lamp head and three small antenna rods, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mining-rig", 28000,
     "small mining rig, drill head mounted on a tripod frame with hydraulic arms and a hopper bin, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("fuel-tank", 24000,
     "fuel storage tank, horizontal capsule tank on two saddle stands with a valve wheel and pipe stub, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("holo-slab", 26000,
     "holographic slab, upright dark glass panel in a rough stone frame with faint concentric etchings, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("supply-crate", 22000,
     "supply crate, reinforced box with hinged lid, corner brackets and a stenciled stripe, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("pipe-cluster", 22000,
     "cluster of industrial pipes, three bent conduits with flanges and a junction valve box, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("comm-dish", 24000,
     "communication dish, small parabolic dish on a braced tripod mount with a feed horn at the focus, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("thermal-stack", 24000,
     "thermal exhaust stack, tall vent tower with louvered slats and a rusted flare crown, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("databank", 24000,
     "data bank terminal, squat cabinet with a slanted screen and two rows of small status lights, no ground plane, no pedestal, no base, no text, no backdrop"),
]

PROPS += [
    ("bone-fossil", 22000,
     "exposed fossil bones, curved rib cage half buried in rock with a spine segment and scattered vertebrae, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("stone-cairn", 18000,
     "stacked stone cairn, five flat rocks balanced into a tapering pile, weathered and lichen speckled, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mossy-boulder", 18000,
     "large mossy boulder, rounded rock with thick green moss patches and small ferns at its base, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("icicle-cluster", 18000,
     "cluster of icicles, hanging frozen spikes of different lengths under a broken rock lip, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("dune-grass", 16000,
     "dry dune grass tufts, sparse clumps of thin pale blades bent by wind, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("ore-scrap", 18000,
     "heap of ore scrap, angular metallic chunks and slag lumps mixed together, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("rail-segment", 20000,
     "broken rail segment, short length of rusted track with two sleepers and bent spikes, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("banner-pole", 20000,
     "tattered banner pole, leaning metal pole with a torn cloth strip hanging from the crossbar, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("rope-coil", 16000,
     "coiled rope on the ground, thick weathered line wound into a loose ring beside a wooden peg, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("plank-walkway", 20000,
     "short plank walkway, two narrow boards laid across support blocks with worn edges, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("gravel-pile", 16000,
     "pile of loose gravel and small stones, scattered rubble mound with mixed grain sizes, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("rusted-hull", 24000,
     "rusted hull plate fragment, torn curved metal panel with rivets and a few missing sections, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("glass-shards", 18000,
     "heap of broken glass shards, sharp translucent fragments piled in a shallow scatter, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("twisted-metal", 22000,
     "twisted metal wreckage, bent beams and sheared plate tangled into a low heap, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("dead-shrub", 18000,
     "small dead shrub, dry brittle twigs with a few clinging curled leaves, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("bleached-log", 18000,
     "sun bleached fallen log, cracked white wood trunk lying on its side with broken branch stubs, no ground plane, no pedestal, no base, no text, no backdrop"),
]

PROPS += [
    ("lf-crater-rim", 26000,
     "crater rim ridge, raised circular ridge of ejected rock around a shallow bowl, radial fractures on the outer slope, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-dry-riverbed", 26000,
     "dry riverbed channel, winding bed of rounded stones between low banks with undercut edges, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-glacier-wall", 26000,
     "glacier ice wall, tall blue frozen face with vertical fracture lines and a moraine of debris at its foot, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-boulder-field", 26000,
     "field of scattered boulders, dozens of rounded rocks of mixed sizes strewn across open ground, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-cliff-terraces", 26000,
     "stepped cliff terraces, three stacked rock ledges with flat tops and rubble slopes between them, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-sinkhole", 26000,
     "sinkhole depression, collapsed circular pit with cracked overhanging rim and rubble on the floor, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-lava-flow", 24000,
     "hardened lava flow, ropy black basalt surface with cracked cooled crust and a raised channel, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-salt-flat", 24000,
     "salt crust expanse, cracked polygonal white crust plates lifting at the seams, no ground plane, no pedestal, no base, no text, no backdrop"),
]

# ── 第五批：互动机器 + 生态装饰 + 大型地貌 (18 个) ──
PROPS += [
    ("med-station", 26000,
     "field medical station, upright cabinet with a cross panel, two small drawers and a rolled stretcher leaning beside it, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("oxygen-generator", 26000,
     "oxygen generator unit, ribbed drum with intake vents, pressure gauge and a hose coiled on top, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("ore-crusher", 28000,
     "ore crusher machine, heavy hopper feeding two toothed rollers on a bolted steel frame with an output chute, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("holo-terminal", 26000,
     "hologram terminal, angled plinth projecting a floating stack of thin glowing rings above a small screen, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("wind-turbine", 24000,
     "small wind turbine, three-bladed rotor on a lattice tower with a guy wire and a control box at the base, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("landing-beacon", 26000,
     "landing beacon pylon, squat tower with four outward floodlights and a flat painted top plate, no ground plane, no pedestal, no base, no text, no backdrop"),
]

PROPS += [
    ("crystal-vein", 20000,
     "crystal vein outcrop, a jagged seam of translucent shards splitting a low rock shelf, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("frozen-pond", 20000,
     "small frozen pond, cracked ice sheet in a shallow rock basin with white frost rims, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("sand-ripple", 18000,
     "wind carved sand ripples, parallel wave ridges across a low dune surface, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("alien-mound", 22000,
     "alien termite mound, tall twisted spire of packed earth with ridges and small dark openings, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lava-drip", 20000,
     "cooled lava drips, frozen black tendrils hanging from a broken rock lip with glassy tips, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("coral-stack", 20000,
     "coral stack formation, branching pale coral growths clustered into a low column, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mushroom-ring", 18000,
     "fairy mushroom ring, a circle of small glowing mushrooms on bare ground, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("glass-crater", 22000,
     "vitrified crater, small impact bowl with slick fused glass lining and radiating cracks, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("bone-yard", 22000,
     "bone yard scatter, tangled ribs and long limb bones half buried in dust, no ground plane, no pedestal, no base, no text, no backdrop"),
]

PROPS += [
    ("lf-mesa-spire", 26000,
     "mesa spire, tall isolated rock tower with a flat top and vertical eroded fluting along its sides, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-dune-sea", 26000,
     "dune sea, long parallel sand ridges with sharp crests stretching across the ground, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lf-crystal-forest", 26000,
     "crystal forest, a dense stand of tall angular translucent crystal columns of mixed heights, no ground plane, no pedestal, no base, no text, no backdrop"),
]

# ── 批六：外星生物（先做 2 个，额度有限）──
PROPS += [
    ("creature-grazer", 26000,
     "alien grazing beast, four thick legs, low heavy body with a ridged back and a small blunt head lowered to feed, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-tall-walker", 28000,
     "tall alien walker, slender three metre legs, compact body and a long narrow head on a curved neck, no ground plane, no pedestal, no base, no text, no backdrop"),
]

# ── 批六二期：20 个第二地标 + 3 个生物（23 个）──
PROPS += [
    ("lm2-qinglan", 26000,
     "weathered stone watchpost, three storey square tower with a shingled roof and a wooden signal platform on top, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-zheya", 26000,
     "salt crusted survey mast, leaning lattice tower with a rusted drum antenna and frayed guy wires, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-cangbo", 26000,
     "ice core drilling rig, braced derrick over a bored shaft with a coiled cable spool and heated control hut, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-xuanjing", 26000,
     "orbital debris shrine, ring of bent hull plates arranged upright around a fused engine core, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-xuanyuan", 26000,
     "black stone causeway, raised road of polished slabs leading into a narrow gap between two rock walls, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-baiyao", 24000,
     "frozen geode arch, split crystal geode forming a natural doorway with pale blue interior facets, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-pansha", 24000,
     "buried caravan frame, half exposed skeletal wagon frame and cargo boxes under a dune lip, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-taiyuan", 24000,
     "overgrown garden terrace, stepped stone planting beds with tangled frosted shrubs, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-liuwu", 26000,
     "collapsed gantry crane, toppled steel crane lying across a loading bay with snapped cables, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-jianmo", 24000,
     "silent bell tower, open stone tower holding a huge cracked bell on a rusted yoke, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-jiangxiao", 26000,
     "open pit mine head, timber framed shaft mouth with a winch drum and spoil heap, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-cangwu", 26000,
     "hollow giant stump, enormous felled tree base with a carved doorway and climbing roots, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-jinwu", 24000,
     "dry salt well, stone rimmed well in cracked salt crust with a broken windlass, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-yuheng", 24000,
     "quartz cutting floor, terraced stone yard with embedded white veins and a stone saw frame, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-sue", 24000,
     "crater observatory ring, low circular wall of dressed stones around a shallow bowl with marker posts, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-danxia", 26000,
     "striped rock bridge, thick banded sandstone arch spanning a gully with stepped abutments, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-biluo", 24000,
     "tidal shrine, low white coral platform with a shallow reflecting basin and bone wind chimes, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-youdu", 26000,
     "ice cave mouth, blue frozen overhang framing a dark opening with hanging icicle teeth, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-yaoguang", 26000,
     "mirror shard monument, tall thin mirrored slab tilted on a crystal plinth reflecting the ground, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lm2-xuanpu", 24000,
     "moss terrace altar, low stone platform covered in glowing green moss with crude offering stones, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-glider", 24000,
     "alien gliding creature, wide thin membrane wings stretched between long finger bones, small streamlined body, perched with wings folded up, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-burrower", 26000,
     "alien burrowing creature, armoured segmented body emerging from a mound with two broad digging claws, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-ruin-guardian", 30000,
     "ancient ruin guardian construct, tall faceted stone body with a hollow glowing chest core and segmented arms, no ground plane, no pedestal, no base, no text, no backdrop"),
]

# ── 批六收尾：窟穴陈设 + 其余生物 + 植被 + 模块化建筑件 ──
PROPS += [
    ("cave-stalagmite", 22000,
     "cave stalagmite, tall tapered mineral column rising from a cave floor with rippled flowstone surface, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-stalactite", 22000,
     "cave stalactite cluster, several downward tapering mineral spikes hanging from a rock ceiling, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-crystal-cluster", 24000,
     "underground crystal cluster, large pale crystals growing out of wet cave rock with glowing tips, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-mine-cart", 26000,
     "abandoned mine cart, rusted metal box on four iron wheels with a broken handle and ore spilling over the rim, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-elevator", 28000,
     "cave lift platform, square metal cage with guide rails and a hanging cable, open front, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-lantern", 20000,
     "mining lantern on a post, caged glass lamp with a warm glowing core mounted on a bent iron stake, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-altar", 26000,
     "underground stone altar, squat carved block with a shallow basin and faint spiral etching, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-pillar", 24000,
     "cave pillar, thick natural rock column connecting floor and ceiling with eroded fluted sides, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-lake-stone", 22000,
     "underground lake stones, cluster of smooth wet boulders in shallow dark water with pale mineral rims, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-bridge", 26000,
     "natural cave bridge, narrow stone span across a chasm with rough broken edges, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-fossil-wall", 24000,
     "fossil bearing cave wall, slab of layered rock with large embedded bone shapes and shell impressions, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("cave-rail", 22000,
     "mine rail track, short curved length of narrow gauge track with wooden sleepers and rusted spikes, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-beetle-swarm", 24000,
     "cluster of large alien beetles, three chitinous oval bodies with ridged carapaces and short antennae gathered on the ground, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-crystal-crawler", 26000,
     "crystal shelled crawler, low six legged body covered in translucent faceted plates with faint inner glow, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-glow-jelly", 24000,
     "floating glow jelly, translucent bell with long trailing tendrils, hovering above the ground, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-pack-hound", 26000,
     "alien pack hound, lean quadruped with a narrow wedge head, raised shoulder spines and a whip tail, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-spore-drifter", 22000,
     "spore drifter organism, rounded puffed body trailing thin filaments, floating low over the ground, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-ice-herd", 26000,
     "ice adapted herd beast, shaggy pale body with broad flat feet and curved brow horns, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("creature-lava-mite", 22000,
     "lava mite, small squat creature with a cracked glowing carapace and short stiff legs, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("fern-cluster", 18000,
     "alien fern cluster, arching fronds with fine divided leaflets rising from a central crown, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("vine-drape", 18000,
     "hanging vine drape, dense curtain of thin vines with small leaves falling from a rock lip, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("moss-mat", 16000,
     "moss mat patch, low dense cushion of soft moss with tiny pale cups, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("spore-pod", 18000,
     "spore pod plant, bulbous hollow pods on thin stalks with split seams leaking fine dust, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("giant-fungus", 22000,
     "giant fungus, massive curved cap on a thick fibrous stalk with shelf growths climbing up, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("grass-plume", 16000,
     "feather grass plume, tall thin stalks topped with pale waving plumes, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("reed-stand", 18000,
     "reed stand, tight cluster of hollow pale reeds with narrow blade leaves, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("bulb-plant", 18000,
     "bulb plant, fat translucent bulb with three wide fleshy leaves splayed outward, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("thorn-vine", 18000,
     "thorn vine tangle, woody climbing stems covered in long pale thorns, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("canopy-shrub", 20000,
     "umbrella canopy shrub, flat disc of foliage held on a single short trunk, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("lichen-rock", 16000,
     "lichen covered rock, low boulder encrusted with flat grey and orange lichen crusts, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("seed-head", 16000,
     "dry seed head plant, branching skeleton of dry stems holding small clusters of seed capsules, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-doorframe", 22000,
     "modular doorway frame, rectangular stone lintel and two jambs sized for a wall opening, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-railing", 20000,
     "modular railing section, three posts joined by two horizontal rails, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-stairs", 22000,
     "modular stair flight, eight straight stone steps between two low side walls, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-tower-top", 22000,
     "modular tower roof, conical shingled cap with an overhanging eave ring, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-platform", 20000,
     "modular platform slab, square stone deck with a raised edge lip, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-archway", 22000,
     "modular archway, single wide stone arch span with voussoir blocks, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-window-panel", 18000,
     "modular window panel, square frame with a grid of narrow light slots, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-ladder", 18000,
     "modular ladder, two vertical rails with eight evenly spaced rungs, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-pipe-run", 20000,
     "modular pipe run, three parallel conduits with flange joints and a support bracket, no ground plane, no pedestal, no base, no text, no backdrop"),
    ("mod-signage", 18000,
     "modular sign board, weathered rectangular plate on two short posts with blank face, no ground plane, no pedestal, no base, no text, no backdrop"),
]
PROPS += [
    ("alien-tree-lo",  10000,
     "alien umbrella tree, slender trunk with a flat mushroom canopy, "
     "low detail silhouette only"),
    ("rock-cluster-lo",  10000,
     "cluster of rounded weathered boulders of varied size, low detail"),
    ("rock-spire-lo",  10000,
     "sharp faceted obsidian spire, low detail"),
    ("crystal-cluster-lo",  10000,
     "cluster of tall glowing crystal shards growing from stone, low detail "
     "silhouette only"),
    ("vent-lo",  10000,
     "volcanic fumarole vent, cracked crater rim with ash crust, low detail "
     "silhouette only"),
    ("stone-bridge",  26000,
     "ancient stone bridge spanning a chasm, two thick pillars, cracked carved "
     "deck with low side walls, weathered alien ruin"),
]

DEV_NAMES = {
    "tree": "伞冠异星树",
    "rock-cluster": "层积巨岩群",
    "rock-spire": "黑曜石尖峰",
    "ruin-arch": "遗迹拱门",
    "obelisk": "符纹方尖碑",
    "dome-habitat": "废弃穹顶居所",
    "signal-tower": "信号中继塔",
    "crystal-cluster": "发光晶簇",
    "vent": "火山喷口",
    "floating-rock": "悬浮碎石岛",
    "alien-tree-lo": "伞冠异星树（低模）",
    "rock-cluster-lo": "层积巨岩群（低模）",
    "rock-spire-lo": "黑曜石尖峰（低模）",
    "crystal-cluster-lo": "发光晶簇（低模）",
    "vent-lo": "火山喷口（低模）",
    "stone-bridge": "古石桥",
}


def load_creds():
    env = dict(os.environ)
    with open(CREDS, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)", line)
            if m:
                env[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    env["PYTHONIOENCODING"] = "utf-8"
    return env


def one(prop_id, faces, desc, env):
    out_dir = os.path.join(OUT_ROOT, prop_id)
    target = os.path.join(out_dir, "model.glb")
    if os.path.isfile(target):
        print("[skip] %s 已存在" % prop_id, flush=True)
        return True
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.join(out_dir, "_gen")
    prompt = desc + ", " + TAIL
    cmd = [
        sys.executable, CLIENT, "--region", "cn", "text", prompt, base,
        "--style", "photorealistic", "--version", "G1-Turbo",
        "--face-count", str(faces), "--format", "glb",
        "--enable-pbr", "--no-ai-predict-size",
    ]
    print("[gen ] %s (%d 面) ..." % (prop_id, faces), flush=True)
    r = subprocess.run(cmd, env=env, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print("[FAIL] %s\n%s\n%s" % (prop_id, r.stdout[-1500:], r.stderr[-1500:]),
              flush=True)
        return False
    produced = base + ".glb"
    if not os.path.isfile(produced):
        print("[FAIL] %s 没产出 glb\n%s" % (prop_id, r.stdout[-800:]), flush=True)
        return False
    os.replace(produced, target)
    print("[ok  ] %s -> %.1f MB" % (prop_id, os.path.getsize(target) / 1048576.0),
          flush=True)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        for pid, faces, desc in PROPS:
            have = os.path.isfile(os.path.join(OUT_ROOT, pid, "model.glb"))
            print("%-16s %-6d %s  %s" % (pid, faces, "有" if have else "缺",
                                         DEV_NAMES.get(pid, "")))
        return

    wanted = set(x.strip() for x in args.only.split(",") if x.strip())
    env = load_creds()
    ok = fail = 0
    for pid, faces, desc in PROPS:
        if wanted and pid not in wanted:
            continue
        if one(pid, faces, desc, env):
            ok += 1
        else:
            fail += 1
    print("\n完成：成功/跳过 %d，失败 %d" % (ok, fail), flush=True)


if __name__ == "__main__":
    main()
