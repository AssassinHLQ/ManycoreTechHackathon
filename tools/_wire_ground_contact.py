"""地面接触改成走降落状态机，而不是直接 land() 贴地。

现状（ship.gd 1494 起）：
  altitude < 3.4 且 impact_speed < 14 → `land(planet)`
  `land()` 会速度清零 + 位置贴到地表 2.3 米 —— 玩家看到「啪一下贴地」。

改成：
  · 轻触（impact_speed < 14）→ 若还没进入降落，进入 FLARE 阶段，
    由 `_process_landing` 用真实速度把最后十来米走完（拉平 + 缓冲）
  · 重撞（>= 14）→ 维持原有的反弹 + 扣血逻辑，不受影响

注意 `_process_landing` 已经在 altitude 到 FLARE 区间时自动接管，
所以这里只需要「进入降落」这一下；一旦进入，主循环会先走 _process_landing，
不会再落到这段地面接触判定里。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIP = Path(__file__).resolve().parent.parent / "scripts" / "ship.gd"

OLD = '''		if impact_speed < 14.0:
			land(planet)'''

NEW = '''		if impact_speed < 14.0:
			# ⚠ 2026-11-11 不再直接 land() 贴地。
			#   轻触只代表「够慢、可以落」，交给降落状态机从 FLARE 走完最后一段：
			#   抬机头 → 反推降到 0 → 落稳，全程按真实速度推进，没有瞬移。
			#   已经处在降落流程里就什么都不做（_process_landing 会接管）。
			if land_phase == LandPhase.NONE:
				request_landing(planet)
				# 立刻切到 FLARE：这一刻已经在离地 3.4 米以内了，不需要再 APPROACH
				land_phase = LandPhase.FLARE
				land_impact_sink = maxf(0.0, impact_speed)'''

def main() -> None:
    text = SHIP.read_text(encoding="utf-8", errors="replace")
    if "request_landing(planet)" in text and "if impact_speed < 14.0:\n\t\t\tif land_phase" in text:
        print("已改过，跳过")
        return
    if OLD not in text:
        raise SystemExit("没找到 'if impact_speed < 14.0: land(planet)' 块")
    text = text.replace(OLD, NEW, 1)
    SHIP.write_text(text, encoding="utf-8", newline="")
    print("已改为进入降落状态机")


if __name__ == "__main__":
    main()
