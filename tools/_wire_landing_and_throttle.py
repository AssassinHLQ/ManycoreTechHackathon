"""1) 把降落状态机接进 _physics_process；2) 自动驾驶改「一路加速 + 末端急刹」。

用户原话：
  「现在的自动航线太不智能了，是加速到很高然后一直缓慢减速，这样子太消耗燃料了，
    应该是一直加速，快到星球时迅速制动[相当于按S或X]然后降落」

旧速度剖面 sqrt(2·a·d) 从出发就在压速度，等于全程反推 —— 燃料全浪费在压制上。
新策略分两段：
  · 刹车距离够（d > 刹车所需距离）→ 目标速度 = 巡航上限，**全力加速不回头**
  · 进入刹车距离后 → 目标速度按**真实可用减速度**下降（等同按住 S 硬刹）
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIP = Path(__file__).resolve().parent.parent / "scripts" / "ship.gd"

# ── 1. 把降落状态机插到「着陆 / 对接」分支之后、主飞行逻辑之前 ──
OLD_ANCHOR = '''	var planet = game.nearest_planet(global_position)
	var offset: Vector3 = global_position - planet.global_position
	var normal: Vector3 = offset.normalized()
	var altitude: float = offset.length() - planet.radius'''

NEW_ANCHOR = '''	# ── 降落状态机接管（全程按真实速度推进，无瞬移）──
	if _process_landing(delta):
		_update_engine(delta)
		return

	var planet = game.nearest_planet(global_position)
	var offset: Vector3 = global_position - planet.global_position
	var normal: Vector3 = offset.normalized()
	var altitude: float = offset.length() - planet.radius'''

# ── 2. 新的自动驾驶速度剖面 ──
OLD_PROFILE = '''	var available: float = maxf(AUTOPILOT_ACCEL - gravity.length(), AUTOPILOT_BRAKE_FLOOR)
	var brake: float = available * AUTOPILOT_BRAKE_FRACTION
	var d: float = maxf(altitude - AUTOPILOT_TOUCHDOWN_ALT, 0.0)
	var feasible: float = sqrt(2.0 * brake * d)
	var creep: float = d / AUTOPILOT_CREEP_TIME
	# 下限 1 m/s：低于这个数等于悬停不动，永远落不了地。
	return clampf(minf(feasible, creep), 1.0, AUTOPILOT_CRUISE)'''

NEW_PROFILE = '''	# ⚠ 2026-11-11 改成「一路加速 + 末端急刹」，不再全程缓慢减速。
	#
	#   旧版 `sqrt(2·a·d)` 有个致命观感问题：它从出发那一刻就在压低目标速度，
	#   于是自动驾驶**全程都在反推**压制速度 —— 玩家看到的是「一直缓慢减速」，
	#   燃料也全耗在这上面（用户：「这样子太消耗燃料了」）。
	#
	#   新逻辑：
	#     · 距离还很远 → 目标速度直接给巡航上限，**全力加速，不反向修正**
	#     · 进入刹车距离（用真实可用减速度反算）→ 目标速度沿 √(2ad) 下降，
	#       这一段就等价于「按住 S 硬刹」
	#   刹车距离用**稍保守**的减速度算（BRAKE_FRACTION），留出跟踪余量。
	var available: float = maxf(AUTOPILOT_ACCEL - gravity.length(), AUTOPILOT_BRAKE_FLOOR)
	var brake: float = available * AUTOPILOT_BRAKE_FRACTION
	var d: float = maxf(altitude - AUTOPILOT_TOUCHDOWN_ALT, 0.0)
	# 从巡航速度刹停所需的距离
	var stop_dist: float = (AUTOPILOT_CRUISE * AUTOPILOT_CRUISE) / (2.0 * brake)
	if d > stop_dist:
		# 还早：全力加速到巡航，不做任何减速修正
		return AUTOPILOT_CRUISE
	# 进入刹车段：按真实能力反算允许速度，并留一点下限保证能落地
	var feasible: float = sqrt(2.0 * brake * d)
	var creep: float = d / AUTOPILOT_CREEP_TIME
	return clampf(minf(feasible, creep), 1.0, AUTOPILOT_CRUISE)'''


def main() -> None:
    text = SHIP.read_text(encoding="utf-8", errors="replace")

    if "if _process_landing(delta):" in text:
        print("降落状态机已接入，跳过")
    elif OLD_ANCHOR in text:
        text = text.replace(OLD_ANCHOR, NEW_ANCHOR, 1)
        print("已把 _process_landing 接入主循环")
    else:
        print("没找到主循环锚点")

    if "stop_dist" in text:
        print("速度剖面已是新版，跳过")
    elif OLD_PROFILE in text:
        text = text.replace(OLD_PROFILE, NEW_PROFILE, 1)
        print("已替换自动驾驶速度剖面")
    else:
        print("没找到速度剖面")

    SHIP.write_text(text, encoding="utf-8", newline="")
    print("完成")


if __name__ == "__main__":
    main()
