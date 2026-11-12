"""生成第二批十颗星球（总数变 20）。Plan B 规格：真实地貌 + 名字配色。

与第一批同一套硬约束：单一闭合球面、无独立树石/内部壳层、起伏约 6%、
photorealistic、240000 面目标。只换地形气质与配色。

用法：
    python tools/_gen_planets_v3.py            # 只打印
    python tools/_gen_planets_v3.py --run      # 提交（10 × 13 = 130 credits）
"""
import os
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parent.parent
CLIENT = Path(r"C:\Users\WY157\.dsh\skills\aholo-lux3d") / "core" / "runtime" / "lux3d_client.py"
CRED = Path(r"C:\Users\WY157\.dsh\credentials\lux3d-cn.env")

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
        "id": "chixiao", "name": "赤霄星",
        "palette": (
            "a burning crimson-sky world: deep vermilion and blood-red haematite sand plains, "
            "dark maroon mesa walls and sharp red ridgelines, rust-orange dune seas, "
            "pale pink salt crusts in the low basins, and a hot dusty rose haze over the horizon"
        ),
        "identity": "a burning crimson haematite desert world under a red sky",
    },
    {
        "id": "cangwu", "name": "苍梧星",
        "palette": (
            "a deep jade and ink-green forest world: dark emerald and pine-green canopy texture across "
            "the lowlands, near-black deep green ravines, mossy jade uplands, "
            "silver-grey wet rock on the steepest cliffs, and pale jade mist filling the valleys"
        ),
        "identity": "a deep ink-green and jade rainforest world",
    },
    {
        "id": "jinwu", "name": "金乌星",
        "palette": (
            "a sun-scorched gold and amber world: brilliant golden-amber sand and scorched ochre crust, "
            "deep orange-amber canyon walls, glowing honey-coloured dunes, "
            "white-hot bleached salt pans, and thin dark basalt seams cracking the gold surface"
        ),
        "identity": "a sun-scorched gold and amber desert world",
    },
    {
        "id": "yuheng", "name": "玉衡星",
        "palette": (
            "a jade and milk-white mineral world: luminous celadon and jade-green plains, "
            "creamy milk-white quartz veins and mineral terraces, pale mint shallow basins, "
            "soft grey-green rock ridges, and a gentle cool jade glow across the terrain"
        ),
        "identity": "a luminous jade-green and milk-white mineral world",
    },
    {
        "id": "sue", "name": "素娥星",
        "palette": (
            "a pale silver moon-dust world: soft chalk and pearl-grey regolith plains, "
            "pale bone-white crater rims and dusty ridges, faint cool blue-grey shadows in the basins, "
            "delicate grey dust streaks, and an almost monochrome pale silver surface"
        ),
        "identity": "a pale silver moon-dust world with soft grey craters",
    },
    {
        "id": "danxia", "name": "丹霞星",
        "palette": (
            "a danxia layered-red landform world: vivid crimson and vermilion stratified rock bands, "
            "warm orange-pink terraced escarpments, deep red-brown canyon walls, "
            "pale cream and ochre sandstone ledges, and striking horizontal colour banding across the ridges"
        ),
        "identity": "a vivid crimson layered danxia rock world with horizontal strata",
    },
    {
        "id": "biluo", "name": "碧落星",
        "palette": (
            "an azure and jade sky world: bright cyan and turquoise shallow seas, vivid azure deep water, "
            "luminous jade-green islands and atolls, white cloud-bright reef rings, "
            "pale aquamarine lagoons, and a brilliant clean blue overall tone"
        ),
        "identity": "a brilliant azure and jade ocean world",
    },
    {
        "id": "youdu", "name": "幽都星",
        "palette": (
            "a cold gloomy blue-black world: very dark navy and slate rock plains, "
            "deep indigo chasms, cold steel-blue glacial ice in the shaded basins, "
            "dim desaturated blue-grey ridges, and only faint cold light on the highest crests"
        ),
        "identity": "a cold gloomy blue-black world in dim light",
    },
    {
        "id": "yaoguang", "name": "瑶光星",
        "palette": (
            "a luminous cyan-white crystal world: brilliant pale cyan and icy white crystal fields, "
            "bright glowing white shard ridges, pale aquamarine glassy flats, "
            "soft silver-blue shadowed clefts, and a radiant clean light over the surface"
        ),
        "identity": "a luminous cyan-white crystal world",
    },
    {
        "id": "xuanpu", "name": "玄圃星",
        "palette": (
            "a dark violet-green garden world: deep plum and dark teal mossy plains, "
            "glowing pale mint and bioluminescent green patches in the low hollows, "
            "near-black purple rock terraces, muted sage and lichen tones, "
            "and a soft dim green glow over the dark terrain"
        ),
        "identity": "a dark violet-green mossy garden world with faint bioluminescence",
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
        dest_dir = out_root / f"{pid}-lux3d"
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / "model.glb"
        print("=" * 72)
        print(f"{pid}（{p['name']}）")
        if not run:
            print("  palette:", p["palette"][:110], "…")
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
        print(((r.stdout or "") + (r.stderr or ""))[-240:])
        got = list(dest_dir.glob("*.glb"))
        print("  " + (f"✓ {got[0].name} {got[0].stat().st_size/1e6:.2f} MB" if got else "✗ 没有产出"))


if __name__ == "__main__":
    main()
