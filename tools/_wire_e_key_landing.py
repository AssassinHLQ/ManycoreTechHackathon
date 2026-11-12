"""E 键自动着陆也改走降落状态机（原来也是瞬移）。

旧代码三行连击：
    velocity = Vector3.ZERO
    global_position = planet.surface_position(normal, 3.4)
    land(planet)
→ 速度清零 + 位置贴地 + 置 landed 全在同一帧，玩家看到的就是「瞬移贴地」。

改成：只请求降落（进入 APPROACH），剩下的抬机头 / 减速 / 落稳
由 _process_landing 按真实速度演完。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIP = Path(__file__).resolve().parent.parent / "scripts" / "ship.gd"

OLD = '''	else:
		velocity = Vector3.ZERO
		global_position = planet.global_position + planet.surface_position(normal, 3.4)
		land(planet)'''

NEW = '''	else:
		# ⚠ 2026-11-11：不再瞬移贴地。
		#   只请求降落，由 _process_landing 依次演完
		#   APPROACH → FLARE（缓慢抬机头）→ TOUCHDOWN（反推渐停）→ LANDED。
		#   全程按真实速度推进位置，玩家能看到完整的落地过程。
		request_landing(planet)'''


def main() -> None:
    text = SHIP.read_text(encoding="utf-8", errors="replace")
    if OLD not in text:
        raise SystemExit("没找到 E 键着陆的瞬移块")
    if "request_landing(planet)\n" in text and "global_position = planet.global_position + planet.surface_position(normal, 3.4)" not in text:
        print("已改过，跳过")
        return
    text = text.replace(OLD, NEW, 1)
    SHIP.write_text(text, encoding="utf-8", newline="")
    print("E 键着陆已改为走状态机")


if __name__ == "__main__":
    main()
