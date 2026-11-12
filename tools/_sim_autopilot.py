"""对比自动航行减速剖面的「改前 / 改后」。

复刻 ship.gd::_autopilot_desired_speed 的公式 + 一个 60Hz 的下降积分，
算出从 40000 米开始、初速 0，到落点 2.6 米要多久、刹车段多长。
"""

AUTOPILOT_ACCEL = 230.0
AUTOPILOT_CRUISE = 2000.0
AUTOPILOT_BRAKE_FLOOR = 30.0
AUTOPILOT_CREEP_TIME = 1.0
AUTOPILOT_TOUCHDOWN_ALT = 2.6
SHIP_BRAKE_DECEL = 260.0


def desired(alt, g, frac, approach_t, use_manual_brake):
    if use_manual_brake:
        available = max(SHIP_BRAKE_DECEL - g, AUTOPILOT_BRAKE_FLOOR)
    else:
        available = max(AUTOPILOT_ACCEL - g, AUTOPILOT_BRAKE_FLOOR)
    brake = available * frac
    d = max(alt - AUTOPILOT_TOUCHDOWN_ALT, 0.0)
    stop_dist = (AUTOPILOT_CRUISE ** 2) / (2.0 * brake)
    if d > stop_dist:
        return AUTOPILOT_CRUISE
    feasible = (2.0 * brake * d) ** 0.5
    gentle = d / approach_t
    creep = d / AUTOPILOT_CREEP_TIME
    return min(max(min(feasible, min(gentle, creep)), 1.0), AUTOPILOT_CRUISE)


def simulate(g, frac, approach_t, use_manual_brake, start_alt=40000.0, dt=1.0 / 60.0):
    alt = start_alt
    v = 0.0
    t = 0.0
    brake_start_alt = None
    peak = 0.0
    while alt > AUTOPILOT_TOUCHDOWN_ALT and t < 600.0:
        d_target = desired(alt, g, frac, approach_t, use_manual_brake)
        # 重力先把速度往下拉，再按 AUTOPILOT_ACCEL 追踪目标速度
        v += g * dt
        if v < d_target:
            v = min(v + AUTOPILOT_ACCEL * dt, d_target)
        else:
            v = max(v - AUTOPILOT_ACCEL * dt, d_target)
        if brake_start_alt is None and d_target < AUTOPILOT_CRUISE:
            brake_start_alt = alt
        peak = max(peak, v)
        alt -= v * dt
        t += dt
    return t, peak, brake_start_alt


CASES = [
    ("改前：frac 0.35 / 用 AUTOPILOT_ACCEL / 12 秒剖面", 0.35, 12.0, False),
    ("改后：frac 0.90 / 用 SHIP_BRAKE_DECEL / 4 秒剖面", 0.90, 4.0, True),
]

print("=" * 78)
print("从 40000 米、初速 0 落到 2.6 米，总耗时对比")
print("=" * 78)
for label, frac, at, manual in CASES:
    print("\n%s" % label)
    avail = SHIP_BRAKE_DECEL - 20 if manual else AUTOPILOT_ACCEL - 20
    print("  剖面刹车能力 = %.1f m/s²（可用 %.0f × %.2f）" % (max(avail, 30) * frac, max(avail, 30), frac))
    for g in (7.0, 20.0, 32.0):
        t, peak, bstart = simulate(g, frac, at, manual)
        print("    重力 %2.0f → 总耗时 %5.1f 秒（%.2f 分）｜峰值 %.0f m/s｜开始刹车高度 %s 米"
              % (g, t, t / 60.0, peak, ("%.0f" % bstart) if bstart else "-"))

print("\n" + "=" * 78)
print("制动阶段本身：从 2000 m/s 刹到 0")
print("=" * 78)
for label, frac, manual in (("改前", 0.35, False), ("改后", 0.90, True)):
    avail = SHIP_BRAKE_DECEL - 20 if manual else AUTOPILOT_ACCEL - 20
    brake = max(avail, 30) * frac
    dist = 2000 ** 2 / (2 * brake)
    print("  %s：减速度 %6.1f m/s²  刹车距离 %7.0f 米  刹车耗时 %5.1f 秒" % (
        label, brake, dist, 2000 / brake))
print("  手动硬刹（SHIP_BRAKE_DECEL）：减速度 %6.1f m/s²  距离 %7.0f 米  耗时 %5.1f 秒" % (
    SHIP_BRAKE_DECEL, 2000 ** 2 / (2 * SHIP_BRAKE_DECEL), 2000 / SHIP_BRAKE_DECEL))
