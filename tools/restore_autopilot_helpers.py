# -*- coding: utf-8 -*-
"""补回被并行会话覆盖掉的三个自动航行辅助函数（幂等）。

工作区里有另一个会话在同时改 scripts/ship.gd，它会把我加的代码覆盖掉。
这个脚本每次运行都会检查三个函数是否都在，缺哪个补哪个。
"""
import io
import sys

PATH = "scripts/ship.gd"
ANCHOR = "func _autopilot_aim(target_position: Vector3) -> Vector3:"

HELPERS = '''## 自动航行的速度剖面。
##
## 2026-11-11 用户：「自动驾驶太差了，一直加速直接撞上星球却毫发无伤」。
##
## 旧剖面是 (高度 - 8) * 1.25（150 米内再切成 (高度 - 4) * 0.28）。两个致命问题：
##
##   1. 动力学上不可行。跟住 `v = k*d` 需要减速度 `a = k²*d`，随高度线性增长。
##      取 k = 1.25、可用减速度 230，则在 d = 2*230/1.25² = 294 米处就已经吃满，
##      再高就完全跟不住 —— 而剖面在 1200 米处报的是 1490（被上限压到 900）。
##      实测：从 1200 米正上方下降，速度一路涨到 574 m/s，
##      最后以 348 m/s 砸在地面上。
##
##   2. 150 米处有个断崖。`if 高度 < 150` 是「替换」而不是「取较小者」，
##      期望速度从 177 直接跳到 41（实测帧 186 到 187：179.0 变成 39.2），
##      飞船根本来不及回应这个阶跃。
##
## 现在改成两条各自可行的剖面取较小者（min 保连续，不会再有断崖）：
##
##   · 可行上限 sqrt(2*a*d) —— 恒定减速度 a 的刹车距离公式反解。
##     它保证在任何高度 d 上，以当前速度开始全力减速都能在撞地前收住。
##   · 末端蠕行 d/tau —— 指数逼近。`v = d/tau` 对应的减速度是 `d/tau²`，
##     在 d 附近才需要用力，所以最后几米是「贴」上去的，接触速度约为 d/tau。
##
## 两条线的交点在 d = 2*a*tau²，那里 `d/tau = 2*a*tau`、需要的减速度恰好是 2*a。
## 也就是说只要 `a <= 可用减速度 / 2`，整条剖面就是可行的 ——
## 这正是 AUTOPILOT_BRAKE_FRACTION 必须小于 0.5 的原因。
## 取 0.35 时最坏情况用掉 70% 的机动能力，剩下 30% 是跟踪余量。
func _autopilot_desired_speed(altitude: float, gravity: Vector3) -> float:
	# 可用减速度 = 机动能力 - 引力。下降时引力是反向的，会吃掉一部分减速能力。
	var available: float = maxf(AUTOPILOT_ACCEL - gravity.length(), AUTOPILOT_BRAKE_FLOOR)
	var brake: float = available * AUTOPILOT_BRAKE_FRACTION
	var d: float = maxf(altitude - AUTOPILOT_TOUCHDOWN_ALT, 0.0)
	var feasible: float = sqrt(2.0 * brake * d)
	var creep: float = d / AUTOPILOT_CREEP_TIME
	# 下限 1 m/s：低于这个数等于悬停不动，永远落不了地。
	return clampf(minf(feasible, creep), 1.0, AUTOPILOT_CRUISE)


## 当前目标脚下地面的高度（米）。
##
## 不用 radius：行星地表有 ±5% 的起伏（terrain_height），用球心半径算出来的
## 「高度」在山地上偏小、在海面上偏大，和落点判定用的根本不是同一个量。
## 这里直接跟落点判定（offset.length() - terrain_height(normal)）对齐。
func _target_altitude(target_node) -> float:
	if target_node == null:
		return 0.0
	var from_target: Vector3 = global_position - target_node.global_position
	var distance: float = from_target.length()
	if distance < 0.001:
		return 0.0
	if target_node.has_method("terrain_height"):
		return distance - target_node.terrain_height(from_target / distance)
	return distance - target_node.radius


## 目标的公转速度；目标不是行星（没有这个接口）时按静止处理。
func _target_orbital_velocity() -> Vector3:
	if target != null and target.has_method("orbital_velocity"):
		return target.orbital_velocity()
	return Vector3.ZERO


'''

with io.open(PATH, "r", encoding="utf-8", newline="") as fh:
    src = fh.read()

missing = [n for n in ("_autopilot_desired_speed", "_target_altitude", "_target_orbital_velocity")
           if ("func %s(" % n) not in src]
if not missing:
    print("already present, nothing to do")
    sys.exit(0)

if src.count(ANCHOR) != 1:
    sys.exit("abort: anchor count = %d (expect 1)" % src.count(ANCHOR))
if len(missing) != 3:
    sys.exit("abort: partial state, missing = %s" % missing)

src = src.replace(ANCHOR, HELPERS + ANCHOR, 1)

with io.open(PATH, "w", encoding="utf-8", newline="") as fh:
    fh.write(src)

print("ok: restored %s (%d bytes)" % (",".join(missing), len(src.encode("utf-8"))))
