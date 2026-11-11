"""批量生成九颗 Lux3D 星球（青岚星已单独做完）。

每颗：单一闭合球面 + 起伏约 6% + 森林/岩石用贴图（与 v3 成功版同一结构），
只替换生物群系与配色，避免十颗星球长得一样。

用法：
    python tools/_gen_planets.py            # 只打印将要生成的 prompt
    python tools/_gen_planets.py --run      # 真正提交（会花 credits）
"""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parent.parent
WORK = REPO.parent / "_lux3d_work"
SKILL = Path(r"C:\Users\WY157\.dsh\skills\aholo-lux3d")
CLIENT = SKILL / "core" / "runtime" / "lux3d_client.py"
CRED = Path(r"C:\Users\WY157\.dsh\credentials\lux3d-cn.env")

TEMPLATE = (
    "One single closed sphere, a whole low-poly planet seen from outside, round silhouette. "
    "The entire model is ONE continuous watertight globe surface with no separate pieces: "
    "absolutely no individual trees, no detached boulders, no props, no structures, "
    "no floating objects, no shell inside the sphere. "
    "The sphere itself is sculpted with pronounced continuous terrain: long ridges, rolling hills, "
    "broad valleys and a few flat plateau areas, with terrain height variation up to about six "
    "percent of the planet radius, smoothly connected with no spikes and no overhangs. "
    "Colour and surface detail are painted flat onto the terrain instead of being modelled: {biome} "
    "Painterly hand-painted flat texture, low-poly faceted shading, {tint} palette, "
    "even soft daylight, no harsh specular highlights, no space background, no stars, "
    "planet fills the frame, orthographic view of a complete round globe."
)


def load_key() -> str:
    for line in CRED.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip().startswith("LUX3D_CN_API_KEY"):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("lux3d-cn.env 里没有 LUX3D_CN_API_KEY")


def main() -> None:
    run = "--run" in sys.argv
    spec = json.loads((WORK / "planets_batch.json").read_text(encoding="utf-8"))
    env = dict(os.environ)
    env["LUX3D_CN_API_KEY"] = load_key()

    out_root = REPO / "assets" / "models"
    for p in spec["planets"]:
        pid = p["id"]
        prompt = TEMPLATE.format(biome=p["biome"], tint=p["tint"])
        dest = out_root / f"{pid}-lux3d" / "model.glb"
        dest.parent.mkdir(parents=True, exist_ok=True)
        print("=" * 70)
        print(f"{pid}（{p['name']}）-> {dest}")
        if not run:
            print(prompt[:220] + " …")
            continue
        if dest.exists() and dest.stat().st_size > 100_000:
            print("  已存在，跳过")
            continue
        cmd = [
            sys.executable, str(CLIENT), "--region", "cn",
            "text", prompt, str(dest.parent / "model"),
            "--style", "hand_painted", "--version", "G1-Turbo",
            "--face-count", "160000", "--format", "glb",
            "--enable-pbr", "--no-ai-predict-size",
            "--interval", "10", "--max-attempts", "90",
        ]
        # 客户端会写成 <base>.glb；先清掉残留
        for stale in (dest.parent / "model.glb",):
            if stale.exists() and stale.stat().st_size < 100_000:
                stale.unlink()
        r = subprocess.run(cmd, env=env, capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        tail = (r.stdout or "")[-400:] + (r.stderr or "")[-400:]
        print(tail)
        got = list(dest.parent.glob("*.glb"))
        if got:
            print(f"  ✓ 产出 {got[0].name} {got[0].stat().st_size/1e6:.2f} MB")
        else:
            print("  ✗ 没有产出")


if __name__ == "__main__":
    main()
