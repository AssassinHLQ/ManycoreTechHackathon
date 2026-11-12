"""校准 smoke_test 里两条黑洞断言。

背景：2026-11-11 用户要求「黑洞太强了」，把 BH_FORCE_CAPTURE 从 2400 收到 1400、
逃逸层梯度也放缓了。于是 1800 米处的径向引力已低于喷气推力 150，
原来那两条断言（「近处引力超过喷气 150」「近处油耗明显更高」）不再成立。

这两条描述的是**旧参数下的手感**，不是恒定真理。现在按新参数改成校验
「真正的设计意图」，而不是把数字随便改小糊过去：
  · 引力随距离单调增大，且近处（600 米）确实压过常规推力 72
  · 油耗倍率随接近而上升（外圈 1.0 → 内圈 > 2.0）
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

T = Path(__file__).resolve().parent.parent / "tests" / "smoke_test.gd"

OLD_NEAR = '''	bh_ship.global_position = hole + Vector3(0.0, 0.0, 1800.0)
	bh_ship.velocity = Vector3.ZERO
	var near_pull: float = bh_ship._black_hole_pull(0.016).length()
	_check(near_pull > far_pull * 8.0,
		"the black hole pulls harder the closer the ship gets")
	_check(near_pull > 150.0,
		"up close the pull beats even the boost thruster (150)")'''

NEW_NEAR = '''	bh_ship.global_position = hole + Vector3(0.0, 0.0, 1800.0)
	bh_ship.velocity = Vector3.ZERO
	var near_pull: float = bh_ship._black_hole_pull(0.016).length()
	_check(near_pull > far_pull * 8.0,
		"the black hole pulls harder the closer the ship gets")
	# ⚠ 2026-11-11 校准：用户要求减弱黑洞后，1800 米处引力已低于喷气 150。
	#   这里改成校验真正的设计意图 —— 贴近到 600 米时引力必须压过常规推力 72。
	bh_ship.global_position = hole + Vector3(0.0, 0.0, 600.0)
	bh_ship.velocity = Vector3.ZERO
	var close_pull: float = bh_ship._black_hole_pull(0.016).length()
	_check(close_pull > bh_ship.SHIP_THRUST,
		"within 600 m the pull beats the normal thruster (%.0f)" % close_pull)'''

OLD_FUEL = '''	bh_ship.global_position = hole + Vector3(0.0, 0.0, 2400.0)
	bh_ship.velocity = Vector3.ZERO
	bh_ship._black_hole_pull(0.016)
	var mid_fuel: float = bh_ship.bh_fuel_multiplier
	bh_ship.global_position = hole + Vector3(0.0, 0.0, 300.0)
	bh_ship.velocity = Vector3.ZERO
	bh_ship._black_hole_pull(0.016)
	var deep_fuel: float = bh_ship.bh_fuel_multiplier
	_check(mid_fuel > 1.4 and deep_fuel > mid_fuel * 1.4,
		"thrusting near the black hole burns noticeably more propellant")'''

NEW_FUEL = '''	bh_ship.global_position = hole + Vector3(0.0, 0.0, 1800.0)
	bh_ship.velocity = Vector3.ZERO
	bh_ship._black_hole_pull(0.016)
	var mid_fuel: float = bh_ship.bh_fuel_multiplier
	bh_ship.global_position = hole + Vector3(0.0, 0.0, 300.0)
	bh_ship.velocity = Vector3.ZERO
	bh_ship._black_hole_pull(0.016)
	var deep_fuel: float = bh_ship.bh_fuel_multiplier
	# ⚠ 校准同上：2400 米已在减弱后的捕获圈外太多，倍率接近 1。
	#   改从 1800 米量起，校验「越靠近油耗越高」这条设计意图不变。
	_check(mid_fuel > 1.05 and deep_fuel > mid_fuel * 1.4,
		"thrusting near the black hole burns noticeably more propellant")'''


def main() -> None:
    text = T.read_text(encoding="utf-8", errors="replace")
    n = 0
    for old, new in ((OLD_NEAR, NEW_NEAR), (OLD_FUEL, NEW_FUEL)):
        if old in text:
            text = text.replace(old, new)
            n += 1
        else:
            print("没找到块（前 60 字）：", old.strip()[:60])
    T.write_text(text, encoding="utf-8", newline="")
    print("替换 %d/2 块" % n)


if __name__ == "__main__":
    main()
