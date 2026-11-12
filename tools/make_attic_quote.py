"""从 Lux3D contract 自动生成询价文件（正确 schema）。

quote items 的结构（读 workflow_contracts.normalize_quote_call 得出）：
{
  "1": {
    "endpoint": {"method": "POST", "path": "/lux3d/v1/generate/text-to-3d/task/create"},
    "parameters": { "pathParameters": {}, "queryParameters": {}, "body": {...} }
  }, ...
}
"""
import io
import json
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

BASE = r"C:\Users\WY157\.dsh\skills\aholo-lux3d"
CONTRACT = BASE + r"\core\contracts\lux3d-generation.v1.json"

PROMPT_PATH = r"scripts\main.gd"  # 仅用于说明，不实际读取

# 阁楼线 13 个道具的提示词
ITEMS = [
    ("茶桌", "A small round wooden tea table, warm aged oak, four slender turned legs, gently worn edges, cozy attic furniture, realistic PBR materials, no tablecloth"),
    ("茶壶", "A small ceramic teapot with curved spout and bamboo handle, celadon green glaze with subtle crackle, realistic PBR materials"),
    ("茶杯", "A small handleless ceramic tea cup, celadon green glaze, thin rim, realistic PBR materials"),
    ("木凳", "A simple rustic wooden stool with four legs, worn seat surface, warm brown wood, realistic PBR materials"),
    ("书架", "A tall narrow wooden bookshelf with three empty shelves, aged dark walnut, simple joinery, slightly weathered, realistic PBR materials"),
    ("旧木箱", "An old wooden storage chest with brass corner brackets and a small latch, scratched varnished planks, realistic PBR materials"),
    ("矮柜", "A low wooden side cabinet with two small doors, rustic dark wood, realistic PBR materials"),
    ("提灯", "An antique brass hurricane lantern with glass chimney and curved handle, warm weathered metal, realistic PBR materials"),
    ("唱片机", "A vintage wooden gramophone record player with a brass horn, dark walnut base, rounded wooden turntable, realistic PBR materials"),
    ("地毯", "A small flat woven rectangular area rug, muted indigo and rust geometric pattern, worn edges, realistic cloth material"),
    ("燕子", "A small barn swallow bird standing, dark blue-black back, pale cream belly, forked tail, folded wings, realistic plumage, natural pose"),
    ("挂画", "A small framed landscape painting of a clear blue sky with soft white clouds, simple dark wood frame, canvas texture"),
    ("旅行小册", "An open travel notebook lying flat, worn leather cover, cream pages with faint handwriting, realistic PBR materials"),
]

contract = json.load(io.open(CONTRACT, encoding="utf-8"))
ep = contract["endpoints"]["text-to-3d"]
path = ep["path"]
method = ep["method"]

plan = {}
names = {}
for i, (name, prompt) in enumerate(ITEMS, start=1):
    plan[str(i)] = {
        "endpoint": {"method": method, "path": path},
        "parameters": {
            "pathParameters": {},
            "queryParameters": {},
            "body": {"prompt": prompt, "version": "G1"},
        },
    }
    names[str(i)] = name

out = r"_attic_quote.json"
io.open(out, "w", encoding="utf-8", newline="").write(
    json.dumps(plan, ensure_ascii=False, indent=2)
)
io.open("_attic_names.json", "w", encoding="utf-8", newline="").write(
    json.dumps(names, ensure_ascii=False, indent=2)
)
print("已生成 %s（%d 项）" % (out, len(plan)))
print("endpoint = %s %s" % (method, path))
