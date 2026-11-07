extends CanvasLayer

## 冰钓 HUD：张力条（含鱼竿决定的窗口）+ 收线进度 + 鱼饵/浮标。
## 全部代码绘制，不依赖外部素材。

var game
var font: Font
var painter: Painter
## 水面涟漪相位（纯视觉，喂给浮标）
var ripple := 0.0

## 三款鱼饵的主题色：面团饵 暖米 / 萤光饵 黄绿 / 星屑饵 淡紫
const BAIT_COLORS := {
	"plain": Color(0.88, 0.80, 0.62),
	"glow": Color(0.72, 0.94, 0.55),
	"star": Color(0.80, 0.72, 0.98),
}


class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_hud(self)


func setup(host) -> void:
	game = host
	layer = 2
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


func show_hud() -> void:
	ripple = 0.0
	if painter != null:
		painter.visible = true


func hide_hud() -> void:
	if painter != null:
		painter.visible = false


func _process(delta: float) -> void:
	ripple += delta
	if painter != null and painter.visible:
		painter.queue_redraw()


func draw_hud(control: Control) -> void:
	if game == null or font == null:
		return
	var center := control.size * 0.5
	# 浮标在水面上一直看得见（等咬钩时也看得见，只是下面没有张力条）
	draw_bobber(control, Vector2(center.x, control.size.y - 300.0))
	if game.fishing_phase != "reel":
		return

	var bar_w := 320.0
	var bar_h := 16.0
	# 整体抬高：底部还留着一条按键提示，张力条压上去会糊在一起
	var base := Vector2(center.x - bar_w * 0.5, control.size.y - 268.0)

	# 张力条底
	control.draw_rect(Rect2(base, Vector2(bar_w, bar_h)), Color(0.08, 0.1, 0.13, 0.85))
	# 窗口区间
	var window_width: float = game.progress.rod_tension_window() if game.progress != null else 0.3
	var window_low: float = 0.45 - window_width * 0.5
	var window_high: float = 0.45 + window_width * 0.5
	control.draw_rect(Rect2(base + Vector2(bar_w * window_low, 0), Vector2(bar_w * window_width, bar_h)),
		Color(0.5, 0.85, 0.6, 0.35))
	# 当前张力
	var tension: float = clampf(game.fishing_tension, 0.0, 1.0)
	var in_window: bool = tension >= window_low and tension <= window_high
	control.draw_rect(Rect2(base + Vector2(bar_w * tension - 2.0, -4.0), Vector2(4.0, bar_h + 8.0)),
		Color(0.96, 0.92, 0.6, 0.95) if in_window else Color(0.95, 0.45, 0.4, 0.95))
	control.draw_string(font, base + Vector2(0, -12.0), "张力 · 按住 E 收线，让它待在绿区里",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.86, 0.92, 0.9))

	# 收线进度
	var progress_base := base + Vector2(0, 34.0)
	control.draw_rect(Rect2(progress_base, Vector2(bar_w, 10.0)), Color(0.08, 0.1, 0.13, 0.85))
	control.draw_rect(Rect2(progress_base, Vector2(bar_w * clampf(game.fishing_reel, 0.0, 1.0), 10.0)),
		Color(0.55, 0.82, 0.9, 0.95))
	control.draw_string(font, progress_base + Vector2(0, 28.0),
		"收线 %d%%" % int(clampf(game.fishing_reel, 0.0, 1.0) * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.78, 0.86, 0.88, 0.9))

	# 鱼在挣扎时给一句提示（张力被扰动得越厉害越明显）
	var struggle: float = game.fishing_struggle_amplitude()
	if struggle > 0.0 and game.fishing_phase == "reel":
		var heat: float = clampf((struggle - 0.10) / 0.5, 0.0, 1.0)
		var line := "鱼在挣 · 稳住"
		if heat > 0.66:
			line = "它开始拼命了 · 稳住！"
		elif heat > 0.33:
			line = "鱼在使劲 · 别硬拉"
		control.draw_string(font, progress_base + Vector2(0, 56.0), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.98, 0.78, 0.62, 0.5 + 0.45 * heat))


## 浮标：颜色与辉光随当前鱼饵变化（面团饵朴素、萤光饵泛绿光、星屑饵带碎星）
func draw_bobber(control: Control, at: Vector2) -> void:
	var bait: String = "plain"
	if game.progress != null:
		bait = game.progress.bait
	var tint: Color = BAIT_COLORS.get(bait, BAIT_COLORS["plain"])
	var bob := sin(ripple * 2.2) * 3.0
	var pos := at + Vector2(0, bob)

	# 水面涟漪：随鱼饵变宽变亮
	var ring_scale: float = 1.0
	var ring_alpha: float = 0.28
	if bait == "glow":
		ring_scale = 1.35
		ring_alpha = 0.40
	elif bait == "star":
		ring_scale = 1.7
		ring_alpha = 0.46
	for i in range(3):
		var t := fmod(ripple * 0.55 + float(i) / 3.0, 1.0)
		var radius := (10.0 + 46.0 * t) * ring_scale
		var alpha := (1.0 - t) * ring_alpha
		control.draw_arc(at + Vector2(0, 26.0), radius, 0.0, TAU, 48, Color(tint, alpha), 1.6)

	# 萤光饵：身后拖一层绿雾
	if bait == "glow":
		var glow := 0.5 + 0.5 * sin(ripple * 3.4)
		control.draw_circle(pos, 16.0, Color(0.62, 0.95, 0.5, 0.10 + 0.10 * glow))
		control.draw_circle(pos, 10.0, Color(0.72, 0.98, 0.58, 0.16 + 0.12 * glow))
	elif bait == "star":
		# 星屑饵：绕着浮标转的碎屑
		for i in range(6):
			var angle := ripple * 1.6 + float(i) * TAU / 6.0
			var r := 20.0 + 4.0 * sin(ripple * 4.0 + float(i))
			var spark := pos + Vector2(cos(angle) * r, sin(angle) * r * 0.55)
			var twinkle := 0.45 + 0.55 * absf(sin(ripple * 5.0 + float(i) * 1.7))
			control.draw_circle(spark, 2.2 * twinkle, Color(0.92, 0.86, 1.0, 0.75 * twinkle))

	# 浮标本体：上红下白的老式浮子，杆身按饵色
	control.draw_line(pos + Vector2(0, -14.0), pos + Vector2(0, 12.0), Color(0.35, 0.32, 0.3, 0.9), 2.0)
	control.draw_circle(pos + Vector2(0, -14.0), 5.0, Color(0.9, 0.38, 0.32, 0.95))
	control.draw_circle(pos + Vector2(0, 2.0), 6.5, tint)
	control.draw_circle(pos + Vector2(0, 2.0), 3.0, Color(0.98, 0.98, 0.96, 0.9))

	# 饵名
	if game.progress != null:
		control.draw_string(font, pos + Vector2(18.0, 6.0), game.progress.bait_name(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(tint, 0.92))
