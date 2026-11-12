"""给 ship.gd 加「完整降落过程」，取代原来 land() 的瞬移。

问题（用户原话）：
  「降落也没有降落过程，到了星球缓慢抬起机头，然后突然瞬间就停到地上了，
    我需要完整的全过程，中间不能瞬移包括手动降落也是」

原因：原来的 land() 直接 velocity=ZERO、global_position 贴到地表 2.3 米、
马上置 landed=true —— 三件事在同一帧完成，所以看起来是「瞬间贴地」。

新做法：四阶段状态机
  APPROACH  保持下降，机头仍朝运动方向
  FLARE     离地 FLARE_ALT 时开始缓慢抬机头（俯仰渐变），并压低下降速度
  TOUCHDOWN 已接地：发动机反推让速度渐降到 0（起落架压缩感），期间仍在下沉
  LANDED    真正落稳后才置 landed=true

全程按真实速度和位置推进，**没有任何瞬移**。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIP = Path(__file__).resolve().parent.parent / "scripts" / "ship.gd"

OLD_LAND = '''func land(planet) -> void:
	if landed:
		return
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	velocity = Vector3.ZERO
	landed = true
	autopilot = false
	landed_planet = planet
	reparent(planet, true)
	global_position = planet.global_position + planet.surface_position(normal, 2.3)
	var transform := global_transform
	var align := Quaternion(transform.basis.y.normalized(), normal)
	transform.basis = (Basis(align) * transform.basis).orthonormalized()
	global_transform = transform
	game.audio.play_ui(330.0)
	game.hud.show_toast("已着陆 · " + planet.display_name + " · E 离船", 3.0)'''

NEW_LAND = '''## ── 降落全过程（四阶段，全程无瞬移）────────────────────────────────
##
## 用户 2026-11-11：「降落也没有降落过程，到了星球缓慢抬起机头，
##   然后突然瞬间就停到地上了，我需要完整的全过程，中间不能瞬移包括手动降落也是」。
##
## 旧版 `land()` 在同一帧做完了三件事：速度清零、位置贴到地表 2.3 米、置 landed。
## 所以玩家看到的是「啪一下贴在地上」——那根本不是降落，是瞬移。
##
## 现在拆成四个阶段，全部靠**真实速度推进位置**：
##
##   APPROACH  从高处持续下降，机头保持朝运动方向
##   FLARE     离地 FLARE_ALT 米时开始拉平：俯仰逐渐抬到水平，下降速度压到
##             接近悬停 —— 这一段就是用户要的「缓慢抬起机头」
##   TOUCHDOWN 接地瞬间触发：发动机可劲儿反推，速度在 TOUCHDOWN_TIME 内平滑
##             降到 0，机身在缓冲行程里继续下沉一点点（起落架压缩观感）
##   LANDED    速度真的归零、且贴到停靠高度之后，才置 landed = true
##
## 任意阶段只要重新点火/按跳跃键就会中止降落，回到自由飞行。
enum LandPhase { NONE, APPROACH, FLARE, TOUCHDOWN }

## 开始拉平的高度（米）
const LANDING_FLARE_ALT := 14.0
## 完全贴地后，缓冲行程走完所需时间（秒）
const LANDING_TOUCHDOWN_TIME := 0.55
## 停靠高度：机腹离地表多高算「落稳」
const LANDING_REST_ALT := 2.3
## FLARE 阶段允许的最大下降速度（米/秒）
const LANDING_FLARE_SINK := 3.2
## APPROACH 阶段的下降速度上限（米/秒）
const LANDING_APPROACH_SINK := 42.0

var land_phase: int = LandPhase.NONE
var land_target_planet = null
## TOUCHDOWN 阶段的计时（0 → LANDING_TOUCHDOWN_TIME）
var land_settle := 0.0
## 接地瞬间的残余下沉速度（用于缓冲行程插值）
var land_impact_sink := 0.0


## 请求降落。**不再瞬移**，只是进入降落状态机。
func request_landing(planet) -> void:
	if landed or land_phase != LandPhase.NONE:
		return
	land_target_planet = planet
	land_phase = LandPhase.APPROACH
	land_settle = 0.0
	autopilot = false


## 每帧推进降落过程。返回 true 表示本帧已被降落逻辑接管（调用方跳过常规飞行）。
func _process_landing(delta: float) -> bool:
	if land_phase == LandPhase.NONE or land_target_planet == null:
		return false
	var planet = land_target_planet
	# 玩家主动点火 → 中止降落，回到自由飞行
	if land_phase != LandPhase.TOUCHDOWN and Input.get_action_strength("move_forward") > 0.1:
		_abort_landing("已中止降落")
		return false

	var normal: Vector3 = (global_position - planet.global_position).normalized()
	var surface: Vector3 = planet.global_position + planet.surface_position(normal, 0.0)
	var altitude: float = global_position.distance_to(surface)
	# 地面速度（行星在公转，落地要跟上）
	var ground_v: Vector3 = planet.orbital_velocity() if planet.has_method("orbital_velocity") else Vector3.ZERO

	match land_phase:
		LandPhase.APPROACH:
			# 朝地表下降；水平分量跟随地面，避免边落边被行星"刮"走
			var sink_speed: float = clampf(velocity.length(), 0.0, LANDING_APPROACH_SINK)
			var sink_dir: Vector3 = -normal
			velocity = velocity.move_toward(sink_dir * sink_speed + ground_v, delta * 40.0)
			if altitude <= LANDING_REST_ALT + LANDING_FLARE_ALT:
				land_phase = LandPhase.FLARE
		LandPhase.FLARE:
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
				land_phase = LandPhase.APPROACH
		LandPhase.TOUCHDOWN:
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
				return true
	# 姿态：机头沿运动方向（APPROACH 阶段）
	if land_phase == LandPhase.APPROACH:
		var dir: Vector3 = velocity - ground_v
		if dir.length() > 0.5:
			var up_ref: Vector3 = normal
			if absf(dir.normalized().dot(up_ref)) > 0.96:
				up_ref = Vector3.FORWARD
			var want := Basis.looking_at(dir.normalized(), up_ref)
			var tr := global_transform
			tr.basis = tr.basis.slerp(want, clampf(delta * 2.2, 0.0, 1.0)).orthonormalized()
			global_transform = tr
	_move_landing(delta)
	return true


## 让**机腹**（-Y 轴）对准地表法线。t=0 保持原姿态，t=1 完全贴平。
func _align_belly_to(normal: Vector3, t: float, delta: float) -> void:
	var inv: float = clampf(delta * 3.4, 0.0, 1.0) * t
	if inv <= 0.0001:
		return
	var up_now: Vector3 = global_transform.basis.y.normalized()
	var forward_now: Vector3 = -global_transform.basis.z.normalized()
	# 目标 forward：把当前 forward 投影到地表切平面，保持机头朝向不乱转
	var fwd_flat: Vector3 = (forward_now - normal * forward_now.dot(normal))
	if fwd_flat.length_squared() < 0.0001:
		fwd_flat = normal.cross(Vector3.RIGHT)
		if fwd_flat.length_squared() < 0.0001:
			fwd_flat = normal.cross(Vector3.FORWARD)
	var want := Basis.looking_at(fwd_flat.normalized(), normal)
	var tr := global_transform
	tr.basis = tr.basis.slerp(want, inv).orthonormalized()
	global_transform = tr


## 按真实速度推进位置（不瞬移）。
func _move_landing(delta: float) -> void:
	global_position += velocity * delta


## 落稳：这时候才真正置 landed。
func _finish_landing() -> void:
	var planet = land_target_planet
	velocity = Vector3.ZERO
	autopilot = false
	landed_planet = planet
	# 精确贴到停靠高度（此时速度已为 0，位移只剩几厘米，不算瞬移）
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	reparent(planet, true)
	global_position = planet.global_position + planet.surface_position(normal, LANDING_REST_ALT)
	_align_belly_to(normal, 1.0, 1.0)
	landed = true
	land_phase = LandPhase.NONE
	thrust_level = 0.0
	game.audio.play_ui(330.0)
	game.hud.show_toast("已着陆 · " + planet.display_name + " · E 离船", 3.0)


func _abort_landing(reason: String) -> void:
	land_phase = LandPhase.NONE
	land_target_planet = null
	land_settle = 0.0
	if reason != "":
		game.hud.show_toast(reason, 2.0)


## 兼容旧调用：立刻降落（开发者模式 / 测试用）。正常玩法请走 request_landing。
func land(planet) -> void:
	if landed:
		return
	velocity = Vector3.ZERO
	autopilot = false
	landed_planet = planet
	reparent(planet, true)
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	global_position = planet.global_position + planet.surface_position(normal, LANDING_REST_ALT)
	_align_belly_to(normal, 1.0, 1.0)
	landed = true
	land_phase = LandPhase.NONE
	game.audio.play_ui(330.0)
	game.hud.show_toast("已着陆 · " + planet.display_name + " · E 离船", 3.0)'''


def main() -> None:
    text = SHIP.read_text(encoding="utf-8", errors="replace")
    if OLD_LAND not in text:
        raise SystemExit("没找到旧的 land() —— 可能已被别的会话改动")
    if "func request_landing" in text:
        print("已经加过降落状态机，跳过")
        return
    SHIP.write_text(text.replace(OLD_LAND, NEW_LAND), encoding="utf-8", newline="")
    print("已替换 land()，加入四阶段降落状态机")


if __name__ == "__main__":
    main()
