import io

p = r"scripts\player.gd"
s = io.open(p, encoding="utf-8").read()
o = s

# ── 1. 成员：当前所处环境的尺度 ──
old = """var blocked_time := 0.0
var blocked_hint_cooldown := 0.0"""
new = """var blocked_time := 0.0
var blocked_hint_cooldown := 0.0
## 当前所处环境的「世界尺度」。星球表面 = planet.prop_scale（现在 5），
## 站内 / 阁楼这类手工空间 = 1.0。
##
## ⚠ 2026-11-11 用户选了 B 方案：建筑、洞穴、树石全部按 prop_scale ×5 放大，
##   而玩家一直是 8.5 m/s 的人类速度 —— 于是走进一栋 65 米高的塔要 30 秒，
##   walk_test 的「进出门」三条断言全部翻红（局部走了不到 1 米）。
##   所以人也要按同一比例变大：跑得更快、跳得更高、胶囊更大。
##   这样「相对建筑」的手感和放大前一模一样。
var body_scale := 1.0"""
assert s.count(old) == 1, "member anchor"
s = s.replace(old, new)

# ── 2. 胶囊尺寸跟着尺度 ──
old = """	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.65
	collision.shape = capsule
	collision.position.y = 0.82
	add_child(collision)"""
new = """	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# 基准尺寸（body_scale = 1 时的人类尺度）。实际值在 _physics_process 里
	# 按所处环境的 body_scale 更新，见 _apply_body_scale()。
	capsule.radius = 0.34
	capsule.height = 1.65
	collision.shape = capsule
	collision.position.y = 0.82
	add_child(collision)
	_body_collision = collision
	_body_capsule = capsule"""
assert s.count(old) == 1, "capsule anchor"
s = s.replace(old, new)

# ── 3. 成员变量记录胶囊 ──
old = """var body_scale := 1.0"""
new = """var body_scale := 1.0
var _body_collision: CollisionShape3D
var _body_capsule: CapsuleShape3D"""
assert s.count(old) == 1, "collision member anchor"
s = s.replace(old, new)

# ── 4. 在 _physics_process 里按环境决定 scale ──
old = """	_align_up(normal)
	up_direction = normal"""
new = """	_align_up(normal)
	up_direction = normal
	# 星球表面按星球尺度放大，室内（站内 / 阁楼）保持人类尺度。
	var wanted_scale := 1.0
	if not in_station and not game.in_attic and planet != null:
		wanted_scale = planet.prop_scale if planet.prop_scale > 0.0 else 1.0
	_apply_body_scale(wanted_scale)"""
assert s.count(old) == 1, "physics hook anchor"
s = s.replace(old, new)

# ── 5. 速度 / 跳跃 / 喷气按 body_scale ──
old = """	var speed := 8.5
	if Input.is_action_pressed("thrust_down"):
		speed = 15.5
	if focus:
		speed = 4.0"""
new = """	# 速度按 body_scale 缩放：世界大 5 倍，人相对也要跑 5 倍快，
	# 才能维持「相对建筑」的原手感。
	var speed := 8.5 * body_scale
	if Input.is_action_pressed("thrust_down"):
		speed = 15.5 * body_scale
	if focus:
		speed = 4.0 * body_scale"""
assert s.count(old) == 1, "speed anchor"
s = s.replace(old, new)

old = """	horizontal = horizontal.move_toward(wish * speed, delta * (34.0 if is_on_floor() else 12.0))"""
new = """	horizontal = horizontal.move_toward(wish * speed,
		delta * (34.0 if is_on_floor() else 12.0) * body_scale)"""
assert s.count(old) == 1, "accel anchor"
s = s.replace(old, new)

old = """			vertical_speed = 9.5"""
new = """			vertical_speed = 9.5 * body_scale"""
assert s.count(old) == 1, "jump anchor"
s = s.replace(old, new)

old = """		vertical_speed += 46.0 * delta
		vertical_speed = minf(vertical_speed, 17.0)"""
new = """		vertical_speed += 46.0 * delta * body_scale
		vertical_speed = minf(vertical_speed, 17.0 * body_scale)"""
assert s.count(old) == 1, "jetpack anchor"
s = s.replace(old, new)

# ── 6. 相机高度与走路晃动按 body_scale ──
old = """	camera.position.y = 1.48 + sin(bob_time) * minf(planar_speed / 8.5, 1.0) * 0.035"""
new = """	camera.position.y = (1.48 + sin(bob_time) * minf(planar_speed / (8.5 * body_scale), 1.0) * 0.035) * body_scale"""
assert s.count(old) == 1, "camera height anchor"
s = s.replace(old, new)

old = """	if is_on_floor() and planar_speed > 0.5:
		bob_time += delta * planar_speed * 1.25"""
new = """	if is_on_floor() and planar_speed > 0.5 * body_scale:
		bob_time += delta * planar_speed / maxf(body_scale, 0.001) * 1.25"""
assert s.count(old) == 1, "bob anchor"
s = s.replace(old, new)

# ── 7. 新增 _apply_body_scale ──
old = """func _sensitivity_multiplier() -> float:"""
new = """## 把胶囊与「贴地/台阶」相关的容差按 body_scale 重设。
## 只在数值真的变了的时候写一次，避免每帧改碰撞体（会让物理服务器反复重建）。
func _apply_body_scale(wanted: float) -> void:
	if is_equal_approx(wanted, body_scale) and _body_scaled_once:
		return
	body_scale = maxf(wanted, 0.01)
	_body_scaled_once = true
	if _body_capsule != null and _body_collision != null:
		_body_capsule.radius = 0.34 * body_scale
		_body_capsule.height = 1.65 * body_scale
		_body_collision.position.y = 0.82 * body_scale
	# 贴地吸附、台阶余量也要跟着放大，否则大尺度下会被小台阶卡住。
	floor_snap_length = 0.55 * body_scale
	safe_margin = 0.025 * body_scale


func _sensitivity_multiplier() -> float:"""
assert s.count(old) == 1, "helper anchor"
s = s.replace(old, new)

old = """var _body_collision: CollisionShape3D
var _body_capsule: CapsuleShape3D"""
new = """var _body_collision: CollisionShape3D
var _body_capsule: CapsuleShape3D
var _body_scaled_once := false"""
assert s.count(old) == 1
s = s.replace(old, new)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("player.gd body_scale:", o != s)
