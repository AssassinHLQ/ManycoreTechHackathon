"""用 Poly Haven 的 CC0 渲染图做 image-to-3D（1 credit/件）。

流程：
  1. 从 Poly Haven API 取资产的 2048px 缩略渲染图（全站 CC0，可商用可改造）
  2. 该图 URL 直接传给 Lux3D image-to-3d（外部 HTTPS URL 允许）
  3. 下载 glb → 压缩贴图

⚠ 版权说明：
  Poly Haven 全站 CC0 1.0 —— 无需署名、可商用、可修改。
  用它当 image-to-3D 的输入图，来源链干净可查证。
"""
import io
import json
import os
import sys
import urllib.request

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

BASE = r"C:\Users\WY157\.dsh\skills\aholo-lux3d"
sys.path.insert(0, BASE)
sys.path.insert(0, BASE + r"\core\runtime")
import lux3d_client as lx  # noqa: E402

OUT_ROOT = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets\models\props\attic-worlds"
LEDGER = os.path.join(OUT_ROOT, "_ledger.json")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

# 我们的目录名 → (Poly Haven 资产 id, 面数, 目标高度)
ITEMS = {
    "pine-tree":    ("fir_tree_01", 16000, 2.6),
    "snow-lantern": ("Lantern_01", 10000, 1.5),
    "boulder":      ("boulder_01", 12000, 1.2),
    "wooden-table": ("WoodenTable_01", 14000, 0.75),
    "shelf":        ("Shelf_01", 16000, 1.55),
    "barrel":       ("Barrel_01", 10000, 0.9),
    "ceramic-pot":  ("ceramic_pot", 10000, 0.35),
    "brass-pot":    ("brass_pot_01", 10000, 0.3),
}


def image_url(asset_id):
    """取该资产的 2048px PNG 渲染图直链。"""
    return ("https://cdn.polyhaven.com/asset_img/thumbs/%s.png"
            "?width=2048&height=2048&format=png" % asset_id)


def head_ok(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status == 200


def find_glb(d):
    if not os.path.isdir(d):
        return None
    for f in os.listdir(d):
        if f.endswith(".glb") and os.path.getsize(os.path.join(d, f)) > 1024:
            return os.path.join(d, f)
    return None


def main():
    only = [a for a in sys.argv[1:] if not a.startswith("--")] or None
    ledger = {}
    if os.path.isfile(LEDGER):
        try:
            ledger = json.loads(io.open(LEDGER, encoding="utf-8").read())
        except Exception:
            pass

    for name, (asset_id, faces, height) in ITEMS.items():
        if only and name not in only:
            continue
        out_dir = os.path.join(OUT_ROOT, name)
        if find_glb(out_dir):
            print("[skip] %-14s 已存在" % name, flush=True)
            continue
        url = image_url(asset_id)
        try:
            ok = head_ok(url)
        except Exception as exc:
            print("[FAIL] %-14s 参考图不可达: %s" % (name, str(exc)[:80]), flush=True)
            continue
        if not ok:
            print("[FAIL] %-14s 参考图 404" % name, flush=True)
            continue
        os.makedirs(out_dir, exist_ok=True)
        print("[gen ] %-14s ref=%s faceCount=%d" % (name, asset_id, faces), flush=True)
        try:
            lx.generate_3d_model(
                img=url,
                output_path=os.path.join(out_dir, "model.glb"),
                version="G1-Turbo",
                faceCount=faces,
                region="cn",
            )
            glb = find_glb(out_dir)
            size = os.path.getsize(glb) if glb else 0
            ledger[name] = {"ok": True, "ref": asset_id, "ref_url": url,
                            "faceCount": faces, "height": height,
                            "file": glb, "bytes": size}
            print("[ok  ] %-14s %5.1f MB" % (name, size / 1048576), flush=True)
        except Exception as exc:
            ledger[name] = {"ok": False, "ref": asset_id, "error": str(exc)[:300]}
            print("[FAIL] %-14s %s" % (name, str(exc)[:160]), flush=True)
        io.open(LEDGER, "w", encoding="utf-8", newline="").write(
            json.dumps(ledger, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
