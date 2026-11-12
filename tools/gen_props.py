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
