"""把 chixiao / 赤霄星 改名为 jiangxiao / 绛霄星。

原因：「赤霄」虽然是刘邦佩剑的古典词，但当代最广为人知的用法是
《明日方舟》陈的佩剑，对比赛作品来说联想风险不值得承担。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

MAIN = Path(__file__).resolve().parent.parent / "scripts" / "main.gd"

REPLACEMENTS = [
    ('"id": "chixiao", "name": "赤霄星"', '"id": "jiangxiao", "name": "绛霄星"'),
    ('"kind": "chixiao"', '"kind": "jiangxiao"'),
    ('"chixiao": ["红色的第一课", "赤霄星的沙是锈的。',
     '"jiangxiao": ["红色的第一课", "绛霄星的沙是锈的。'),
    ('"chixiao": "res://assets/models/chixiao-lux3d/model.glb"',
     '"jiangxiao": "res://assets/models/jiangxiao-lux3d/model.glb"'),
    # 描述里如果还有赤霄
    ("赤铁矿红沙、血色台地与铁锈雾", "赤铁矿红沙、血色台地与铁锈雾"),
]


def main() -> None:
    text = MAIN.read_text(encoding="utf-8", errors="replace")
    changed = 0
    for old, new in REPLACEMENTS:
        if old in text:
            text = text.replace(old, new)
            changed += 1
    # 兜底：任何残留的「赤霄」字样都换成绛霄
    if "赤霄" in text:
        text = text.replace("赤霄", "绛霄")
        changed += 1
    MAIN.write_text(text, encoding="utf-8", newline="")

    print("替换了 %d 处" % changed)
    print("残留 chixiao :", text.count("chixiao"))
    print("残留 赤霄     :", text.count("赤霄"))
    print("jiangxiao 命中:", text.count("jiangxiao"))


if __name__ == "__main__":
    main()
