"""让 smoke_test 等降落状态机走完，而不是假设「一调就落地」。

背景：2026-11-11 降落改成四阶段异步状态机（APPROACH→FLARE→TOUCHDOWN→LANDED），
但 smoke_test 里 `try_land()` 后立刻断言 `ship.landed` —— 那时还在 APPROACH 阶段，
于是后续 exit_ship / brake / autopilot / fuel 一连串断言全部连锁失败（5 条）。

这里不是放宽断言，而是**等待新行为完成**：轮询到 landed 为止，最多等 600 帧。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

T = Path(__file__).resolve().parent.parent / "tests" / "smoke_test.gd"

OLD = '''	game.ship.try_land()
	_check(game.ship.landed and game.ship.landed_planet == game.home, "ship auto-lands near a landmark at 20m altitude")'''

NEW = '''	game.ship.try_land()
	# ⚠ 2026-11-11 降落改成异步状态机：try_land 只请求降落，
	#   完整落地要 1~8 秒（APPROACH → FLARE → TOUCHDOWN）。
	#   这里等到真的落稳，而不是假设同一帧就完成。
	for _wait in range(600):
		await physics_frame
		if game.ship.landed:
			break
	_check(game.ship.landed and game.ship.landed_planet == game.home,
		"ship auto-lands near a landmark at 20m altitude (took the full landing sequence)")'''


def main() -> None:
    text = T.read_text(encoding="utf-8", errors="replace")
    if "took the full landing sequence" in text:
        print("已改过，跳过")
        return
    if OLD not in text:
        raise SystemExit("没找到 try_land 断言块")
    T.write_text(text.replace(OLD, NEW), encoding="utf-8", newline="")
    print("已改成等待降落完成")


if __name__ == "__main__":
    main()
