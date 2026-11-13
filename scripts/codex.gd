extends CanvasLayer

## 星图图鉴（C 键）：把玩家走过的每颗星球记成一页。
##
## 为什么要有这一页：
##   遗迹扫描（E 键）已经在每颗星球记进度了，但玩家只能靠靠近遗迹时
##   那一行提示看到「图鉴 3/7」，看不到「我一共走过几颗星、哪颗集满了」。
##   这一页把这些汇总起来：每颗星的名称、重力、一句话地貌、
##   遗迹扫描进度、以及亲手记下的遗迹条目。
##
## 设计原则（与 handbook.gd 一致）：
##   · 纯代码绘制，不依赖贴图，任何分辨率都不糊
##   · 只读，不改游戏状态 —— 打开时不暂停、不收鼠标
##   · 没去过的星球显示为「未发现」，信息不留白也不剧透
##
## 数据来源：
##   · 星球目录 → game 的 built_planet_ids / PLANETS
##   · 扫描进度 → planet.relic_progress()
##   · 逐条记录 → game.relic_seen（键为 "星球id:索引"）

var game
var font: Font
var painter: Painter
var open := false
## 当前选中的星球序号（在 _planet_rows() 返回的列表里）
var cursor := 0
## 列表滚动偏移
var scroll := 0


class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_codex(self)


func setup(host) -> void:
	game = host
	layer = 15
	font = load("res://assets/ui_font.ttf")
	if font == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(
			["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
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
		open_codex()


func open_codex() -> void:
	open = true
	scroll = 0
	# 打开时自动定位到「当前所在的星球」，省得每次都从头翻
	var rows: Array = _planet_rows()
	var cur: String = _current_planet_id()
	for i in range(rows.size()):
		if String(rows[i]["id"]) == cur:
			cursor = i
			break
	painter.visible = true
	painter.queue_redraw()
	if game != null and game.audio != null:
		game.audio.play_ui(700.0)


func close() -> void:
	open = false
	painter.visible = false


## 上下切换选中的星球。返回是否真的移动了。
func move_cursor(step: int) -> bool:
	if not open:
		return false
	var rows: Array = _planet_rows()
	if rows.is_empty():
		return false
	var next: int = clampi(cursor + step, 0, rows.size() - 1)
	if next == cursor:
		return false
	cursor = next
	# 让选中项始终在可视范围里
	var visible_rows := _visible_row_count()
	if cursor < scroll:
		scroll = cursor
	elif cursor >= scroll + visible_rows:
		scroll = cursor - visible_rows + 1
	scroll = maxi(0, mini(scroll, maxi(0, rows.size() - visible_rows)))
	if game != null and game.audio != null:
		game.audio.play_ui(640.0)
	painter.queue_redraw()
	return true


func _process(_delta: float) -> void:
	if open:
		painter.queue_redraw()


# ── 数据 ──────────────────────────────────────────────────────────────

## 当前所在星球的 planet_id（不在星球上时返回空串）。
func _current_planet_id() -> String:
	if game == null:
		return ""
	var host: Node = null
	if game.player != null:
		host = game.player.get_parent()
	if host != null and host.has_method("relic_progress"):
		return String(host.get("planet_id"))
	if game.ship != null:
		var p: Node = game.nearest_planet(game.ship.global_position)
		if p != null:
			return String(p.get("planet_id"))
	return ""


## 收集所有「已经建出来」的星球（即玩家可能走到的那些）。
##
## ��用 game.built_planet_ids：那是实际构建成功的星球集合，
## 没建出来的不该出现在图鉴里（玩家根本去不了）。
func _planet_rows() -> Array:
	var rows: Array = []
	if game == null:
		return rows
	var ids: Dictionary = game.built_planet_ids
	if ids.is_empty():
		return rows
	var discovered: Dictionary = game.discovered
	for key in ids.keys():
		var pid := String(key)
		var planet := _find_planet(pid)
		if planet == null:
			continue
		var prog: Array = planet.relic_progress()
		rows.append({
			"id": pid,
			"node": planet,
			"name": String(planet.get("display_name")) if planet.get("display_name") != null else pid,
			"found": discovered.has(pid),
			"scanned": int(prog[0]),
			"total": int(prog[1]),
		})
	# 主页青岚星排最前，其余按 id 排，保证每次打开顺序一致
	rows.sort_custom(func(a, b):
		if String(a["id"]) == "qinglan":
			return true
		if String(b["id"]) == "qinglan":
			return false
		return String(a["id"]) < String(b["id"])
	)
	return rows


func _find_planet(pid: String) -> Node:
	for c in game.get_children():
		if c.has_method("relic_progress") and String(c.get("planet_id")) == pid:
			return c
	return null


## 某颗星球上「已扫描的遗迹条目」：返回 [{seen, prop, index}]。
##
## ⚠ 索引取的是**数组下标**，不是条目里的 "index" 字段 ——
##   interactive_spots 里的条目本身没有 index 字段，
##   那个字段是 nearest_interactive() 返回副本时才补上的。
##   main.gd 写 relic_seen 时用的也是这个下标（E 键交互的 spot["index"]），
##   两边必须一致，否则图鉴永远显示「尚未记录」。
func _relic_entries(planet: Node) -> Array:
	var out: Array = []
	if planet == null or game == null:
		return out
	var pid := String(planet.get("planet_id"))
	var spots: Array = planet.get("interactive_spots")
	for i in range(spots.size()):
		var entry: Dictionary = spots[i]
		if String(entry.get("kind")) != "relic":
			continue
		var seen: bool = game.relic_seen.has("%s:%d" % [pid, i])
		out.append({
			"seen": seen or bool(entry.get("scanned", false)),
			"prop": String(entry.get("id", "")),
			"index": i,
		})
	return out


# ── 绘制 ──────────────────────────────────────────────────────────────

const PANEL_W := 1060.0
const PANEL_H := 660.0
const ROW_H := 34.0
const LIST_TOP := 176.0
const LIST_BOTTOM := 574.0


func _visible_row_count() -> int:
	return int((LIST_BOTTOM - LIST_TOP) / ROW_H)


func draw_codex(control: Control) -> void:
	if game == null or font == null:
		return
	var size := control.size
	control.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.07, 0.92))
	var panel := Rect2(size * 0.5 - Vector2(PANEL_W * 0.5, PANEL_H * 0.5),
		Vector2(PANEL_W, PANEL_H))
	control.draw_rect(panel, Color(0.06, 0.09, 0.12, 0.98))
	control.draw_rect(panel, Color(0.36, 0.56, 0.6, 0.55), false, 2.0)

	var left := panel.position + Vector2(36, 56)
	control.draw_string(font, left, "星 图 图 鉴", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(0.93, 0.96, 0.94))
	control.draw_string(font, left + Vector2(210, 4), "STARCHART CODEX",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.72, 0.7, 0.75))

	var rows: Array = _planet_rows()
	var found := 0
	var scanned := 0
	var total := 0
	for r in rows:
		if bool(r["found"]):
			found += 1
		scanned += int(r["scanned"])
		total += int(r["total"])
	control.draw_string(font, left + Vector2(0, 32),
		"走过 %d / %d 颗星球　·　遗迹记录 %d / %d" % [found, rows.size(), scanned, total],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.66, 0.78, 0.78, 0.9))

	# 分隔线
	var sep_y := panel.position.y + 108.0
	control.draw_line(Vector2(panel.position.x + 36, sep_y),
		Vector2(panel.position.x + panel.size.x - 36, sep_y),
		Color(0.3, 0.46, 0.48, 0.45), 1.0)

	if rows.is_empty():
		control.draw_string(font, panel.position + Vector2(40, 160),
			"还没有记录到任何星球。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			Color(0.7, 0.78, 0.78, 0.9))
		_draw_footer(control, panel)
		return

	cursor = clampi(cursor, 0, rows.size() - 1)
	_draw_list(control, panel, rows)
	_draw_detail(control, panel, rows[cursor])
	_draw_footer(control, panel)


func _draw_list(control: Control, panel: Rect2, rows: Array) -> void:
	var x := panel.position.x + 36.0
	var visible := _visible_row_count()
	var end: int = mini(rows.size(), scroll + visible)
	for i in range(scroll, end):
		var r: Dictionary = rows[i]
		var y: float = panel.position.y + LIST_TOP + float(i - scroll) * ROW_H
		var active: bool = i == cursor
		var found: bool = bool(r["found"])
		if active:
			control.draw_rect(Rect2(Vector2(x - 8.0, y - 19.0),
				Vector2(370.0, ROW_H - 4.0)), Color(0.18, 0.34, 0.38, 0.85))
		var name_color: Color = Color(0.94, 0.97, 0.95) if found else Color(0.42, 0.48, 0.5, 0.75)
		var name := String(r["name"]) if found else "未发现"
		control.draw_string(font, Vector2(x, y), name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, name_color)
		# 进度条：右侧的小方点，一眼看出哪颗集满
		var total := int(r["total"])
		var done := int(r["scanned"])
		var dot_x := x + 210.0
		for k in range(mini(total, 12)):
			var on: bool = k < done
			control.draw_rect(Rect2(Vector2(dot_x + float(k) * 11.0, y - 10.0),
				Vector2(7.0, 7.0)),
				Color(0.55, 0.92, 0.72, 0.95) if on else Color(0.22, 0.30, 0.33, 0.8))


func _draw_detail(control: Control, panel: Rect2, row: Dictionary) -> void:
	var x := panel.position.x + 440.0
	var y := panel.position.y + LIST_TOP + 4.0
	var found: bool = bool(row["found"])
	if not found:
		control.draw_string(font, Vector2(x, y), "未 发 现",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.5, 0.58, 0.6, 0.9))
		control.draw_string(font, Vector2(x, y + 34.0),
			"这颗星球还没有被观测到。", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.6, 0.7, 0.7, 0.85))
		control.draw_string(font, Vector2(x, y + 58.0),
			"靠近它并按 E 着陆，就会被记进这一页。", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.6, 0.7, 0.7, 0.85))
		return

	var planet: Node = row["node"]
	control.draw_string(font, Vector2(x, y), String(row["name"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.94, 0.97, 0.95))

	var accent: Color = planet.get("accent_color")
	if accent == null:
		accent = Color(0.7, 0.85, 0.85)
	control.draw_rect(Rect2(Vector2(x, y + 12.0), Vector2(48.0, 2.0)),
		Color(accent.r, accent.g, accent.b, 0.8))

	var gravity: float = float(planet.get("gravity_strength"))
	control.draw_string(font, Vector2(x, y + 40.0),
		"重力 %.2f G　·　半径 %.0f m" % [gravity / 9.8, float(planet.get("radius"))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.8, 0.8, 0.9))

	var desc := String(planet.get("description")) if planet.get("description") != null else ""
	if desc == "":
		desc = "一颗还没有写下地貌记录的行星。"
	control.draw_string(font, Vector2(x, y + 66.0), desc,
		HORIZONTAL_ALIGNMENT_LEFT, 570, 15, Color(0.72, 0.82, 0.82, 0.92))

	# 遗迹扫描进度
	var done := int(row["scanned"])
	var total := int(row["total"])
	var line_y := y + 108.0
	control.draw_string(font, Vector2(x, line_y),
		"遗迹记录 %d / %d" % [done, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(0.88, 0.93, 0.9))
	if total > 0 and done >= total:
		control.draw_string(font, Vector2(x + 150.0, line_y), "已集满",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.92, 0.72, 0.95))

	var bar := Rect2(Vector2(x, line_y + 10.0), Vector2(570.0, 6.0))
	control.draw_rect(bar, Color(0.16, 0.22, 0.25, 0.9))
	if total > 0:
		control.draw_rect(Rect2(bar.position,
			Vector2(bar.size.x * float(done) / float(total), bar.size.y)),
			Color(0.4, 0.82, 0.7, 0.95))

	# 逐条遗迹
	var entries: Array = _relic_entries(planet)
	control.draw_string(font, Vector2(x, line_y + 42.0), "记下的条目",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.86, 0.92, 0.9))
	var ey := line_y + 68.0
	var shown := 0
	for e in entries:
		if shown >= 8:
			break
		var seen: bool = bool(e["seen"])
		var label := "· 尚未记录的遗迹"
		if seen:
			label = "✓ " + _relic_title(String(e["prop"]))
		control.draw_string(font, Vector2(x, ey), label,
			HORIZONTAL_ALIGNMENT_LEFT, 570, 14,
			Color(0.66, 0.9, 0.74, 0.95) if seen else Color(0.5, 0.58, 0.6, 0.85))
		ey += 22.0
		shown += 1
	if entries.is_empty():
		control.draw_string(font, Vector2(x, ey), "· 这颗星球上还没有发现遗迹",
			HORIZONTAL_ALIGNMENT_LEFT, 570, 14, Color(0.5, 0.58, 0.6, 0.85))


func _relic_title(prop: String) -> String:
	match prop:
		"ruin-arch":
			return "旧时代的门洞"
		"stone-idol":
			return "风蚀的石像"
		"obelisk":
			return "浅刻的方尖碑"
		"rubble-wall":
			return "带灰层的断墙"
		"control-console":
			return "停机的控制台"
		"stasis-pod":
			return "封存的静置舱"
		"holo-slab":
			return "半熄的全息碑"
		"databank":
			return "没读完的数据库"
		"comm-dish":
			return "对着空处的天线"
		_:
			return prop if prop != "" else "某处遗迹"


func _draw_footer(control: Control, panel: Rect2) -> void:
	var bottom := panel.position + Vector2(36, panel.size.y - 30)
	control.draw_string(font, bottom,
		"↑ / ↓ 选择星球　·　C / Esc 合上图鉴　·　遗迹靠近后按 E 扫描",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.72, 0.72, 0.85))
