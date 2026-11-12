"""更新 smoke_test 里两条按星球数量硬编码的断言（10 → 20）。"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

T = Path(__file__).resolve().parent.parent / "tests" / "smoke_test.gd"


def main() -> None:
    text = T.read_text(encoding="utf-8", errors="replace")
    pairs = [
        (
            "_check(game.planets.size() == 10, "
            '"ten explorable bodies created (five major + five secondary)")',
            "_check(game.planets.size() == 20, "
            '"twenty explorable bodies created (ten major + ten secondary)")',
        ),
        (
            '_check(game.anomalies.size() == 16, '
            '"ten planetary signals plus six hidden echoes")',
            '_check(game.anomalies.size() == 26, '
            '"twenty planetary signals plus six hidden echoes")',
        ),
    ]
    n = 0
    for old, new in pairs:
        if old in text:
            text = text.replace(old, new)
            n += 1
        else:
            print("没找到:", old[:50])
    T.write_text(text, encoding="utf-8", newline="")
    print("替换 %d/%d" % (n, len(pairs)))


if __name__ == "__main__":
    main()
