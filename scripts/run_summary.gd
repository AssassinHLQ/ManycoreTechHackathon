extends CanvasLayer

## 镜牢结算画面：照伴随版 HTML 的 run-summary 版式。
##
## 两种形态：
##   通关      —— 标题「镜牢 · 已净」+ 大字评级（S/A/B）+ 评级说明
##   未通关/中断 —— 标题「镜牢 · 探索结束」+ 「镜门仍在身后」+ 说明
##
## 四个数值：用时 / 受击 / 击杀 / 镜币
## 底下一行：镜印 N 枚 · 抵达第 N 层
## 再一行：最佳纪录 S · 00:00 · 成绩已写入行囊

var game
var font: Font
var painter: Painter
var open := false
## 结算数据
var data: Dictionary = {}


class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_summary(self)


func setup(host) -> void:
	game = host
	layer = 13
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


## 弹出结算
## payload: {cleared, failed, rank, rank_name, rank_note, seconds, hits, kills, coins,
##           rooms, boons, depth, best_rank, best_seconds, is_best, has_best}
func show_summary(payload: Dictionary) -> void:
	data = payload
	open = true
	painter.visible = true
	painter.queue_redraw()
	if game != null and game.audio != null:
		game.audio.play_ui(760.0 if bool(payload.get("cleared", false)) else 340.0)


func close() -> void:
	open = false
	painter.visible = false


func _process(_delta: float) -> void:
	if open:
		painter.queue_redraw()


## 评级配色
func _rank_color(rank: String) -> Color:
	match rank:
		"S":
			return Color(0.98, 0.86, 0.46)
		"A":
			return Color(0.72, 0.92, 0.78)
		"B":
			return Color(0.76, 0.84, 0.92)
		_:
			return Color(0.8, 0.8, 0.8)


func draw_summary(control: Control) -> void:
	if font == null or data.is_empty():
		return
	var size := control.size
	# 半透明底 —— 比全黑浅，能看见身后的镜界
	control.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.72))

	var panel := Rect2(size * 0.5 - Vector2(310, 260), Vector2(620, 520))
	control.draw_rect(panel, Color(0.06, 0.09, 0.12, 0.97))
	var cleared: bool = bool(data.get("cleared", false))
	var border := Color(0.94, 0.82, 0.5, 0.65) if cleared else Color(0.5, 0.6, 0.68, 0.55)
	control.draw_rect(panel, border, false, 2.0)

	var cx := panel.position.x + panel.size.x * 0.5
	var center_align := HORIZONTAL_ALIGNMENT_CENTER

	# 标题
	var title := "镜牢 · 已净" if cleared else "镜牢 · 探索结束"
	control.draw_string(font, Vector2(panel.position.x, panel.position.y + 54.0), title,
		center_align, panel.size.x, 28,
		Color(0.94, 0.97, 0.95) if cleared else Color(0.8, 0.86, 0.9))

	# 新纪录角标
	if bool(data.get("is_best", false)) and cleared:
		control.draw_string(font, Vector2(panel.position.x, panel.position.y + 82.0), "新纪录",
			center_align, panel.size.x, 15, Color(0.98, 0.84, 0.46, 0.95))

	if cleared:
		# 大字评级
		var rank := String(data.get("rank", "B"))
		var rank_name := String(data.get("rank_name", ""))
		var rank_note := String(data.get("rank_note", ""))
		var glyph_y := panel.position.y + 168.0
		control.draw_string(font, Vector2(panel.position.x, glyph_y), rank,
			center_align, panel.size.x, 72, _rank_color(rank))
		control.draw_string(font, Vector2(panel.position.x, glyph_y + 34.0), rank_name,
			center_align, panel.size.x, 20, _rank_color(rank))
		if rank_note != "":
			control.draw_string(font, Vector2(panel.position.x, glyph_y + 62.0), rank_note,
				center_align, panel.size.x, 14, Color(0.68, 0.76, 0.78, 0.9))
	else:
		# 未通关：镜门仍在身后
		var failed: bool = bool(data.get("failed", false))
		control.draw_string(font, Vector2(panel.position.x, panel.position.y + 160.0),
			"◇", center_align, panel.size.x, 44, Color(0.6, 0.7, 0.78, 0.9))
		control.draw_string(font, Vector2(panel.position.x, panel.position.y + 196.0),
			"镜光碎了" if failed else "镜门仍在身后", center_align, panel.size.x, 20,
			Color(0.84, 0.88, 0.9))
		var note := "本次未通关，最佳纪录仍留在行囊" if bool(data.get("has_best", true)) \
			else "本次探索已记下，还没有通关纪录"
		control.draw_string(font, Vector2(panel.position.x, panel.position.y + 224.0), note,
			center_align, panel.size.x, 14, Color(0.66, 0.74, 0.76, 0.9))

	# 四个数值：一行四格
	var stats_y := panel.position.y + 318.0
	var labels := ["用时", "受击", "击杀", "镜币"]
	var values := [
		String(data.get("time_text", "00:00")),
		str(int(data.get("hits", 0))),
		str(int(data.get("kills", 0))),
		"+%d" % int(data.get("coins", 0)),
	]
	var cell_w: float = panel.size.x / 4.0
	for i in range(4):
		var cell_x := panel.position.x + cell_w * float(i)
		control.draw_string(font, Vector2(cell_x, stats_y), String(labels[i]),
			center_align, cell_w, 14, Color(0.6, 0.7, 0.72, 0.85))
		control.draw_string(font, Vector2(cell_x, stats_y + 34.0), String(values[i]),
			center_align, cell_w, 26, Color(0.92, 0.95, 0.92))

	# 镜印 / 层数
	var extra := "镜印 %d 枚 · 抵达第 %d 层" % [int(data.get("boons", 0)), int(data.get("depth", 1))]
	control.draw_string(font, Vector2(panel.position.x, panel.position.y + 392.0), extra,
		center_align, panel.size.x, 15, Color(0.7, 0.78, 0.8, 0.9))

	# 最佳纪录
	var best_rank := String(data.get("best_rank", ""))
	var best_seconds := float(data.get("best_seconds", 0.0))
	var best_tail := " · 成绩已写入行囊"
	if best_rank != "" and best_seconds > 0.0 and game != null and game.progress != null:
		control.draw_string(font, Vector2(panel.position.x, panel.position.y + 426.0),
			"最佳纪录  %s · %s%s" % [best_rank, game.progress.time_text(best_seconds), best_tail],
			center_align, panel.size.x, 15, Color(0.94, 0.85, 0.56, 0.9))

	# 底部提示
	control.draw_string(font, Vector2(panel.position.x, panel.position.y + panel.size.y - 34.0),
		"Enter / E / Esc 收起", center_align, panel.size.x, 15, Color(0.6, 0.7, 0.7, 0.85))
