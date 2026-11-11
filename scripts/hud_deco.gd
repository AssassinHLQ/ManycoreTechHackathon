extends Control
## HUD 装饰层：给面板加「仪表盘」质感。
##
## 为什么单独一层而不是塞进 hud_draw：
##   hud_draw 已经 410 行、管着准星/标记/星图那一整套，再往里加会让它更难维护。
##   这一层只做装饰，可以随时 on/off，也不影响任何现有绘制。
##
## 这里画的东西全部是**纯代码**，不依赖贴图：
##   · 切角面板框（chamfered rect）—— 直线 + 45° 斜角，比圆角更像仪表盘
##   · 四角括号（corner brackets）—— 科幻 UI 最标志性的元素
##   · 扫描线（scanlines）—— 极低透明度的横线，远看是「屏幕感」
##   · 刻度（ticks）—— 沿边缘的短竖线，像仪表刻度
##
## 全部用 draw_ 系列，所以任意分辨率都锐利，不需要导入素材。

## 主题色。和 hud.gd 里的青色系保持一致。
const INK := Color(0.42, 0.78, 0.80, 1.0)
const INK_SOFT := Color(0.42, 0.78, 0.80, 0.34)
const AMBER := Color(0.90, 0.72, 0.45, 1.0)

var game
var font: Font

## 面板矩形：由 hud.gd 在布局完成后填进来。
## 每项是 {rect: Rect2, accent: Color, label: String}
var frames: Array = []

## 状态条的分段刻度：{rect: Rect2, color: Color}
var bar_ticks: Array = []

## 面板网格底纹：{rect: Rect2, alpha: float}
var grid_rects: Array = []

## 环形燃料表参数，由 hud.gd 每帧更新
## ⚠ 默认 gauge_center 必须是「未设置」而不是 ZERO ——
##   ZERO 会被当成合法坐标，在 hud.gd 还没跑到 _update_gauge 时
##   环就被画到屏幕左上角（实测踩过，截图里左上角挂着一个半截环）。
var gauge_center := Vector2(-99999, -99999)
var gauge_radius := 30.0
var gauge_value := 1.0

var _grid_tex: Texture2D


## 环形表：自己画自己。
##
## ⚠ 为什么要做成独立节点而不是让 deco 统一画：
##   之前 deco 拿着 hud.gd 传来的「屏幕坐标」去画，需要跨 CanvasLayer →
##   Control → 面板 三层做坐标换算，实测在窗口模式/不同视口尺寸下会错位
##   （环跑到屏幕左上角，或者干脆画不出来）。
##   改成让环当 status_panel 的子节点、用**自己的局部坐标**画，
##   位置就由 Godot 的布局系统管，永远不会错。
class RingGauge extends Control:
	var value := 1.0
	var font: Font
	var accent := Color(0.95, 0.72, 0.42, 0.95)
	var ring_color := Color(0.16, 0.34, 0.38, 0.55)
	var tick_on := Color(0.42, 0.78, 0.80, 0.85)
	var tick_off := Color(0.2, 0.36, 0.4, 0.5)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: float) -> void:
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 3.0
		if r <= 2.0:
			return
		# 底环
		draw_arc(c, r, 0.0, TAU, 56, ring_color, 3.0, true)
		# 12 段刻度，每 3 段一根长的
		for i in range(12):
			var ang := -PI * 0.5 + TAU * float(i) / 12.0
			var dir := Vector2(cos(ang), sin(ang))
			var lit: bool = float(i) / 12.0 <= value
			var ln: float = 5.0 if i % 3 == 0 else 3.0
			draw_line(c + dir * (r - ln), c + dir * r,
				tick_on if lit else tick_off, 1.0 if i % 3 else 1.5)
		# 已用量弧
		if value > 0.001:
			draw_arc(c, r - 6.0, -PI * 0.5, -PI * 0.5 + TAU * value, 48, accent, 3.0, true)
		# 中心数字
		if font != null:
			var txt := "%d" % int(round(value * 100.0))
			draw_string(font, c + Vector2(-14, 5), txt, HORIZONTAL_ALIGNMENT_CENTER, 28, 15,
				Color(0.98, 0.88, 0.70, 0.98))

## 扫描线开关（可运行时关，方便截图对比）
var scanlines := true
## 扫描线间距（像素）。太密会闪，3~4 比较稳。
const SCAN_STEP := 3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 注册一块要装饰的面板。hud.gd 在摆好布局后调它。
func add_frame(rect: Rect2, accent := INK, label := "") -> void:
	frames.append({"rect": rect, "accent": accent, "label": label})
	queue_redraw()


func clear_frames() -> void:
	frames.clear()
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var view := get_viewport_rect().size

	# 1) 扫描线：整屏铺一层，透明度极低
	if scanlines:
		var y := 0.0
		while y < view.y:
			draw_line(Vector2(0, y), Vector2(view.x, y), Color(0, 0.05, 0.08, 0.16), 1.0)
			y += SCAN_STEP

	# 2) 每块面板的装饰
	for item in frames:
		var r: Rect2 = item["rect"]
		var accent: Color = item["accent"]
		_draw_chamfer_frame(r, accent)
		_draw_corner_brackets(r, accent)
		if String(item["label"]) != "":
			_draw_edge_label(r, accent, String(item["label"]))

	# 3) 状态条的分段刻度
	for t in bar_ticks:
		var br: Rect2 = t["rect"]
		draw_bar_ticks(br, t["color"], 10)

	# 4) 面板网格底纹（Grid.png 平铺，极低透明度，让面板内部不空）
	if _grid_tex == null:
		var gp := "res://assets/ui/wenrexa/Grid.png"
		if ResourceLoader.exists(gp):
			_grid_tex = load(gp)
	if _grid_tex != null:
		for g in grid_rects:
			var gr: Rect2 = g["rect"]
			var a: float = g["alpha"]
			draw_texture_rect(_grid_tex, gr, true, Color(0.45, 0.85, 0.90, a))

	# 5) 环形燃料表已经改由 RingGauge 节点自绘（见 hud_deco.gd 里的 RingGauge），
	#    这里不再重复画 —— 之前的 deco 统一绘制需要跨层坐标换算，会错位。


## 环形表：外圈底环 + 12 段刻度 + 已用量弧 + 中心百分比。
func _draw_ring_gauge() -> void:
	var c := gauge_center
	var r := gauge_radius
	# 底环
	draw_arc(c, r, 0.0, TAU, 64, Color(0.16, 0.34, 0.38, 0.55), 3.0, true)
	# 12 段刻度
	for i in range(12):
		var ang := -PI * 0.5 + TAU * float(i) / 12.0
		var dir := Vector2(cos(ang), sin(ang))
		var lit := float(i) / 12.0 <= gauge_value
		var len := 5.0 if i % 3 == 0 else 3.0
		draw_line(c + dir * (r - len), c + dir * r,
			Color(0.42, 0.78, 0.80, 0.85) if lit else Color(0.2, 0.36, 0.4, 0.5),
			1.5 if i % 3 == 0 else 1.0)
	# 已用量弧：从 -90° 顺时针
	if gauge_value > 0.001:
		var end := -PI * 0.5 + TAU * gauge_value
		draw_arc(c, r - 8.0, -PI * 0.5, end, 48,
			Color(0.95, 0.72, 0.42, 0.95), 3.0, true)
	# 中心百分比
	if font != null:
		var txt := "%d" % int(round(gauge_value * 100.0))
		draw_string(font, c + Vector2(-11, 5), txt, HORIZONTAL_ALIGNMENT_CENTER, 22, 13,
			Color(0.95, 0.85, 0.68, 0.95))
		if font != null:
			draw_string(font, c + Vector2(-8, 17), "%", HORIZONTAL_ALIGNMENT_CENTER, 16, 9,
				Color(0.72, 0.62, 0.45, 0.8))


## 切角矩形：四角各切掉 c 像素。
func _chamfer_path(r: Rect2, c: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var l := r.position.x
	var t := r.position.y
	var rt := r.position.x + r.size.x
	var b := r.position.y + r.size.y
	# 顺时针：左上切角 -> 右上 -> 右下 -> 左下
	p.append(Vector2(l + c, t))
	p.append(Vector2(rt - c, t))
	p.append(Vector2(rt, t + c))
	p.append(Vector2(rt, b - c))
	p.append(Vector2(rt - c, b))
	p.append(Vector2(l + c, b))
	p.append(Vector2(l, b - c))
	p.append(Vector2(l, t + c))
	p.append(Vector2(l + c, t))
	return p


func _draw_chamfer_frame(r: Rect2, accent: Color) -> void:
	var path := _chamfer_path(r, 10.0)
	# 双层描边：外圈更淡、内圈实一点，做出「边框有厚度」的错觉
	draw_polyline(path, Color(accent.r, accent.g, accent.b, 0.22), 3.0, true)
	draw_polyline(path, Color(accent.r, accent.g, accent.b, 0.72), 1.2, true)
	# 内侧再缩 3px 画一条更淡的线
	var inner := _chamfer_path(r.grow(-3.0), 8.0)
	draw_polyline(inner, Color(accent.r, accent.g, accent.b, 0.16), 1.0, true)


## 四角括号：每角两条短线，比整圈框更有「瞄准/锁具」感。
func _draw_corner_brackets(r: Rect2, accent: Color) -> void:
	var arm := 18.0
	var thick := 2.0
	var c := Color(accent.r, accent.g, accent.b, 0.95)
	var l := r.position.x
	var t := r.position.y
	var rt := r.position.x + r.size.x
	var b := r.position.y + r.size.y

	# 左上
	draw_line(Vector2(l, t + 10), Vector2(l, t + 10 + arm), c, thick)
	draw_line(Vector2(l + 10, t), Vector2(l + 10 + arm, t), c, thick)
	# 右上
	draw_line(Vector2(rt, t + 10), Vector2(rt, t + 10 + arm), c, thick)
	draw_line(Vector2(rt - 10, t), Vector2(rt - 10 - arm, t), c, thick)
	# 右下
	draw_line(Vector2(rt, b - 10), Vector2(rt, b - 10 - arm), c, thick)
	draw_line(Vector2(rt - 10, b), Vector2(rt - 10 - arm, b), c, thick)
	# 左下
	draw_line(Vector2(l, b - 10), Vector2(l, b - 10 - arm), c, thick)
	draw_line(Vector2(l + 10, b), Vector2(l + 10 + arm, b), c, thick)


## 面板右上角的标签 + 一条渐隐分隔线。让面板「像是仪器而不是对话框」。
func _draw_edge_label(r: Rect2, accent: Color, text: String) -> void:
	if font == null:
		return
	var p := Vector2(r.position.x + r.size.x - 14, r.position.y + 18)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12,
		Color(accent.r, accent.g, accent.b, 0.85))
	# 标签下方一条渐隐横线
	var y := r.position.y + 25
	var x0 := r.position.x + r.size.x * 0.45
	var x1 := r.position.x + r.size.x - 14
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(accent.r, accent.g, accent.b, 0.06), 1.0)
	draw_line(Vector2(x0 + (x1 - x0) * 0.6, y), Vector2(x1, y),
		Color(accent.r, accent.g, accent.b, 0.42), 1.0)


## 给进度条画分段刻度。hud.gd 在 _bar 之后调它。
## 这儿单独做成静态绘制，是因为 ProgressBar 自己是 Control，
## 直接在上面叠一层 draw 需要额外节点；改成由装饰层统一画更省。
func draw_bar_ticks(r: Rect2, color: Color, segments := 10) -> void:
	var gap := r.size.x / float(segments)
	for i in range(1, segments):
		var x := r.position.x + gap * float(i)
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y),
			Color(0, 0.04, 0.06, 0.55), 1.0)
