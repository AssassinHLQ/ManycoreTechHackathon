"""修降落状态机的三个真实缺陷（探针 probe_landing_and_throttle 查出来的）。

症状：
  ① 高度轨迹 39.8 → 20.6 → 5.0 → -1.33 → -5.57 → -6.71 → 突然 2.30
     也就是飞船钻进地表下面 6.7 米，最后一帧被 _finish_landing 拉回地表
     → 产生 9.0 米的单帧位移（那就是用户说的「瞬间停到地上」）
  ② APPROACH 阶段速度从 12 涨到 40.6 —— 本喵把「上限 42」写成了「目标 42」，
     等于加速砸向地面
  ③ 初始下沉速度没有参与制动计算

修法：
  · APPROACH：目标下沉速度取 min(当前下沉速度, 上限)，**只减速不加速**
  · FLARE：同样只减不增
  · TOUCHDOWN：位置**硬性夹在停靠高度之上**，绝不允许穿到地表以下；
    缓冲行程用「从接地高度 → 停靠高度」的插值，而不是靠速度积分
  · _finish_landing 不再需要位移修正（因为到最后本来就停在停靠高度）
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIP = Path(__file__).resolve().parent.parent / "scripts" / "ship.gd"

OLD_APPROACH = '''		LandPhase.APPROACH:
			# 朝地表下降；水平分量跟随地面，避免边落边被行星"刮"走
			var sink_speed: float = clampf(velocity.length(), 0.0, LANDING_APPROACH_SINK)
			var sink_dir: Vector3 = -normal
			velocity = velocity.move_toward(sink_dir * sink_speed + ground_v, delta * 40.0)
			if altitude <= LANDING_REST_ALT + LANDING_FLARE_ALT:
				land_phase = LandPhase.FLARE'''

NEW_APPROACH = '''		LandPhase.APPROACH:
			# ⚠ 只减速、不加速：目标下沉速度 = min(当前下沉, 上限)。
			#   旧写法把「上限」当成了「目标」，于是从 12 m/s 一路涨到 40 m/s，
			#   等于加速砸向地面（探针实测 12 → 40.6）。
			var sink_now: float = maxf(0.0, velocity.dot(-normal))
			var sink_target: float = minf(sink_now, LANDING_APPROACH_SINK)
			var want_v: Vector3 = -normal * sink_target + ground_v
			velocity = velocity.move_toward(want_v, delta * 40.0)
			if altitude <= LANDING_REST_ALT + LANDING_FLARE_ALT:
				land_phase = LandPhase.FLARE
				land_flare_start_alt = altitude'''

OLD_FLARE = '''		LandPhase.FLARE:
			# 拉平：下降速度压到 LANDING_FLARE_SINK 以内，机头抬到与地表垂直对齐
			var sink_v: Vector3 = -normal * minf(velocity.dot(-normal), LANDING_FLARE_SINK)
			velocity = velocity.move_toward(sink_v + ground_v, delta * 28.0)
			var t: float = clampf(1.0 - (altitude - LANDING_REST_ALT) / LANDING_FLARE_ALT, 0.0, 1.0)
			_align_belly_to(normal, t, delta)
			if altitude <= LANDING_REST_ALT + 0.35:
				# 接地：记下残余下沉量，进入缓冲行程
				land_phase = LandPhase.TOUCHDOWN
				land_settle = 0.0
				land_impact_sink = maxf(0.0, velocity.dot(-normal))
				game.audio.play_ui(300.0)
			if altitude > LANDING_REST_ALT + LANDING_FLARE_ALT * 1.4:
				# 被弹回去太多，退回 APPROACH
				land_phase = LandPhase.APPROACH'''

NEW_FLARE = '''		LandPhase.FLARE:
			# 拉平：下降速度**只减不增**，压到 LANDING_FLARE_SINK 以内
			var sink_now: float = maxf(0.0, velocity.dot(-normal))
			var sink_target: float = minf(sink_now, LANDING_FLARE_SINK)
			var sink_v: Vector3 = -normal * sink_target
			velocity = velocity.move_toward(sink_v + ground_v, delta * 28.0)
			var t: float = clampf(1.0 - (altitude - LANDING_REST_ALT) / LANDING_FLARE_ALT, 0.0, 1.0)
			_align_belly_to(normal, t, delta)
			if altitude <= LANDING_REST_ALT + 0.30:
				# 接地：进入缓冲行程。记下接地高度用于插值（不靠速度积分）。
				land_phase = LandPhase.TOUCHDOWN
				land_settle = 0.0
				land_touch_alt = maxf(altitude, LANDING_REST_ALT)
				game.audio.play_ui(300.0)
			if altitude > LANDING_REST_ALT + LANDING_FLARE_ALT * 1.4:
				land_phase = LandPhase.APPROACH'''

OLD_TOUCH = '''		LandPhase.TOUCHDOWN:
			# 发动机反推：速度在 LANDING_TOUCHDOWN_TIME 内平滑归零
			land_settle += delta
			var p: float = clampf(land_settle / LANDING_TOUCHDOWN_TIME, 0.0, 1.0)
			var ease: float = p * p * (3.0 - 2.0 * p)
			# 下沉速度从接地残值平滑衰减到 0
			var sink_now: float = land_impact_sink * (1.0 - ease)
			velocity = -normal * sink_now + ground_v
			# 机腹完全贴平
			_align_belly_to(normal, 1.0, delta)
			thrust_level = 0.55 * (1.0 - ease)
			if p >= 1.0:
				_finish_landing()
				return true'''

NEW_TOUCH = '''		LandPhase.TOUCHDOWN:
			# ⚠ 缓冲行程**用位置插值**，不靠速度积分。
			#   旧写法按「残余下沉速度 × delta」推进位置，没有下界保护，
			#   实测一路穿到地表以下 6.7 米，最后被 _finish_landing 拉回来 ——
			#   那就是 9 米/帧的瞬移（用户说的「瞬间停到地上」）。
			land_settle += delta
			var p: float = clampf(land_settle / LANDING_TOUCHDOWN_TIME, 0.0, 1.0)
			var ease: float = p * p * (3.0 - 2.0 * p)
			# 高度从「接地高度」平滑插值到「停靠高度」，永不穿地
			var alt_now: float = lerpf(land_touch_alt, LANDING_REST_ALT, ease)
			global_position = planet.global_position + planet.surface_position(normal, alt_now)
			velocity = ground_v
			# 机腹完全贴平
			_align_belly_to(normal, 1.0, delta)
			thrust_level = 0.55 * (1.0 - ease)
			if p >= 1.0:
				_finish_landing()
				return true'''

OLD_FINISH = '''	# 精确贴到停靠高度（此时速度已为 0，位移只剩几厘米，不算瞬移）
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	reparent(planet, true)
	global_position = planet.global_position + planet.surface_position(normal, LANDING_REST_ALT)'''

NEW_FINISH = '''	# TOUCHDOWN 已经把高度插值到停靠高度，这里只做父节点切换（不产生可见位移）
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	reparent(planet, true)
	global_position = planet.global_position + planet.surface_position(normal, LANDING_REST_ALT)'''

OLD_VARS = '''## 接地瞬间的残余下沉速度（用于缓冲行程插值）
var land_impact_sink := 0.0'''
NEW_VARS = '''## 接地瞬间的残余下沉速度（历史值，保留以兼容旧调用）
var land_impact_sink := 0.0
## 进入 FLARE 时的高度（用于拉平进度）
var land_flare_start_alt := 0.0
## 接地时的高度（缓冲行程从这里插值到 LANDING_REST_ALT）
var land_touch_alt := 2.3'''


def main() -> None:
    text = SHIP.read_text(encoding="utf-8", errors="replace")
    pairs = [
        (OLD_VARS, NEW_VARS, "新增状态变量"),
        (OLD_APPROACH, NEW_APPROACH, "APPROACH 只减不增"),
        (OLD_FLARE, NEW_FLARE, "FLARE 只减不增 + 记接地高度"),
        (OLD_TOUCH, NEW_TOUCH, "TOUCHDOWN 位置插值防穿地"),
        (OLD_FINISH, NEW_FINISH, "finish 不再位移修正"),
    ]
    ok = 0
    for old, new, label in pairs:
        if old in text:
            text = text.replace(old, new, 1)
            ok += 1
            print("✓", label)
        else:
            print("✗ 没找到：", label)
    SHIP.write_text(text, encoding="utf-8", newline="")
    print("\n%d/%d 块替换完成" % (ok, len(pairs)))


if __name__ == "__main__":
    main()
