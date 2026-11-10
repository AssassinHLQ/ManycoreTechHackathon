extends CanvasLayer

## 门后世界的三个小游戏，照同伴版 HTML 的规则实现：
##   chime   云海「风律回响」——听四声风铃，A/S/D/F 原样奏回去，共 6 轮，3 颗心
##   firefly 萤火「萤火引路」——W/S 在三根树根间穿行，躲横枝、收微光，坚持 40 秒
##   rain    雨巷「檐雨合拍」——四列音符落进石槽，A/S/D/F 按节拍接住，33 秒
##
## 全部用代码绘制（与项目其它 UI 一致），不引入贴图。

const CHIME_KEYS := ["KeyA", "KeyS", "KeyD", "KeyF"]
const CHIME_LABELS := ["A", "S", "D", "F"]
const CHIME_NAMES := ["回风", "檐风", "静风", "石槽"]
const CHIME_FREQS := [587.33, 659.25, 783.99, 987.77]

const RAIN_LABELS := ["A", "S", "D", "F"]
const RAIN_NAMES := ["檐左", "檐中", "檐右", "石槽"]

const FIREFLY_LANES := 3
const FIREFLY_DURATION := 40.0
const RAIN_DURATION := 33.0
const CHIME_ROUNDS := 6

var game
var font: Font
var painter: Painter
var active := false
var kind := ""
var best: Dictionary = {}

# --- 通用 ---
var hearts := 3
var score := 0
var time := 0.0
var hint := ""
var finished_once := false

# --- 风律回响 ---
var sequence: Array = []
var phase := "idle"
var play_index := 0
var play_timer := 0.0
var input_index := 0
var round_index := 1
var lit_chime := -1
var lit_timer := 0.0
var wrong_flash := 0.0

# --- 萤火引路 ---
var lane := 1
var lane_pos := 1.0
var obstacles: Array = []
var glints: Array = []
var motes := 0
var spawn_timer := 0.8
var glint_timer := 0.7
var invuln := 0.0

# --- 檐雨合拍 ---
var notes: Array = []
var combo := 0
var best_combo := 0
var flashes := [0.0, 0.0, 0.0, 0.0]
var rain_drops: Array = []


class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_board(self)


func setup(host) -> void:
	game = host
	layer = 1
	font = load("res://assets/ui_font.ttf")
	if font == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
		font = system_font
	painter = Painter.new()
	painter.layer = self
	painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painter.visible = false
	add_child(painter)


func open(which: String) -> bool:
	if active:
		return false
	if not ["chime", "firefly", "rain"].has(which):
		return false
	kind = which
	active = true
	finished_once = false
	hearts = 3
	score = 0
	time = 0.0
	combo = 0
	best_combo = 0
	lit_chime = -1
	lit_timer = 0.0
	wrong_flash = 0.0
	match kind:
		"chime":
			round_index = 1
			_start_chime_round()
			hint = "风会先奏一遍 · 听清 A / S / D / F"
		"firefly":
			lane = 1
			lane_pos = 1.0
			obstacles.clear()
			glints.clear()
			motes = 0
			spawn_timer = 0.8
			glint_timer = 0.7
			invuln = 0.0
			hint = "W / S 在三条树根间移动 · 躲开横枝，收集微光"
		"rain":
			_build_rain_song()
			for i in range(4):
				flashes[i] = 0.0
			hint = "雨点落进石槽的一瞬按下对应的 A / S / D / F"
	painter.visible = true
	painter.queue_redraw()
	return true


func close() -> void:
	active = false
	kind = ""
	phase = "idle"
	painter.visible = false


func _process(delta: float) -> void:
	if not active:
		return
	var step := minf(delta, 0.05)
	time += step
	if lit_timer > 0.0:
		lit_timer -= step
		if lit_timer <= 0.0:
			lit_chime = -1
	if wrong_flash > 0.0:
		wrong_flash -= step
	match kind:
		"chime":
			_update_chime(step)
		"firefly":
			_update_firefly(step)
		"rain":
			_update_rain(step)
	painter.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: String = OS.get_keycode_string((event as InputEventKey).physical_keycode)
	if code == "Escape":
		close()
		if game != null:
			game.minigame_open = false
		return
	_press(code)
	get_viewport().set_input_as_handled()


func _beep(freq: float, _duration := 0.2) -> void:
	if game == null or game.audio == null:
		return
	var audio = game.audio
	if audio.has_method("play_ui"):
		audio.play_ui(freq)


# ===================== 风律回响 =====================
func _start_chime_round() -> void:
	sequence.clear()
	var length: int = 2 + round_index
	for i in range(length):
		sequence.append(randi() % 4)
	input_index = 0
	phase = "play"
	play_index = 0
	play_timer = 0.9


func _update_chime(step: float) -> void:
	if phase != "play":
		return
	play_timer -= step
	if play_timer > 0.0:
		return
	if play_index >= sequence.size():
		phase = "input"
		input_index = 0
		hint = "轮到你了 · %d 声" % sequence.size()
		return
	var note: int = sequence[play_index]
	play_index += 1
	lit_chime = note
	lit_timer = 0.32
	_beep(CHIME_FREQS[note], 0.4)
	play_timer = 0.62


func _chime_press(index: int) -> void:
	if phase != "input":
		return
	var expected: int = sequence[input_index]
	lit_chime = index
	lit_timer = 0.2
	_beep(CHIME_FREQS[index], 0.2)
	if index == expected:
		input_index += 1
		score += 3
		if input_index >= sequence.size():
			score += 40 + hearts * 6
			if round_index >= CHIME_ROUNDS:
				_finish(true, "六段来风都记住了 · 风把回声还给了你")
				return
			round_index += 1
			hint = "这一轮记住了 · 风又起"
			_start_chime_round()
		else:
			hint = "跟上 · %d / %d" % [input_index, sequence.size()]
	else:
		hearts -= 1
		score = maxi(0, score - 8)
		wrong_flash = 0.42
		if hearts <= 0:
			_finish(false, "风从指缝里散开了 · 安静一会儿再听")
			return
		hint = "错了 · 风还记得，再听一遍"
		phase = "play"
		input_index = 0
		play_index = 0
		play_timer = 0.85


# ===================== 萤火引路 =====================
func _update_firefly(step: float) -> void:
	lane_pos = lerpf(lane_pos, float(lane), minf(1.0, step * 9.0))
	if invuln > 0.0:
		invuln -= step
	var speed_scale: float = 1.0 + minf(0.9, time / 34.0)
	spawn_timer -= step
	glint_timer -= step
	if spawn_timer <= 0.0:
		var wide: bool = randf() < 0.18
		obstacles.append({"x": 1.12, "lane": randi() % FIREFLY_LANES, "wide": wide})
		spawn_timer = maxf(0.62, 1.35 - time * 0.012) * randf_range(0.85, 1.25)
	if glint_timer <= 0.0:
		glints.append({"x": 1.1, "lane": randi() % FIREFLY_LANES})
		glint_timer = randf_range(0.62, 1.12)
	var player_x := 0.265
	for obstacle in obstacles:
		obstacle["x"] = float(obstacle["x"]) - step * 0.19 * speed_scale
		if time > 0.9 and float(obstacle["x"]) < player_x + 0.026 and float(obstacle["x"]) > player_x - 0.05:
			var lanes: Array = [int(obstacle["lane"])]
			if bool(obstacle["wide"]):
				lanes.append(int(obstacle["lane"]) + 1)
			for candidate in lanes:
				if absf(lane_pos - float(candidate)) < 0.46 and invuln <= 0.0:
					_hit_firefly()
					break
	obstacles = obstacles.filter(func(o): return float(o["x"]) > 0.1)
	for glint in glints:
		glint["x"] = float(glint["x"]) - step * 0.22 * speed_scale
		if float(glint["x"]) < player_x + 0.04 and float(glint["x"]) > player_x - 0.05:
			if absf(lane_pos - float(glint["lane"])) < 0.6:
				glint["taken"] = true
				motes += 1
				score += 9
				_beep(880.0 + float(motes % 5) * 60.0, 0.18)
	glints = glints.filter(func(g): return not bool(g.get("taken", false)) and float(g["x"]) > 0.1)
	hint = "微光 %d · 坚持 %d 秒" % [motes, int(maxf(0.0, FIREFLY_DURATION - time))]
	if time >= FIREFLY_DURATION:
		score += int(time * 2.0) + 40
		_finish(true, "萤火穿过了整条夜路 · 收下 %d 簇微光" % motes)


func _hit_firefly() -> void:
	hearts -= 1
	invuln = 0.95
	score = maxi(0, score - 6)
	_beep(140.0, 0.3)
	if hearts <= 0:
		_finish(false, "夜路在树根间停住了 · 带回了 %d 簇微光" % motes)
	else:
		hint = "撞到横枝 · 还剩 %d 颗心" % hearts


# ===================== 檐雨合拍 =====================
func _build_rain_song() -> void:
	notes.clear()
	var at := 1.3
	var seed_value := 77
	while at < RAIN_DURATION - 3.0:
		seed_value = (seed_value * 16807) % 2147483647
		var line := float(seed_value) / 2147483647.0
		var lane_pick: int = int(line * 4.0) % 4
		notes.append({"at": at, "lane": lane_pick, "hit": false, "missed": false})
		seed_value = (seed_value * 16807) % 2147483647
		if float(seed_value) / 2147483647.0 < 0.22:
			notes.append({"at": at, "lane": (lane_pick + 2) % 4, "hit": false, "missed": false})
		at += randf_range(0.42, 0.76)
	notes.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	rain_drops.clear()
	for i in range(60):
		rain_drops.append({"x": randf(), "y": randf(), "speed": randf_range(0.35, 0.95)})


func _update_rain(step: float) -> void:
	for i in range(4):
		if flashes[i] > 0.0:
			flashes[i] -= step
	for note in notes:
		if bool(note["hit"]) or bool(note["missed"]):
			continue
		if time - float(note["at"]) > 0.24:
			note["missed"] = true
			hearts -= 1
			combo = 0
			score = maxi(0, score - 4)
			_beep(120.0, 0.12)
			if hearts <= 0:
				_finish(false, "雨声乱了一拍 · 最高连击 %d" % best_combo)
				return
			hint = "漏了一滴 · 还剩 %d 颗心" % hearts
	var all_done := true
	for note in notes:
		if not bool(note["hit"]) and not bool(note["missed"]):
			all_done = false
			break
	if all_done or time > RAIN_DURATION:
		score += hearts * 25 + int(float(best_combo) * 1.5)
		_finish(true, "整条雨巷跟上了节拍 · 最高连击 %d" % best_combo)


func _rain_press(index: int) -> void:
	flashes[index] = 0.16
	var picked = null
	var best_delta := 99.0
	for note in notes:
		if bool(note["hit"]) or bool(note["missed"]) or int(note["lane"]) != index:
			continue
		var delta: float = absf(float(note["at"]) - time)
		if delta < best_delta:
			best_delta = delta
			picked = note
	if picked == null or best_delta > 0.24:
		_beep(160.0, 0.06)
		return
	picked["hit"] = true
	var perfect: bool = best_delta <= 0.1
	combo += 1
	best_combo = maxi(best_combo, combo)
	score += (10 if perfect else 6) + int(float(combo) / 8.0)
	_beep(RAIN_FREQ(index) + (120.0 if perfect else 0.0), 0.16)
	hint = "正好 · 雨水落进石槽" if perfect else "接住了 · 再稳一点"


func RAIN_FREQ(index: int) -> float:
	return [392.0, 523.25, 659.25, 783.99][clampi(index, 0, 3)]


# ===================== 输入分派 / 结束 =====================
func _press(code: String) -> void:
	match kind:
		"chime":
			var chime_index: int = CHIME_KEYS.find(code)
			if chime_index >= 0:
				_chime_press(chime_index)
		"firefly":
			if code == "KeyW" or code == "ArrowUp":
				lane = clampi(lane - 1, 0, FIREFLY_LANES - 1)
				_beep(420.0 + float(lane) * 90.0, 0.12)
			elif code == "KeyS" or code == "ArrowDown":
				lane = clampi(lane + 1, 0, FIREFLY_LANES - 1)
				_beep(420.0 + float(lane) * 90.0, 0.12)
		"rain":
			var rain_index: int = CHIME_KEYS.find(code)
			if rain_index >= 0:
				_rain_press(rain_index)


func _finish(complete: bool, message: String) -> void:
	if finished_once:
		return
	finished_once = true
	phase = "done"
	var previous: int = int(best.get(kind, 0))
	if score > previous:
		best[kind] = score
	if game != null:
		game.on_minigame_finished(kind, score, complete, message, previous)
	close()
	if game != null:
		game.minigame_open = false


# ===================== 绘制 =====================
func draw_board(control: Control) -> void:
	var size := control.size
	match kind:
		"chime":
			_draw_chime(control, size)
		"firefly":
			_draw_firefly(control, size)
		"rain":
			_draw_rain(control, size)


func _draw_frame(control: Control, size: Vector2, top: Color, bottom: Color) -> void:
	control.draw_rect(Rect2(Vector2.ZERO, size), bottom)
	control.draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.55)), top)


func _draw_hud(control: Control, size: Vector2, title: String) -> void:
	var hearts_text := ""
	for i in range(3):
		hearts_text += "♥ " if i < hearts else "♡ "
	control.draw_string(font, Vector2(28, 40), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92, 0.96, 0.95))
	control.draw_string(font, Vector2(28, 68), hearts_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.85, 0.75))
	control.draw_string(font, Vector2(size.x - 160, 40), "%d 分" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92, 0.96, 0.95))
	control.draw_string(font, Vector2(28, size.y - 28), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.78, 0.88, 0.88, 0.85))
	control.draw_string(font, Vector2(size.x - 210, size.y - 28), "Esc 离开", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.8, 0.8, 0.6))


func _draw_chime(control: Control, size: Vector2) -> void:
	_draw_frame(control, size, Color("1a2430"), Color("0d141c"))
	_draw_hud(control, size, "风律回响 · 第 %d / %d 轮" % [round_index, CHIME_ROUNDS])
	var base_y := size.y * 0.52
	var step := size.x / 5.2
	for i in range(4):
		var center := Vector2(size.x * 0.5 + (float(i) - 1.5) * step, base_y)
		var lit: bool = i == lit_chime
		var ring := Color(0.86, 0.93, 0.98) if lit else Color(0.42, 0.5, 0.56)
		control.draw_circle(center, 54.0, Color(ring, 0.22 if lit else 0.1))
		control.draw_circle(center, 34.0, ring)
		control.draw_string(font, center + Vector2(-9, 9), CHIME_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("101a22"))
		control.draw_string(font, center + Vector2(-22, 84), CHIME_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.83, 0.86, 0.8))
	var total: int = sequence.size()
	for i in range(total):
		var x := size.x * 0.5 - float(total) * 9.0 + float(i) * 18.0
		var color := Color(0.55, 0.62, 0.66, 0.5)
		if i < input_index:
			color = Color(0.72, 0.92, 0.82)
		elif i == input_index and phase == "input":
			color = Color(0.95, 0.87, 0.6)
		control.draw_circle(Vector2(x, base_y + 128.0), 5.0, color)
	if wrong_flash > 0.0:
		control.draw_rect(Rect2(Vector2.ZERO, size), Color(0.72, 0.3, 0.26, wrong_flash * 0.5))


func _draw_firefly(control: Control, size: Vector2) -> void:
	_draw_frame(control, size, Color("0a211b"), Color("04120f"))
	_draw_hud(control, size, "萤火引路 · %d 秒" % int(maxf(0.0, FIREFLY_DURATION - time)))
	# 三条树根
	for i in range(FIREFLY_LANES):
		var y := lane_y(size, i)
		var active_lane: bool = i == lane
		control.draw_line(Vector2(0, y), Vector2(size.x, y),
			Color(0.42, 0.66, 0.45, 0.5 if active_lane else 0.18), 2.0 if active_lane else 1.0)
	# 横枝
	for obstacle in obstacles:
		var x := float(obstacle["x"]) * size.x
		var lanes: Array = [int(obstacle["lane"])]
		if bool(obstacle["wide"]):
			lanes.append(int(obstacle["lane"]) + 1)
		for candidate in lanes:
			var y2 := lane_y(size, candidate)
			control.draw_rect(Rect2(Vector2(x - 20.0, y2 - 12.0), Vector2(40.0, 24.0)), Color(0.24, 0.14, 0.1, 0.95))
			control.draw_rect(Rect2(Vector2(x - 20.0, y2 - 3.0), Vector2(40.0, 4.0)), Color(0.47, 0.33, 0.21, 0.7))
	# 微光
	for glint in glints:
		var center := Vector2(float(glint["x"]) * size.x, lane_y(size, int(glint["lane"])))
		control.draw_circle(center, 14.0, Color(0.93, 1.0, 0.7, 0.22))
		control.draw_circle(center, 4.0, Color(0.97, 1.0, 0.85))
	# 萤火本体
	var player_center := Vector2(size.x * 0.265, lane_y(size, 0) + lane_pos * size.y * 0.22)
	var alpha := 0.35 if (invuln > 0.0 and int(time * 30.0) % 2 == 0) else 1.0
	control.draw_circle(player_center, 20.0, Color(1.0, 1.0, 0.8, 0.18 * alpha))
	control.draw_circle(player_center, 7.0, Color(0.99, 1.0, 0.81, alpha))


func lane_y(size: Vector2, index: int) -> float:
	return size.y * (0.32 + float(index) * 0.22)


func _draw_rain(control: Control, size: Vector2) -> void:
	_draw_frame(control, size, Color("0d1b26"), Color("071018"))
	_draw_hud(control, size, "檐雨合拍 · 连击 %d" % combo)
	var hit_y := size.y * 0.82
	for drop in rain_drops:
		var p := Vector2(float(drop["x"]) * size.x, float(drop["y"]) * size.y)
		control.draw_line(p, p + Vector2(-2.0, 14.0), Color(0.65, 0.77, 0.8, 0.25), 1.0)
		drop["y"] = float(drop["y"]) + 0.004 * float(drop["speed"])
		if float(drop["y"]) > 1.05:
			drop["y"] = -0.05
			drop["x"] = randf()
	for i in range(4):
		var x := size.x * (0.2 + float(i) * 0.2)
		control.draw_line(Vector2(x, size.y * 0.16), Vector2(x, hit_y), Color(0.74, 0.86, 0.88, 0.16), 1.5)
		var flash: float = flashes[i]
		var slot := Color(1.0, 0.88, 0.65, 0.55) if flash > 0.0 else Color(0.82, 0.9, 0.9, 0.12)
		control.draw_rect(Rect2(Vector2(x - 26.0, hit_y - 6.0), Vector2(52.0, 12.0)), slot)
		control.draw_string(font, Vector2(x - 6.0, hit_y + 34.0), RAIN_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.95, 0.93, 0.8))
		control.draw_string(font, Vector2(x - 16.0, hit_y + 56.0), RAIN_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.86, 0.86, 0.45))
	for note in notes:
		if bool(note["hit"]) or bool(note["missed"]):
			continue
		var remain: float = float(note["at"]) - time
		if remain > 2.5 or remain < -0.4:
			continue
		var progress := 1.0 - clampf(remain / 2.5, 0.0, 1.0)
		var x2 := size.x * (0.2 + float(int(note["lane"])) * 0.2)
		var y2 := lerpf(size.y * 0.16, hit_y, progress)
		control.draw_circle(Vector2(x2, y2), 12.0, Color(0.82, 0.96, 0.97, 0.85))
		control.draw_circle(Vector2(x2, y2), 5.0, Color(0.95, 1.0, 0.99))
