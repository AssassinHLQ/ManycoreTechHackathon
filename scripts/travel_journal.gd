extends CanvasLayer

## 旅行小册（阁楼茶几上，按 E 翻开）：收录「谁来到了家里」的五条目。
## 照伴随版 HTML 的原文，全是代码绘制。

var game
var font: Font
var painter: Painter
var open := false

## 五条目：标题 / 引句 / 对应纪念 key（空串表示镜心）
## 字形都取自内嵌字体已覆盖的集合（✦ ◇ ♧ ☂ ◈），不引入新的字体依赖。
const ENTRIES := [
	["✦", "围巾小客人", "留一点空间，\n雪也会靠近炉火。", "snow"],
	["◈", "会飞的折纸", "风翻开一页纸，\n远方便有了翅膀。", "cloud"],
	["♧", "窗边的微光", "跟着一点萤火，\n等一朵光慢慢醒来。", "firefly"],
	["☂", "雨巷的钟声", "把三滴雨对齐，\n时间就重新走动。", "alley"],
	["◇", "镜心的回声", "让镜影安静，\n光才会想起自己。", ""],
]


class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_journal(self)


func setup(host) -> void:
	game = host
	layer = 11
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


func toggle() -> void:
	if open:
		close()
	else:
		open_book()


func open_book() -> void:
	open = true
	painter.visible = true
	painter.queue_redraw()
	if game != null and game.audio != null:
		game.audio.play_ui(580.0)


func close() -> void:
	open = false
	painter.visible = false


func _process(_delta: float) -> void:
	if open:
		painter.queue_redraw()


## 某一条是否已解锁
func entry_seen(index: int) -> bool:
	if game == null:
		return false
	if index < 0 or index >= ENTRIES.size():
		return false
	var key: String = String(ENTRIES[index][3])
	if key == "":
		# 镜心：拿到棱镜之心即算
		return game.has_prism_heart
	return game.keepsakes.has(key)


func seen_count() -> int:
	var total := 0
	for i in range(ENTRIES.size()):
		if entry_seen(i):
			total += 1
	return total


func draw_journal(control: Control) -> void:
	if game == null or font == null:
		return
	var size := control.size
	control.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.045, 0.06, 0.90))
	var panel := Rect2(size * 0.5 - Vector2(430, 300), Vector2(860, 600))
	control.draw_rect(panel, Color(0.11, 0.10, 0.085, 0.98))
	control.draw_rect(panel, Color(0.42, 0.36, 0.26, 0.55), false, 2.0)

	var left := panel.position + Vector2(40, 62)
	control.draw_string(font, left, "旅 行 小 册", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(0.93, 0.90, 0.80))
	control.draw_string(font, left + Vector2(0, 34),
		"不记录远方有多远，只记录谁来到了家里", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(0.72, 0.66, 0.54, 0.9))
	control.draw_string(font, panel.position + Vector2(panel.size.x - 150, 62),
		"%d / 5" % seen_count(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(0.78, 0.70, 0.55, 0.85))

	# 五条目，一列排下来
	var y := panel.position.y + 140.0
	for i in range(ENTRIES.size()):
		var row: Array = ENTRIES[i]
		var seen: bool = entry_seen(i)
		var glyph := String(row[0])
		var title := String(row[1])
		var quote := String(row[2])
		var title_color := Color(0.94, 0.90, 0.78) if seen else Color(0.42, 0.40, 0.36, 0.85)
		var quote_color := Color(0.78, 0.75, 0.66, 0.9) if seen else Color(0.34, 0.33, 0.30, 0.7)
		var glyph_color := Color(0.92, 0.80, 0.52) if seen else Color(0.38, 0.36, 0.32, 0.8)

		control.draw_string(font, Vector2(panel.position.x + 44, y), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, glyph_color)
		if seen:
			control.draw_string(font, Vector2(panel.position.x + 86, y), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, title_color)
			# 引句是两行（带换行），逐行画
			var parts: PackedStringArray = quote.split("\n")
			var qy := y + 26.0
			for part in parts:
				control.draw_string(font, Vector2(panel.position.x + 86, qy), part,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16, quote_color)
				qy += 22.0
			y = qy + 8.0
		else:
			control.draw_string(font, Vector2(panel.position.x + 86, y), "？？？",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, title_color)
			control.draw_string(font, Vector2(panel.position.x + 86, y + 26.0),
				"还没有人来到这里", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, quote_color)
			y += 56.0

	# 底部
	control.draw_string(font, panel.position + Vector2(40, panel.size.y - 26),
		"E / Esc 合上小册", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.56, 0.46, 0.85))
