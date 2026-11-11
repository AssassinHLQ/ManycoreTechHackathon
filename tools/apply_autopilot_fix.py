# -*- coding: utf-8 -*-
"""把「自动航行剖面 + 落点判定」三处改动一次性写回 scripts/ship.gd。

为什么用一个脚本而不是三次 edit 调用：工作区里有**另一个会话在同时改这个文件**，
分三次写会让它有机会夹在中间把文件覆盖掉。读-改-写一次完成，窗口最小。
每处改动都要求原片段**恰好出现一次**，对不上就整体放弃、不写。
"""
import io
import sys

PATH = "scripts/ship.gd"

CONSTS_OLD = """const AUTOPILOT_ACCEL := 230.0
const AUTOPILOT_FUEL_PER_DV := 0.008
const MANUAL_FUEL_PER_DV := 0.00625
"""

CONSTS_NEW = """const AUTOPILOT_ACCEL := 230.0
const AUTOPILOT_FUEL_PER_DV := 0.008
## 自动航行的巡航速度上限（米/秒）。远距离赶路时压在这条线上。
const AUTOPILOT_CRUISE := 900.0
## 速度剖面按「可用减速度的多少比例」来设计。
##
## 这个值不能到 0.5，原因见 _autopilot_desired_speed 的注释：
## sqrt 剖面与蠕行剖面的交点处，减速需求恒等于「2 x 剖面减速度」。
## 取 0.35 就是「最坏情况下也只用掉 70% 的机动能力」，留 30% 给跟踪误差。
const AUTOPILOT_BRAKE_FRACTION := 0.35
## 可用减速度的下限。行星引力最大 32，留个地板免得剖面被压成 0 而卡死。
const AUTOPILOT_BRAKE_FLOOR := 30.0
## 末端指数逼近的时间常数（秒）。d/tau 就是最后几米的下降速度。
const AUTOPILOT_CREEP_TIME := 1.0
## 期望停在地表上方多高。留 2.6 米，落点判定（< 3.4 米）之前就已经几乎悬停。
const AUTOPILOT_TOUCHDOWN_ALT := 2.6
const MANUAL_FUEL_PER_DV := 0.00625
"""

AUTOPILOT_OLD = """	if autopilot and target != null:
		var to_target: Vector3 = target.global_position - global_position
		var target_altitude: float = to_target.length() - target.radius
		var desired_speed := clampf((target_altitude - 8.0) * 1.25, 18.0, 900.0)
		if target_altitude < 150.0:
			desired_speed = clampf((target_altitude - 4.0) * 0.28, 3.0, 42.0)
		var aim := _autopilot_aim(target.global_position)
		var desired_direction := (aim - global_position).normalized()
		var desired_velocity := desired_direction * desired_speed
		var before_velocity := velocity
		velocity = velocity.move_toward(desired_velocity, delta * AUTOPILOT_ACCEL)
"""

AUTOPILOT_NEW = """	if autopilot and target != null:
		# 自动驾驶也要吃引力。
		#
		# 旧版把 `velocity += gravity * delta` 只写在手动分支里，自动航行等于
		# 在一个没有引力的空间里飞 —— 它算出来的速度剖面根本没考虑自己还在往下掉。
		# 这里先加引力，紧接着的 move_toward 会立刻把它抵掉，
		# 所以效果是「自动驾驶知道自己在掉，并主动修正」，而不是被拽偏。
		velocity += gravity * delta
		var target_velocity := _target_orbital_velocity()
		var target_altitude := _target_altitude(target)
		var desired_speed := _autopilot_desired_speed(target_altitude, gravity)
		var aim := _autopilot_aim(target.global_position)
		var desired_direction := (aim - global_position).normalized()
		# 期望速度以「地面」为参照系：行星在公转，相对速度才算数。
		var desired_velocity := desired_direction * desired_speed + target_velocity
		var before_velocity := velocity
		velocity = velocity.move_toward(desired_velocity, delta * AUTOPILOT_ACCEL)
"""

IMPACT_OLD = """	if altitude < 3.4:
		var impact_speed := velocity.length()
		if impact_speed < 14.0 or autopilot:
			land(planet)
		else:
			global_position = planet.global_position + planet.surface_position(normal, 5.0)
			velocity = normal * maxf(12.0, impact_speed * 0.42)
"""

IMPACT_NEW = """	if altitude < 3.4:
		# 撞击严重程度 = 「相对地面、沿地面法线的接近速度」。
		#
		# 不能再用 velocity.length()（飞船自己的绝对速度）。行星在以
		# 10~39 m/s 公转（缄默星 0.0042 rad/s x 9200 m = 38.6），这个速度
		# 玩家看不见也匹配不了，拿它算伤害等于随机扣血：
		#   · 跟着行星同步飞行的飞船（新版自动航行就是这样）相对静止，
		#     却会被判成 38.6 m/s 撞击 —— 自动驾驶每落一次炸一次。
		#   · 反过来，飞船自己速度为 0 时又完全免责。
		#
		# 也不能用「相对速度的模长」。试过，会在反弹上出现刀锋平衡：
		# 反弹把径向速度置成 12（低于 14 的门槛，本该着陆），但飞船并没有
		# 拿到行星的切向速度，于是 |相对速度| = sqrt(12^2 + 6.6^2) = 13.7~15.2
		# 在门槛上来回跳 —— 实测变成「每 1.8 秒扣 6.4 点船体直到解体」。
		#
		# 取法线方向的分量就没这个问题：它只回答「撞得有多狠」，
		# 切向的擦碰不算撞地。行星公转是切向的，也不会把地面「扫」进一艘
		# 静止的飞船里，所以这样取不会漏掉任何真实的撞击。
		var ground_velocity: Vector3 = planet.orbital_velocity()
		var relative_velocity: Vector3 = velocity - ground_velocity
		var impact_speed := maxf(0.0, -relative_velocity.dot(normal))
		# 旧版这里写的是 `if impact_speed < 14.0 or autopilot:`。
		# 那个 `or autopilot` 就是用户说的「毫发无伤」：自动航行哪怕以
		# 348 m/s 砸到地面，也走 land() 这条路 —— 直接判定为完美着陆。
		# 当时的用意是「自动航行负责安全降落」，但那是拿豁免掩盖剖面算错，
		# 所以现在两处一起改：剖面改成动力学可行的（见 _autopilot_desired_speed），
		# 豁免删掉 —— 自动驾驶要是真撞快了，它也得挨这一下。
		if impact_speed < 14.0:
			land(planet)
		else:
			global_position = planet.global_position + planet.surface_position(normal, 5.0)
			velocity = ground_velocity + normal * maxf(12.0, impact_speed * 0.42)
"""

with io.open(PATH, "r", encoding="utf-8", newline="") as fh:
    src = fh.read()

for name, old in (("consts", CONSTS_OLD), ("autopilot", AUTOPILOT_OLD), ("impact", IMPACT_OLD)):
    n = src.count(old)
    if n != 1:
        sys.exit("abort: %s anchor count = %d (expect 1)" % (name, n))

src = src.replace(CONSTS_OLD, CONSTS_NEW, 1)
src = src.replace(AUTOPILOT_OLD, AUTOPILOT_NEW, 1)
src = src.replace(IMPACT_OLD, IMPACT_NEW, 1)

with io.open(PATH, "w", encoding="utf-8", newline="") as fh:
    fh.write(src)

print("ok: %d bytes written" % len(src.encode("utf-8")))
