"""批量生成阁楼外面（六个口袋世界）的 Lux3D 摆件。

产物 → assets/models/props/attic-worlds/<name>/
⚠ 该路径在 .gitignore 的例外名单里（与 attic/ 同级处理，见 .gitignore 注释）。
"""
import io
import json
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

BASE = r"C:\Users\WY157\.dsh\skills\aholo-lux3d"
sys.path.insert(0, BASE)
sys.path.insert(0, BASE + r"\core\runtime")
sys.path.insert(0, r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\tools")

import lux3d_client as lx  # noqa: E402
from attic_worlds_items import ITEMS  # noqa: E402

OUT_ROOT = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets\models\props\attic-worlds"
LEDGER = os.path.join(OUT_ROOT, "_ledger.json")

# ⚠ 2026-11-12 用户指出：G1-Turbo 比 G1 便宜 7 credits/件（13 vs 20，省 35%）。
#   实测询价对比：
#     G1       20 credits/件
#     G1-Turbo 13 credits/件
#   本喵一开始照技能文档的「G1 适合材质细节丰富的物件」选了 G1，
#   但**没有先询价对比** —— 这是本喵的疏忽。
#
#   现在默认走 G1-Turbo。技能文档对它的定位是「建筑外壳/复杂结构的首选」，
#   对摆件同样适用：观感差异在小物件上肉眼难辨，但单价便宜三分之一。
#   想改回 G1 时把下面改成 "G1" 即可。
VERSION = "G1-Turbo"


def find_glb(d):
    if not os.path.isdir(d):
        return None
    for f in os.listdir(d):
        if f.endswith(".glb") and os.path.getsize(os.path.join(d, f)) > 1024:
            return os.path.join(d, f)
    return None


def load_ledger():
    if os.path.isfile(LEDGER):
        try:
            return json.loads(io.open(LEDGER, encoding="utf-8").read())
        except Exception:
            pass
    return {}


def main():
    only = set(a for a in sys.argv[1:] if not a.startswith("--")) or None
    ledger = load_ledger()
    ok_n = 0
    for name, faces, height, prompt in ITEMS:
        if only and name not in only:
            continue
        out_dir = os.path.join(OUT_ROOT, name)
        if find_glb(out_dir):
            print("[skip] %-18s 已存在" % name, flush=True)
            ok_n += 1
            continue
        os.makedirs(out_dir, exist_ok=True)
        print("[gen ] %-18s faceCount=%d ..." % (name, faces), flush=True)
        try:
            lx.generate_text_to_3d(
                prompt,
                output_path=os.path.join(out_dir, "model.glb"),
                version=VERSION,
                faceCount=faces,
                region="cn",
            )
            glb = find_glb(out_dir)
            size = os.path.getsize(glb) if glb else 0
            ledger[name] = {"ok": True, "faceCount": faces, "height": height,
                            "file": glb, "bytes": size}
            ok_n += 1
            print("[ok  ] %-18s %5.1f MB" % (name, size / 1048576), flush=True)
        except Exception as exc:
            ledger[name] = {"ok": False, "error": str(exc)[:300]}
            print("[FAIL] %-18s %s" % (name, str(exc)[:160]), flush=True)
        io.open(LEDGER, "w", encoding="utf-8", newline="").write(
            json.dumps(ledger, ensure_ascii=False, indent=2))

    io.open(LEDGER, "w", encoding="utf-8", newline="").write(
        json.dumps(ledger, ensure_ascii=False, indent=2))
    print("\n完成：%d / %d" % (ok_n, len(ITEMS)))


if __name__ == "__main__":
    main()
