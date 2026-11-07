extends CanvasLayer

## 新手引导（旅人初记）：四步分步提示，照伴随版 HTML 的原文。
##
## 流程照原作：
##   · 进入阁楼后约 0.9 秒自动开始第一步
##   · 走到天气旋钮旁 → 第 2 步；推门 → 第 3 步；进过世界 → 第 4 步
##   · 第三步之后 18 秒自动收尾
##   · G 键随时跳过；档案里记「已完成」，之后不再自动出现
##   · 旅人手册里有「重播新手提示」

var game
var font: Font
var painter: Painter
## 是否正在显示
var active := false
## 当前第几步（0 起）
var step := 0
## 总共几步
const STEP_COUNT := 4

## 四步原文（照抄伴随版 HTML）
const STEPS := [
	["先走两步",
		"用 WASD 在阁楼里走动，按住 Shift 可以疾跑；按住鼠标拖动（或点击画面锁定鼠标）环顾四周。"],
	["让窗外换一个世界",
		"走到门边，对准黄铜天气旋钮按 E。窗外会按云海、萤火森林、雨巷、雪夜的顺序轮换。"],
	["推门，跨过门槛",
		"对准门按 E 推开它，再向前跨过门槛。远方就在门外，沿原路走回即可回家。"],
	["看看「此刻的小事」",
		"左上角会列出当前能做的事。完成每个世界的小事，带回纪念放上旅行架；按 H 可随时查看完整手册。"],
]

## 自动收尾的计时（第三步之后）
var auto_timer := 0.0
const AUTO_FINISH := 18.0
## 出现时的淡入动画进度
var fresh := 0.0


class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_guide(self)


func setup(host) -> void:
	game = host
	layer = 9
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


## 开始引导（从第一步）
func begin() -> void:
	active = true
	step = 0
	auto_timer = 0.0
	fresh = 1.0
	_show()


## 推进到第 index 步（只前进，不后退）
func advance(index: int) -> void:
	if not active or index <= step or index >= STEP_COUNT:
		return
	step = index
	fresh = 1.0
	if step >= 3:
		auto_timer = AUTO_FINISH
	if game != null and game.audio != null:
		game.audio.play_ui(640.0)


## 收尾：隐藏并记进存档
func finish() -> void:
	if not active:
		return
	active = false
	auto_timer = 0.0
	_hide()
	if game != null and game.progress != null:
		game.progress.guide_done = true
		game.progress.save()


## G 键跳过
func skip() -> void:
	finish()


func _show() -> void:
	if painter != null:
		painter.visible = true
		painter.queue_redraw()


func _hide() -> void:
	if painter != null:
		painter.visible = false


func _process(delta: float) -> void:
	if not active:
		return
	if fresh > 0.0:
		fresh = maxf(0.0, fresh - delta * 2.4)
	if auto_timer > 0.0:
		auto_timer -= delta
		if auto_timer <= 0.0:
			finish()
			return
	if painter != null and painter.visible:
		painter.queue_redraw()


func draw_guide(control: Control) -> void:
	if font == null:
		return
	# 卡片贴在左下角上方，别挡住中间的视线
	var card_w := 430.0
	var card_h := 150.0
	var origin := Vector2(28.0, control.size.y - card_h - 132.0)
	var alpha: float = 0.88 + 0.12 * (1.0 - fresh)
	control.draw_rect(Rect2(origin, Vector2(card_w, card_h)), Color(0.05, 0.08, 0.10, alpha))
	control.draw_rect(Rect2(origin, Vector2(card_w, card_h)), Color(0.42, 0.62, 0.6, 0.5), false, 1.5)

	# 标题行：旅人初记 + G · 跳过
	var head := origin + Vector2(18.0, 26.0)
	control.draw_string(font, head, "旅 人 初 记", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(0.72, 0.84, 0.80, 0.9))
	control.draw_string(font, origin + Vector2(card_w - 88.0, 26.0), "G · 跳过",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.7, 0.7, 0.75))

	# 步骤标题
	var title := String(STEPS[step][0])
	control.draw_string(font, origin + Vector2(18.0, 62.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.94, 0.97, 0.95))

	# 正文：按宽度手动折行
	var body := String(STEPS[step][1])
	var lines := _wrap(body, card_w - 36.0, 15)
	var by := origin.y + 90.0
	for line in lines:
		control.draw_string(font, Vector2(origin.x + 18.0, by), String(line),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.76, 0.85, 0.84, 0.95))
		by += 21.0

	# 圆点进度
	var dot_y := origin.y + card_h - 16.0
	for i in range(STEP_COUNT):
		var dot_x := origin.x + 18.0 + float(i) * 16.0
		var color := Color(0.42, 0.5, 0.5, 0.7)
		if i < step:
			color = Color(0.55, 0.82, 0.68, 0.9)
		elif i == step:
			color = Color(0.96, 0.88, 0.6, 0.95)
		control.draw_circle(Vector2(dot_x, dot_y), 4.0, color)


## 按像素宽度折行（中文按字切）
func _wrap(text: String, max_width: float, size: int) -> Array:
	var lines: Array = []
	var current := ""
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		var candidate := current + ch
		if _text_width(candidate, size) > max_width and current != "":
			lines.append(current)
			current = ch
		else:
			current = candidate
	if current != "":
		lines.append(current)
	return lines


func _text_width(text: String, size: int) -> float:
	if font == null:
		return float(text.length()) * float(size) * 0.55
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
