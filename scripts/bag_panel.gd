extends CanvasLayer

## 行囊面板（B 键）：总览 / 鱼类详情两页。全部用代码绘制。
##
## 页（← / → 轮转）：
##   "overview"  金币 / 九鱼一览 / 进度
##   "dex"       鱼类详情：一页一条鱼，大字显示星级、最长纪录、已钓数量
##   "achievements"  成就总览：按类别分组，已解锁高亮
##   "runs"      最近远行：最近 5 次镜牢探索记录

var game
var font: Font
var painter: Painter
var open := false
var scroll := 0.0
## 当前页："overview" / "dex" / "achievements" / "runs"
var page := "overview"
## 成就总览的滚动行（↑ / ↓ 一次移一行）
var ach_scroll := 0
## 鱼类详情页当前翻到第几条（0 起，对应 FISH_IDS 顺序）
var dex_index := 0

## 图鉴顺序（与原作 FISH_TABLE 的插入顺序一致，稳定可翻页）
const FISH_IDS := [
	"ice-crucian", "snow-lamp", "bell-carp", "star-scale", "moon-perch",
	"aurora-trout", "cloud-ray", "galaxy-eel", "mirror-koi",
]


class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_panel(self)


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


func toggle() -> void:
	if open:
		close()
	else:
		open_panel()


func open_panel() -> void:
	if game == null or game.progress == null:
		return
	open = true
	scroll = 0.0
	page = "overview"
	painter.visible = true
	painter.queue_redraw()
	if game.audio != null:
		game.audio.play_ui(560.0)


func close() -> void:
	open = false
	painter.visible = false


## 翻页：总览 → 鱼类详情 → 成就 → 总览 轮转
func toggle_page() -> void:
	if not open:
		return
	match page:
		"overview":
			page = "dex"
		"dex":
			page = "achievements"
			ach_scroll = 0
		"achievements":
			page = "runs"
		_:
			page = "overview"
	if game.audio != null:
		game.audio.play_ui(640.0 if page != "overview" else 560.0)
	painter.queue_redraw()


## 回到总览（↓ 用）
func back_to_overview() -> bool:
	if not open or page == "overview":
		return false
	page = "overview"
	painter.queue_redraw()
	return true


## 成就页滚动
func scroll_achievements(step: int) -> bool:
	if not open or page != "achievements":
		return false
	var next_scroll: int = maxi(0, ach_scroll + step)
	if next_scroll == ach_scroll:
		return false
	ach_scroll = next_scroll
	painter.queue_redraw()
	return true


func _process(delta: float) -> void:
	if open:
		painter.queue_redraw()


## 鱼类详情页：左右翻鱼。返回是否真的动了（到头不绕圈）。
func page_fish(step: int) -> bool:
	if not open or page != "dex":
		return false
	var count: int = FISH_IDS.size()
	var next_index: int = clampi(dex_index + step, 0, count - 1)
	if next_index == dex_index:
		return false
	dex_index = next_index
	if game.audio != null:
		game.audio.play_ui(600.0 + float(dex_index) * 18.0)
	painter.queue_redraw()
	return true


func draw_panel(control: Control) -> void:
	if game == null or game.progress == null:
		return
	var size := control.size
	# 底板
	control.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.08, 0.86))
	var panel := Rect2(size * 0.5 - Vector2(420, 300), Vector2(840, 600))
	control.draw_rect(panel, Color(0.07, 0.10, 0.13, 0.96))
	control.draw_rect(panel, Color(0.35, 0.55, 0.6, 0.5), false, 2.0)
	if page == "dex":
		draw_dex_page(control, panel)
	elif page == "achievements":
		draw_achievements_page(control, panel)
	elif page == "runs":
		draw_runs_page(control, panel)
	else:
		draw_overview(control, panel)


func draw_overview(control: Control, panel: Rect2) -> void:
	var data: Dictionary = game.progress.summary()
	var left := panel.position + Vector2(34, 54)
	control.draw_string(font, left, "行 囊", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.92, 0.96, 0.95))
	control.draw_string(font, left + Vector2(150, 2), "金币 %d" % int(data["coins"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.85, 0.6))
	control.draw_string(font, left + Vector2(0, 34), "B / Esc 收起 · ← / → 翻页",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.8, 0.8, 0.6))
	# 页码提示
	control.draw_string(font, panel.position + Vector2(panel.size.x - 168, 54),
		"总览 · 1 / 4", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.62, 0.74, 0.74, 0.8))

	# --- 鱼类图鉴（一览）---
	var y := left.y + 78.0
	control.draw_string(font, Vector2(left.x, y), "鱼类图鉴 %d / %d · 鱼篓 %d 尾 · %s · %s" % [
		game.progress.dex_count(), game.progress.FISH_TABLE.size(),
		game.progress.held_count(), game.progress.rod_name(), game.progress.bait_name()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.85, 0.92, 0.9))
	y += 24.0
	var caught: Dictionary = data["fish"]
	# 单列：一行一条鱼。两列会重叠（「冰纹鲫 ★☆☆☆☆ ×2 · 最长 25cm」比列宽还长）
	for id in game.progress.FISH_TABLE.keys():
		var entry: Dictionary = caught.get(id, {})
		var count: int = int(entry.get("count", 0))
		var stars_text: String = game.progress.stars_text(id)
		var name_part: String
		var tail_part: String
		var color: Color
		if count > 0:
			name_part = game.progress.fish_name(id)
			tail_part = "×%d · 最长 %dcm" % [count, int(entry.get("best_length", 0))]
			color = Color(0.86, 0.94, 0.9)
		else:
			name_part = "？？？"
			tail_part = "还没钓到"
			color = Color(0.55, 0.62, 0.62, 0.7)
		control.draw_string(font, Vector2(left.x + 12.0, y), name_part,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
		control.draw_string(font, Vector2(left.x + 152.0, y), stars_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.96, 0.86, 0.5, 0.95) if count > 0 else Color(0.44, 0.5, 0.5, 0.75))
		control.draw_string(font, Vector2(left.x + 268.0, y), tail_part,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.78, 0.86, 0.84, 0.9) if count > 0 else Color(0.44, 0.5, 0.5, 0.7))
		y += 21.0
	# 推进到图鉴块之后（单列，按鱼种数算行数），避免最后一行压到成就标题
	var dex_rows: int = game.progress.FISH_TABLE.size()
	y = left.y + 78.0 + 24.0 + float(dex_rows) * 21.0 + 12.0

	# --- 成就概览（详细列表在第三页）---
	var ach_total: int = int(data["achievement_total"])
	var ach_all: int = game.progress.ACHIEVEMENTS.size()
	control.draw_string(font, Vector2(left.x, y), "成就 %d / %d" % [ach_total, ach_all],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.85, 0.92, 0.9))
	# 进度条
	var ach_bar := Vector2(left.x + 190.0, y - 8.0)
	var ach_w := 260.0
	control.draw_rect(Rect2(ach_bar, Vector2(ach_w, 8.0)), Color(0.12, 0.16, 0.19, 0.9))
	var ach_ratio: float = float(ach_total) / float(maxi(1, ach_all))
	control.draw_rect(Rect2(ach_bar, Vector2(ach_w * ach_ratio, 8.0)), Color(0.82, 0.76, 0.5, 0.95))
	control.draw_string(font, Vector2(left.x + 466.0, y), "→ 看成就总览",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.62, 0.74, 0.72, 0.85))
	y += 26.0
	# 最近解锁的三条
	var unlocked: Dictionary = data["achievements"]
	var shown := 0
	for id in game.progress.ACHIEVEMENTS.keys():
		if shown >= 3:
			break
		if not unlocked.has(id):
			continue
		var info: Array = game.progress.ACHIEVEMENTS[id]
		control.draw_string(font, Vector2(left.x + 12.0, y), "✦ " + String(info[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.92, 0.8))
		y += 22.0
		shown += 1
	if shown == 0:
		control.draw_string(font, Vector2(left.x + 12.0, y), "还没有解锁任何成就",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 0.56, 0.58, 0.6))

	# --- 进度 ---
	var bottom := panel.position + Vector2(34, panel.size.y - 56)
	var games: Dictionary = data["games"]
	var game_text := "小游戏 %d / 3" % games.size()
	for kind in games:
		var titles := {"chime": "风律", "firefly": "萤火", "rain": "檐雨"}
		game_text += " · %s %d" % [String(titles.get(kind, kind)), int(games[kind])]
	var bait_line := "S 卖出渔获（%d 尾）· R 升级鱼竿 · F 买鱼饵 · T 换鱼饵（%s）· 金币 %d" % [
		game.progress.held_count(), game.progress.bait_name(), int(data["coins"])]
	var charges: Array = []
	for id in ["glow", "star"]:
		var left_count: int = game.progress.bait_charge(id)
		if left_count > 0:
			charges.append("%s×%d" % [String(game.progress.BAITS[id][0]), left_count])
	if not charges.is_empty():
		bait_line += " · " + " ".join(charges)
	control.draw_string(font, bottom - Vector2(0, 22), bait_line,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.88, 0.66, 0.9))
	control.draw_string(font, bottom, "纪念 %d / 4 · 茶席 %d / 3 · %s" % [
		game.keepsakes.size(), game.attic.tea_step if game.attic != null else 0, game_text],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.78, 0.86, 0.86, 0.9))
	if game.progress != null and not game.progress.dungeon.is_empty():
		var dungeon: Dictionary = game.progress.dungeon
		control.draw_string(font, bottom + Vector2(0, 46),
			"镜牢 · 探索 %d · 通关 %d · 最好 %s %s · 累计镜印 %d" % [
				int(dungeon.get("runs", 0)), int(dungeon.get("clears", 0)),
				String(dungeon.get("best_rank", "")),
				game.progress.time_text(float(dungeon.get("best_seconds", 0.0))),
				int(dungeon.get("total_boons", 0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.82, 0.78, 0.9, 0.9))
	if game.attic != null and game.attic_worlds != null:
		control.draw_string(font, bottom + Vector2(0, 24),
			"冰钓 %d / 3 · 听雨灯 %d / 3%s · %s" % [
				game.attic_worlds.caught_count(),
				game.attic_worlds.court_lit_count(),
				"（已坐过）" if game.attic_worlds.court_rested else "",
				"棱镜之心 已带回" if game.has_prism_heart else "棱镜之心 还在镜界"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.72, 0.82, 0.82, 0.85))


## 鱼类详情页：一页一条鱼，大字显示星级 / 最长纪录 / 已钓数量
func draw_dex_page(control: Control, panel: Rect2) -> void:
	var data: Dictionary = game.progress.summary()
	var caught: Dictionary = data["fish"]
	var id: String = String(FISH_IDS[dex_index])
	var entry: Dictionary = caught.get(id, {})
	var count: int = int(entry.get("count", 0))
	var best: int = int(entry.get("best_length", 0))
	var stars: int = game.progress.fish_stars(id)
	var known: bool = count > 0

	var left := panel.position + Vector2(34, 54)
	control.draw_string(font, left, "鱼 类 详 情", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(0.92, 0.96, 0.95))
	control.draw_string(font, panel.position + Vector2(panel.size.x - 168, 54),
		"详情 · 2 / 4", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.62, 0.74, 0.74, 0.8))
	control.draw_string(font, left + Vector2(0, 34), "B / Esc 收起 · ← / → 换一条 · ↓ 回总览",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.8, 0.8, 0.6))

	# 序号：01 / 09
	control.draw_string(font, panel.position + Vector2(34, 128),
		"%02d / %02d" % [dex_index + 1, FISH_IDS.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.7, 0.72, 0.85))

	# 鱼名（未钓到则隐去）
	var name_y := panel.position + Vector2(34, 208)
	if known:
		control.draw_string(font, name_y, game.progress.fish_name(id),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0.94, 0.97, 0.95))
	else:
		control.draw_string(font, name_y, "？？？",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0.42, 0.48, 0.5, 0.9))

	# 星级（大字）
	var star_text := ""
	for i in range(5):
		star_text += "★" if i < stars else "☆"
	var star_color := Color(0.98, 0.84, 0.46) if known else Color(0.45, 0.5, 0.5, 0.8)
	control.draw_string(font, panel.position + Vector2(34, 268), star_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 40, star_color)
	control.draw_string(font, panel.position + Vector2(34 + 20.0 * 5.0 + 22.0, 258),
		"稀有度 %d / 5" % stars, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.82, 0.88, 0.86, 0.9))

	# 分隔线
	var sep_y := panel.position.y + 300.0
	control.draw_line(Vector2(panel.position.x + 34, sep_y),
		Vector2(panel.position.x + panel.size.x - 34, sep_y), Color(0.3, 0.45, 0.48, 0.5), 1.0)

	# 三条关键数值
	var rows := [
		["已钓数量", ("%d 尾" % count) if known else "还没钓到"],
		["最长纪录", ("%d cm" % best) if best > 0 else "—"],
		["单尾价值", "%d 金" % game.progress.fish_value(id)],
	]
	var row_y := sep_y + 44.0
	for row in rows:
		control.draw_string(font, Vector2(panel.position.x + 40, row_y), String(row[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.62, 0.74, 0.74, 0.9))
		control.draw_string(font, Vector2(panel.position.x + 236, row_y), String(row[1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(0.92, 0.95, 0.92) if known else Color(0.5, 0.56, 0.56, 0.8))
		row_y += 48.0

	# 传说鱼标记
	if game.progress.LEGEND_FISH.has(id):
		control.draw_string(font, Vector2(panel.position.x + 40, row_y + 6),
			"传说 · 只有星屑饵才引得动它", HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			Color(0.86, 0.72, 0.98, 0.9))
	elif not known:
		control.draw_string(font, Vector2(panel.position.x + 40, row_y + 6),
			"钓上来才会记进这里", HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			Color(0.6, 0.68, 0.68, 0.8))

	# 底部：整册进度条 + 当前饵
	var bar_base := panel.position + Vector2(34, panel.size.y - 62)
	var bar_w: float = panel.size.x - 68.0
	control.draw_rect(Rect2(bar_base, Vector2(bar_w, 8.0)), Color(0.12, 0.16, 0.19, 0.9))
	var ratio: float = float(game.progress.dex_count()) / float(FISH_IDS.size())
	control.draw_rect(Rect2(bar_base, Vector2(bar_w * ratio, 8.0)), Color(0.5, 0.8, 0.72, 0.95))
	control.draw_string(font, bar_base + Vector2(0, 32),
		"图鉴 %d / %d · 鱼竿 %s · 当前饵 %s · 鱼篓 %d 尾" % [
			game.progress.dex_count(), FISH_IDS.size(),
			game.progress.rod_name(), game.progress.bait_name(), game.progress.held_count()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.84, 0.84, 0.9))

## 成就页的分类：id -> 组名（照原作把成就分成六组）
const ACH_GROUPS := [
	["冰钓与鱼市", ["first_fish", "three_fish", "ice-lanterns", "dex-half", "dex-all",
		"angler", "merchant", "rich"]],
	["四个远方", ["keepsake_snow", "keepsake_cloud", "keepsake_forest", "keepsake_rain",
		"keepsake_all", "wind_organ"]],
	["阁楼日常", ["tea_full", "court_rest", "listening-court", "prism_heart"]],
	["三处小游戏", ["wind-song", "firefly-guide", "rain-tempo", "games_all"]],
	["镜界与镜牢", ["mirror-calm", "three-faces", "dungeon_first", "dungeon_clear",
		"dungeon_flawless", "deep-run"]],
]


## 成就总览页：按组列出全部成就，已解锁高亮
func draw_achievements_page(control: Control, panel: Rect2) -> void:
	var data: Dictionary = game.progress.summary()
	var unlocked: Dictionary = data["achievements"]
	var total: int = int(data["achievement_total"])
	var ach_all: int = game.progress.ACHIEVEMENTS.size()

	var left := panel.position + Vector2(34, 54)
	control.draw_string(font, left, "成 就", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(0.92, 0.96, 0.95))
	control.draw_string(font, left + Vector2(110, 2), "%d / %d" % [total, ach_all],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.85, 0.6))
	control.draw_string(font, panel.position + Vector2(panel.size.x - 176, 54),
		"成就 · 3 / 4", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.62, 0.74, 0.74, 0.8))
	control.draw_string(font, left + Vector2(0, 34),
		"B / Esc 收起 · ← / → 翻页 · ↑ / ↓ 滚动", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(0.7, 0.8, 0.8, 0.6))

	# 顶部总进度条
	var bar := Vector2(left.x, left.y + 62.0)
	var bar_w: float = panel.size.x - 68.0
	control.draw_rect(Rect2(bar, Vector2(bar_w, 10.0)), Color(0.12, 0.16, 0.19, 0.9))
	var ratio: float = float(total) / float(maxi(1, ach_all))
	control.draw_rect(Rect2(bar, Vector2(bar_w * ratio, 10.0)), Color(0.86, 0.78, 0.52, 0.95))

	# 分组逐条列出
	var y := bar.y + 40.0
	var group_gap := 10.0
	var row_h := 24.0
	for group in ACH_GROUPS:
		var title := String(group[0])
		var ids: Array = group[1]
		# 组标题 + 该组进度
		var got := 0
		for id in ids:
			if unlocked.has(String(id)):
				got += 1
		control.draw_string(font, Vector2(left.x, y), "%s　%d / %d" % [title, got, ids.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.82, 0.89, 0.86))
		y += row_h - 2.0
		for id in ids:
			if not game.progress.ACHIEVEMENTS.has(String(id)):
				continue
			var info: Array = game.progress.ACHIEVEMENTS[String(id)]
			var has: bool = unlocked.has(String(id))
			var mark := "✦" if has else "·"
			var name_color := Color(0.94, 0.92, 0.78) if has else Color(0.5, 0.56, 0.58, 0.7)
			var desc_color := Color(0.72, 0.78, 0.72, 0.85) if has else Color(0.4, 0.46, 0.48, 0.55)
			control.draw_string(font, Vector2(left.x + 8.0, y), mark,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, name_color)
			control.draw_string(font, Vector2(left.x + 32.0, y), String(info[0]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_color)
			control.draw_string(font, Vector2(left.x + 216.0, y), String(info[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, desc_color)
			y += row_h
		y += group_gap
		if y > panel.position.y + panel.size.y - 70.0:
			break

	control.draw_string(font, panel.position + Vector2(34, panel.size.y - 30),
		"✦ 已解锁　· 未解锁 · 继续走，它们会自己亮起来",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.62, 0.72, 0.72, 0.85))

## 最近远行页：最近 5 次镜牢探索（最新在前）
func draw_runs_page(control: Control, panel: Rect2) -> void:
	var data: Dictionary = game.progress.summary()
	var dungeon: Dictionary = game.progress.dungeon
	var runs: Array = game.progress.recent_runs

	var left := panel.position + Vector2(34, 54)
	control.draw_string(font, left, "最 近 远 行", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(0.92, 0.96, 0.95))
	control.draw_string(font, panel.position + Vector2(panel.size.x - 168, 54),
		"远行 · 4 / 4", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.62, 0.74, 0.74, 0.8))
	control.draw_string(font, left + Vector2(0, 34),
		"B / Esc 收起 · ← / → 翻页 · 镜牢的最近五次探索",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.8, 0.8, 0.6))

	# 顶部汇总：探索次数 / 通关次数 / 最佳
	var y := left.y + 74.0
	var best_rank := String(dungeon.get("best_rank", ""))
	var best_seconds := float(dungeon.get("best_seconds", 0.0))
	var best_text := "—"
	if best_rank != "" and best_seconds > 0.0:
		best_text = "%s · %s" % [best_rank, game.progress.time_text(best_seconds)]
	control.draw_string(font, Vector2(left.x, y),
		"探索 %d 次 · 通关 %d 次 · 最佳 %s" % [
			int(dungeon.get("runs", 0)), int(dungeon.get("clears", 0)), best_text],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.88, 0.9, 0.82))
	y += 22.0
	var flawless: bool = bool(dungeon.get("flawless", false))
	control.draw_string(font, Vector2(left.x, y),
		"累计镜币 %d · 累计镜印 %d · %s" % [
			game.progress.mirror_coins_total, int(dungeon.get("total_boons", 0)),
			"有无伤纪录" if flawless else "还没有无伤通关"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.72, 0.8, 0.8, 0.9))

	# 分隔线
	var sep_y := y + 26.0
	control.draw_line(Vector2(panel.position.x + 34, sep_y),
		Vector2(panel.position.x + panel.size.x - 34, sep_y), Color(0.3, 0.45, 0.48, 0.5), 1.0)

	# 表头
	var head_y := sep_y + 28.0
	control.draw_string(font, Vector2(left.x + 6, head_y), "序",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.56, 0.68, 0.68, 0.85))
	control.draw_string(font, Vector2(left.x + 52, head_y), "结果",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.56, 0.68, 0.68, 0.85))
	control.draw_string(font, Vector2(left.x + 152, head_y), "用时",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.56, 0.68, 0.68, 0.85))
	control.draw_string(font, Vector2(left.x + 252, head_y), "受击",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.56, 0.68, 0.68, 0.85))
	control.draw_string(font, Vector2(left.x + 332, head_y), "击杀",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.56, 0.68, 0.68, 0.85))
	control.draw_string(font, Vector2(left.x + 412, head_y), "镜币",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.56, 0.68, 0.68, 0.85))
	control.draw_string(font, Vector2(left.x + 500, head_y), "评级",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.56, 0.68, 0.68, 0.85))
	control.draw_string(font, Vector2(left.x + 580, head_y), "层",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.56, 0.68, 0.68, 0.85))

	var row_y := head_y + 26.0
	if runs.is_empty():
		control.draw_string(font, Vector2(left.x + 6, row_y), "还没有远行记录。走进镜牢回廊，尽头会记下你这一趟。",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.56, 0.64, 0.64, 0.85))
	else:
		for i in range(runs.size()):
			var run: Dictionary = runs[i]
			var cleared: bool = bool(run.get("cleared", false))
			var rank := String(run.get("rank", ""))
			var row_color := Color(0.86, 0.92, 0.9) if cleared else Color(0.66, 0.7, 0.72, 0.85)
			control.draw_string(font, Vector2(left.x + 6, row_y), str(i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.58, 0.7, 0.7, 0.85))
			control.draw_string(font, Vector2(left.x + 52, row_y),
				"抵达尽头" if cleared else "中途退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, row_color)
			control.draw_string(font, Vector2(left.x + 152, row_y),
				game.progress.time_text(float(run.get("seconds", 0.0))),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, row_color)
			control.draw_string(font, Vector2(left.x + 252, row_y),
				str(int(run.get("hits", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, row_color)
			control.draw_string(font, Vector2(left.x + 332, row_y),
				str(int(run.get("kills", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, row_color)
			control.draw_string(font, Vector2(left.x + 412, row_y),
				"+%d" % int(run.get("coins", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				Color(0.94, 0.86, 0.6))
			var rank_color := Color(0.5, 0.56, 0.58, 0.6)
			if cleared:
				match rank:
					"S":
						rank_color = Color(0.98, 0.84, 0.46)
					"A":
						rank_color = Color(0.72, 0.92, 0.78)
					_:
						rank_color = Color(0.76, 0.84, 0.92)
			control.draw_string(font, Vector2(left.x + 500, row_y), rank if rank != "" else "—",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, rank_color)
			control.draw_string(font, Vector2(left.x + 580, row_y),
				str(int(run.get("rooms", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, row_color)
			row_y += 30.0

	# 底部
	control.draw_string(font, panel.position + Vector2(34, panel.size.y - 30),
		"镜币在离开镜牢时结算进行囊 · 最佳纪录只被更好的成绩覆盖",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.62, 0.72, 0.72, 0.85))
