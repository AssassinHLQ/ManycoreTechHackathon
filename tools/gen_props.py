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
