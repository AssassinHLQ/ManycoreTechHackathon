extends CanvasLayer

## 自动演示（开始页「自动演示 · 约 2 分半」）：照伴随版 HTML 的脚本化旅程。
##
## 159 秒，70 个机位、40 条字幕、40 个动作。全部数据从原作抽出，见文件底部。
## 演示只走四个远方与大世界的流程；镜界回廊、各处小游戏与镜牢不在演示内（照原作）。

var game
var font: Font
var painter: Painter
## 是否在演示中
var active := false
## 演示时间轴（秒）
var clock := 0.0
## 当前字幕条序号（-1 表示还没有）
var caption_index := -1
## 已触发的动作序号
var action_index := 0
## 当前机位缓动（在两条机位之间）
var cam_from := 0
var cam_to := 0
## 相机初始状态（退出演示时恢复）
var saved_camera_transform: Transform3D
var saved_camera_fov := 70.0
var has_saved_camera := false
## 截图/回归用：暂停时间轴推进（默认关）
var clock_paused := false




class Painter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_demo(self)


func setup(host) -> void:
	game = host
	layer = 14
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


## 开始演示
func start() -> void:
	active = true
	clock = 0.0
	caption_index = -1
	action_index = 0
	cam_from = 0
	cam_to = 1
	painter.visible = true
	painter.queue_redraw()


## 停止演示
func stop() -> void:
	active = false
	painter.visible = false


func progress() -> float:
	if DEMO_DURATION <= 0.0:
		return 1.0
	return clampf(clock / DEMO_DURATION, 0.0, 1.0)


## 当前该显示的字幕（空串表示不显示）
func current_caption() -> String:
	if caption_index < 0 or caption_index >= DEMO_CAPTIONS.size():
		return ""
	return String(DEMO_CAPTIONS[caption_index][1])


## 每个动作的「施放」：把演示里的动作名翻成对世界的调用
func fire_action(action: String) -> void:
	if game == null:
		return
	match action:
		"dialCloud", "dialForest", "dialRain", "dialSnow":
			# 转动天气旋钮（照原作的四个方向）
			var wanted := {"dialCloud": "cloud", "dialForest": "firefly",
				"dialRain": "alley", "dialSnow": "snow"}
			game.demo_set_weather(String(wanted.get(action, "cloud")))
		"openCloud", "openForest", "openRain", "openSnow":
			var wanted2 := {"openCloud": "cloud", "openForest": "firefly",
				"openRain": "alley", "openSnow": "snow"}
			game.demo_enter_world(String(wanted2.get(action, "cloud")))
		"close":
			game.demo_leave_to_attic()
		"winch":
			game.demo_use_prop("cloud_winch")
		"beacon":
			game.demo_use_prop("cloud_beacon")
		"chime":
			game.demo_use_prop("wind_organ")
		"guide":
			game.demo_use_prop("ranger_lamp")
		"hutLantern":
			game.demo_use_prop("lantern_snow")
		"water":
			game.demo_use_prop("waterwheel")
		"rune":
			game.demo_use_prop("rune")
		"drum":
			game.demo_use_prop("wood_drum")
		"mushroom":
			game.demo_use_prop("mushroom")
		"paper":
			game.demo_use_prop("paper_boat")
		"rainBoat":
			game.demo_use_prop("paper_boat")
		"rainSign":
			game.demo_use_prop("sign_alley")
		"rainUmbrella":
			game.demo_use_prop("umbrella")
		"rainCat":
			game.demo_use_prop("stone_cat")
		"rainSpout0":
			game.demo_turn_device("alley", 0)
		"rainSpout1":
			game.demo_turn_device("alley", 1)
		"rainSpout2":
			game.demo_turn_device("alley", 2)
		"snowMirror":
			game.demo_turn_device("snow", 0)
		"sled":
			game.demo_use_prop("sled")
		"lantern":
			game.demo_use_prop("lantern_snow")
		"greet":
			game.demo_greet_swallow()
		"hearth":
			game.demo_use_prop("hearth_snow")
		"swallow":
			game.demo_show_swallow()
		"stationDoor":
			pass
		_:
			pass


## 每帧：推进时间轴、开字幕、放动作、推相机
func tick(delta: float) -> void:
	if not active:
		return
	clock += delta
	if clock >= DEMO_DURATION:
		clock = DEMO_DURATION
	# 字幕
	var next_caption := caption_index
	for i in range(DEMO_CAPTIONS.size()):
		if float(DEMO_CAPTIONS[i][0]) <= clock:
			next_caption = i
	caption_index = next_caption
	# 动作
	while action_index < DEMO_ACTIONS.size() \
			and float(DEMO_ACTIONS[action_index][0]) <= clock:
		fire_action(String(DEMO_ACTIONS[action_index][1]))
		action_index += 1
	# 机位：找到包住当前时间的两条
	var slot := cam_from
	for i in range(DEMO_CAMERAS.size()):
		if float(DEMO_CAMERAS[i][0]) <= clock:
			slot = i
	cam_from = slot
	cam_to = mini(slot + 1, DEMO_CAMERAS.size() - 1)
	_apply_camera()
	painter.queue_redraw()
	if clock >= DEMO_DURATION:
		stop()
		if game != null:
			game.demo_finished()


## 把相机推到当前机位（两条之间做平滑插值）
func _apply_camera() -> void:
	if game == null or not has_saved_camera:
		return
	var cam: Camera3D = game.demo_camera()
	if cam == null:
		return
	var a: Array = DEMO_CAMERAS[cam_from]
	var b: Array = DEMO_CAMERAS[cam_to]
	var ta := float(a[0])
	var tb := float(b[0])
	var t := 0.0
	if tb > ta:
		t = clampf((clock - ta) / (tb - ta), 0.0, 1.0)
	# 缓入缓出，别让镜头顿住
	t = t * t * (3.0 - 2.0 * t)
	var eye: Vector3 = (a[1] as Vector3).lerp(b[1] as Vector3, t)
	var look: Vector3 = (a[2] as Vector3).lerp(b[2] as Vector3, t)
	var fov: float = lerpf(float(a[3]), float(b[3]), t)
	var world: Node3D = game.demo_world_container()
	if world == null:
		return
	# 四个远方的场地已按原作尺度建好并对齐到原作中心，
	# 所以原作机位可以直接用，不需要再缩放或环绕。
	cam.global_position = world.to_global(eye)
	cam.look_at(world.to_global(look), Vector3.UP)
	cam.fov = fov


func _process(delta: float) -> void:
	if not active:
		return
	if clock_paused:
		# 截图/回归用：时间轴停住，但画面继续重绘
		if painter != null and painter.visible:
			painter.queue_redraw()
		return
	if painter != null and painter.visible:
		tick(delta)


func draw_demo(control: Control) -> void:
	if font == null:
		return
	var size := control.size
	# 上下两条暗边，让字幕清楚
	control.draw_rect(Rect2(0, size.y - 148.0, size.x, 148.0), Color(0.02, 0.03, 0.05, 0.62))

	# 字幕
	var caption := current_caption()
	if caption != "":
		control.draw_string(font, Vector2(0, size.y - 74.0), caption,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(0.95, 0.96, 0.92))

	# 进度条
	var bar_x := size.x * 0.5 - 260.0
	var bar_y := size.y - 46.0
	var bar_w := 520.0
	control.draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, 4.0)),
		Color(0.28, 0.34, 0.36, 0.7))
	control.draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w * progress(), 4.0)),
		Color(0.94, 0.84, 0.5, 0.9))

	# 标题与退出提示
	control.draw_string(font, Vector2(0, 34.0), "自动演示 · 同一扇门的实时旅程",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(0.86, 0.9, 0.88, 0.85))
	control.draw_string(font, Vector2(0, size.y - 22.0), "退出演示  Esc",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(0.7, 0.76, 0.76, 0.75))
	# 时间
	control.draw_string(font, Vector2(size.x - 190.0, 34.0),
		"%02d:%02d / %02d:%02d" % [int(clock) / 60, int(clock) % 60,
			int(DEMO_DURATION) / 60, int(DEMO_DURATION) % 60],
		HORIZONTAL_ALIGNMENT_RIGHT, 160.0, 14, Color(0.72, 0.8, 0.8, 0.8))


# ---- 自动演示数据（从伴随版 HTML 抽出，勿手改）----
## 演示总时长
const DEMO_DURATION := 159

## 机位：[时间, Vector3(eye), Vector3(look), fov]
const DEMO_CAMERAS := [
	[0, Vector3(4.6, 2.2, 4.9), Vector3(0, 1.65, -2), 67],
	[5.5, Vector3(2.6, 2.05, 2.8), Vector3(0, 1.8, -3.2), 66],
	[8.5, Vector3(0.7, 2.05, -0.6), Vector3(0, 1.95, -3.94), 60],
	[10.2, Vector3(0.35, 1.99, -1.05), Vector3(0, 1.97, -3.94), 55],
	[13.4, Vector3(0.5, 1.95, -1), Vector3(0, 1.97, -3.94), 55],
	[15.8, Vector3(0.45, 1.8, -2.2), Vector3(0, 1.6, -7), 64],
	[17.8, Vector3(0.1, 1.72, -7.4), Vector3(0, 1.35, -17), 68],
	[19.5, Vector3(0.2, 1.7, -10.8), Vector3(0, 1.4, -24), 68],
	[23, Vector3(0, 1.75, -18.5), Vector3(0, 1.2, -28), 68],
	[25, Vector3(0.7, 2.1, -22.5), Vector3(0, 0.3, -37), 70],
	[27.5, Vector3(0, 2, -27.5), Vector3(0, 0.1, -37), 69],
	[30, Vector3(0, 1.7, -33.5), Vector3(4, 1.8, -33), 67],
	[33, Vector3(8, 1.7, -29.2), Vector3(14.8, 3.2, -31), 66],
	[36, Vector3(-8, 1.75, -26.8), Vector3(-14.8, 1.4, -29), 66],
	[38, Vector3(-10.5, 1.7, -29), Vector3(-15, 1.3, -29), 62],
	[41, Vector3(2, 1.7, -18), Vector3(-4, 1.5, -25), 68],
	[44, Vector3(1.6, 1.7, -2.3), Vector3(0, 1.9, -4), 62],
	[46, Vector3(0.8, 1.85, -0.6), Vector3(0, 1.95, -3.94), 56],
	[50.5, Vector3(0.45, 1.9, -0.9), Vector3(0, 1.97, -3.94), 55],
	[51.5, Vector3(1, 1.75, -1.9), Vector3(0, 1.45, -7), 62],
	[53.5, Vector3(0.1, 1.7, -6.6), Vector3(0, 1.35, -18), 68],
	[55.5, Vector3(0.2, 1.7, -11), Vector3(0, 1.4, -25), 68],
	[58.5, Vector3(4.8, 1.7, -23), Vector3(10.5, 1.7, -28), 67],
	[60.5, Vector3(6.5, 1.7, -27.2), Vector3(5.8, 1.4, -28.9), 62],
	[62.5, Vector3(-4.8, 1.7, -26.8), Vector3(-9.5, 1.1, -30.4), 67],
	[65, Vector3(-9, 1.9, -28), Vector3(-9.5, 1.4, -30.5), 63],
	[67.5, Vector3(0, 1.8, -34.5), Vector3(0, 2.6, -42.5), 69],
	[70, Vector3(4.2, 1.75, -38), Vector3(5.6, 1.1, -41.5), 64],
	[72.5, Vector3(0, 2.2, -34), Vector3(-2, 1.4, -26), 69],
	[75, Vector3(0.2, 1.7, -14), Vector3(0, 1.4, -5), 68],
	[77.5, Vector3(1.6, 1.7, -2.3), Vector3(0, 1.9, -4), 62],
	[80, Vector3(0.7, 1.88, -0.7), Vector3(0, 1.96, -3.94), 56],
	[83.5, Vector3(0.4, 1.95, -0.9), Vector3(0, 1.98, -3.94), 55],
	[84.5, Vector3(1, 1.75, -1.6), Vector3(0, 1.4, -6), 62],
	[86.5, Vector3(1.2, 1.7, -5.4), Vector3(2.9, 1.3, -6.35), 64],
	[88.5, Vector3(2.2, 1.7, -8.4), Vector3(-2.4, 2.2, -12), 66],
	[90.5, Vector3(1.2, 1.7, -10.2), Vector3(-3.7, 2.9, -12), 64],
	[92.5, Vector3(1.2, 1.72, -14), Vector3(4.2, 2.9, -21), 66],
	[94.8, Vector3(-2.6, 1.7, -18.2), Vector3(-8.2, 1.75, -20.35), 66],
	[97, Vector3(-4.9, 1.7, -19.4), Vector3(-8.2, 1.78, -20.35), 61],
	[99.8, Vector3(-4.9, 1.7, -19.4), Vector3(-8.2, 1.82, -20.35), 61],
	[101, Vector3(-3.6, 1.7, -18.4), Vector3(6, 1.4, -26), 68],
	[103.2, Vector3(2.6, 1.7, -24.8), Vector3(9.5, 1.3, -28.3), 66],
	[105.5, Vector3(7.2, 1.68, -27.2), Vector3(10.35, 1.1, -28.5), 62],
	[107, Vector3(8.9, 1.66, -26.9), Vector3(10.3, 1.1, -28.5), 61],
	[109.2, Vector3(8.9, 1.66, -26.9), Vector3(10.3, 1.1, -28.5), 61],
	[111, Vector3(1, 1.7, -27.8), Vector3(-4, 2.4, -30.2), 66],
	[113, Vector3(0.2, 1.72, -29.2), Vector3(-3.6, 2.6, -30.4), 66],
	[115, Vector3(1.2, 1.72, -32.4), Vector3(0, 4.2, -39.7), 67],
	[117, Vector3(2.4, 1.75, -34.6), Vector3(0, 3, -38.6), 67],
	[120, Vector3(-2.4, 1.75, -34.6), Vector3(0, 3.8, -39.8), 67],
	[123, Vector3(0, 2, -33.7), Vector3(0, 4.2, -39.7), 65],
	[125.5, Vector3(0.8, 1.8, -3.2), Vector3(0, 1.9, -4), 62],
	[127.5, Vector3(0.45, 1.9, -0.9), Vector3(0, 1.97, -3.94), 55],
	[131.5, Vector3(0.4, 1.93, -0.9), Vector3(0, 1.98, -3.94), 55],
	[133.5, Vector3(0.8, 1.75, -0.9), Vector3(0, 1.3, -7), 63],
	[135.5, Vector3(0.2, 1.7, -6.8), Vector3(0, 1.2, -18), 68],
	[137.8, Vector3(2.4, 1.7, -16.6), Vector3(5.7, 0.7, -20.8), 64],
	[140, Vector3(-2.2, 1.7, -19.4), Vector3(-5.2, 1.5, -21.8), 63],
	[142.8, Vector3(-4.6, 1.7, -22.4), Vector3(-9, 2, -28), 67],
	[145.2, Vector3(-6.4, 1.7, -24), Vector3(-9.4, 1.6, -29.4), 63],
	[146.6, Vector3(-1.8, 1.7, -23.2), Vector3(8, 1.5, -25.4), 66],
	[147.8, Vector3(9.4, 1.62, -23), Vector3(11.8, 1.02, -29.85), 64],
	[149.2, Vector3(9.1, 1.7, -28), Vector3(11.8, 1.05, -29.9), 62],
	[150, Vector3(9.1, 1.7, -28), Vector3(11.8, 1.05, -29.9), 62],
	[151.2, Vector3(9.6, 1.65, -23), Vector3(3, 1.4, -26.6), 64],
	[152.2, Vector3(3.4, 1.9, -26.2), Vector3(0, 0.2, -37), 68],
	[154, Vector3(4.5, 2.1, -36.2), Vector3(-2, 0.2, -38.2), 66],
	[155.8, Vector3(1.6, 1.75, -2.2), Vector3(0, 1.9, -4), 62],
	[159, Vector3(2.8, 2.2, 2.7), Vector3(0, 1.7, -2.8), 67],
]

## 字幕：[时间, 文案]
const DEMO_CAPTIONS := [
	[0, "每个远方，都从一间温暖的小屋开始"],
	[5.5, "门上的黄铜旋钮，能把窗外的世界折成另一个样子"],
	[10.6, "窗棂咬合，旧的雪与新的云在同一块玻璃里折射"],
	[15.5, "第一扇 · 金色云海"],
	[23, "浮岛之间，云桥要靠绞盘一节节放下"],
	[32.5, "点亮云灯塔，飞艇便循着光靠泊"],
	[35.5, "风铃替高处的风，说出它的名字"],
	[44.5, "回到阁楼，再把窗外的天气转一格"],
	[46.2, "这一次，玻璃里长出树影与萤火"],
	[51.5, "第二扇 · 萤火森林"],
	[56, "门边的一点萤火，记得回阁楼的路"],
	[58.5, "护林灯亮起，树屋的路从暗处显出来"],
	[67, "三枚古树符文，要一枚一枚唤醒"],
	[69.5, "鼓声沿着树根，传进森林更深处"],
	[73.5, "窗边的蘑菇醒了，森林便有了回应"],
	[79.5, "玻璃里换成一场夜雨，檐角开始滴水"],
	[84.5, "第三扇 · 雨巷水钟"],
	[87.5, "木牌说，拨正三只檐兽，水钟就会醒来"],
	[90.5, "三只檐口水兽，把雨水分向石槽"],
	[94.8, "巷子深处，一把油纸伞收着小小的晴天"],
	[98.2, "伞下没有雨，只有灯和一小片安静"],
	[105.5, "石猫蹲在巷子尽头，替人记着旧约"],
	[107.3, "铃铛一响，雨声也轻了一拍"],
	[111, "纸船顺着水槽，慢慢漂向巷尾"],
	[112, "第一道水落进石槽，檐兽开始应答"],
	[113.6, "一道、两道、三道——雨水终于对齐"],
	[117, "水钟醒来，钟声把整条雨巷擦亮"],
	[123, "停摆的时间，又开始走了"],
	[126.2, "雨巷的燕子跟回阁楼，把雨声留在门外"],
	[127.6, "把这一场雨，折回旧雪的窗外"],
	[132.8, "窗外落回旧雪，提灯还等在原来的地方"],
	[135.5, "第四扇 · 雪夜小屋"],
	[137.2, "雪橇停在门口，旧雪辙一直通到松林"],
	[140.2, "一盏提灯，把通往木屋的路照亮"],
	[143, "雪团停在门廊前，等你先迈出一步"],
	[145.2, "给雪团留一点空间，信任就会自己走近"],
	[147.8, "炉火在屋子另一侧，替夜留了一小团暖"],
	[149.2, "炉火边，旧雪也慢慢融成水"],
	[152.2, "冰溪在桥下慢慢流，远方安静得可以住人"],
	[159, "原来远方，也可以住进家里"],
]

## 动作：[时间, 动作名]
const DEMO_ACTIONS := [
	[10.6, "dialCloud"],
	[14.6, "openCloud"],
	[19.5, "paper"],
	[25, "winch"],
	[32.5, "beacon"],
	[35.5, "chime"],
	[44.5, "close"],
	[46.2, "dialForest"],
	[51.5, "openForest"],
	[56, "guide"],
	[58.5, "hutLantern"],
	[62, "water"],
	[67, "rune"],
	[67.8, "rune"],
	[68.6, "rune"],
	[69.5, "drum"],
	[73.5, "mushroom"],
	[77.8, "close"],
	[79.5, "dialRain"],
	[84.5, "openRain"],
	[86.8, "rainBoat"],
	[87.5, "rainSign"],
	[98.2, "rainUmbrella"],
	[107.3, "rainCat"],
	[112, "rainSpout2"],
	[113.6, "rainSpout0"],
	[114.2, "rainSpout0"],
	[114.8, "rainSpout0"],
	[115.4, "rainSpout1"],
	[116, "rainSpout1"],
	[125.7, "close"],
	[126.1, "swallow"],
	[127.6, "dialSnow"],
	[132.8, "openSnow"],
	[137.2, "sled"],
	[140.2, "lantern"],
	[145.2, "greet"],
	[145.6, "stationDoor"],
	[149.2, "hearth"],
	[156.7, "close"],
]
