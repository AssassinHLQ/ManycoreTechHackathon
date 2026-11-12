"""生成阁楼外面（六世界）的资产询价文件。"""
import io
import json
import sys

sys.path.insert(0, r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon\tools")
from attic_worlds_items import ITEMS  # noqa: E402

BASE = r"C:\Users\WY157\.dsh\skills\aholo-lux3d"
contract = json.load(io.open(BASE + r"\core\contracts\lux3d-generation.v1.json",
                             encoding="utf-8"))
ep = contract["endpoints"]["text-to-3d"]

plan = {}
for i, (name, faces, height, prompt) in enumerate(ITEMS, start=1):
    plan[str(i)] = {
        "endpoint": {"method": ep["method"], "path": ep["path"]},
        "parameters": {
            "pathParameters": {},
            "queryParameters": {},
            "body": {"prompt": prompt, "version": "G1", "faceCount": faces},
        },
    }

io.open("_worlds_quote.json", "w", encoding="utf-8", newline="").write(
    json.dumps(plan, ensure_ascii=False, indent=2))
print("已生成 _worlds_quote.json（%d 项）" % len(plan))
