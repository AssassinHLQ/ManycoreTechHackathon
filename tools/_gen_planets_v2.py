"""批量生成其余九颗星球：Plan B（真实细节）+ 配色呼应星球名字。

继承 v5 成功版青岚星的规格：
  · 单一闭合球面、无独立树石/内部壳层（可着陆前提）
  · 起伏约半径 6%
  · photorealistic 风格、240000 面目标
  · 地形细节：山脊支脉、侵蚀沟、岩层台地、河谷水系、撞击坑缘

只换「配色描述」——每颗按名字取色，避免十颗长得一样、也避免整体灰掉。

用法：
    python tools/_gen_planets_v2.py            # 只打印
    python tools/_gen_planets_v2.py --run      # 提交（花 credits）
"""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parent.parent
WORK = REPO.parent / "_lux3d_work"
CLIENT = Path(r"C:\Users\WY157\.dsh\skills\aholo-lux3d") / "core" / "runtime" / "lux3d_client.py"
CRED = Path(r"C:\Users\WY157\.dsh\credentials\lux3d-cn.env")

# 共用骨架：地形细节部分（与 v5 青岚星一致）
TERRAIN = (
    "One single closed sphere, a whole highly detailed planet seen from outside, round silhouette. "
    "The entire model is ONE continuous watertight globe surface with no separate pieces: "
    "no individual trees, no detached boulders, no props, no structures, no shell inside the sphere. "
    "The sphere surface is richly sculpted with fine continuous terrain detail: mountain ranges with "
    "ridgelines and spurs, winding canyons and erosion gullies, clusters of small rugged peaks, "
    "layered rock strata and terraces, broad valleys, river networks carved into the land, crater rims, "
    "and patches of broken rocky ground, with overall elevation staying within about six percent of "
    "the planet radius so the silhouette remains round. The colouring is {palette}. "
    "The whole planet reads clearly as {identity}, in a vivid saturated palette, not grey and not muddy. "
    "Detailed realistic natural expression, high micro-detail, bright even daylight, subtle surface "
    "shading, no harsh specular highlights, no space background, no stars, planet fills the frame, "
    "orthographic view of a complete round globe."
)

PLANETS = [
    {
        "id": "zheya",
        "name": "赭崖星",
        "palette": (
            "a warm ochre and rust-red cliff world: glowing orange-ochre and burnt sienna rock faces, "
            "deep rust-red canyon walls with sharp ridgelines, warm sand and honey-coloured plateaus, "
            "pale bone-white salt flats in the low basins, dry riverbeds in dusty tan, "
            "and only thin cool grey shadows in the deepest crevices"
        ),
        "identity": "a sunbaked ochre and rust-red canyon world",
    },
    {
        "id": "cangbo",
        "name": "沧波星",
        "palette": (
            "a deep sapphire and glacial blue ocean world: vast luminous deep-blue seas, "
            "bright pale cyan ice shelves and frozen tidal cracks, white pack ice drifting on dark water, "
            "soft teal shallows along coastlines, blue-white snow on the highest ridges, "
            "and cool pale blue mist on the horizon"
        ),
        "identity": "a deep sapphire and glacial blue frozen ocean world",
    },
    {
        "id": "xuanjing",
        "name": "悬晶星",
        "palette": (
            "a crystalline violet and cyan mineral world: faceted crystal ridges catching cool violet "
            "and magenta light, glassy pale cyan crystal flats, snowy white crystal shards and sharp "
            "sparkling crests, deep blue-violet shadowed clefts, and thin bright mineral seams glowing "
            "pale cyan across dark slate rock"
        ),
        "identity": "a crystalline violet and cyan mineral world",
    },
    {
        "id": "xuanyuan",
        "name": "玄渊星",
        "palette": (
            "a near-black abyssal world: deep obsidian and dark indigo rock, almost black abyssal plains, "
            "very dark blue-black chasms, and glowing ember-orange and deep crimson fissures and lava "
            "seams running through the dark terrain, with pale ash-grey only on the highest ridge crests"
        ),
        "identity": "a near-black obsidian abyss world with glowing ember fissures",
    },
    {
        "id": "baiyao",
        "name": "白曜星",
        "palette": (
            "a radiant white and pale silver world: brilliant chalk-white plains and bright snowfields, "
            "pale silver-grey rock ridges, luminous white ice with soft pale-blue shadowed hollows, "
            "delicate frost grooves catching light, and a clean cool white glow over the whole surface"
        ),
        "identity": "a radiant chalk-white and pale silver ice world",
    },
    {
        "id": "pansha",
        "name": "磐砂星",
        "palette": (
            "a warm sand and stone world: broad golden ochre dune seas, long wind-carved sand ridges, "
            "warm honey and straw-yellow sand, exposed dark umber bedrock bands and slabby rock mesas, "
            "dry pale dust basins, and warm amber light across the dunes"
        ),
        "identity": "a warm golden sand and rock mesa world",
    },
    {
        "id": "taiyuan",
        "name": "苔垣星",
        "palette": (
            "a mossy green and stone-grey world: deep saturated moss and emerald tundra lowlands, "
            "vivid green cushion vegetation, pale sage and lichen patches, weathered grey stone terrace "
            "walls and slabby rock escarpments, thin pale misty lakes, and cool damp green mist in the valleys"
        ),
        "identity": "a lush moss-green tundra world with grey stone terraces",
    },
    {
        "id": "liuwu",
        "name": "硫坞星",
        "palette": (
            "a vivid sulphur yellow-green world: bright acid yellow and chartreuse mineral plains, "
            "pale creamy sulphur crust rims, turquoise-green shallow acidic pools, dark basalt ridges, "
            "and warm ochre-yellow dust, with sulfur vents ringed in pale mineral bloom"
        ),
        "identity": "a vivid sulphur yellow-green mineral world",
    },
    {
        "id": "jianmo",
        "name": "缄默星",
        "palette": (
            "a silent deep violet-black obsidian world: very dark purple-black glass plains, "
            "deep indigo and violet shadowed basins, faint cold magenta sheen along polished ridges, "
            "dark plum rock, and only a very small amount of pale grey on the highest crests, "
            "brooding and almost colourless except for the violet depth"
        ),
        "identity": "a silent violet-black obsidian world",
    },
]


def load_key() -> str:
    for line in CRED.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip().startswith("LUX3D_CN_API_KEY"):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("没有 LUX3D_CN_API_KEY")


def main() -> None:
    run = "--run" in sys.argv
    env = dict(os.environ)
    env["LUX3D_CN_API_KEY"] = load_key()
    out_root = REPO / "assets" / "models"

    for p in PLANETS:
        pid = p["id"]
        prompt = TERRAIN.format(palette=p["palette"], identity=p["identity"])
        dest_dir = out_root / f"{pid}-lux3d-v2"
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / "model.glb"
        print("=" * 72)
        print(f"{pid}（{p['name']}）-> {dest}")
        if not run:
            print("  palette:", p["palette"][:120], "…")
            continue
        if dest.exists() and dest.stat().st_size > 200_000:
            print("  已存在，跳过")
            continue
        cmd = [
            sys.executable, str(CLIENT), "--region", "cn",
            "text", prompt, str(dest_dir / "model"),
            "--style", "photorealistic", "--version", "G1-Turbo",
            "--face-count", "240000", "--format", "glb",
            "--enable-pbr", "--no-ai-predict-size",
            "--interval", "10", "--max-attempts", "90",
        ]
        r = subprocess.run(cmd, env=env, capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        print(((r.stdout or "") + (r.stderr or ""))[-300:])
        got = list(dest_dir.glob("*.glb"))
        print(f"  {'✓ ' + got[0].name + ' ' + format(got[0].stat().st_size/1e6, '.2f') + ' MB' if got else '✗ 没有产出'}")


if __name__ == "__main__":
    main()
