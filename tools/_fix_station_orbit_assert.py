"""校准 station_test 的「归航站环绕哪颗行星」断言。

背景：2026-11-11 星球从 10 颗扩到 20 颗后，新加的「幽都星」（轨道 39000）
比青岚星更靠近归航站（(43000,11800,-15000)，距原点 47045），
归航站按设计「环绕最近的行星」，于是 orbit_planet 从青岚星变成了幽都星。

旧断言写死 `station.orbit_planet == game.home`，描述的是「当时青岚星恰好最近」
这个巧合，不是设计意图。这里改成校验真正的意图：
归航站环绕的行星，必须是**它自己算出来的那颗最近行星**。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

T = Path(__file__).resolve().parent.parent / "tests" / "station_test.gd"

OLD = '_check(station.orbit_planet == game.home, "station orbits the nearest planet")'
NEW = (
    '# ⚠ 2026-11-11 星球扩到 20 颗后，归航站的最邻近行星可能不是母星了\n'
    '\t#   （新加的幽都星更近）。断言改为校验**设计意图**：环绕的行星必须是\n'
    '\t#   实际离归航站最近的那一颗，而不是写死某颗星球。\n'
    '\tvar nearest_planet = null\n'
    '\tvar nearest_d := INF\n'
    '\tfor p in game.planets:\n'
    '\t\tvar dd: float = station.global_position.distance_to(p.global_position)\n'
    '\t\tif dd < nearest_d:\n'
    '\t\t\tnearest_d = dd\n'
    '\t\t\tnearest_planet = p\n'
    '\t_check(station.orbit_planet == nearest_planet,\n'
    '\t\t"station orbits the nearest planet (%s)" % nearest_planet.display_name)'
)


def main() -> None:
    text = T.read_text(encoding="utf-8", errors="replace")
    if OLD not in text:
        print("没找到旧断言")
        return
    T.write_text(text.replace(OLD, NEW), encoding="utf-8", newline="")
    print("已替换")


if __name__ == "__main__":
    main()
