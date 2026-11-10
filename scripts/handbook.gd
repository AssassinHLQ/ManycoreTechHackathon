extends CanvasLayer

## 旅人手册（H 键）：照伴随版 HTML 的七节结构，全部代码绘制。
##
## 节：
##   1 基本操作
##   2 旅途怎么进行
##   3 行囊 · 鱼市 · 成就
##   4 世界小游戏
##   5 你的旅途进度（动态）
##   6 远方提示（每个世界一段）
##   7 太空线（本作额外的星际原型）

var game
var font: Font
var painter: Painter
var open := false
## 当前节序号
var section := 0
## 可滚动偏移（节内过长时用 ↑ / ↓）
var scroll := 0.0

const SECTIONS := [
	"基本操作",
	"旅途怎么进行",
	"行囊 · 鱼市 · 成就",
	"世界小游戏",
	"你的旅途进度",
	"远方提示",
	"太空线",
]


class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_handbook(self)


func setup(host) -> void:
	game = host
	layer = 12
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
	scroll = 0.0
	painter.visible = true
	painter.queue_redraw()
	if game != null and game.audio != null:
		game.audio.play_ui(600.0)


func close() -> void:
	open = false
	painter.visible = false


## 翻节：-1 上一节 / +1 下一节
func step_section(step: int) -> bool:
	if not open:
		return false
	var next_index: int = clampi(section + step, 0, SECTIONS.size() - 1)
	if next_index == section:
		return false
	section = next_index
	scroll = 0.0
	if game != null and game.audio != null:
		game.audio.play_ui(660.0)
	painter.queue_redraw()
	return true


func _process(_delta: float) -> void:
	if open:
		painter.queue_redraw()


func draw_handbook(control: Control) -> void:
	if game == null or font == null:
		return
	var size := control.size
	control.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.07, 0.92))
	var panel := Rect2(size * 0.5 - Vector2(470, 330), Vector2(940, 660))
	control.draw_rect(panel, Color(0.06, 0.09, 0.12, 0.98))
	control.draw_rect(panel, Color(0.36, 0.56, 0.6, 0.55), false, 2.0)

	var left := panel.position + Vector2(36, 56)
	control.draw_string(font, left, "旅 人 手 册", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(0.93, 0.96, 0.94))
	control.draw_string(font, left + Vector2(230, 4), "TRAVELER'S HANDBOOK",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.72, 0.7, 0.75))
	control.draw_string(font, left + Vector2(0, 32),
		"一间阁楼，四个远方，一面镜界，和五处可以反复玩的小游戏。",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.66, 0.78, 0.78, 0.9))

	# 节标签行
	var tab_y := panel.position.y + 108.0
	var tab_x := panel.position.x + 36.0
	for i in range(SECTIONS.size()):
		var label := String(SECTIONS[i])
		var active: bool = i == section
		var w: float = _text_width(label, 15) + 26.0
		control.draw_rect(Rect2(Vector2(tab_x, tab_y - 17.0), Vector2(w, 28.0)),
			Color(0.20, 0.38, 0.40, 0.9) if active else Color(0.10, 0.15, 0.18, 0.75))
		control.draw_string(font, Vector2(tab_x + 13.0, tab_y + 3.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.94, 0.97, 0.95) if active else Color(0.6, 0.7, 0.7, 0.85))
		tab_x += w + 8.0

	# 分隔线
	var sep_y := panel.position.y + 142.0
	control.draw_line(Vector2(panel.position.x + 36, sep_y),
		Vector2(panel.position.x + panel.size.x - 36, sep_y), Color(0.3, 0.46, 0.48, 0.45), 1.0)

	# 正文
	var body_y := sep_y + 34.0
	var body_x := panel.position.x + 40.0
	var lines: Array = _section_lines()
	for entry in lines:
		var text := String(entry[0])
		var scale := int(entry[1])
		var color: Color = entry[2]
		if body_y > panel.position.y + panel.size.y - 60.0:
			break
		control.draw_string(font, Vector2(body_x + float(entry[3]), body_y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, scale, color)
		body_y += float(scale) + 11.0

	# 底部
	var bottom := panel.position + Vector2(36, panel.size.y - 30)
	control.draw_string(font, bottom,
		"← / → 翻节（%d / %d）· R 重播新手提示 · H / Esc 合上手册" % [section + 1, SECTIONS.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.72, 0.72, 0.85))


func _text_width(text: String, size: int) -> float:
	if font == null:
		return float(text.length()) * float(size) * 0.55
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 每一节的行：[文字, 字号, 颜色, 左缩进]
func _section_lines() -> Array:
	var head := Color(0.86, 0.92, 0.9)
	var body := Color(0.74, 0.83, 0.83, 0.95)
	var dim := Color(0.6, 0.7, 0.7, 0.8)
	var key := Color(0.95, 0.87, 0.62)
	match section:
		0:
			return [
				["[基本操作]", 18, head, 0.0],
				["W A S D　移动　　Shift　疾跑　　R　地形脱困", 16, body, 0.0],
				["鼠标　环顾（点击画面锁定）　　Esc　暂停 / 释放鼠标", 16, body, 0.0],
				["E　互动 / 推门 / 上下云舟 / 交互", 16, body, 0.0],
				["B　行囊（鱼市 · 图鉴 · 成就 · 镜印）", 16, body, 0.0],
				["H　打开 / 合上这本手册", 16, body, 0.0],
				["J　航海日志　　M　星图", 16, body, 0.0],
				["", 8, dim, 0.0],
				["[镜界 / 镜牢]", 18, head, 0.0],
				["1 / 2 / 3　棱镜杖 · 镜刃 · 折光弩", 16, body, 0.0],
				["左键 / F　攻击　　右键 / Q　武器绝技", 16, body, 0.0],
				["Space　闪避（0.45 秒无敌帧）", 16, body, 0.0],
				["", 8, dim, 0.0],
				["[行囊里]", 18, head, 0.0],
				["S　卖出渔获　　R　升级鱼竿", 16, body, 0.0],
				["F　买鱼饵　　T　换鱼饵", 16, body, 0.0],
				["← / →　总览 ⇄ 鱼类详情　　↓　回总览", 16, body, 0.0],
			]
		1:
			return [
				["[旅途怎么进行]", 18, head, 0.0],
				["· 在阁楼里对准门边黄铜天气旋钮按 E，窗外会按", 16, body, 0.0],
				["  云海 → 萤火森林 → 雨巷 → 雪夜 轮换。", 16, body, 18.0],
				["· 对准门按 E 推开，跨过门槛便进入窗外的世界；", 16, body, 0.0],
				["  沿原路跨回门槛即可回阁楼。", 16, body, 18.0],
				["· 跟着左上角「此刻的小事」完成每个世界的一件小事，", 16, body, 0.0],
				["  带回纪念放到阁楼旅行架。", 16, body, 18.0],
				["· 每个世界都有一处小游戏；冰钓的渔获可在 B 行囊中", 16, body, 0.0],
				["  出售，换取鱼竿、鱼饵与图鉴、成就收集。", 16, body, 18.0],
				["· 四件纪念归架后，仍可泡茶、翻旅行小册、再看风景；", 16, body, 0.0],
				["  主线没有失败判定。", 16, body, 18.0],
				["", 8, dim, 0.0],
				["[镜界回廊]", 18, head, 0.0],
				["阁楼深处的立镜通往镜界回廊：走进后靠近中央棱镜按 E", 16, body, 0.0],
				["开始试炼。这是一个完全自愿的额外内容，不影响四件", 16, body, 0.0],
				["纪念、茶席与主线结局，也可以随时从镜门离开。", 16, body, 0.0],
			]
		2:
			return [
				["[行囊 · 鱼市 · 成就]", 18, head, 0.0],
				["按 B 打开行囊：第一页是总览，第二页是鱼类详情。", 16, body, 0.0],
				["", 8, dim, 0.0],
				["[总览页]", 18, head, 0.0],
				["金币 · 九鱼图鉴一览 · 成就一览 · 进度 · 镜牢纪录", 16, body, 0.0],
				["S　出售鱼篓里的渔获换金币", 16, body, 0.0],
				["R　购买并装备黄铜海竿 / 极光冰竿", 16, body, 0.0],
				["F　购买萤光饵 / 星屑饵　　T　换饵", 16, body, 0.0],
				["", 8, dim, 0.0],
				["[鱼类详情页]", 18, head, 0.0],
				["← / → 翻页进入；一页一条鱼，大字显示鱼名、", 16, body, 0.0],
				["1~5 星稀有度、已钓数量、最长纪录与单尾价值。", 16, body, 18.0],
				["左右键换鱼，↓ 回总览。", 16, body, 18.0],
				["", 8, dim, 0.0],
				["图鉴记录每种鱼的尺寸与故事，成就页记录冰钓、三处", 16, body, 0.0],
				["世界小游戏、镜牢深度与镜心三相。金币与图鉴保存在", 16, body, 0.0],
				["本机，不需要账号。", 16, body, 0.0],
			]
		3:
			return [
				["[世界小游戏]", 18, head, 0.0],
				["云海广场东侧是「风律回响」，跟着风铃与风向敲出节奏；", 16, body, 0.0],
				["森林林间空地是「萤火引路」，在三条林径间接住微光；", 16, body, 0.0],
				["雨巷巷口屋檐下是「檐雨合拍」，跟着滴水敲出节拍。", 16, body, 0.0],
				["雪夜静冰湾是完整的第一人称冰钓：", 16, body, 0.0],
				["蓄力抛竿 → 浮标沉下时提竿 → 按住与松开稳住张力收线。", 16, body, 18.0],
				["镜牢则是带镜印构筑的地牢式第一人称战斗。", 16, body, 0.0],
				["", 8, dim, 0.0],
				["每处小游戏都有独立规则、最佳成绩与成就。", 16, body, 0.0],
			]
		4:
			return _progress_lines()
		5:
			return [
				["[远方提示]", 18, head, 0.0],
				["✦　雪夜小屋", 17, key, 0.0],
				["三面冰镜与炉火。让冰镜朝向该去的方向，极光会给出回礼；", 16, body, 0.0],
				["提灯和雪橇也值得碰一碰。主路西侧的静冰湾可以冰钓。", 16, body, 18.0],
				["", 6, dim, 0.0],
				["☁　金色云海", 17, key, 0.0],
				["木板尽头有云舟。划到三盏浮标旁按 E 点灯；云灯塔、", 16, body, 0.0],
				["风铃、望远镜与云桥各有回应。栈桥东侧的绳桥通向风琴礁，", 16, body, 0.0],
				["三种来风各奏一次会有和鸣。", 16, body, 0.0],
				["", 6, dim, 0.0],
				["✦　萤火森林", 17, key, 0.0],
				["先找到玻璃罐，再收起三簇萤火，最后去林间的放飞处。", 16, body, 0.0],
				["水车、符文与木鼓会改变林子的光。", 16, body, 0.0],
				["", 6, dim, 0.0],
				["☂　雨巷水钟", 17, key, 0.0],
				["转动三只檐口水兽的铜阀，让雨水一起落进石槽，巷尾的", 16, body, 0.0],
				["水钟会重新走动。油纸伞、石猫的铃铛与顺水沟漂走的纸船", 16, body, 0.0],
				["都在等一阵回应；雨停后，窗台会多一只避雨的燕子。", 16, body, 0.0],
				["", 6, dim, 0.0],
				["◇　镜界回廊", 17, key, 0.0],
				["棱镜杖、镜刃与折光弩；三波镜影之后，镜心会以初相、", 16, body, 0.0],
				["折光相、逆光相三次变身。通关后东侧镜牢门升起。", 16, body, 0.0],
			]
		_:
			return [
				["[太空线]", 18, head, 0.0],
				["这扇门之外还有一条星际原型线（本作在阁楼线之外额外保留）。", 16, body, 0.0],
				["", 8, dim, 0.0],
				["M　实时星图　　J　航海日志　　Tab　切换目的地", 16, body, 0.0],
				["T　自动航行 / 着陆　　E　低速着陆 / 离船 / 登船", 16, body, 0.0],
				["Space　上升 / 起飞　　Ctrl 或 C　下降　　Shift　加力", 16, body, 0.0],
				["X　制动　　L　头灯　　F　按住扫描符文　　R　地形脱困", 16, body, 0.0],
				["", 8, dim, 0.0],
				["· 每颗星球的重力不同：低重力跳得更高。", 16, body, 0.0],
				["· 氧气在徒步时缓慢消耗，靠近飞船或篝火即可补充。", 16, body, 0.0],
				["· 篝火边按 E 烤棉花糖：火候 8 秒从生白走到焦黑，", 16, body, 0.0],
				["  金黄时取下补得最多。", 16, body, 18.0],
				["· 恒星会在约 17 分钟后爆发；轮回重置位置与资源，", 16, body, 0.0],
				["  但你写入日志的知识会永久保留。", 16, body, 18.0],
			]


## 「你的旅途进度」：按当前存档动态生成
func _progress_lines() -> Array:
	var head := Color(0.86, 0.92, 0.9)
	var body := Color(0.74, 0.83, 0.83, 0.95)
	var ok := Color(0.6, 0.92, 0.66)
	var todo := Color(0.92, 0.78, 0.55)
	var lines: Array = []
	lines.append(["[你的旅途进度]", 18, head, 0.0])
	lines.append(["下一件值得做的事", 17, head, 0.0])
	lines.append([game.next_worth_doing(), 16, todo, 0.0])
	lines.append(["", 8, body, 0.0])
	lines.append(["纪念 %d / 4　·　棱镜之心 %s" % [
		game.keepsakes.size(), "已带回" if game.has_prism_heart else "还在镜界"], 16, body, 0.0])
	if game.attic_worlds != null:
		lines.append(["冰钓 %d / 3　·　听雨灯 %d / 3" % [
			game.attic_worlds.caught_count(), game.attic_worlds.court_lit_count()], 16, body, 0.0])
	if game.progress != null:
		lines.append(["图鉴 %d / %d　·　成就 %d / %d　·　金币 %d" % [
			game.progress.dex_count(), game.progress.FISH_TABLE.size(),
			game.progress.achievement_count(), game.progress.ACHIEVEMENTS.size(),
			game.progress.coins], 16, body, 0.0])
		var dungeon: Dictionary = game.progress.dungeon
		if not dungeon.is_empty():
			lines.append(["镜牢　探索 %d · 通关 %d · 最好 %s %s" % [
				int(dungeon.get("runs", 0)), int(dungeon.get("clears", 0)),
				String(dungeon.get("best_rank", "")),
				game.progress.time_text(float(dungeon.get("best_seconds", 0.0)))], 16, body, 0.0])
	lines.append(["", 8, body, 0.0])
	lines.append(["四个远方", 17, head, 0.0])
	var world_titles := {
		"snow": "雪夜小屋", "cloud": "金色云海",
		"firefly": "萤火森林", "alley": "雨巷水钟",
	}
	for key in ["cloud", "firefly", "alley", "snow"]:
		var has: bool = game.keepsakes.has(key)
		lines.append(["%s　%s" % ["✦" if has else "·", String(world_titles[key])],
			16, ok if has else body, 0.0])
	return lines
