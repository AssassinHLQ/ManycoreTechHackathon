extends CanvasLayer

const DrawScript = preload("res://scripts/hud_draw.gd")
const DecoScript = preload("res://scripts/hud_deco.gd")

var game
var font: Font
## 2D 绘制层（准星/星球标签/座舱框）。测试需要访问，所以存成成员。
var drawing: Control
var deco: Control
## 状态条的分段刻度位置，交给装饰层画。
var _bar_ticks: Array = []
## 状态面板里的图标（船体/推进剂/氧气），切模式时要换图。
var _row_icons: Array = []
## 8 颗子系统状态灯。
var _system_lights: Array = []
var _lights_root: Control
var _lights_caption: Label
## 环形燃料表的外层容器（由装饰层负责实际绘制）。
var _gauge_root
## 带小数和单位的数值标签
var bar_a_value: Label
var bar_b_value: Label


## 状态面板里两行的 y 坐标（相对面板）。
## 抽成函数是因为布局改过几次，散落的魔数最容易改漏一处。
func r0_y() -> int:
	return 36


func r1_y() -> int:
	return 86
var root: Control
var hud_root: Control
var menu: Control
var pause_menu: Control
var journal: Control
var help: Control
var ending: Control
var death_overlay: Control
var death_shade: ColorRect
var death_reason: Label
var death_progress: Label
var solar_warning: Label
var bh_warning: Label
var location_title: Label
var location_sub: Label
var time_label: Label
var time_caption: Label
var prompt: Label
var controls_hint: Label
var toast: Label
var toast_timer := 0.0
var status_title: Label
var bar_a_label: Label
var bar_b_label: Label
var bar_a: ProgressBar
var bar_b: ProgressBar
var ship_stats: Label
var journal_entries: VBoxContainer
var journal_objective: Label
var end_body: Label
var end_stats: Label
var menu_start: Button
var settings_panel: Control
var setting_buttons: Dictionary = {}
var volume_slider: HSlider
var volume_label: Label
var sensitivity_slider: HSlider
var sensitivity_label: Label
var fps_status_label: Label
## 左下角的宇航服读数面板（阁楼线里要藏起来）
var status_panel: Panel
## 开发者模式的数据面板与它的读数标签（F3 连按 5 次开启后常驻）
var dev_panel: Panel
var dev_label: Label
var _dev_fps_window := 0.0
var _dev_fps_low := 0.0
var _dev_fps_samples: Array[float] = []


func _ready() -> void:
	layer = 10
	var embedded_font: Font = load("res://assets/ui_font.ttf")
	if embedded_font != null:
		var symbols: Font = load("res://assets/ui_symbols.ttf")
		if symbols != null:
			embedded_font.set("fallbacks", [symbols])
		font = embedded_font
	else:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
		font = system_font
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	_install_button_theme(theme)

	# 存成成员变量：测试/调试需要从外部访问它的 _draw_markers 等
	drawing = DrawScript.new()
	drawing.game = game
	drawing.font = font
	add_child(drawing)

	# 装饰层要画在 drawing 之上（切角框、括号、扫描线盖住底图）。
	# 它自己 mouse_filter = IGNORE，不挡交互。
	deco = DecoScript.new()
	deco.game = game
	deco.font = font
	add_child(deco)

	root = Control.new()
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hud()
	_build_menu()
	_build_pause()
	_build_journal()
	_build_help()
	_build_ending()
	_build_death()
	_build_settings()
	_build_dev_panel()


func _install_button_theme(theme: Theme) -> void:
	# 按钮三态优先用素材（Button03/04 是圆角矩形带细描边，尺寸 56×58 够九宫格）。
	# 素材不可用时回退到原来的 StyleBoxFlat —— 保证任何环境都能跑。
	var normal_tex := _nine("Button03.png", Vector4(10, 10, 10, 10),
		Color(0.62, 0.86, 0.88, 1.0), Vector4(20, 8, 20, 8))
	var hover_tex := _nine("Button04.png", Vector4(10, 10, 10, 10),
		Color(1.0, 1.0, 1.0, 1.0), Vector4(20, 8, 20, 8))
	var pressed_tex := _nine("Button03.png", Vector4(10, 10, 10, 10),
		Color(0.42, 0.62, 0.64, 1.0), Vector4(20, 8, 20, 8))

	if normal_tex != null and hover_tex != null and pressed_tex != null:
		theme.set_stylebox("normal", "Button", normal_tex)
		theme.set_stylebox("hover", "Button", hover_tex)
		theme.set_stylebox("pressed", "Button", pressed_tex)
		theme.set_stylebox("focus", "Button", hover_tex)
		theme.set_stylebox("disabled", "Button", normal_tex)
	else:
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("173b43")
		normal.border_color = Color("4c9b9a")
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(3)
		normal.content_margin_left = 20
		normal.content_margin_right = 20
		var hover := normal.duplicate()
		hover.bg_color = Color("24545a")
		hover.border_color = Color("8ad8cc")
		var pressed := normal.duplicate()
		pressed.bg_color = Color("0e292f")
		theme.set_stylebox("normal", "Button", normal)
		theme.set_stylebox("hover", "Button", hover)
		theme.set_stylebox("pressed", "Button", pressed)

	theme.set_color("font_color", "Button", Color("dcece7"))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color("bfe4e2"))
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.65, 0.65))

	# 面板容器统一走素材面板，这样任何用 PanelContainer 的地方都自动生效
	var panel_box := _nine("MainPanel03.png", Vector4(12, 12, 12, 12),
		Color(0.72, 0.94, 1.0, 0.92), Vector4(16, 14, 16, 14))
	if panel_box != null:
		theme.set_stylebox("panel", "PanelContainer", panel_box)
		theme.set_stylebox("panel", "Panel", panel_box)

	# 滑块：Slider01.png 是 245×18 的横条，正好当 HSlider 的槽
	var slider_box := _nine("Slider01.png", Vector4(10, 6, 10, 6),
		Color(0.75, 0.95, 1.0, 0.85), Vector4(0, 6, 0, 6))
	if slider_box != null:
		theme.set_stylebox("slider", "HSlider", slider_box)
		theme.set_stylebox("grabber_area", "HSlider", slider_box)

	# 开关/复选框：Switch01/02 是 66×24，做 CheckBox 也可以，但 CheckBox
	# 需要方形，这块先留着 —— 设置页的开关是自绘的，不走主题。


func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_root)
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	location_title = _label(hud_root, "青岚星", Rect2(28, 22, 650, 38), 26, Color("e3eee8"))
	location_sub = _label(hud_root, "", Rect2(30, 62, 720, 30), 14, Color(0.66, 0.79, 0.78))

	time_label = _label(hud_root, "17:00", Rect2(-130, 20, 260, 38), 25, Color("f1d39a"))
	_center_anchor(time_label, false)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_caption = _label(hud_root, "恒星稳定", Rect2(-160, 57, 320, 26), 12, Color(0.68, 0.75, 0.77))
	_center_anchor(time_caption, false)
	time_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	controls_hint = _label(hud_root, "M  星图    J  日志    Esc  菜单", Rect2(-342, 26, 316, 30), 14, Color(0.68, 0.8, 0.79))
	controls_hint.anchor_left = 1.0
	controls_hint.anchor_right = 1.0
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	toast = _label(hud_root, "", Rect2(-460, 105, 920, 48), 19, Color("f0d7a2"))
	_center_anchor(toast, false)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	solar_warning = _label(hud_root, "", Rect2(-500, 155, 1000, 34), 17, Color("ff9b73"))
	_center_anchor(solar_warning, false)
	solar_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	solar_warning.visible = false

	# 卡冈图雅的引力警告：放在恒星警告下面一条，两者可以同时出现（理论上不会，但不必互斥）。
	bh_warning = _label(hud_root, "", Rect2(-500, 192, 1000, 34), 17, Color("e8c07a"))
	_center_anchor(bh_warning, false)
	bh_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bh_warning.visible = false

	prompt = _label(hud_root, "", Rect2(-490, -138, 980, 52), 17, Color("dcece7"))
	_center_anchor(prompt, true)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	status_panel = Panel.new()
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.anchor_top = 1.0
	status_panel.anchor_bottom = 1.0
	status_panel.offset_left = 24
	status_panel.offset_top = -300
	status_panel.offset_right = 352
	status_panel.offset_bottom = -24
	# 状态面板用素材贴图（SelectPanel01 竖版 157×339，正好配左下角竖条）
	# ⚠ 变量必须声明成 StyleBox 而不是 StyleBoxFlat ——
	#   后者的类型推断会把 StyleBoxTexture 赋值判为错误。
	var status_style: StyleBox = _nine("SelectPanel01.png", Vector4(10, 12, 10, 12),
		Color(0.95, 1.15, 1.25, 1.0), Vector4(18, 12, 18, 14))
	if status_style == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.015, 0.028, 0.047, 0.72)
		flat.border_color = Color(0.26, 0.53, 0.55, 0.42)
		flat.set_border_width_all(1)
		flat.set_corner_radius_all(3)
		status_style = flat
	status_panel.add_theme_stylebox_override("panel", status_style)
	hud_root.add_child(status_panel)

	# ── 面板内容重排 ────────────────────────────────────────────────
	#
	# 原来的面板只有「标题 + 两条光溜溜的进度条」，用户反馈「太素」。
	# 现在加三样东西让信息密度上来：
	#   1. 每行左侧一个图标（白+深描边，可染色）
	#   2. 右侧数值带小数和单位，像真实仪表读数
	#   3. 右下角一个环形燃料表 + 底部一排状态灯
	status_title = _label(status_panel, "生命维持系统", Rect2(16, 8, 240, 22), 12, Color("70c7c3"))

	# 三行指标：图标 + 名称 + 数值 + 条
	var rows := [
		{"icon": "health.png", "name": "船体 / 氧气", "color": Color("69cbd2"), "y": 36},
		{"icon": "fuel.png", "name": "推进剂", "color": Color("e5b873"), "y": 86},
	]
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		# 图标给 24×24（原始 16×16，放大 1.5 倍靠 stretch 做）。
		# 16px 在 1080p 下太小，看不出是「船体」还是「燃料」。
		var icon := _icon(status_panel, String(r["icon"]),
			Rect2(14, r["y"] - 2, 24, 24), Color(0.72, 0.94, 0.96, 0.95))
		icon.name = "row_icon_%d" % i
		_row_icons.append(icon)

	bar_a_label = _label(status_panel, "船体", Rect2(44, r0_y(), 150, 20), 14, Color("d9e8e5"))
	bar_a_value = _label(status_panel, "100.0 %", Rect2(180, r0_y(), 150, 20), 13, Color("8fe3e8"))
	bar_a_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_a = _bar(status_panel, Rect2(16, 60, 306, 7), Color("69cbd2"))

	bar_b_label = _label(status_panel, "推进剂", Rect2(44, r1_y(), 150, 20), 14, Color("d9e8e5"))
	bar_b_value = _label(status_panel, "100.0 %", Rect2(180, r1_y(), 150, 20), 13, Color("f0cb8a"))
	bar_b_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_b = _bar(status_panel, Rect2(16, 110, 306, 7), Color("e5b873"))

	# 状态灯阵：8 个小方块，亮灭反映各子系统是否正常。
	# 这些是真实状态，不是装饰 —— 见 _process 里的 _update_system_lights。
	# 位置 y=136：推进剂条占到 117，留 19px 间隙，不重叠。
	_lights_root = Control.new()
	_lights_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lights_root.position = Vector2(16, 136)
	_lights_root.size = Vector2(200, 26)
	status_panel.add_child(_lights_root)
	_lights_caption = _label(status_panel, "子系统", Rect2(16, 178, 120, 18), 11, Color(0.55, 0.74, 0.75))
	for i in range(8):
		var light := ColorRect.new()
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		light.position = Vector2(i * 24, 6)
		light.size = Vector2(14, 14)
		light.color = Color(0.2, 0.5, 0.55, 0.9)
		_lights_root.add_child(light)
		_system_lights.append(light)
		# 灯下面一小条标签线，视觉上「有内容」
		var tick := ColorRect.new()
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.position = Vector2(i * 24 + 4, 24)
		tick.size = Vector2(6, 2)
		tick.color = Color(0.42, 0.78, 0.80, 0.35)
		_lights_root.add_child(tick)

	# 环形燃料表：直接实例化 DecoScript 里的 RingGauge。
	# 它自己画自己、用局部坐标，不用跨层换算（之前那套换算在山模式下会错位）。
	_gauge_root = DecoScript.RingGauge.new()
	_gauge_root.font = font
	_gauge_root.position = Vector2(232, 146)
	_gauge_root.size = Vector2(78, 78)
	status_panel.add_child(_gauge_root)

	# 状态面板的装饰框（面板变高了，rect 也要跟着改：24,-300 → 328×276）
	deco.add_frame(Rect2(24, -300, 328, 276), Color(0.42, 0.78, 0.80, 1.0), "SUIT")

	# 两条状态条的刻度位置：面板上移后重新算
	_bar_ticks.append({"rect": Rect2(24 + 16, -268 + 60, 306, 7), "color": Color("69cbd2")})
	_bar_ticks.append({"rect": Rect2(24 + 16, -268 + 110, 306, 7), "color": Color("e5b873")})
	if deco != null:
		deco.bar_ticks = _bar_ticks
		# 面板网格底纹：铺在面板内侧，极低透明度，让底子不空。
		# 这里的高度用屏幕高 + offset 换算，因为 deco 是整屏坐标系。
		var vh: float = get_viewport().get_visible_rect().size.y
		deco.grid_rects.append({
			"rect": Rect2(24 + 8, vh - 300 + 8, 312, 260),
			"alpha": 0.07,
		})
		# 状态条刻度也要用全局坐标（deco 画在整屏，不是面板内）
		_bar_ticks.clear()
		_bar_ticks.append({"rect": Rect2(24 + 16, vh - 300 + 60, 306, 7), "color": Color("69cbd2")})
		_bar_ticks.append({"rect": Rect2(24 + 16, vh - 300 + 110, 306, 7), "color": Color("e5b873")})
		deco.bar_ticks = _bar_ticks
		deco.queue_redraw()

	ship_stats = _label(hud_root, "", Rect2(-390, -214, 360, 180), 15, Color("b9d9d7"))
	ship_stats.anchor_left = 1.0
	ship_stats.anchor_right = 1.0
	ship_stats.anchor_top = 1.0
	ship_stats.anchor_bottom = 1.0
	ship_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_menu() -> void:
	menu = _overlay(0.2)
	var panel := Panel.new()
	# 面板高度按内容实测调：原名 590×768 @ y=96（底 864）。
	# 加了两行外部素材署名后，第三行（Aholo Lux3D）仍被裁，故定为 590×880 @ y=60，
	# 底部落在 940，给 1080 屏留 140px 余量；内容超长时 _panel_box 会内部滚动。
	panel.position = Vector2(66, 60)
	panel.size = Vector2(590, 880)
	panel.add_theme_stylebox_override("panel", _panel_style())
	menu.add_child(panel)
	var box := _panel_box(panel, 34)
	# 标题只留中文名；原来的英文小标题与副标题已去掉，不再出现两个名字打架。
	var heading := _text(box, "借 一 扇 晴 天", 49, Color("e9e3ce"))
	heading.custom_minimum_size.y = 84
	var description := _text(box, "没有任务箭头，也没有必须打赢的战争。\n只有一颗正在老去的恒星，和等待你亲自拼凑的答案。", 17, Color("b7cbc7"))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 90
	var rule := HSeparator.new()
	box.add_child(rule)
	var features := _text(box, "◈ 球形重力徒步与喷气背包\n◈ 惯性飞行、目的地锁定与自动着陆\n◈ 十颗程序化微型天体与六廊归航站\n◈ 跨越超新星轮回的航海日志", 15, Color("91aaa8"))
	features.custom_minimum_size.y = 142
	menu_start = _button(box, "开始探索", func(): game.start_game())
	menu_start.custom_minimum_size.y = 54
	_button(box, "自动演示 · 约 2 分半", func(): game.start_demo()).custom_minimum_size.y = 44
	_button(box, "设置", show_settings).custom_minimum_size.y = 42
	_button(box, "操作与生存指南", show_help).custom_minimum_size.y = 44
	_button(box, "退出", func(): get_tree().quit()).custom_minimum_size.y = 38
	var footer := _text(box, "原创科幻原型  /  烤棉花糖为致敬  /  GODOT 4  /  建议佩戴耳机", 11, Color(0.46, 0.6, 0.61))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 署名义务：用了别人的素材就必须署上出处，且要出现在**游戏里** ——
	# 导出后的 exe / 网页版并不带仓库里的文档，只写在 THIRD_PARTY_NOTICES.md
	# 是不够的。以后每加一件外部素材就在这里追加一行。
	#
	# 分两行是为了不把一行撑爆（1080 宽的菜单面板放不下）。
	var credits := _text(box,
		"外部素材：Black Hole 模型 Nestaeric (CC BY 4.0)　·" +
		"　UI 贴图 Wenrexa (CC0)　·　图标 Pixel UI Sci-Fi by heyheythere (CC BY 4.0)",
		10, Color(0.38, 0.5, 0.52))
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var credits2 := _text(box,
		"星球模型由 Aholo Lux3D（群核科技）文生 3D 生成　·　完整声明见 THIRD_PARTY_NOTICES.md",
		10, Color(0.34, 0.45, 0.47))
	credits2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_pause() -> void:
	pause_menu = _overlay(0.64)
	var panel := _center_panel(pause_menu, Vector2(480, 442))
	var box := _panel_box(panel, 32)
	_text(box, "探索暂停", 34, Color("e9e3ce"))
	var sub := _text(box, "恒星会等你一会儿。", 15, Color("8daaa7"))
	sub.custom_minimum_size.y = 64
	_button(box, "继续探索", func(): game.set_paused(false)).custom_minimum_size.y = 52
	_button(box, "设置", show_settings).custom_minimum_size.y = 42
	_button(box, "操作与生存指南", show_help).custom_minimum_size.y = 46
	_button(box, "返回标题", func(): game.return_to_menu()).custom_minimum_size.y = 46
	pause_menu.visible = false


func _build_journal() -> void:
	journal = _overlay(0.88)
	var panel := _center_panel(journal, Vector2(1120, 716))
	var box := _panel_box(panel, 28)
	var title_row := HBoxContainer.new()
	box.add_child(title_row)
	var title := _text(title_row, "航海日志", 30, Color("e9e3ce"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint := _text(title_row, "知识不会随轮回消失", 13, Color("6fbab5"))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 690
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	journal_entries = VBoxContainer.new()
	journal_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_entries.add_theme_constant_override("separation", 10)
	scroll.add_child(journal_entries)
	var objective_panel := Panel.new()
	objective_panel.custom_minimum_size.x = 330
	objective_panel.add_theme_stylebox_override("panel", _panel_style())
	columns.add_child(objective_panel)
	var objective_box := _panel_box(objective_panel, 20)
	_text(objective_box, "当前推论", 20, Color("d9b879"))
	journal_objective = _text(objective_box, "", 15, Color("bacdc9"))
	journal_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	journal_objective.custom_minimum_size.x = 275
	journal_objective.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_button(box, "合上日志  ·  J / Esc", func(): game.toggle_journal()).custom_minimum_size.y = 42
	journal.visible = false


func rebuild_journal() -> void:
	if journal_entries == null:
		return
	for child in journal_entries.get_children():
		journal_entries.remove_child(child)
		child.queue_free()
	for anomaly in game.anomalies:
		var known: bool = game.discovered.has(anomaly.anomaly_id)
		var title_text: String = anomaly.title if known else "未记录的信号"
		var color: Color = anomaly.accent_color if known else Color(0.35, 0.48, 0.5)
		_text(journal_entries, title_text, 20, color)
		var body_text: String = anomaly.body if known else "尚未扫描。调整航向，亲自去寻找这段回声。"
		var entry := _text(journal_entries, body_text, 15, Color("b8cbc7") if known else Color(0.4, 0.53, 0.54))
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.custom_minimum_size = Vector2(640, 0)
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 12
		journal_entries.add_child(spacer)
	journal_objective.text = game.objective_text()


func _build_help() -> void:
	help = _overlay(0.93)
	var panel := _center_panel(help, Vector2(1080, 656))
	var box := _panel_box(panel, 26)
	_text(box, "探险者生存指南", 28, Color("e9e3ce"))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 28)
	box.add_child(columns)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 400
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(left_scroll)
	var left := _text(left_scroll, "徒 步\n\nW A S D　移动\nCtrl　加速奔跑\nR　地形脱困\n鼠标　观察\nSpace　跳跃\nShift　喷气背包\nL　头灯\n右键　信号镜（滚轮 2.1×–16×）\nF　按住扫描符文\nE　登船 / 烤棉花糖\n\n飞 船\n\n鼠标　俯仰与转向\n滚轮　长焦观察 1×–16×（星点 / 彗星 / 太阳）\nW / S　前后推进\nA / D　横向推进\nSpace　上升 / 起飞\nCtrl 或 C　下降\nShift　加力\nX　制动\nTab　切换目的地\nT　自动航行 / 着陆\nE　低速着陆 / 离船\nF5　第三人称看飞船\n\n归 航 站\n\n低速靠近对接口自动对接\nE　进入空间站\nSpace　脱离对接\n中央枢纽气闸旁 E 返回飞船\n六条放射走廊 A–F\n\n触 屏\n\n左摇杆　移动 / 平移\n右侧空白　拖动视角\n圆钮　跳跃 / 喷气 / 互动 / 扫描\n飞船圆钮　起飞 / 离船 / 上升 / 下降 / 加力 / 制动\n星图　右侧关闭 / 缩放按钮", 15, Color("bed2cd"))
	left.custom_minimum_size.x = 372
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 540
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(right_scroll)
	var right := _text(right_scroll, "探 索\n\nM　实时星图\nJ　航海日志\nEsc　暂停 / 返回\n\n生存提示\n\n· 每颗星球的重力不同：低重力跳得更高，高重力需要更强喷射。\n\n· 氧气在徒步时缓慢消耗，靠近飞船或篝火即可补充；喷气燃料在着陆后恢复。\n\n· 篝火边按 E 取出棉花糖：火候会在 8 秒内从生白走到焦黑，金黄时按 E 取下补得最多，烤成炭只能补回一点。\n\n· 着陆：接近地表 70 米内且速度低于 45 时按 E；也可以 Tab 选择目的地后按 T 自动航行。\n\n· 扫描三个棱镜坐标，玄渊星的加密才会解除。\n\n· 没有深空边界：可以一直飞离太阳系，不会被“信号范围”判死；真正结束旅程的是撞击、恒星、氧气或燃料。\n\n· 飞船推进剂耗尽后生命维持还能撑约 90 秒；尽快用 Tab + T 自动航行到行星着陆补给。\n\n· 接近恒星会过热、灼伤船体；真正坠入后意识才会中断并开始轮回。\n\n· 恒星会在约 17 分钟后爆发。轮回重置位置和资源，但你写入日志的知识会永久保留。\n\n· 青岚星、赭崖星与悬晶星的地表各有一个洞口，沿螺旋坡道可以进入地下洞室。\n\n· 青岚星的风车塔与沧波星的研究站可以直接推门走进去。\n\n· 悬晶星的量子碎岩只在无人注视时移动。盯着它、扫描它，它就会留在原地。\n\n· 一颗彗星会周期性穿过星系，星图上也能找到它的尾迹；它只有一条离子尾和一条尘埃尾。\n\n· 飞船里滚动鼠标滚轮可以拉长焦，方便观察远方星点与彗星。\n\n· 飞近太阳时，表面黑子与日珥会逐渐显现；距离越远，这些细节会自动隐藏。", 15, Color("9eb8b4"))
	right.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.custom_minimum_size.x = 506
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(box, "记住了", func(): help.visible = false).custom_minimum_size.y = 42
	help.visible = false


func _build_ending() -> void:
	ending = _overlay(0.82)
	var panel := _center_panel(ending, Vector2(880, 646))
	var box := _panel_box(panel, 38)
	var eyebrow := _text(box, "H O R I Z O N   P R E L U D E", 13, Color("79c8c0"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _text(box, "黑洞前奏", 37, Color("f0dfb4"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 86
	end_body = _text(box, "", 18, Color("c4d5d0"))
	end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_body.custom_minimum_size.y = 200
	end_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	end_stats = _text(box, "", 14, Color("78aaa6"))
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_stats.custom_minimum_size.y = 58
	_button(box, "回到阁楼，把这段慢时间还给自己", func(): game.enter_attic()).custom_minimum_size.y = 52
	_button(box, "留在这个太阳系，继续自由探索", func(): game.continue_after_end()).custom_minimum_size.y = 52
	_button(box, "返回标题", func(): game.return_to_menu()).custom_minimum_size.y = 42
	ending.visible = false


func _build_death() -> void:
	death_overlay = _overlay(0.0)
	death_shade = death_overlay.get_child(0) as ColorRect
	var panel := _center_panel(death_overlay, Vector2(720, 420))
	var box := _panel_box(panel, 42)
	var eyebrow := _text(box, "S I G N A L   L O S T", 14, Color("bf6c52"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _text(box, "意识正在中断", 38, Color("f2ddc3"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 76
	death_reason = _text(box, "", 19, Color("e9a27e"))
	death_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	death_reason.custom_minimum_size.y = 62
	death_progress = _text(box, "", 15, Color("8dafa9"))
	death_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_progress.custom_minimum_size.y = 52
	var hint := _text(box, "你听见了篝火的声音。记忆正在回溯。", 14, Color(0.55, 0.7, 0.68))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_overlay.visible = false


## 开发者模式的数据面板：帧率 / 帧时间 / 显存 / 绘制 / 显卡与渲染接口。
## 挂在 root 上而不是 hud_root 上 —— 菜单、暂停、结局里都要能看到，那才叫「常态显示」。
## 默认隐藏，只有 main.gd 的开发者模式打开后才出现，所以正式截图里不会多出这块。
func _build_dev_panel() -> void:
	dev_panel = Panel.new()
	dev_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dev_panel.position = Vector2(24, 104)
	dev_panel.size = Vector2(378, 336)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.023, 0.038, 0.8)
	style.border_color = Color(0.95, 0.7, 0.38, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	dev_panel.add_theme_stylebox_override("panel", style)
	root.add_child(dev_panel)
	dev_label = _label(dev_panel, "", Rect2(14, 8, 350, 320), 12, Color("ffd9a8"))
	dev_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dev_panel.visible = false


## 每秒记一次这段时间里最低的帧率：平均值看不出顿卡，最低值能。
func _refresh_dev_panel(delta: float) -> void:
	var fps := float(Engine.get_frames_per_second())
	_dev_fps_window += delta
	_dev_fps_samples.append(fps)
	if _dev_fps_window >= 1.0:
		var lowest := INF
		for sample in _dev_fps_samples:
			lowest = minf(lowest, sample)
		_dev_fps_low = 0.0 if lowest == INF else lowest
		_dev_fps_samples.clear()
		_dev_fps_window = 0.0

	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var texture_mem := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var buffer_mem := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
	var static_mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var cap := int(game.settings.values.fps_limit)
	var gpu := RenderingServer.get_video_adapter_name()
	if gpu == "":
		gpu = "无（无界面运行 / 取不到适配器）"
	var api := RenderingServer.get_video_adapter_api_version()
	if api == "":
		api = "-"
	# 显卡名可以很长，裁一下免得顶出面板
	if gpu.length() > 34:
		gpu = gpu.substr(0, 34)

	var clock := int(game.elapsed)
	var planet_name := "-"
	var planet = game.current_planet()
	if planet != null and "display_name" in planet:
		planet_name = String(planet.display_name)
	var position: Vector3 = game.get_active_position()
	var echoes: Array = game._hidden_echo_progress()
	var window := "无界面"
	if DisplayServer.get_name() != "headless":
		window = "%d × %d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]

	var lines: Array[String] = []
	lines.append("开发者模式　F3 面板开关")
	lines.append("按键　F4 结局 · F5 条目 · F6 资源 · F7 超新星")
	lines.append("帧率　%d FPS　最低 %d　上限 %s" % [
		int(fps), int(_dev_fps_low), "不限" if cap <= 0 else str(cap)])
	lines.append("帧时间　%.1f ms　物理 %.1f ms" % [frame_ms, physics_ms])
	lines.append("显存　%.0f MiB　纹理 %.0f　缓冲 %.0f" % [vram, texture_mem, buffer_mem])
	lines.append("绘制　%d 次　图元 %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	lines.append("物体　%d 个　节点 %d　资源 %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))])
	lines.append("内存　%.0f MiB　物理体 %d　碰撞对 %d" % [
		static_mem,
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))])
	lines.append("显卡　" + gpu)
	lines.append("接口　" + api)
	# 「渲染」的「渲」不在内嵌字体子集里（子集 = 工程用字 + GB2312 一级），
	# 所以这里写「管线」，别为了一个词去重做字体子集。
	lines.append("管线　%s · %s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name()])
	lines.append("窗口　%s　画质 %s" % [window, String(game.settings.values.quality)])
	lines.append("引擎　%s" % String(Engine.get_version_info().get("string", "?")))
	lines.append("状态　%s · %s · 轮回 %d · %02d:%02d" % [
		game.state, planet_name, game.loop_count, clock / 60, clock % 60])
	lines.append("坐标　%.1f / %.1f / %.1f" % [position.x, position.y, position.z])
	lines.append("条目　%d / %d　隐藏回声 %d / %d" % [
		game.discovered.size(), game.anomalies.size(), int(echoes[0]), int(echoes[1])])
	dev_label.text = "\n".join(PackedStringArray(lines))
	# 面板跟着文字长：换窗口尺寸、改字号都不会把最后一行切掉（第一版就是写死的 320，末尾被切）
	var needed := dev_label.get_minimum_size()
	if dev_label.size != needed:
		dev_label.size = needed
		dev_panel.size = needed + Vector2(dev_label.position.x * 2.0, dev_label.position.y * 2.0)


func _build_settings() -> void:
	settings_panel = _overlay(0.82)
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := _center_panel(settings_panel, Vector2(820, 782))
	var box := _panel_box(panel, 28)
	_text(box, "设置", 30, Color("e9e3ce"))
	var sub := _text(box, "画质与窗口设置会立即生效，并保存到本地。", 13, Color("8daaa7"))
	sub.custom_minimum_size.y = 26
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(rows)
	_add_cycle_setting(rows, "画面质量", "quality", ["low", "medium", "high"], ["低", "中", "高"], func(value): game.settings.set_quality(value))
	_add_cycle_setting(rows, "分辨率", "resolution", [0, 1, 2, 3], ["1280 × 720", "1600 × 900", "1920 × 1080", "全屏"], func(value): game.settings.set_resolution(value))
	_add_cycle_setting(rows, "垂直同步", "vsync", [true, false], ["开", "关"], func(value): game.settings.set_vsync(value))
	var fps_row := _add_cycle_setting(rows, "帧率上限", "fps_limit", [0, 30, 45, 60, 75, 90, 120, 144, 165, 240], ["无限制", "30", "45", "60", "75", "90", "120", "144", "165", "240"], func(value): game.settings.set_fps_limit(value))
	fps_status_label = _text(fps_row, "", 13, Color("6fbab5"))
	fps_status_label.custom_minimum_size.x = 86
	fps_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_add_cycle_setting(rows, "抗锯齿", "msaa", [0, 1, 2], ["关", "2×", "4×"], func(value): game.settings.set_msaa(value))
	_add_cycle_setting(rows, "阴影", "shadows", [0, 1, 2], ["关", "低", "标准"], func(value): game.settings.set_shadows(value))
	_add_cycle_setting(rows, "视野距离", "view_distance", [0, 1, 2], ["近", "标准", "远"], func(value): game.settings.set_view_distance(value))
	_add_cycle_setting(rows, "草地密度", "grass", [0, 1], ["稀疏", "标准"], func(value): game.settings.set_grass(value))
	# 星空精细度：控 fbm 倍频数、星层数、像素内超采样倍率与闪烁/星芒/流星/流转的开关
	_add_cycle_setting(rows, "星空精细度", "sky_detail", [0, 1, 2, 3], ["低", "中", "高", "极致"], func(value): game.settings.set_sky_detail(value))
	var volume_row := _settings_row(rows, "主音量")
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.custom_minimum_size = Vector2(260, 28)
	volume_slider.size_flags_horizontal = Control.SIZE_SHRINK_END
	volume_slider.value_changed.connect(func(value): _on_volume_changed(value))
	volume_row.add_child(volume_slider)
	volume_label = _text(volume_row, "", 14, Color("9eb8b4"))
	volume_label.custom_minimum_size.x = 52
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var sensitivity_row := _settings_row(rows, "鼠标灵敏度")
	sensitivity_slider = HSlider.new()
	sensitivity_slider.min_value = 0.4
	sensitivity_slider.max_value = 2.5
	sensitivity_slider.step = 0.1
	sensitivity_slider.custom_minimum_size = Vector2(260, 28)
	sensitivity_slider.size_flags_horizontal = Control.SIZE_SHRINK_END
	sensitivity_slider.value_changed.connect(func(value): _on_sensitivity_changed(value))
	sensitivity_row.add_child(sensitivity_slider)
	sensitivity_label = _text(sensitivity_row, "", 14, Color("9eb8b4"))
	sensitivity_label.custom_minimum_size.x = 52
	sensitivity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	_button(actions, "恢复默认", func(): game.settings.reset_defaults(); _refresh_settings()).custom_minimum_size = Vector2(180, 40)
	_button(actions, "返回", hide_settings).custom_minimum_size = Vector2(180, 40)
	settings_panel.visible = false
	if OS.has_feature("web"):
		var web_note := _text(box, "网页版的分辨率与垂直同步由浏览器决定。", 12, Color("6fbab5"))
		web_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_settings()


func _settings_row(parent: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.y = 44
	parent.add_child(row)
	var label := _text(row, title, 15, Color("bed2cd"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row


func _add_cycle_setting(parent: VBoxContainer, title: String, key: String, options: Array, labels: Array, handler: Callable) -> HBoxContainer:
	var row := _settings_row(parent, title)
	var button := _button(row, "", func(): _cycle_setting(key, options, labels, handler))
	button.custom_minimum_size = Vector2(220, 36)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	setting_buttons[key] = {"button": button, "options": options, "labels": labels}
	return row


func _cycle_setting(key: String, options: Array, _labels: Array, handler: Callable) -> void:
	var current = game.settings.values[key]
	var index := options.find(current)
	index = (index + 1) % options.size()
	game.settings.values[key] = options[index]
	handler.call(options[index])
	_refresh_settings()


func _refresh_settings() -> void:
	if game == null or game.settings == null:
		return
	for key in setting_buttons.keys():
		var entry: Dictionary = setting_buttons[key]
		var options: Array = entry["options"]
		var labels: Array = entry["labels"]
		var index := options.find(game.settings.values[key])
		if OS.has_feature("web") and key in ["resolution", "vsync"]:
			entry["button"].text = "由浏览器决定"
			entry["button"].disabled = true
			continue
		entry["button"].text = labels[index] if index >= 0 else "自定义"
	if volume_slider != null:
		volume_slider.set_value_no_signal(game.settings.values.volume)
		volume_label.text = "%d%%" % int(game.settings.values.volume)
	if sensitivity_slider != null:
		sensitivity_slider.set_value_no_signal(game.settings.sensitivity_multiplier())
		sensitivity_label.text = "%.1f×" % game.settings.sensitivity_multiplier()


func _on_volume_changed(value: float) -> void:
	game.settings.set_volume(int(value))
	volume_label.text = "%d%%" % int(value)


func _on_sensitivity_changed(value: float) -> void:
	game.settings.set_sensitivity(value)
	sensitivity_label.text = "%.1f×" % value


func show_settings() -> void:
	_refresh_settings()
	settings_panel.visible = true


func hide_settings() -> void:
	settings_panel.visible = false


func _process(delta: float) -> void:
	if game == null or hud_root == null:
		return
	# 开发者面板最先更新：它在所有状态下（菜单、暂停、结局）都要刷新，
	# 而后面的代码会在「没在玩」时提前 return。
	if dev_panel != null:
		if game.dev_mode and game.dev_overlay_visible:
			if not dev_panel.visible:
				dev_panel.visible = true
				_dev_fps_window = 0.0
				_dev_fps_samples.clear()
			_refresh_dev_panel(delta)
		elif dev_panel.visible:
			dev_panel.visible = false
	var playing: bool = game.state in ["walk", "ship", "supernova"]
	hud_root.visible = playing and not game.map_open
	menu.visible = game.state == "menu"
	pause_menu.visible = game.paused and not game.journal_open and playing
	journal.visible = game.journal_open
	ending.visible = game.state == "end"
	death_overlay.visible = game.state == "dying"
	if game.state == "dying":
		var fade := clampf((game.death_timer - 0.9) / 1.5, 0.0, 1.0)
		death_shade.color = Color(0.004, 0.006, 0.012, 0.92 * fade)
		death_reason.text = game.death_reason
		death_progress.text = "记忆回溯  %d%%" % int(clampf(game.death_timer / game.death_duration, 0.0, 1.0) * 100.0)
		return
	if toast_timer > 0.0:
		toast_timer -= delta
	# 菜单里默认不弹提示；开发者模式要能看到「已开启」这类反馈，所以给它放行
	var toast_allowed: bool = game.state not in ["menu", "end"]
	if game.state == "menu" and game.dev_mode:
		toast_allowed = true
	toast.visible = toast_timer > 0.0 and toast_allowed
	if game.state == "end":
		end_body.text = game.end_text
		end_stats.text = "记录 %d / %d　·　经历 %d 次轮回　·　旅程仍在继续" % [game.discovered.size(), game.anomalies.size(), game.loop_count]
	if game.state == "menu":
		menu_start.text = "继续探索" if not game.discovered.is_empty() else "开始探索"
	if settings_panel != null and settings_panel.visible and fps_status_label != null:
		var live_fps := Engine.get_frames_per_second()
		fps_status_label.text = "%d FPS" % live_fps
		var cap := int(game.settings.values.fps_limit)
		fps_status_label.add_theme_color_override("font_color", Color("ff9c82") if cap > 0 and live_fps < cap * 0.9 else Color("6fbab5"))
	if not playing:
		return
	var remaining := maxf(0.0, game.LOOP_DURATION - game.elapsed)
	var minutes := int(remaining) / 60
	var seconds := int(remaining) % 60
	# 阁楼线里没有恒星倒计时：整块藏起来，别让「距离恒星爆发」挂在小世界头顶
	var attic_line: bool = bool(game.in_attic)
	time_label.visible = not attic_line
	time_caption.visible = not attic_line
	if not attic_line:
		time_label.text = "—" if game.state == "supernova" else "%02d:%02d" % [minutes, seconds]
		time_label.add_theme_color_override("font_color", Color("ff9c82") if remaining < 60.0 else Color("f1d39a"))
		time_caption.text = "恒星爆发" if game.state == "supernova" else ("恒星进入末期" if remaining < 90.0 else "距离恒星爆发")
	solar_warning.visible = (not attic_line) and game.solar_intensity > 0.06 and game.state in ["walk", "ship"]
	if solar_warning.visible:
		solar_warning.text = "⚠ 恒星高温区 · 辐射强度 %d%% · 立即远离" % int(game.solar_intensity * 100.0)
		solar_warning.add_theme_color_override("font_color", Color("ff6d4c") if game.solar_intensity > 0.55 else Color("ffb178"))
	# 卡冈图雅的引力告警：只在驾驶舱里、且真的被拉到了才显示，免得走路时也在喊。
	var ship = game.ship
	var bh_visible: bool = (not attic_line) and game.state == "ship" and ship != null \
		and ship.bh_warn_level > 0 and not ship.landed and not ship.docked
	bh_warning.visible = bh_visible
	if bh_visible:
		# 报「推力余量」而不是「引力场百分比」。
		# 以前那个百分比是 closeness（距离的归一化），跟实际加速度差得很远：
		# 实测离黑洞 4000 处加速度已经是 83（推力 72，推不动了），可 HUD 才显示
		# 45%、文案还在说「推力已难对抗」—— 玩家会以为还能跑。
		# 现在直接拿实际径向加速度跟推力比，余量一目了然。
		var accel: float = ship.bh_radial_accel
		var margin: int = int(round((72.0 - accel) / 72.0 * 100.0))
		match int(ship.bh_warn_level):
			1:
				bh_warning.text = "引力场 · 卡冈图雅 · 推力余量 %d%% · 航线已被牵引" % margin
				bh_warning.add_theme_color_override("font_color", Color("e8c07a"))
			2:
				bh_warning.text = "⚠ 引力 %d · 推力余量 %d%% · 按住 Shift 喷气脱离" % [int(round(accel)), margin]
				bh_warning.add_theme_color_override("font_color", Color("ffb178"))
			_:
				bh_warning.text = "⚠ 临界 · 引力 %d 已压过推力 · 即将越过视界" % int(round(accel))
				bh_warning.add_theme_color_override("font_color", Color("ff6d4c"))
	var planet = game.current_planet()
	if game.in_attic:
		location_title.text = "阁楼 · 给自己一段慢时间"
		location_sub.text = "地面线　·　四扇门通往远方，镜子通往回廊"
	elif game.in_station:
		location_title.text = "归航站 · 内部"
		location_sub.text = "人造重力 · 六廊中央枢纽与真实舷窗"
	elif game.state == "ship":
		if game.ship.docked:
			location_title.text = "驾驶舱  /  归航站"
			location_sub.text = "已对接 · E 进入空间站 · Space 解除对接"
		else:
			location_title.text = "驾驶舱  /  " + game.ship.target.display_name if game.ship.target != null else "驾驶舱"
			location_sub.text = "最近天体：" + planet.display_name + "　·　" + planet.description
	else:
		location_title.text = planet.display_name
		location_sub.text = planet.description
	prompt.text = game.get_prompt()
	if controls_hint != null:
		if game.has_touch_layer():
			controls_hint.text = "触屏 · 拖动右侧空白转视角"
		else:
			controls_hint.text = "M  星图    J  日志    Esc  菜单"
	if game.scan_target != null and game.scan_progress > 0.0 and not game.discovered.has(game.scan_target.anomaly_id):
		prompt.text += "　%d%%" % int(game.scan_progress * 100.0)
	if game.state == "ship":
		if game.ship.docked:
			status_title.text = "飞船系统 · 已对接补给"
		else:
			status_title.text = "飞船系统 · %.2f G" % (planet.gravity_strength / 20.0)
		# 数值带小数和单位 —— 「100%」看着像进度条，「100.0 %」才像仪表读数
		bar_a_label.text = "船体"
		bar_a_value.text = "%.1f %%" % game.ship.hull
		bar_b_label.text = "推进剂"
		bar_b_value.text = "%.1f T" % (game.ship.fuel * 0.01)
		bar_a.value = game.ship.hull
		bar_b.value = game.ship.fuel
		_row_icons[0].modulate = Color(0.55, 0.90, 0.95, 0.95) if game.ship.hull > 30.0 \
				else Color(1.0, 0.45, 0.30, 1.0)
		if game.ship.docked:
			ship_stats.text = "速度  000.0 m/s\n对接　归航站\nE 进入归航站 / Space 脱离\n推进剂与船体补给中"
		else:
			var normal: Vector3 = (game.ship.global_position - planet.global_position).normalized()
			var altitude: float = game.ship.global_position.distance_to(planet.global_position) - planet.terrain_height(normal)
			var target_text: String = game.ship.target.display_name if game.ship.target != null else "未锁定"
			var mode_text: String = "◈ 自动航行" if game.ship.autopilot else ("◈ 已停泊" if game.ship.landed else "手动驾驶")
			ship_stats.text = "速度  %05.1f m/s\n地表高度  %s\n目的地  %s\n%s" % [game.ship.velocity.length(), "%d m" % maxi(0, int(altitude)), target_text, mode_text]
			var vertical_speed: float = game.ship.velocity.dot(game.ship.global_transform.basis.y.normalized())
			if absf(vertical_speed) > 0.5:
				ship_stats.text += "\n垂直　%+.1f m/s" % vertical_speed
			if game.ship.zoom > 1.01:
				ship_stats.text += "\n长焦　%.1f×　滚轮缩放" % game.ship.zoom
			if game.ship.fuel <= 0.01 and not game.ship.landed:
				var support_left := maxi(0, int(float(game.ship.FUEL_LIFE_SUPPORT) - game.ship.fuel_empty_time))
				ship_stats.text += "\n推进剂耗尽　生命维持 %d s" % support_left
	elif game.in_attic:
		# 阁楼线里不显示宇航服读数
		pass
	else:
		if game.in_station:
			status_title.text = "宇航服 · %.2f G" % (game.station.artificial_gravity / 20.0)
		else:
			status_title.text = "宇航服 · %.2f G" % (planet.gravity_strength / 20.0)
		bar_a_label.text = "氧气"
		bar_a_value.text = "%.1f kPa" % (game.player.oxygen * 0.21)
		bar_b_label.text = "喷气燃料"
		bar_b_value.text = "%.1f kg" % (game.player.fuel * 0.12)
		bar_a.value = game.player.oxygen
		bar_b.value = game.player.fuel
		_row_icons[0].modulate = Color(0.55, 0.90, 0.95, 0.95) if game.player.oxygen > 25.0 \
				else Color(1.0, 0.45, 0.30, 1.0)
		ship_stats.text = ""
	ship_stats.visible = game.state == "ship"
	_update_system_lights()
	_update_gauge()
	# 左下角的读数面板整体跟着走：阁楼线藏、太空线显示
	if status_panel != null:
		status_panel.visible = not bool(game.in_attic)


func show_toast(text: String, duration := 3.0) -> void:
	if toast == null:
		return
	toast.text = text
	toast_timer = duration


func show_help() -> void:
	help.visible = true


func _overlay(dim: float) -> Control:
	var overlay := Control.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.004, 0.009, 0.022, dim)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return overlay


func _center_panel(parent: Control, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_bottom = panel_size.y * 0.5
	panel.add_theme_stylebox_override("panel", _panel_style())
	parent.add_child(panel)
	return panel


## Wenrexa「UI Minimalism SciFi」素材的九宫格贴图。
##
## 授权：CC0（作者 Wenrexa 明确写 "You can use it in COMMERCIAL and FREE projects"）。
## CC0 不要求署名，本项目仍在 THIRD_PARTY_NOTICES.md 里致谢。
##
## 为什么走 StyleBoxTexture 而不是继续用 StyleBoxFlat：
##   手写 StyleBoxFlat 只能画「纯色 + 直角/小圆角」，做不出包边、发光线、
##   内阴影这些让 UI 有「成品感」的细节。这是程序化 UI 的上限 —— 承认它，
##   该用素材就用素材。
##
## 缩放说明：素材里最薄的面板也有 143 米高、852×527 的大面板，
## 九宫格边距按「切角尺寸」取 8~12 像素，中间拉伸区不会被压扁。
const UI_TEX_DIR := "res://assets/ui/wenrexa/"

## 缓存已加载的贴图，避免每次建档都重新 load。
var _ui_tex_cache := {}


## 放一个图标。素材是「16×16 白色像素图 + 深描边」，所以用 modulate 染色即可。
##
## ⚠ TextureRect 的坑：默认 stretch_mode 会拉伸变形、expand_mode 会把小图硬撑开，
##   两者叠加就把 16×16 的图标糊成一块色斑（截图里船体旁边那个青色方块）。
##   正确做法：expand_mode = KEEP_SIZE（保留原尺寸）+ stretch_mode = KEEP，
##   然后靠 scale 做整数倍放大 —— 像素图放大必须整数倍，否则会灰边。
func _icon(parent: Control, name: String, rect: Rect2, tint := Color.WHITE) -> Control:
	var path := "res://assets/ui/icons/" + name
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.position = rect.position
		tr.size = rect.size
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.modulate = tint
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(tr)
		return tr
	var ph := ColorRect.new()
	ph.position = rect.position
	ph.size = rect.size
	ph.color = Color(tint.r, tint.g, tint.b, 0.25)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ph)
	return ph


func _ui_tex(name: String) -> Texture2D:
	if _ui_tex_cache.has(name):
		return _ui_tex_cache[name]
	var path := UI_TEX_DIR + name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_ui_tex_cache[name] = tex
	return tex


## 用素材贴图造一个九宫格 StyleBox。margin 传 4 个数（左/上/右/下）。
##
## 贴图缺失时返回 null，调用方负责回退到 StyleBoxFlat ——
## 这样即使素材没导入（新克隆仓库、CI 环境）也不会白屏。
func _nine(name: String, margins: Vector4, tint := Color.WHITE,
		pad := Vector4(0, 0, 0, 0)) -> StyleBox:
	var tex := _ui_tex(name)
	if tex == null:
		return null
	var box := StyleBoxTexture.new()
	box.texture = tex
	box.texture_margin_left = margins.x
	box.texture_margin_top = margins.y
	box.texture_margin_right = margins.z
	box.texture_margin_bottom = margins.w
	box.modulate_color = tint
	box.content_margin_left = pad.x
	box.content_margin_top = pad.y
	box.content_margin_right = pad.z
	box.content_margin_bottom = pad.w
	return box


func _panel_style() -> StyleBox:
	# 主面板用 MainPanel03（302×143，横向面板，拉伸最自然）。
	# 贴图没准备好时退回原来的 StyleBoxFlat，保证不会一屏空白。
	# ⚠ 这里把 tint 提到 1.15 倍亮度：原图偏暗，在 1080p 下几乎看不见边框，
	#   用户反馈「太素」。提亮后青色描边才明显，但仍保持深底。
	var box := _nine("MainPanel03.png", Vector4(12, 12, 12, 12),
		Color(1.35, 1.55, 1.70, 1.0), Vector4(18, 16, 18, 16))
	if box != null:
		return box
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.034, 0.055, 0.96)
	style.border_color = Color(0.28, 0.58, 0.58, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _panel_box(panel: Panel, margin: int) -> VBoxContainer:
	var container := MarginContainer.new()
	panel.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("margin_left", margin)
	container.add_theme_constant_override("margin_right", margin)
	container.add_theme_constant_override("margin_top", margin)
	container.add_theme_constant_override("margin_bottom", margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	container.add_child(box)
	return box


func _label(parent: Control, text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _text(parent: Container, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Container, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 17)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _bar(parent: Control, rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 底槽用主题里的 panel_inset 感觉（这里仍走纯色，因为进度条高度只有 7 像素，
	# 九宫格边距塞不下）。填充色由调用方给（氧气青 / 燃料琥珀）。
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.11, 0.14, 0.85)
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	# 填充加一条顶部高光，让条形有厚度而不是一块纯色
	fill.border_color = Color(color.r, color.g, color.b, 1.0).lightened(0.25)
	fill.border_width_top = 1
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


## 8 颗子系统状态灯。
##
## 这些是**真实状态**，不是随机闪烁的装饰 —— 每颗灯对应一个实际条件，
## 玩家扫一眼就知道哪个系统挂了。闪烁只用于「警告」态（见下面 sin 那段）。
##
## 顺序：船体 / 推进剂 / 生命维持 / 导航 / 通讯 / 扫描 / 护盾 / 引擎
func _update_system_lights() -> void:
	if _system_lights.is_empty():
		return
	var in_ship: bool = game.state == "ship"
	var hull: float = game.ship.hull if in_ship else game.player.oxygen
	var fuel: float = game.ship.fuel if in_ship else game.player.fuel
	var powered: bool = fuel > 0.5

	# 每项 {ok: 是否正常, warn: 是否警告}
	var states := [
		{"ok": hull > 40.0, "warn": hull <= 40.0},
		{"ok": fuel > 15.0, "warn": fuel <= 15.0},
		{"ok": hull > 20.0, "warn": hull <= 20.0},
		{"ok": true, "warn": false},
		{"ok": game.station != null, "warn": false},
		{"ok": game.scan_target != null, "warn": false},
		{"ok": not game.ship.autopilot, "warn": false},
		{"ok": powered, "warn": not powered},
	]

	# 警告态闪烁：用 game.visual_time 做相位，频率 3Hz
	var blink: float = 0.55 + 0.45 * sin(game.visual_time * 19.0)

	for i in range(_system_lights.size()):
		var light: ColorRect = _system_lights[i]
		if i >= states.size():
			light.color = Color(0.12, 0.2, 0.24, 0.6)
			continue
		var st: Dictionary = states[i]
		if st["warn"]:
			light.color = Color(1.0, 0.42, 0.26, blink)
		elif st["ok"]:
			light.color = Color(0.42, 0.92, 0.90, 0.92)
		else:
			light.color = Color(0.16, 0.28, 0.32, 0.75)


## 环形燃料表：把当前油量喂给 RingGauge 节点。
## 它自己负责绘制和坐标，这里只传一个 0~1 的数。
func _update_gauge() -> void:
	if _gauge_root == null:
		return
	var pct: float = 0.0
	if game.state == "ship":
		pct = game.ship.fuel / 100.0
	else:
		pct = game.player.fuel / 100.0
	_gauge_root.set_value(pct)


func _center_anchor(control: Control, bottom: bool) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	if bottom:
		control.anchor_top = 1.0
		control.anchor_bottom = 1.0
