"""批量生成阁楼线 13 个 Lux3D 道具（带面数上限）。

⚠ 为什么要限面数：
   默认产出一个茶壶就是 155,781 顶点 / 270,396 三角面 / 14.1 MB。
   阁楼里的家具在屏幕上只占几十像素，27 万面完全是浪费 —— 而且
   这类文件还要进 pck、进显存。faceCount 允许 10000~300000，按尺寸分级：
     小物件（茶杯/茶壶/提灯/燕子/小册）  10,000
     中等（茶桌/木凳/木箱/矮柜/唱片机/地毯/挂画） 16,000
     大件（书架）                        20,000

⚠ 产物在 assets/models/props/attic/，已被 .gitignore 排除（用户要求省流量）。
"""
import io
import json
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

BASE = r"C:\Users\WY157\.dsh\skills\aholo-lux3d"
sys.path.insert(0, BASE)
sys.path.insert(0, BASE + r"\core\runtime")

import lux3d_client as lx  # noqa: E402

OUT_ROOT = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\assets\models\props\attic"

# (目录名, 面数, 提示词)
ITEMS = [
    ("tea-table", 16000, "A small round wooden tea table, warm aged oak, four slender turned legs, gently worn edges, cozy attic furniture, realistic PBR materials, no tablecloth"),
    ("teapot", 10000, "A small ceramic teapot with curved spout and bamboo handle, celadon green glaze with subtle crackle, realistic PBR materials"),
    ("teacup", 10000, "A small handleless ceramic tea cup, celadon green glaze, thin rim, realistic PBR materials"),
    ("wooden-stool", 12000, "A simple rustic wooden stool with four legs, worn seat surface, warm brown wood, realistic PBR materials"),
    ("bookshelf", 20000, "A tall narrow wooden bookshelf with three empty shelves, aged dark walnut, simple joinery, slightly weathered, realistic PBR materials"),
    ("wooden-chest", 14000, "An old wooden storage chest with brass corner brackets and a small latch, scratched varnished planks, realistic PBR materials"),
    ("side-cabinet", 14000, "A low wooden side cabinet with two small doors, rustic dark wood, realistic PBR materials"),
    ("lantern", 12000, "An antique brass hurricane lantern with glass chimney and curved handle, warm weathered metal, realistic PBR materials"),
    ("gramophone", 16000, "A vintage wooden gramophone record player with a brass horn, dark walnut base, rounded wooden turntable, realistic PBR materials"),
    ("rug", 10000, "A small flat woven rectangular area rug, muted indigo and rust geometric pattern, worn edges, realistic cloth material"),
    ("swallow", 10000, "A small barn swallow bird standing, dark blue-black back, pale cream belly, forked tail, folded wings, realistic plumage, natural pose"),
    ("painting", 10000, "A small framed landscape painting of a clear blue sky with soft white clouds, simple dark wood frame, canvas texture"),
    ("travel-notebook", 10000, "An open travel notebook lying flat, worn leather cover, cream pages with faint handwriting, realistic PBR materials"),
]

LEDGER = os.path.join(OUT_ROOT, "_ledger.json")


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


def save_ledger(led):
    io.open(LEDGER, "w", encoding="utf-8", newline="").write(
        json.dumps(led, ensure_ascii=False, indent=2))


def main():
    only = set(sys.argv[1:]) or None
    force = "--force" in sys.argv
    ledger = load_ledger()

    for name, faces, prompt in ITEMS:
        if only and name not in only:
            continue
        out_dir = os.path.join(OUT_ROOT, name)
        existing = find_glb(out_dir)
        if existing and not force:
            print("[skip] %-16s 已存在 %5.1f MB" % (
                name, os.path.getsize(existing) / 1048576), flush=True)
            continue
        os.makedirs(out_dir, exist_ok=True)
        if force:
            for f in os.listdir(out_dir):
                if f.endswith((".glb", ".zip")):
                    try:
                        os.remove(os.path.join(out_dir, f))
                    except OSError:
                        pass
        print("[gen ] %-16s faceCount=%d ..." % (name, faces), flush=True)
        try:
            lx.generate_text_to_3d(
                prompt,
                output_path=os.path.join(out_dir, "model.glb"),
                version="G1",
                faceCount=faces,
                region="cn",
            )
            glb = find_glb(out_dir)
            size = os.path.getsize(glb) if glb else 0
            ledger[name] = {"ok": True, "faceCount": faces, "file": glb,
                            "bytes": size}
            print("[ok  ] %-16s %5.1f MB" % (name, size / 1048576), flush=True)
        except Exception as exc:
            ledger[name] = {"ok": False, "faceCount": faces, "error": str(exc)[:300]}
            print("[FAIL] %-16s %s" % (name, str(exc)[:160]), flush=True)
        save_ledger(ledger)

    save_ledger(ledger)
    ok = sum(1 for v in ledger.values() if v.get("ok"))
    print("\n完成：%d / %d" % (ok, len(ledger)))


if __name__ == "__main__":
    main()
