"""生成第三批 14 件（太空站内部 + 洞穴 + 通用星球物件）。

产物 → assets/models/props/station/<name>/
⚠ station/ 目录在 .gitignore 例外名单之外 —— 按用户「加入gitignore」的要求，
  这批**不进仓库**（只保留在本地供运行）。若要入库需在 .gitignore 加例外。
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
from batch3_items import ITEMS  # noqa: E402

OUT_ROOT = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets\models\props\station"
LEDGER = os.path.join(OUT_ROOT, "_ledger3.json")
VERSION = "G1-Turbo"


def find_glb(d):
    if not os.path.isdir(d):
        return None
    for f in os.listdir(d):
        if f.endswith(".glb") and os.path.getsize(os.path.join(d, f)) > 1024:
            return os.path.join(d, f)
    return None


def main():
    ledger = {}
    if os.path.isfile(LEDGER):
        try:
            ledger = json.loads(io.open(LEDGER, encoding="utf-8").read())
        except Exception:
            pass
    for name, faces, height, prompt in ITEMS:
        out_dir = os.path.join(OUT_ROOT, name)
        if find_glb(out_dir):
            print("[skip] %-18s 已存在" % name, flush=True)
            continue
        os.makedirs(out_dir, exist_ok=True)
        print("[gen ] %-18s faceCount=%d" % (name, faces), flush=True)
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
            print("[ok  ] %-18s %6.1f MB" % (name, size / 1048576), flush=True)
        except Exception as exc:
            ledger[name] = {"ok": False, "error": str(exc)[:300]}
            print("[FAIL] %-18s %s" % (name, str(exc)[:150]), flush=True)
        io.open(LEDGER, "w", encoding="utf-8", newline="").write(
            json.dumps(ledger, ensure_ascii=False, indent=2))
    print("\n完成")


if __name__ == "__main__":
    main()
