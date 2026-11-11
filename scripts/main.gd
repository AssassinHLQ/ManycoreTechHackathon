extends Node3D

const PlanetScript = preload("res://scripts/planet.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ShipScript = preload("res://scripts/ship.gd")
const AnomalyScript = preload("res://scripts/anomaly.gd")
const QuantumScript = preload("res://scripts/quantum.gd")
## 一维星：纯点云的装饰星球。单独一个脚本，不进 planet.gd ——
## 它没有地形/碰撞/信号，塞进行星那套会带一堆死代码。
const OneDimStarScript = preload("res://scripts/one_dim_star.gd")
const HudScript = preload("res://scripts/hud.gd")
const AudioScript = preload("res://scripts/audio.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const RoastScript = preload("res://scripts/roast.gd")
const TouchScript = preload("res://scripts/touch_controls.gd")
const StationScript = preload("res://scripts/station.gd")
const DistantStationScript = preload("res://scripts/distant_station.gd")

const LOOP_DURATION := 1020.0
## 打印跨帧建场各阶段耗时（排查首屏卡顿时打开）
const BUILD_TIMING := false
var _stage_usec := 0
var save_path := "user://starward_knowledge.json"
## 行囊进度的存档路径；测试可在 add_child 之前覆盖，避免写进正式存档
var progress_path := "user://starward_progress.json"

var state := "menu"
var previous_state := "walk"
## 世界是否已构建完成。跨帧渐进式建场期间为 false，供测试与外部脚本等待。
var world_ready := false
## 世界构建完成时发出；`await_world_ready()` 依赖它。
signal world_ready_finished
var paused := false
var journal_open := false
var map_open := false
var map_zoom := 1.0
var map_pan := Vector2.ZERO
var map_selected := 0
var map_dragging := false
var map_drag_distance := 0.0
var elapsed := 0.0
var visual_time := 0.0
var loop_count := 1
var discovered: Dictionary = {}
var planets: Array = []
var anomalies: Array = []
var quantum: Node3D
var station: Node3D
## 玩家此刻身处哪座站的内部（归航站或某座远景站）。
## station 是归航站专用变量，远景站走这条，别混用。
var active_station: Node3D = null
var in_station := false
var in_attic := false
var attic: Node3D
var _sun_was_visible := true
var comet: Node3D
var comet_dust: Node3D
## 一维星：纯点云的装饰星球（远看美、靠近即散）。不进 planets / anomalies / 星图。
var one_dim_star: Node3D
var home: Node3D
var player: CharacterBody3D
var ship: Node3D
var hud: CanvasLayer
var touch_controls
var audio: Node
var campfire: Node3D
var roast: Node3D
var fire_light: OmniLight3D
var fire_coal_material: StandardMaterial3D
var menu_camera: Camera3D
var key_light: DirectionalLight3D
var settings: Node
var sun_mesh: MeshInstance3D
var sun_light: OmniLight3D
var sun_material: ShaderMaterial
var corona_shells: Array = []
var sun_detail: Node3D
var prominence_materials: Array = []
## ── 世界尺度 ───────────────────────────────────────────────────────
##
## 用户 2026-11-11：「场景做大每个星球距离增加 10 倍 … 星球加大」。
##
## 三个尺度分开定，是因为它们该不该等比放大并不一样：
##   · 轨道距离 ×10   —— 用户要求，星系变空旷，飞行距离感强
##   · 星球半径 ×3    —— **不能**跟着 ×10：最远轨道 9.2 万米处若有 4300 米半径
##                       的星球，观感会被吞掉、碰撞子步长也会爆
##   · 太阳半径 ×10   —— 太阳本来就要撑起整个星系的天光，等比放才不显得渺小
##
## ⚠ 改这里之前先看 camera.far：放大后最远天体到相机约 20 万米，
##   `far = 60000` 会直接把远轨道裁掉（见 player.gd / ship.gd 的 far 注释）。
const ORBIT_SCALE := 10.0
const PLANET_RADIUS_SCALE := 3.0
const SUN_SCALE := 10.0
## 黑洞整体位置的外移倍率。黑洞不属于行星系统，但要保持在系统外围，
## 所以位置跟轨道同比例外移（尺寸不动 —— 它的 7200 米引力范围是玩法标定值）。
const BH_POSITION_SCALE := 10.0

## ── Lux3D 生成的星球表面 ────────────────────────────────────────────
## 键 = 行星 id，值 = GLB 路径。不在表里的行星继续用程序化球面。
##
## ⚠ 目前**故意留空**。接入管线已经写好并验证过（planet.gd 里
##   `_build_lux3d_surface` / `_sample_lux_height` / `_fill_lux_gaps`，
##   连接口探针 `tests/probe_lux3d_planet.gd` 都有），但**现有的青岚星 GLB
##   不适合当可着陆表面**：
##
##     实测顶点半径 0.137 ~ 0.625（比值 4.56），中位数 0.437；
##     56% 的方向格只有不到 5 个顶点。
##
##   也就是说它不是「一张连续球面 + 轻微起伏」，而是**散开的树/岩石 +
##   一个很崎岖的基体**。「按方向取高度」取到的是树顶和岩尖：
##   高度表平均 1022 米（< 行星半径 1200）、最大偏离半径 49%。
##   接上去的实测后果：`walk_test` 里进门、门框、螺旋坡道三条直接翻红。
##
##   要真正接上，得先有一版**闭合、平滑、连续**的星球 GLB
##   （地表起伏控制在半径的 ±3% 以内、不要有散落的独立植被）。
##   到时候只要在这里加一行：
##     "qinglan": "res://assets/models/qinglan-planet/model.glb",
const LUX3D_PLANET_MODELS := {
	"qinglan": "res://assets/models/qinglan-planet-v2/model.glb",
}

var sun_radius := 260.0 * SUN_SCALE
## 太阳细节层（米面）的生效范围。太阳放大了 10 倍，这一层也要跟着推远，
## 否则飞到原来那圈距离上细节就整片消失。
const SUN_DETAIL_RANGE := 2400.0 * SUN_SCALE
const SUN_DETAIL_FADE := 700.0 * SUN_SCALE

# ── 卡冈图雅：远处那个黑洞 ──────────────────────────────────────────
# 外部模型（res://assets/models/black-hole/model.glb）。
# 授权："Black Hole" by Nestaeric, CC BY 4.0 —— 署名见主菜单页脚与 handbook。
# 它**不是**十颗天体之一：不进星图、不进自动航行目标表，只是可以飞过去看的远景，
# 所以「十颗天体各有地标」那套断言不受影响。
const GARGANTUA_MODEL := "res://assets/models/black-hole/model.glb"
## 放在行星轨道（26400~92000）之外再抬高一点：从母星抬头就能看到它挂在天边。
## ⚠ 2026-11-11 轨道 ×10 之后这里也必须同比例外移（BH_POSITION_SCALE），
##   否则黑洞会落进内圈行星轨道里，变成一颗「路障」而不是远景。
const GARGANTUA_POSITION := Vector3(
	-11800.0 * BH_POSITION_SCALE,
	5200.0 * BH_POSITION_SCALE,
	9600.0 * BH_POSITION_SCALE)
const GARGANTUA_SCALE := 4.0
## 自转角速度（弧度/秒）。原来 0.012，转一圈要 8.7 分钟，近距离看盘面纹理会一帧帧
## 挪动、像在抖；压到 0.004 后约 26 分钟一圈 —— 慢到只能看出「在转」，看不出「在卡」。
const GARGANTUA_SPIN := 0.004
## 吸积盘的着色器：按半径逐像素求值，不采样贴图（原因见 _build_gargantua 的注释）。
const GARGANTUA_DISK_SHADER := "res://shaders/black_hole_disk.gdshader"
## 外圈浮尘 / 碎屑壳的着色器：同一套思路，但更暗更薄。
const GARGANTUA_HAZE_SHADER := "res://shaders/black_hole_haze.gdshader"
## 外圈浮尘壳的内缘 / 外缘半径（模型局部单位，实测）。
## 内缘设在最外那层吸积盘丝带（light3，外缘 1211）之外：blackoutside 这一层
## 原本是从盘心铺到外圈的一整片浮尘，若从 0 就画会把吸积盘整个盖住。
const GARGANTUA_HAZE_INNER := 1211.0
const GARGANTUA_HAZE_OUTER := 1645.0
## 颜色映射的半径上限：三个吸积盘壳共用同一个「半径 → 颜色」映射，
## 数值取最外那层 light3 的外缘半径（实测 1210.6）。
const GARGANTUA_DISK_RAMP_MAX := 1211.0
## 丝带噪声沿半径的频率。原贴图是 512×512 的横条，落到盘面上每条约合
## 半径 100+ 单位一条；这里调到约 90 单位一条，接近原贴图但更连续。
const GARGANTUA_DISK_BAND_FREQ := 0.011
## 三层吸积盘壳的内缘 / 外缘半径（模型局部单位，实测）。
## 顺序与 glb 里的 surface 顺序一致：light1 → light2 → light3。
## 内缘统一设在 180：视界那个球（black hole center）外缘实测约 176，
## 丝带从它外面开始，中心才有那个纯黑的洞，而不是一团过曝的白。
const GARGANTUA_SHELL_INNER := [180.0, 180.0, 180.0]
const GARGANTUA_SHELL_OUTER := [646.0, 558.0, 1211.0]
var gargantua: Node3D
## 带自发光的材质。吸积盘壳用的是 ShaderMaterial，视界壳仍是 StandardMaterial3D，
## 所以这里存基类 Material。
var gargantua_glow_materials: Array[Material] = []
## 带自发光的子网格 —— 只转它们，不转整个 gargantua 节点。
var gargantua_glow_nodes: Array[MeshInstance3D] = []
var solar_intensity := 0.0
var death_timer := 0.0
var death_duration := 3.8
var death_reason := ""
var fire_flames: Array = []
var fire_flame_bases: Array = []
var fire_flame_offsets: Array = []
var scan_target: Node3D
var scan_progress := 0.0
var target_index := 0
var supernova_active := false
var supernova_timer := 0.0
var end_text := ""

# ── 开发者模式 ──────────────────────────────────────────────────────
# F3 连按 5 次开启。它只活在这一次运行里：不写存档、不进设置项，
# 发行包给别人玩时不知道这串节奏就开不出来。开启后 F3 开关数据面板，
# 其余特殊按键见 dev_handle_key()。
const DEV_TAP_COUNT := 5
## 相邻两次 F3 的最大间隔（毫秒）；超过就当作重新开始数。
const DEV_TAP_GAP_MS := 1200
var dev_mode := false
var dev_overlay_visible := true
var _dev_taps := 0
var _dev_tap_last_ms := 0


func _ready() -> void:
	_migrate_legacy_user_data()
	_build_input_map()
	_build_world_progressive()


## 跨帧渐进式建场：每个阶段让出一帧渲染，避免网页版单线程 wasm 在一帧内卡死十几秒。
## 阶段顺序与原同步版本完全一致，依赖关系不变；服务节点（设置/音频/HUD/触屏）在最后创建。
func _build_world_progressive() -> void:
	await _yield_frame()
	_stage_begin()
	_build_environment()
	_stage_end("environment")
	await _yield_frame()
	await _build_planets()
	_stage_end("planets")
	await _yield_frame()
	_stage_begin()
	_build_campfire()
	_build_explorers()
	_stage_end("campfire+explorers")
	await _yield_frame()
	_stage_begin()
	_build_menu_camera()
	_build_comet()
	_stage_end("menu_camera+comet")
	await _yield_frame()
	_stage_begin()
	_build_gargantua()
	_stage_end("gargantua")
	await _yield_frame()
	_stage_begin()
	_build_station()
	_stage_end("station")
	await _yield_frame()
	_stage_begin()
	_build_distant_stations()
	_stage_end("distant_stations")
	await _yield_frame()
	_stage_begin()
	_build_attic()
	_stage_end("attic")
	await _yield_frame()
	_stage_begin()
	settings = SettingsScript.new()
	settings.game = self
	add_child(settings)
	settings.load_and_apply()
	_stage_end("settings")
	await _yield_frame()
	_stage_begin()
	audio = AudioScript.new()
	audio.game = self
	add_child(audio)
	_add_campfire_audio()
	_stage_end("audio")
	await _yield_frame()
	_stage_begin()
	hud = HudScript.new()
	hud.game = self
	add_child(hud)
	minigames = MinigameScript.new()
	minigames.name = "Minigames"
	add_child(minigames)
	minigames.setup(self)
	progress = ProgressScript.new()
	progress.name = "Progress"
	progress.save_path = progress_path
	add_child(progress)
	progress.load_progress()
	_restore_progress()
	# 口袋世界在 _build_attic() 里就建好了，那时 progress 还没创建；
	# 这里补上引用，风琴礁等道具才能读到存档状态。
	if attic_worlds != null:
		attic_worlds.progress_ref = progress
	bag = BagPanelScript.new()
	bag.name = "Bag"
	add_child(bag)
	bag.setup(self)
	fishing_hud = FishingHudScript.new()
	fishing_hud.name = "FishingHud"
	add_child(fishing_hud)
	fishing_hud.setup(self)
	handbook = HandbookScript.new()
	handbook.name = "Handbook"
	add_child(handbook)
	handbook.setup(self)
	travel_journal = TravelJournalScript.new()
	travel_journal.name = "TravelJournal"
	add_child(travel_journal)
	travel_journal.setup(self)
	guide_card = GuideScript.new()
	guide_card.name = "GuideCard"
	add_child(guide_card)
	guide_card.setup(self)
	run_summary = RunSummaryScript.new()
	run_summary.name = "RunSummary"
	add_child(run_summary)
	run_summary.setup(self)
	demo = DemoScript.new()
	demo.name = "Demo"
	add_child(demo)
	demo.setup(self)
	_stage_end("hud")
	await _yield_frame()
	_stage_begin()
	touch_controls = TouchScript.new()
	touch_controls.game = self
	add_child(touch_controls)
	_load_knowledge()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		DisplayServer.window_set_ime_active(false)
	_stage_end("touch+knowledge")
	world_ready = true
	world_ready_finished.emit()


## 让出一帧，供渐进式建场分片。
func _yield_frame() -> void:
	await get_tree().process_frame


func _stage_begin() -> void:
	_stage_usec = Time.get_ticks_usec()


func _stage_end(label: String) -> void:
	var now := Time.get_ticks_usec()
	if BUILD_TIMING:
		print("BUILD STAGE  %-24s %8.1f ms" % [label, (now - _stage_usec) / 1000.0])
	_stage_usec = now


## 等待世界构建完成；已就绪时立即返回，可安全重复调用。
func await_world_ready() -> void:
	if world_ready:
		return
	await world_ready_finished


func _migrate_legacy_user_data() -> void:
	var base := OS.get_user_data_dir().get_base_dir()
	var current := OS.get_user_data_dir().get_file()
	if base == "" or current == "":
		return
	for directory in DirAccess.get_directories_at(base):
		if directory == current:
			continue
		for file in ["starward_knowledge.json", "starward_settings.json"]:
			var target := OS.get_user_data_dir().path_join(file)
			if FileAccess.file_exists(target):
				continue
			var source := base.path_join(directory).path_join(file)
			if FileAccess.file_exists(source):
				DirAccess.copy_absolute(source, target)


func _build_input_map() -> void:
	_add_key("move_forward", KEY_W)
	# ⚠ S 原来是 move_back（倒车），现在改成**制动**。
	#   物理上飞船的发动机在船尾，只能往机头方向推 —— 没有倒车挡。
	#   用户：「按照物理，飞船不能朝后飞」「制动改成 S」。
	#   move_back 仍然保留绑定（避免其它脚本引用时报错），但飞船逻辑不再读它。
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("jump", KEY_SPACE)
	_add_key("jetpack", KEY_SHIFT)
	_add_key("thrust_down", KEY_CTRL)
	_add_key("thrust_down", KEY_C)
	_add_key("interact", KEY_E)
	_add_key("scan", KEY_F)
	_add_key("map", KEY_M)
	_add_key("journal", KEY_J)
	_add_key("target", KEY_TAB)
	_add_key("autopilot", KEY_T)
	# 制动：S（主键，和 move_back 是同一个物理键）+ X（备用，老玩家习惯）
	_add_key("brake", KEY_S)
	_add_key("brake", KEY_X)
	_add_key("lamp", KEY_L)
	_add_key("unstuck", KEY_R)
	_add_key("bag", KEY_B)
	_add_key("handbook", KEY_H)


func _add_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


# ── 开发者模式：开关、特殊按键 ──────────────────────────────────────
## 所有开发者按键的总入口。返回 true 表示这次输入已被吃掉，不再往下传。
## 开启前只认 F3（要把连按数出来）；开启后才放行 F4~F7。
func dev_handle_key(code: String) -> bool:
	if not world_ready:
		return false
	if code == "F3":
		if dev_mode:
			dev_overlay_visible = not dev_overlay_visible
			hud.show_toast("开发者面板已" + ("显示" if dev_overlay_visible else "隐藏"), 1.6)
		else:
			_dev_count_tap()
		return true
	if not dev_mode:
		return false
	match code:
		"F4":
			dev_jump_to_ending()
		"F5":
			dev_unlock_records()
		"F6":
			dev_refill()
		"F7":
			dev_trigger_supernova()
		_:
			return false
	return true


## 数 F3 连按。间隔超过 DEV_TAP_GAP_MS 就从头数，数满 5 次开门。
func _dev_count_tap() -> void:
	var now := Time.get_ticks_msec()
	if _dev_taps > 0 and now - _dev_tap_last_ms > DEV_TAP_GAP_MS:
		_dev_taps = 0
	_dev_taps += 1
	_dev_tap_last_ms = now
	if _dev_taps < DEV_TAP_COUNT:
		return
	_dev_taps = 0
	dev_mode = true
	dev_overlay_visible = true
	if audio != null:
		audio.play_chime()
	hud.show_toast("开发者模式已开启 · F3 面板 · F4 结局 · F5 条目 · F6 资源 · F7 超新星", 6.0)


## F4：直接拿到宇宙线的结局。走的是和扫描到玄渊之核同一条路 ——
## 记下条目、写存档、把状态切到 end（结局面板自己会读 end_text）。
## 玄渊可能早就被发现过（discover() 会提前返回），所以这里不调 discover()，
## 而是把结局该做的事自己做一遍，保证按下去一定有结局。
func dev_jump_to_ending() -> bool:
	if not dev_mode or not world_ready:
		return false
	if state in ["end", "dying"]:
		return false
	if minigame_open:
		hud.show_toast("小游戏进行中，先按 Esc 退出", 2.4)
		return false
	_dev_clear_overlays()
	var anomaly := _anomaly_by_id("xuanyuan")
	if anomaly != null:
		end_text = anomaly.body
	discovered["xuanyuan"] = true
	_save_knowledge()
	if audio != null:
		audio.play_chime()
	previous_state = state
	state = "end"
	paused = false
	map_open = false
	journal_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


## F5：把所有信号条目一次性写进日志，星图 / 日志 / 手册立刻能看全。
func dev_unlock_records() -> void:
	var added := 0
	for anomaly in anomalies:
		if not discovered.has(anomaly.anomaly_id):
			discovered[anomaly.anomaly_id] = true
			added += 1
	_save_knowledge()
	if added == 0:
		hud.show_toast("所有条目都已在记录里", 2.4)
	else:
		hud.show_toast("已解锁 %d 条记录 · 共 %d / %d" % [added, discovered.size(), anomalies.size()], 3.2)


## F6：补满氧气、喷气燃料、飞船推进剂与船体。
func dev_refill() -> void:
	if player != null:
		player.oxygen = 100.0
		player.fuel = 100.0
	if ship != null:
		ship.fuel = 100.0
		ship.hull = 100.0
		ship.fuel_empty_time = 0.0
	hud.show_toast("氧气 / 燃料 / 船体已补满", 2.4)


## F7：跳过本轮倒计时，直接看超新星与轮回。
func dev_trigger_supernova() -> void:
	if state not in ["walk", "ship"]:
		hud.show_toast("现在不能跳轮回（当前状态：" + state + "）", 2.4)
		return
	_dev_clear_overlays()
	elapsed = LOOP_DURATION
	_trigger_supernova()


## 把可能接管画面的东西收干净：正在跑的演示 / 超新星 / 望远镜 / 各种浮层。
## 收不干净的后果是「按了 F4 却没有结局」——比如超新星会在一秒后把状态改回去。
func _dev_clear_overlays() -> void:
	supernova_active = false
	supernova_timer = 0.0
	if sun_mesh != null:
		sun_mesh.scale = Vector3.ONE
	if sun_material != null:
		sun_material.set_shader_parameter("heat", 0.0)
	if sun_light != null:
		sun_light.light_energy = 3.0
	if demo_active:
		stop_demo()
	if scope_active:
		_exit_scope()
	if bag_open and bag != null:
		bag.close()
		bag_open = false
	if handbook_open and handbook != null:
		handbook.close()
		handbook_open = false
	if journal_book_open and travel_journal != null:
		travel_journal.close()
		journal_book_open = false


## 每个世界的天空预设。
## 键 -> {zenith, horizon, stars, nebula, haze, haze_color}
## 可选 -> {nebula_a, nebula_b, twinkle, meteor, flow}
##   twinkle 闪烁幅度（有大气、离得近的世界星更闪；太空里几乎不闪）
##   meteor  流星频率（白天的天空设 0）
##   flow    流转速度（星层差速自转 + 星云漂移的总开关）
## 可选 -> {n_axis, n_band, n_scale, n_warp, n_thr, n_seed, n_struct}
##   大尺度结构（星云 / 高空云）的**形状**。上一版六个世界共用同一套 fbm，
##   只换颜色与密度，云的轮廓是同一片；现在每个世界各给一套噪声基：
##     n_axis   带子朝向           n_band   带子集中度（1 = 铺满全天）
##     n_scale  噪声尺度（小=大团）  n_warp   域扭曲（小=软团，大=长丝）
##     n_thr    覆盖阈值（小=更多云） n_seed   噪声偏移（换一整套图案）
##     n_struct 银河专属结构（尘埃带/亮核/青红斑）权重，云海这类白天世界为 0
##   缺省值就是太空那一套，漏写字段时回落到的仍是原来的星空。
## 说明：太空是「满天星」；四个远方各有自己的天色 —— 云海是暖金色的黎明，
## 雨巷是灰雨、看不到星，萤火森林暗到几乎只剩萤火，雪夜是冷蓝的夜。
const SKY_PRESETS := {
	"space": {
		"zenith": Vector3(0.0045, 0.0075, 0.02), "horizon": Vector3(0.011, 0.017, 0.038), "grad": 1.0,
		"stars": 1.0, "nebula": 1.0, "haze": 0.0, "haze_color": Vector3(0.1, 0.12, 0.2),
		"twinkle": 0.14, "meteor": 1.0, "flow": 1.0,
		# 银河：窄带、强扭曲、带尘埃带与亮核 —— 这是「母本」，其余世界都从它偏离
		"n_axis": Vector3(0.22, 0.82, -0.46), "n_band": 4.0, "n_scale": 4.2,
		"n_warp": 1.15, "n_thr": 0.32, "n_seed": Vector3(1.7, 4.2, 8.3), "n_struct": 1.0,
	},
	"attic": {
		"zenith": Vector3(0.008, 0.012, 0.028), "horizon": Vector3(0.02, 0.028, 0.05), "grad": 1.8,
		"stars": 0.45, "nebula": 0.45, "haze": 0.0, "haze_color": Vector3(0.1, 0.12, 0.2),
		"twinkle": 0.22, "meteor": 0.6, "flow": 0.85,
		# 阁楼窗外是城市的夜：云是低空的薄云层，块头大、几乎没有丝缕
		"n_axis": Vector3(0.10, 0.94, -0.32), "n_band": 2.2, "n_scale": 3.4,
		"n_warp": 0.55, "n_thr": 0.40, "n_seed": Vector3(9.4, 1.1, 3.8), "n_struct": 0.25,
	},
	"snow": {
		"zenith": Vector3(0.008, 0.016, 0.042), "horizon": Vector3(0.05, 0.09, 0.16), "grad": 2.0,
		"stars": 0.5, "nebula": 0.55, "haze": 0.3, "haze_color": Vector3(0.16, 0.24, 0.36),
		"twinkle": 0.28, "meteor": 0.35, "flow": 0.7,
		# 雪夜：稀薄的卷云，被高空风拉成长丝，星从云缝里透出来
		"n_axis": Vector3(-0.30, 0.62, 0.72), "n_band": 2.6, "n_scale": 6.4,
		"n_warp": 1.85, "n_thr": 0.44, "n_seed": Vector3(2.6, 8.8, 4.1), "n_struct": 0.12,
	},
	"cloud": {
		# 上蓝下金的黎明：天顶留一点蓝，地平线是暖金，中间自然过渡。
		# 星调成 0、星云关掉 —— 白天的天空不该有星星，也不该有流星。
		"zenith": Vector3(0.10, 0.17, 0.36), "horizon": Vector3(0.78, 0.58, 0.34), "grad": 2.2,
		"stars": 0.0, "nebula": 0.78, "haze": 0.30, "haze_color": Vector3(0.86, 0.68, 0.45),
		# 亮色的「高空云」，而不是太空那种深蓝紫星云
		"nebula_a": Vector3(0.80, 0.78, 0.76), "nebula_b": Vector3(1.0, 0.97, 0.93),
		"twinkle": 0.0, "meteor": 0.0, "flow": 1.15,
		# 黎明要有太阳。位置由 apply_sky() 按主光方向推，这里只给亮度和大小。
		"sun": 0.85, "sun_size": 0.021, "sun_color": Vector3(1.0, 0.93, 0.76),
		# 云海的高空云必须铺满整个天，而不是像银河那样只挂一条带子 ——
		# 所以带宽压到 1（无带子）、扭曲很小（是团不是丝）、阈值低（云多而厚）。
		"n_axis": Vector3(0.05, 0.99, 0.10), "n_band": 1.0, "n_scale": 3.0,
		"n_warp": 0.35, "n_thr": 0.36, "n_seed": Vector3(5.7, 3.2, 9.4), "n_struct": 0.0,
		# 白天的云是实体云，必须「替换天空」而不是加色，否则和天一起过曝
		"n_blend": 1.0,
	},
	"firefly": {
		# 树冠会挡掉大部分天光：星要压到「几乎只剩萤火」的程度，
		# 否则满天的亮星会和萤火虫混在一起，分不清哪些是虫、哪些是星。
		"zenith": Vector3(0.005, 0.014, 0.011), "horizon": Vector3(0.03, 0.07, 0.05), "grad": 2.4,
		"stars": 0.085, "nebula": 0.2, "haze": 0.18, "haze_color": Vector3(0.07, 0.13, 0.09),
		"twinkle": 0.16, "meteor": 0.0, "flow": 0.6,
		# 萤火森林：只有头顶一小片天，云又少又碎，剩下全是树影与萤火
		"n_axis": Vector3(-0.52, 0.74, -0.42), "n_band": 5.5, "n_scale": 5.4,
		"n_warp": 1.45, "n_thr": 0.46, "n_seed": Vector3(7.7, 0.6, 6.2), "n_struct": 0.35,
	},
	"alley": {
		"zenith": Vector3(0.045, 0.052, 0.066), "horizon": Vector3(0.16, 0.18, 0.21), "grad": 2.0,
		"stars": 0.0, "nebula": 0.0, "haze": 0.6, "haze_color": Vector3(0.22, 0.25, 0.29),
		"twinkle": 0.0, "meteor": 0.0, "flow": 0.8,
		# 雨巷：星云强度是 0，形状本来就不出图；字段仍写全，免得读的人以为漏了
		"n_axis": Vector3(0.62, 0.44, -0.65), "n_band": 3.0, "n_scale": 5.0,
		"n_warp": 1.30, "n_thr": 0.40, "n_seed": Vector3(4.4, 7.7, 1.3), "n_struct": 0.0,
	},
	"mirror": {
		"zenith": Vector3(0.018, 0.026, 0.042), "horizon": Vector3(0.08, 0.11, 0.16), "grad": 1.6,
		"stars": 0.3, "nebula": 0.45, "haze": 0.1, "haze_color": Vector3(0.14, 0.18, 0.24),
		"twinkle": 0.30, "meteor": 0.6, "flow": 0.9,
		# 镜界：云被拉成极长的镜面条纹，尺度大、扭曲最强
		"n_axis": Vector3(0.86, 0.16, 0.48), "n_band": 3.2, "n_scale": 2.6,
		"n_warp": 2.35, "n_thr": 0.34, "n_seed": Vector3(1.9, 6.3, 8.1), "n_struct": 0.18,
	},
	"dungeon": {
		"zenith": Vector3(0.012, 0.018, 0.03), "horizon": Vector3(0.05, 0.07, 0.11), "grad": 1.8,
		"stars": 0.22, "nebula": 0.35, "haze": 0.05, "haze_color": Vector3(0.1, 0.13, 0.18),
		"twinkle": 0.18, "meteor": 0.0, "flow": 0.5,
		# 镜牢：窄而高的云缝，碎、暗、压抑
		"n_axis": Vector3(-0.16, 0.86, 0.48), "n_band": 5.0, "n_scale": 5.8,
		"n_warp": 1.50, "n_thr": 0.46, "n_seed": Vector3(3.1, 4.4, 7.7), "n_struct": 0.08,
	},
}


## 按世界设天空。key 用 SKY_PRESETS 的键。
func apply_sky(key: String) -> void:
	if sky_material == null:
		return
	var preset: Dictionary = SKY_PRESETS.get(key, SKY_PRESETS["space"])
	sky_material.set_shader_parameter("zenith_color", preset["zenith"])
	sky_material.set_shader_parameter("horizon_color", preset["horizon"])
	sky_material.set_shader_parameter("star_density", float(preset["stars"]))
	sky_material.set_shader_parameter("nebula_strength", float(preset["nebula"]))
	sky_material.set_shader_parameter("haze_strength", float(preset["haze"]))
	sky_material.set_shader_parameter("haze_color", preset["haze_color"])
	# 天色渐变的陡度：越大，暖色越贴着地平线，天顶越冷
	sky_material.set_shader_parameter("gradient_power", float(preset.get("grad", 1.0)))
	var neb_a = preset.get("nebula_a", Vector3(0.035, 0.095, 0.21))
	var neb_b = preset.get("nebula_b", Vector3(0.22, 0.15, 0.3))
	sky_material.set_shader_parameter("nebula_color_a", neb_a)
	sky_material.set_shader_parameter("nebula_color_b", neb_b)
	# 大尺度结构的**形状**：每个世界一套自己的噪声基（轴向/带宽/尺度/扭曲/阈值/种子）。
	# 只推颜色和密度的话，六个世界的云是同一片 —— 上一版就是这样。
	sky_material.set_shader_parameter("nebula_axis", preset.get("n_axis", Vector3(0.22, 0.82, -0.46)))
	sky_material.set_shader_parameter("nebula_band", float(preset.get("n_band", 4.0)))
	sky_material.set_shader_parameter("nebula_scale", float(preset.get("n_scale", 4.2)))
	sky_material.set_shader_parameter("nebula_warp", float(preset.get("n_warp", 1.15)))
	sky_material.set_shader_parameter("nebula_threshold", float(preset.get("n_thr", 0.32)))
	sky_material.set_shader_parameter("nebula_seed", preset.get("n_seed", Vector3(1.7, 4.2, 8.3)))
	sky_material.set_shader_parameter("nebula_structure", float(preset.get("n_struct", 1.0)))
	# 0 = 加色星云（夜里的发光气体），1 = 替换天空（白天被照亮的实体云）
	sky_material.set_shader_parameter("nebula_blend", float(preset.get("n_blend", 0.0)))
	# 动态：闪烁 / 流星频率 / 流转速度。缺字段就回落到一组温和的默认值。
	sky_material.set_shader_parameter("twinkle_amount", float(preset.get("twinkle", 0.24)))
	sky_material.set_shader_parameter("meteor_rate", float(preset.get("meteor", 0.6)))
	sky_material.set_shader_parameter("flow_speed", float(preset.get("flow", 1.0)))
	# 太阳：只有需要「天上有个太阳」的世界才开。方向按主光反推 ——
	# DirectionalLight3D 沿自身 -Z 照出去，所以太阳在 +Z 方向，
	# 这样太阳的位置和投影方向是一致的，不会各朝一边。
	sky_material.set_shader_parameter("sun_strength", float(preset.get("sun", 0.0)))
	sky_material.set_shader_parameter("sun_angular", float(preset.get("sun_size", 0.020)))
	sky_material.set_shader_parameter("sun_color", preset.get("sun_color", Vector3(1.0, 0.90, 0.70)))
	if key_light != null:
		var sun_dir: Vector3 = key_light.global_transform.basis.z.normalized()
		sky_material.set_shader_parameter("sun_direction", sun_dir)


## 星空精细度：0 低 / 1 中 / 2 高 / 3 极致。由 settings.gd 调用。
## 档位控制 fbm 倍频数、星层数、像素内超采样倍率（1×/1×/2×/3×），以及闪烁、
## 十字星芒、流星、流转这些特效的开关。着色器里的分支条件就是这个 uniform，
## 所以换档不产生 warp 分歧，也不会因为同屏像素走了不同分支而额外掉帧。
func apply_sky_detail(detail: int) -> void:
	if sky_material == null:
		return
	sky_material.set_shader_parameter("sky_detail", clampi(detail, 0, 3))


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/space_sky.gdshader")
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.28, 0.36, 0.54)
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38, -32, 0)
	key_light.light_color = Color(1.0, 0.86, 0.68)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 320.0
	add_child(key_light)

	sun_mesh = MeshInstance3D.new()
	var sun_sphere := SphereMesh.new()
	sun_sphere.radius = sun_radius
	sun_sphere.height = sun_radius * 2.0
	sun_sphere.radial_segments = 96
	sun_sphere.rings = 48
	sun_mesh.mesh = sun_sphere
	sun_material = ShaderMaterial.new()
	sun_material.shader = load("res://shaders/sun.gdshader")
	sun_mesh.material_override = sun_material
	add_child(sun_mesh)
	for i in range(3):
		var corona := MeshInstance3D.new()
		var shell := SphereMesh.new()
		var scale_factor := 1.055 + i * 0.045
		shell.radius = sun_radius * scale_factor
		shell.height = sun_radius * scale_factor * 2.0
		shell.radial_segments = 64
		shell.rings = 32
		corona.mesh = shell
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_FRONT
		material.albedo_color = Color(1.0, 0.34 + i * 0.1, 0.055, 0.09 - i * 0.018)
		corona.material_override = material
		corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(corona)
		corona_shells.append(corona)

	sun_light = OmniLight3D.new()
	sun_light.light_color = Color("ffd49a")
	sun_light.light_energy = 3.0
	sun_light.omni_range = 11000.0
	add_child(sun_light)
	_build_sun_detail()


func _build_sun_detail() -> void:
	sun_detail = Node3D.new()
	sun_detail.name = "SunDetailLOD"
	add_child(sun_detail)
	var shader: Shader = load("res://shaders/prominence.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77123
	for i in range(12):
		var normal := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.35, 0.75), rng.randf_range(-1.0, 1.0)).normalized()
		var tangent := normal.cross(Vector3.UP)
		if tangent.length_squared() < 0.01:
			tangent = normal.cross(Vector3.RIGHT)
		tangent = tangent.normalized()
		var half_span := rng.randf_range(0.08, 0.2)
		var height := rng.randf_range(26.0, 58.0)
		if i % 5 == 0:
			height += 22.0
		var width := rng.randf_range(7.0, 14.0)
		var prominence := MeshInstance3D.new()
		prominence.name = "Prominence_%02d" % i
		prominence.mesh = _prominence_mesh(normal, tangent, half_span, height, width)
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("fade", 0.0)
		material.set_shader_parameter("seed", float(i) * 1.73)
		prominence.material_override = material
		prominence.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sun_detail.add_child(prominence)
		prominence_materials.append(material)


func _prominence_mesh(normal: Vector3, tangent: Vector3, half_span: float, height: float, width: float) -> ArrayMesh:
	var plane_normal := normal.cross(tangent).normalized()
	var samples := 26
	var sides := 6
	var rings: Array = []
	for s in range(samples + 1):
		var t := float(s) / float(samples)
		var angle := lerpf(-half_span, half_span, t)
		var radial := (normal * cos(angle) + tangent * sin(angle)).normalized()
		var lift := height * cos((t * 2.0 - 1.0) * PI * 0.5)
		var center := radial * (sun_radius + lift)
		var path_tangent := (tangent * cos(angle) - normal * sin(angle)).normalized()
		var side_a := plane_normal
		var side_b := path_tangent.cross(plane_normal).normalized()
		var radius := width * 0.5 * pow(sin(t * PI), 0.65)
		var ring: Array = []
		for k in range(sides):
			var theta := TAU * float(k) / float(sides)
			ring.append(center + side_a * (cos(theta) * radius) + side_b * (sin(theta) * radius))
		rings.append(ring)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(samples):
		var lower: Array = rings[s]
		var upper: Array = rings[s + 1]
		var v0 := float(s) / float(samples)
		var v1 := float(s + 1) / float(samples)
		for k in range(sides):
			var k2 := (k + 1) % sides
			var u0 := float(k) / float(sides)
			var u1 := float(k2) / float(sides)
			_add_prominence_vertex(tool, lower[k], Vector2(u0, v0))
			_add_prominence_vertex(tool, upper[k], Vector2(u0, v1))
			_add_prominence_vertex(tool, upper[k2], Vector2(u1, v1))
			_add_prominence_vertex(tool, lower[k], Vector2(u0, v0))
			_add_prominence_vertex(tool, upper[k2], Vector2(u1, v1))
			_add_prominence_vertex(tool, lower[k2], Vector2(u1, v0))
	return tool.commit()


func _add_prominence_vertex(tool: SurfaceTool, point: Vector3, uv: Vector2) -> void:
	tool.set_uv(uv)
	tool.add_vertex(point)


## 天空着色器要知道「一个像素对应多大视角」，才能把星盘的角半径换算成像素。
## 换分辨率、换视口、换 fov 都要重推一次 —— 这取代了 v1 的 _update_starfield()。
## v1 那层 2600 个 billboard 方片的 3D 星场已经整层删掉：星现在全在这一个
## 着色器里，抗锯齿、连续色温、闪烁、十字星芒、流星都做在天上，
## 顺带少掉 2600 个实例与 16 张透明方片的绘制。
func _update_sky_pixel_angle() -> void:
	if sky_material == null:
		return
	var height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var fov := 72.0
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		fov = camera.fov
	# 一个像素的视角：视口半高对应的 tan 除以像素数，再乘 2 还原成整像素
	var angle := 2.0 * tan(deg_to_rad(fov) * 0.5) / height
	sky_material.set_shader_parameter("pixel_angle", angle)


func _build_planets() -> void:
	# ⚠ 轨道距离统一 ×ORBIT_SCALE、半径统一 ×PLANET_RADIUS_SCALE、
	#   垂直起伏 ×ORBIT_SCALE（否则星系拉大后起伏会缩成一条平线）。
	#   数字本身保持「设计值」不变，缩放只在下面几步乘一次，方便回退和再调。
	var definitions := [
		{
			"id": "qinglan", "name": "青岚星",
			"radius": 400.0 * PLANET_RADIUS_SCALE, "orbit": 2640.0 * ORBIT_SCALE, "gravity": 20.0,
			"phase": 0.18, "speed": 0.0025, "height": 0.0 * ORBIT_SCALE, "kind": "qinglan",
			"color": Color("2b4f52"), "accent": Color("9fe3d8"),
			"description": "标准重力 · 雾松林、石砌村舍与旧观测塔。"
		},
		{
			"id": "zheya", "name": "赭崖星",
			"radius": 300.0 * PLANET_RADIUS_SCALE, "orbit": 4560.0 * ORBIT_SCALE, "gravity": 32.0,
			"phase": 2.15, "speed": -0.004, "height": 180.0 * ORBIT_SCALE, "kind": "zheya",
			"color": Color("9c9384"), "accent": Color("d8c9a3"),
			"description": "1.6 G · 盐碱裂谷、间歇喷泉与断裂观测环。"
		},
		{
			"id": "cangbo", "name": "沧波星",
			"radius": 430.0 * PLANET_RADIUS_SCALE, "orbit": 6520.0 * ORBIT_SCALE, "gravity": 13.0,
			"phase": 3.75, "speed": 0.0022, "height": -160.0 * ORBIT_SCALE, "kind": "cangbo",
			"color": Color("8fb6c9"), "accent": Color("cfeef7"),
			"description": "0.65 G · 冰架、潮汐裂缝与浮冰研究站。"
		},
		{
			"id": "xuanjing", "name": "悬晶星",
			"radius": 280.0 * PLANET_RADIUS_SCALE, "orbit": 4160.0 * ORBIT_SCALE, "gravity": 7.0,
			"phase": 4.95, "speed": 0.0055, "height": 320.0 * ORBIT_SCALE, "kind": "xuanjing",
			"color": Color("565a60"), "accent": Color("e0a063"),
			"description": "0.35 G · 环站残骸、磁性矿石与低空碎片。"
		},
		{
			"id": "xuanyuan", "name": "玄渊星",
			"radius": 170.0 * PLANET_RADIUS_SCALE, "orbit": 8040.0 * ORBIT_SCALE, "gravity": 25.0,
			"phase": 5.72, "speed": -0.003, "height": 80.0 * ORBIT_SCALE, "kind": "xuanyuan",
			"color": Color("0b0d12"), "accent": Color("ff7a3c"),
			"description": "1.25 G · 黑金巨门与坍缩前的暗核。"
		},
		# ---- 次天体：五颗不承载主线棱镜、但可着陆观测的次级星球 ----
		{
			"id": "baiyao", "name": "白曜星",
			"radius": 240.0 * PLANET_RADIUS_SCALE, "orbit": 3200.0 * ORBIT_SCALE, "gravity": 9.0,
			"phase": 1.05, "speed": 0.0031, "height": 240.0 * ORBIT_SCALE, "kind": "baiyao",
			"color": Color("b9c6cc"), "accent": Color("eaf7ff"),
			"description": "0.45 G · 白垩冰原、冰棱塔林与霜蚀沟槽。"
		},
		{
			"id": "pansha", "name": "磐砂星",
			"radius": 330.0 * PLANET_RADIUS_SCALE, "orbit": 5400.0 * ORBIT_SCALE, "gravity": 22.0,
			"phase": 2.78, "speed": -0.0026, "height": -240.0 * ORBIT_SCALE, "kind": "pansha",
			"color": Color("a8794a"), "accent": Color("f0d9a8"),
			"description": "1.1 G · 风蚀沙海、石柱阵与流沙谷。"
		},
		{
			"id": "taiyuan", "name": "苔垣星",
			"radius": 290.0 * PLANET_RADIUS_SCALE, "orbit": 6200.0 * ORBIT_SCALE, "gravity": 16.0,
			"phase": 4.18, "speed": 0.0019, "height": 120.0 * ORBIT_SCALE, "kind": "taiyuan",
			"color": Color("3f5a45"), "accent": Color("9fd68a"),
			"description": "0.8 G · 苔原、石垣迷宫与湿雾低地。"
		},
		{
			"id": "liuwu", "name": "硫坞星",
			"radius": 310.0 * PLANET_RADIUS_SCALE, "orbit": 7100.0 * ORBIT_SCALE, "gravity": 27.0,
			"phase": 5.35, "speed": -0.0035, "height": -80.0 * ORBIT_SCALE, "kind": "liuwu",
			"color": Color("6d6a3a"), "accent": Color("d8e05a"),
			"description": "1.35 G · 硫磺喷气孔、废弃船坞与酸雾沟。"
		},
		{
			"id": "jianmo", "name": "缄默星",
			"radius": 150.0 * PLANET_RADIUS_SCALE, "orbit": 9200.0 * ORBIT_SCALE, "gravity": 6.0,
			"phase": 6.42, "speed": 0.0042, "height": 300.0 * ORBIT_SCALE, "kind": "jianmo",
			"color": Color("1b1620"), "accent": Color("9c7bd0"),
			"description": "0.3 G · 黑曜石暗面、静默门阵与无声风。"
		}
	]
	var anomaly_text := {
		"qinglan": ["风车塔的最后一课", "我们建造飞船，不是为了逃离这颗星球，而是为了带着问题回来。三块棱镜分别记录着赭崖、沧波与悬晶的坐标。当它们在同一张星图上重合，玄渊星就会开口。"],
		"zheya": ["棱镜坐标 · 赤", "赭崖观测站记录：恒星并非永恒。它的核心正在失去平衡。第一枚棱镜指向一个比恒星更古老的位置——不要相信你抵达那里的时间。"],
		"cangbo": ["棱镜坐标 · 蓝", "沧波潜艇记录：我们在海面下听见了音乐。第二枚棱镜没有指向某颗星球，而是指向所有观测者共同的盲区。保持好奇，但务必系好安全绳。"],
		"xuanjing": ["棱镜坐标 · 紫", "悬晶浮雕记录：空间在这里折叠。第三枚棱镜证实，玄渊星来自玄渊之核。三枚坐标已经完整；去那里，替我们看完这个故事。"],
		"xuanyuan": ["黑洞前奏", "你不是第一个仰望星空的人，也不会是最后一个。恒星燃尽，世界被遗忘，而你带来的每一个问题都成为新宇宙的第一束光。探索没有终点，只有下一位旅人。"],
		# 次天体的观测量：不参与棱镜主线，作为「顺路可读」的记录。
		"baiyao": ["冻在冰里的刻度", "白曜星的冰棱塔不是纪念碑，是量尺。塔顶每一道折光标记着一万年里恒星直径的变化——刻度还在往上走，只是没人再来了。"],
		"pansha": ["被风写坏的碑文", "磐砂星的石柱阵按风向排列。风换了十七次方向，柱阵就重排了十七次。最后一代记录者放弃刻字，只留下柱子的高度：那是他们记得的每一次风向。"],
		"taiyuan": ["苔垣里的人", "苔垣迷宫不是防御工事，是练习题。走通它需要记住三件事：墙会移动、灯会灭、出口从不标注。灯塔顶上留着一句：走不出来的人，就住在里面。"],
		"liuwu": ["下水的船没有名字", "硫坞星的船坞造过十一艘船，全部没有下水。龙骨还挂在龙门吊上，喷气孔在下面嘶嘶作响。最后一块钢板上的批注只有一行：等海回来。"],
		"jianmo": ["门后没有空气", "缄默星的三座门立了多久，没人算得清——这颗星没有声音，也无法留下回声。门框内侧刻着一句被磨平的话，只剩末尾可辨：……所以别关门。"]
	}
	for definition in definitions:
		var planet := PlanetScript.new()
		planet.game = self
		planet.planet_id = definition.id
		planet.display_name = definition.name
		planet.radius = definition.radius
		# 地形起伏按「设计半径」算，不按放大后的半径算 ——
		# 否则行星 ×3 之后地表也 ×3 崎岖，人类尺度的建筑接缝会出现米级落差、
		# 贴地行走被判成瞬移（walk_test 三条会翻红）。详见 planet.gd 的注释。
		planet.terrain_reference_radius = definition.radius / PLANET_RADIUS_SCALE
		# Lux3D 生成的星球表面（Aholo Lux3D text-to-3D）。
		# 设了就用模型当可见表面 + 从模型顶点烘出的高度表当地形查询；
		# 没设的星球继续走程序化球面。逐颗接入，接一颗验一颗。
		if LUX3D_PLANET_MODELS.has(definition.id):
			planet.lux_model_path = LUX3D_PLANET_MODELS[definition.id]
		planet.gravity_strength = definition.gravity
		planet.orbit_radius = definition.orbit
		planet.orbit_phase = definition.phase
		# ⚠ 角速度必须 ÷ORBIT_SCALE，让**线速度**保持设计值不变。
		#
		#   轨道半径 ×10 而角速度不变的话，线速度也 ×10：
		#   青岚 6.6 → 66 m/s、沧波 14 → 143 m/s、缄默 39 → 386 m/s。
		#   后果全是坏的：
		#     · 玩家站在行星上，global_position 每帧被带走 2.4 米 ——
		#       walk_test 里「每帧位移 < 1.5」三条直接翻红（不是测试错，是真瞬移）
		#     · 手动着陆要匹配 143 m/s 的地面速度，基本不可能
		#     · 撞击判定、自动驾驶的 Δv 预算全部要重标定
		#   除回来之后线速度与放大前完全一致，星系只是「变大」而不是「变快」。
		planet.orbit_speed = definition.speed / ORBIT_SCALE
		planet.orbit_height = definition.height
		planet.kind = definition.kind
		planet.base_color = definition.color
		planet.accent_color = definition.accent
		planet.description = definition.description
		add_child(planet)
		planets.append(planet)
		if planet.planet_id == "qinglan":
			home = planet

		var anomaly := AnomalyScript.new()
		anomaly.game = self
		anomaly.anomaly_id = planet.planet_id
		anomaly.title = anomaly_text[planet.planet_id][0]
		anomaly.body = anomaly_text[planet.planet_id][1]
		anomaly.accent_color = definition.accent
		planet.add_child(anomaly)
		var direction := Vector3.UP
		if planet.planet_id == "qinglan":
			direction = Vector3(-0.06, 1.0, -0.04).normalized()
		var tangent := direction.cross(Vector3.FORWARD).normalized()
		var anomaly_direction := (direction + tangent * (22.0 / planet.radius)).normalized()
		anomaly.position = planet.surface_position(anomaly_direction, -0.18)
		anomaly.basis = Basis(Quaternion(Vector3.UP, anomaly_direction))
		anomalies.append(anomaly)
		# 每颗星球建完让出一帧：地形与地标是最贵的一段，逐个分片才能避免长卡顿
		_stage_end("planet " + planet.planet_id)
		await _yield_frame()
		_stage_begin()
	_create_orbit_lines(definitions)
	_build_extra_anomalies()
	_build_quantum()
	_build_one_dim_star()


## 一维星：纯点云的装饰星球。**故意不进 planets / anomalies**：
## 它不能着陆、没有信号、不参与自动航行目标，只是远处好看。
## 放在最外圈轨道上，从青岚星看出去是一颗暗金色的小点云。
func _build_one_dim_star() -> void:
	# 用 preload().new() 而不是 set_script()：
	# set_script 出来的静态类型仍是 Node3D，赋 game 属性会报
	# 「Invalid assignment of property 'game' on a base object of type Node3D」。
	one_dim_star = OneDimStarScript.new()
	one_dim_star.game = self
	one_dim_star.name = "OneDimStar"
	add_child(one_dim_star)
	# 最外圈：比最远的缄默星（9200）还远，明显是「天边的装饰」
	one_dim_star.position = Vector3(cos(0.9) * 11400.0, 620.0, sin(0.9) * 11400.0)


func _build_quantum() -> void:
	var shard := _planet_by_id("xuanjing")
	if shard == null:
		return
	quantum = QuantumScript.new()
	quantum.game = self
	shard.add_child(quantum)
	anomalies.append(quantum)


func _build_extra_anomalies() -> void:
	var entries := [
		{
			"planet": "qinglan", "id": "qinglan_vault", "anchor": "CaveAnomalyAnchor",
			"title": "古井", "accent": Color("ffc46b"),
			"body": "井壁上有上一轮回刻下的星位图。最后一行写着：恒星不是第一次熄灭，只是我们第一次记得。"
		},
		{
			"planet": "zheya", "id": "zheya_cave", "anchor": "CaveAnomalyAnchor",
			"title": "盐壳下的耳语", "accent": Color("ffd08a"),
			"body": "卤水在盐壳下流动，有固定节拍，像一颗缓慢跳动的心。观测站的人曾把这节拍当成恒星的脉搏，直到它比恒星更早停止。"
		},
		{
			"planet": "xuanjing", "id": "xuanjing_cave", "anchor": "CaveAnomalyAnchor",
			"title": "残骸回声", "accent": Color("e0a063"),
			"body": "断裂的舱壁把声音折进自己的内部，再晚一些还给你。你说的每一句话，都会在这座洞窟里多活一次。"
		},
		{
			"planet": "qinglan", "id": "qinglan_archive", "anchor": "InteriorAnomalyAnchor",
			"title": "最后一课的讲台", "accent": Color("e6c27a"),
			"body": "讲台上摊着一页没有讲完的讲义：不要问宇宙为什么给我们一个轮回，问问我们愿意在每一次轮回里记住什么。"
		},
		{
			"planet": "cangbo", "id": "cangbo_lab", "anchor": "InteriorAnomalyAnchor",
			"title": "海底研究日志", "accent": Color("67d5ed"),
			"body": "实验舱的最后一页记录：我们在水面之下听见第二颗太阳。它没有发光，但所有仪器都指向同一个方向。"
		}
	]
	for entry in entries:
		var planet := _planet_by_id(entry.planet)
		if planet == null:
			continue
		var anchor := planet.find_child(entry.anchor, true, false)
		if anchor == null:
			continue
		var anomaly := AnomalyScript.new()
		anomaly.game = self
		anomaly.anomaly_id = entry.id
		anomaly.title = entry.title
		anomaly.body = entry.body
		anomaly.accent_color = entry.accent
		if entry.anchor == "InteriorAnomalyAnchor":
			anomaly.scale = Vector3.ONE * 0.68
			anomaly.scan_range = 14.0
		elif entry.anchor == "CaveAnomalyAnchor":
			anomaly.scan_range = 32.0
		anchor.add_child(anomaly)
		anomalies.append(anomaly)


func _planet_by_id(id: String) -> Node3D:
	for planet in planets:
		if planet.planet_id == id:
			return planet
	return null


func _create_orbit_lines(definitions: Array) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.28, 0.54, 0.64, 0.12)
	for definition in definitions:
		var immediate := ImmediateMesh.new()
		immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
		for i in range(128):
			var a := float(i) / 128.0 * TAU
			var b := float(i + 1) / 128.0 * TAU
			immediate.surface_add_vertex(Vector3(cos(a), 0, sin(a)) * definition.orbit + Vector3.UP * definition.height)
			immediate.surface_add_vertex(Vector3(cos(b), 0, sin(b)) * definition.orbit + Vector3.UP * definition.height)
		immediate.surface_end()
		var lines := MeshInstance3D.new()
		lines.mesh = immediate
		lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lines)


func _build_campfire() -> void:
	campfire = Node3D.new()
	home.add_child(campfire)
	var direction := Vector3(0.09, 1.0, 0.07).normalized()
	campfire.position = home.surface_position(direction, 0.15)
	campfire.basis = Basis(Quaternion(Vector3.UP, direction))
	var stone_light := _material(Color("6d7272"))
	var stone_dark := _material(Color("4b4f50"))
	var wood_material := _material(Color("51372b"))
	var char_material := _material(Color("241a15"))

	var ash := MeshInstance3D.new()
	var ash_mesh := CylinderMesh.new()
	ash_mesh.top_radius = 1.02
	ash_mesh.bottom_radius = 1.02
	ash_mesh.height = 0.06
	ash_mesh.radial_segments = 18
	ash.mesh = ash_mesh
	ash.material_override = _material(Color("33302d"))
	ash.position.y = 0.05
	campfire.add_child(ash)

	for i in range(10):
		var stone := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var wide := 0.88 + float((i * 7) % 5) * 0.055
		mesh.radius = 0.34 * wide
		mesh.height = 0.46 * (0.9 + float((i * 3) % 4) * 0.06)
		mesh.radial_segments = 7
		mesh.rings = 3
		stone.mesh = mesh
		stone.material_override = stone_light if i % 3 != 1 else stone_dark
		var angle := float(i) / 10.0 * TAU
		stone.position = Vector3(cos(angle), 0.1, sin(angle)) * (1.12 + float(i % 3) * 0.035)
		stone.rotation = Vector3(0.0, angle * 1.7, float((i * 5) % 7) * 0.04)
		stone.scale = Vector3(1.0, 0.82 + float(i % 3) * 0.1, 1.0)
		campfire.add_child(stone)

	fire_coal_material = _material(Color("3a2a22"), 1.5)
	for i in range(7):
		var coal := MeshInstance3D.new()
		var coal_mesh := SphereMesh.new()
		coal_mesh.radius = 0.10 + float(i % 3) * 0.02
		coal_mesh.height = 0.1
		coal_mesh.radial_segments = 6
		coal_mesh.rings = 3
		coal.mesh = coal_mesh
		coal.material_override = fire_coal_material
		var angle := float(i) / 7.0 * TAU + 0.3
		coal.position = Vector3(cos(angle) * (0.34 + float(i % 2) * 0.2), 0.1, sin(angle) * (0.34 + float(i % 2) * 0.2))
		coal.scale = Vector3(1.2, 0.55, 1.2)
		campfire.add_child(coal)

	for i in range(4):
		var log_mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.15
		cylinder.bottom_radius = 0.19
		cylinder.height = 1.9
		cylinder.radial_segments = 9
		log_mesh.mesh = cylinder
		log_mesh.material_override = wood_material
		log_mesh.position.y = 0.3 + float(i % 2) * 0.08
		log_mesh.rotation = Vector3(PI * 0.43, float(i) * PI / 4.0 + 0.2, 0.0)
		for side in [-1.0, 1.0]:
			var end := MeshInstance3D.new()
			var end_mesh := SphereMesh.new()
			end_mesh.radius = 0.185
			end_mesh.height = 0.24
			end_mesh.radial_segments = 7
			end_mesh.rings = 3
			end.mesh = end_mesh
			end.material_override = char_material
			end.position = Vector3(0, side * 0.92, 0)
			end.scale = Vector3(1.0, 0.6, 1.0)
			log_mesh.add_child(end)
		campfire.add_child(log_mesh)

	for i in range(4):
		var kindling := MeshInstance3D.new()
		var stick := CylinderMesh.new()
		stick.top_radius = 0.028
		stick.bottom_radius = 0.035
		stick.height = 0.9
		stick.radial_segments = 5
		kindling.mesh = stick
		kindling.material_override = char_material
		kindling.position = Vector3(cos(float(i) * 1.7) * 0.22, 0.16, sin(float(i) * 1.7) * 0.22)
		kindling.rotation = Vector3(PI * 0.5, float(i) * 1.5, 0.3)
		campfire.add_child(kindling)

	var flame_shader: Shader = load("res://shaders/flame.gdshader")
	var flame_offsets := [Vector3(0, 0, 0), Vector3(0.05, 0.05, 0.02), Vector3(-0.06, 0.02, -0.03)]
	for i in range(3):
		var flame := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.02, 1.72)
		flame.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = flame_shader
		material.set_shader_parameter("seed", float(i) * 4.3)
		material.set_shader_parameter("strength", 1.25 - i * 0.18)
		material.set_shader_parameter("opacity", 0.95 - i * 0.12)
		flame.material_override = material
		var base_scale := Vector3(0.86 + i * 0.14, 0.94 + i * 0.18, 1.0)
		flame.scale = base_scale
		flame.position = Vector3(0, 0.9, 0) + flame_offsets[i]
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		campfire.add_child(flame)
		fire_flames.append(flame)
		fire_flame_bases.append(base_scale)
		fire_flame_offsets.append(flame.position)

	var embers := CPUParticles3D.new()
	embers.amount = 26
	embers.lifetime = 1.6
	embers.preprocess = 1.6
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.4
	embers.position = Vector3(0, 0.55, 0)
	embers.direction = Vector3.UP
	embers.spread = 20.0
	embers.gravity = Vector3(0, 0.65, 0)
	embers.initial_velocity_min = 0.7
	embers.initial_velocity_max = 1.9
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.15
	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.025
	ember_mesh.height = 0.05
	ember_mesh.radial_segments = 5
	ember_mesh.rings = 3
	embers.mesh = ember_mesh
	var ember_material := StandardMaterial3D.new()
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.vertex_color_use_as_albedo = true
	ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_material.emission_enabled = true
	ember_material.emission = Color("ff8a35")
	ember_material.emission_energy_multiplier = 2.6
	embers.material_override = ember_material
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ember_ramp := Gradient.new()
	ember_ramp.set_color(0, Color(1.0, 0.78, 0.42, 1.0))
	ember_ramp.set_color(1, Color(1.0, 0.3, 0.08, 0.0))
	embers.color_ramp = ember_ramp
	campfire.add_child(embers)

	fire_light = OmniLight3D.new()
	fire_light.position.y = 1.35
	fire_light.light_color = Color("ff9e54")
	fire_light.light_energy = 2.2
	fire_light.omni_range = 14.0
	campfire.add_child(fire_light)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.25
	shape.height = 1.4
	collision.shape = shape
	collision.position.y = 0.7
	body.add_child(collision)
	campfire.add_child(body)
	for child in campfire.get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = 600.0


func _add_campfire_audio() -> void:
	var fire_sound := AudioStreamPlayer3D.new()
	fire_sound.stream = audio._crackle_stream()
	fire_sound.volume_db = -17.0
	fire_sound.max_distance = 22.0
	fire_sound.unit_size = 3.0
	fire_sound.position.y = 0.8
	campfire.add_child(fire_sound)
	fire_sound.play()


func _build_explorers() -> void:
	player = PlayerScript.new()
	player.game = self
	home.add_child(player)
	ship = ShipScript.new()
	ship.game = self
	home.add_child(ship)
	roast = RoastScript.new()
	roast.game = self
	player.camera.add_child(roast)
	_reset_positions()


func _build_menu_camera() -> void:
	menu_camera = Camera3D.new()
	menu_camera.fov = 52.0
	menu_camera.near = 0.2
	# ⚠ 2026-11-11 轨道 ×10 之后最远天体到相机约 20 万米：
	#   原来 60000 会把远轨道整片裁掉（星球凭空消失）。放宽到 40 万米。
	menu_camera.far = 400000.0
	add_child(menu_camera)
	menu_camera.current = true


## 卡冈图雅：建模 + 吸积盘着色 + 名牌。
## 模型从 Blender 导出时处在「局部网格 3429 单位、靠节点缩放收到 1200」的状态，
## 所以这里只按 GARGANTUA_SCALE 整体再放大，不动它内部的变换。
func _build_gargantua() -> void:
	var packed: PackedScene = load(GARGANTUA_MODEL)
	if packed == null:
		push_warning("卡冈图雅模型缺失：%s" % GARGANTUA_MODEL)
		return
	gargantua = Node3D.new()
	gargantua.name = "Gargantua"
	gargantua.position = GARGANTUA_POSITION
	gargantua.scale = Vector3.ONE * GARGANTUA_SCALE
	# 盘面侧过来一点：正对着看会缩成一条线
	gargantua.rotation = Vector3(deg_to_rad(-13.0), deg_to_rad(34.0), deg_to_rad(4.0))
	add_child(gargantua)
	gargantua.add_child(packed.instantiate())

	# ── 吸积盘着色 ──────────────────────────────────────────────
	#
	# 「曲线不光滑」的根因（实测出来的，别再改回去）：
	#   这件资产的 UV 是极坐标（v ≈ 半径），原贴图上的水平色带落到盘面上本该
	#   是同心圆；但壳的角向只有约 30 段、径向只有 2~11 段，三角面很大，
	#   于是每条色带边界被大三角面切成**直弦** —— 屏幕上就是一圈圈多边形阶梯。
	#   实测：换成纯色（完全不采样贴图）盘面立刻变成完美光滑的椭圆；
	#         恢复贴图立刻变回锯齿。**几何没问题，是贴图色带被网格量化了。**
	#
	# 所以这里不用贴图，改成让着色器**按半径逐像素求值**：同一条半径环上的所有
	# 顶点颜色完全相同，角向分多少段都看不出接缝，色带边界天然是同心圆。
	# 丝带层次用沿半径的一维噪声自己做，密度可以调到比原贴图细得多。
	#
	# 两套着色器：
	#   · disk —— 三层吸积盘丝带（light1/light2/light3），暖金渐变 + 细丝带；
	#   · haze —— 外圈浮尘与碎屑（blackoutside / ring），暗得多，只是一层薄雾。
	#
	# 各壳的半径范围与亮度按实测配（见下面的常量表）。注意 blackoutside 这一层
	# 原本是「从盘心一直到外圈」的一整片浮尘，若从半径 0 就画会把吸积盘整个盖住，
	# 所以它的内缘设在吸积盘外缘之外，只画盘外那一圈。
	#
	# 关于亮度分层：这几层同心盘面按视角轮流遮挡，若全刷成同一个亮度，
	# 面积会忽大忽小，看上去像「一层黄、一层黑」在跳。所以按层号拉开亮度，
	# 层与层之间留余量，遮挡时不会整片塌成黑。
	#
	# 自转交给 _update_gargantua，那里只转发光子节点，不动名牌、不动节点本身。
	var disk_shader: Shader = load(GARGANTUA_DISK_SHADER)
	var haze_shader: Shader = load(GARGANTUA_HAZE_SHADER)
	var glow_layers: Array[MeshInstance3D] = []
	var layer_index := 0
	for node in gargantua.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		for surface in range(mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface)
			if not (material is StandardMaterial3D):
				continue
			var standard := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
			var mat_name: String = standard.resource_name if standard.resource_name != "" else ""
			if standard.emission_enabled:
				# 吸积盘丝带 —— 换成按半径求值的 shader。
				var disk := ShaderMaterial.new()
				disk.shader = disk_shader
				disk.set_shader_parameter("inner_radius", GARGANTUA_SHELL_INNER[layer_index])
				disk.set_shader_parameter("outer_radius", GARGANTUA_SHELL_OUTER[layer_index])
				disk.set_shader_parameter("ramp_max", GARGANTUA_DISK_RAMP_MAX)
				# 层号每多一层，亮度稍降一点；下限 0.55，别让外环彻底黑掉。
				#
				# 亮度不能高：这三层壳在半径上大面积重叠（light1 到 646、light2 到 558、
				# light3 到 1211），加法混合下中心会被叠三次。base 0.45 × 三层 ≈ 1.2，
				# 刚好过曝一点点、还有层次；再高就糊成一团纯白。
				var layer := clampf(1.0 - layer_index * 0.12, 0.55, 1.0)
				disk.set_shader_parameter("energy", 0.45 * layer)
				disk.set_shader_parameter("band_frequency", GARGANTUA_DISK_BAND_FREQ)
				disk.set_shader_parameter("band_strength", 0.5)
				disk.set_shader_parameter("swirl_amount", 0.045)
				disk.set_shader_parameter("edge_fade", 0.16)
				disk.set_shader_parameter("core_fade", 0.012)
				mesh_instance.set_surface_override_material(surface, disk)
				gargantua_glow_materials.append(disk)
				layer_index += 1
			elif mat_name.begins_with("black hole blackoutside") or mat_name.begins_with("ring"):
				# 外圈浮尘 / 碎屑：同一张横向条纹贴图，也会变成虚线状暗环，
				# 所以同样换成按半径求值（更暗、更薄），且从吸积盘外缘才开始画。
				var haze := ShaderMaterial.new()
				haze.shader = haze_shader
				haze.set_shader_parameter("inner_radius", GARGANTUA_HAZE_INNER)
				haze.set_shader_parameter("outer_radius", GARGANTUA_HAZE_OUTER)
				haze.set_shader_parameter("energy", 0.34)
				haze.set_shader_parameter("band_frequency", 0.009)
				haze.set_shader_parameter("band_strength", 0.55)
				mesh_instance.set_surface_override_material(surface, haze)
			else:
				# 视界与扭曲壳：纯黑，本来就没有贴图。
				standard.vertex_color_use_as_albedo = false
				standard.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh_instance.set_surface_override_material(surface, standard)
		if layer_index > 0:
			glow_layers.append(mesh_instance)
	gargantua_glow_nodes = glow_layers


## 吸积盘自转。
##
## 以前是 gargantua.rotate_object_local(Vector3.UP, …)，转的是**整个节点**：
## 盘面跟着一起绕轴，侧过去时会缩成一条线，于是画面周期性「变黑又变亮」。
## 现在只转带自发光的那几个子网格，节点本身保持固定姿态，转速也压慢，
## 看上去就是盘面在匀速转，而不是整体在晃。
## 另外不再做亮度呼吸 —— 那点 ±6% 的脉动会和上面的遮挡问题叠在一起，越看越像闪。
func _update_gargantua(delta: float) -> void:
	if gargantua == null:
		return
	var step := delta * GARGANTUA_SPIN
	for node in gargantua_glow_nodes:
		if is_instance_valid(node):
			node.rotate_object_local(Vector3.UP, step)


func _build_comet() -> void:
	comet = Node3D.new()
	comet.name = "EmberComet"
	add_child(comet)
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color("ffffff")
	core_material.emission_enabled = true
	core_material.emission = Color("eaffff")
	core_material.emission_energy_multiplier = 6.0
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 16.0
	sphere.height = 32.0
	sphere.radial_segments = 20
	sphere.rings = 10
	core.mesh = sphere
	core.material_override = core_material
	comet.add_child(core)

	var coma := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(170.0, 170.0)
	var coma_material := StandardMaterial3D.new()
	coma_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	coma_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	coma_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	coma_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	coma_material.albedo_texture = _coma_texture()
	coma_material.albedo_color = Color(0.72, 0.9, 1.0, 0.55)
	coma.mesh = quad
	coma.material_override = coma_material
	coma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	comet.add_child(coma)

	_add_comet_tail(comet, 760.0, 22.0, Color(0.55, 0.82, 1.0, 0.4), 0.0, "IonTail")
	comet_dust = Node3D.new()
	comet_dust.name = "DustTail"
	comet.add_child(comet_dust)
	_add_comet_tail(comet_dust, 360.0, 30.0, Color(1.0, 0.76, 0.5, 0.2), 10.0, "DustTailMesh")

	var light := OmniLight3D.new()
	light.light_color = Color("bfe9ff")
	light.light_energy = 2.4
	light.omni_range = 420.0
	comet.add_child(light)
	_update_comet()


func _add_comet_tail(parent: Node3D, length: float, radius: float, color: Color, seed: float, tail_name := "Tail") -> void:
	var tail := MeshInstance3D.new()
	tail.name = tail_name
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = length
	cone.radial_segments = 12
	tail.mesh = cone
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/comet_tail.gdshader")
	material.set_shader_parameter("tail_color", color)
	material.set_shader_parameter("seed", seed)
	tail.material_override = material
	tail.rotation = Vector3(PI * 0.5 + 0.05 * sin(seed), 0.0, 0.07 * cos(seed * 1.7))
	tail.position = Vector3(0.06 * cos(seed), 0.06 * sin(seed * 2.0), length * 0.5)
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(tail)


func _coma_texture() -> ImageTexture:
	var texture_size := 64
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	for y in range(texture_size):
		for x in range(texture_size):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) / float(texture_size) * 2.0 - Vector2.ONE
			var radius := clampf(p.length(), 0.0, 1.0)
			var alpha := pow(1.0 - radius, 3.0)
			image.set_pixel(x, y, Color(1.0, 0.98, 0.94, alpha))
	return ImageTexture.create_from_image(image)


func _build_station() -> void:
	station = StationScript.new()
	station.name = "HomecomingStation"
	station.game = self
	station.position = Vector3(4300.0, 1180.0, -1500.0) * ORBIT_SCALE
	station.rotation.y = 0.42
	add_child(station)


## 两座远景空间站（外部模型，CC BY 4.0，作者 re1monsen）。
##
## 与归航站（程序化生成、可进入、有六廊内部）不同，这两座只是**远处可看、可飞近绕行**
## 的布景站：不进星图、不进自动航行目标表、不许进入内部，所以不影响归航站那 73 项自测。
##
## 摆放思路：放在行星轨道外侧、离出生点足够远，抬头或长焦能看到；
## 两者分处不同方位角，避免和归航站挤在一起。
## 模型源文件是按 1 单位 = 1 米导出的（见 tools/station_build.py），
## 包围盒分别约 900 米与 760 米，比归航站（外环 560 米直径）大一圈，远看才压得住。
const DISTANT_STATIONS := [
	{
		"slug": "space-station",
		"name": "DistantStationAlpha",
		"label": "远景站 · 环塔",
		"model": "res://assets/models/space-station/model.glb",
		"position": Vector3(-6200.0, 1650.0, -5400.0) * ORBIT_SCALE,
		"yaw": 62.0,
		"spin": 0.010,
		"dock_height": 0.42,
	},
	{
		"slug": "space-station-3",
		"name": "DistantStationBeta",
		"label": "远景站 · 双环",
		"model": "res://assets/models/space-station-3/model.glb",
		"position": Vector3(5400.0, 2050.0, 6800.0) * ORBIT_SCALE,
		"yaw": -37.0,
		"spin": 0.014,
		"dock_height": 0.40,
	},
]
var distant_stations: Array[Node3D] = []


func _build_distant_stations() -> void:
	for entry in DISTANT_STATIONS:
		var path: String = entry["model"]
		var packed: PackedScene = load(path)
		if packed == null:
			push_warning("远景空间站缺失：%s" % path)
			continue
		var holder: Node3D = DistantStationScript.new()
		holder.name = entry["name"]
		holder.display_name = entry["label"]
		holder.spin_rate = float(entry["spin"])
		holder.position = entry["position"]
		holder.rotation = Vector3(0.0, deg_to_rad(float(entry["yaw"])), 0.0)
		add_child(holder)

		var model: Node3D = packed.instantiate()
		holder.add_child(model)
		# 材质统一：关掉模型自带的 PBR 极端值，双面渲染避免薄壳穿透。
		for node in holder.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for surface in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_active_material(surface)
				if mat is StandardMaterial3D:
					var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					std.cull_mode = BaseMaterial3D.CULL_DISABLED
					std.metallic = clampf(std.metallic, 0.0, 0.85)
					std.roughness = clampf(std.roughness, 0.28, 1.0)
					mi.set_surface_override_material(surface, std)

		# 量包围盒 -> 告诉站脚本「圆盘半径 / 厚度 / 对接点在哪」。
		#
		# ⚠ 坑：MeshInstance3D.get_aabb() 是网格自身局部空间的盒子，
		#   不含节点链上的缩放。外部模型常带 100 倍以上的节点缩放，
		#   直接 merge 出来的尺寸是假的（实测 Alpha 报半高 450，真站体只有 450）。
		#   所以这里先把 8 个角变换到 holder 空间再求包围盒。
		var aabb: AABB = _station_local_aabb(holder)
		var radius: float = maxf(aabb.size.x, aabb.size.z) * 0.5
		var half_h: float = aabb.size.y * 0.5
		holder.half_extent = Vector3(radius, half_h, radius)
		holder.disk_radius = radius
		holder.disk_thickness = maxf(half_h * 0.34, 2.0)
		# 对接端口放在**站体正上方**：包围盒顶 + 一小段余量，
		# 保证飞船停靠时不会嵌进模型里（之前放在盒子内部，截图里船就看不见了）。
		var clearance: float = maxf(half_h * 0.06, 6.0)
		holder.dock_offset = Vector3(aabb.position.x + aabb.size.x * 0.5,
			aabb.position.y + aabb.size.y + clearance,
			aabb.position.z + aabb.size.z * 0.5)
		distant_stations.append(holder)
		print("  远景站 %s：半径 %.0f 米，半高 %.0f 米，包围盒 %s，对接点 %s" % [
			entry["label"], radius, half_h, str(aabb), str(holder.dock_offset)])


## 量一个节点下所有网格的包围盒（**换算到 holder 的局部空间**）。
##
## 坑：MeshInstance3D.get_aabb() 返回的是**网格自身局部空间**的盒子，
##     不含节点链条上的缩放/旋转。外部模型常带 100 倍以上的节点缩放
##     （Blender 导出时 1 单位当作厘米那种），直接 merge 出来的数字是假的 ——
##     实测报了「半径 358 米、半高 450 米」，而真实站体只有约 450 米宽、200 米高。
##     这里把每个节点相对 root 的变换乘进去。
func _station_local_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.get_aabb()
		# 把网格盒子八个角变换到 root 空间，再求新的包围盒
		var to_root: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var _world_box := Transform3D(Basis(), Vector3.ZERO)
		# 用 AABB 的 8 个角手动变换
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in range(8):
			var corner := box.position + Vector3(
				box.size.x if (i & 1) else 0.0,
				box.size.y if (i & 2) else 0.0,
				box.size.z if (i & 4) else 0.0)
			var p: Vector3 = to_root * corner
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		var local_box := AABB(lo, hi - lo)
		if first:
			out = local_box
			first = false
		else:
			out = out.merge(local_box)
	if first:
		return AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	return out


## 远景空间站缓慢自转（只是布景，没有物理）。
func _update_distant_stations(delta: float) -> void:
	for holder in distant_stations:
		if holder != null and holder.has_method("update_spin"):
			holder.update_spin(delta)


func _update_comet() -> void:
	if comet == null:
		return
	var angle := visual_time * 0.0045 + 1.2
	var orbit := Vector3(cos(angle) * 6600.0, 850.0 + sin(angle * 1.35) * 620.0, sin(angle) * 5200.0)
	var next_angle := angle + 0.02
	var next_orbit := Vector3(cos(next_angle) * 6600.0, 850.0 + sin(next_angle * 1.35) * 620.0, sin(next_angle) * 5200.0)
	var motion := (next_orbit - orbit).normalized()
	var away := orbit.normalized()
	var up := Vector3.UP
	if absf(away.dot(up)) > 0.96:
		up = Vector3.FORWARD
	comet.global_position = orbit
	comet.basis = Basis.looking_at(-away, up)
	if comet_dust != null:
		var dust_direction := (away * 0.55 - motion * 0.85).normalized()
		comet_dust.basis = Basis.looking_at(-dust_direction, up)


func _reset_positions() -> void:
	in_station = false
	ship.docked = false
	ship.docked_station = null
	if player.get_parent() != home:
		player.reparent(home, false)
	var site_direction := Vector3(-0.06, 1.0, -0.04).normalized()
	var arch := home.find_child("Architecture_Qinglan", true, false)
	var base_tangent: Vector3 = site_direction.cross(Vector3.FORWARD)
	if arch != null:
		base_tangent = arch.global_transform.basis.z.normalized()
	if base_tangent.length_squared() < 0.01:
		base_tangent = site_direction.cross(Vector3.RIGHT).normalized()
	var parking_tangent: Vector3 = base_tangent
	var ship_direction: Vector3 = (site_direction + base_tangent * (30.0 / float(home.radius))).normalized()
	var ship_position: Vector3 = home.surface_position(ship_direction, 2.3)
	if not _ship_parking_clear(ship_position):
		for step in range(1, 7):
			var offset := float(step) * 0.14 * (1.0 if step % 2 == 1 else -1.0)
			var candidate_tangent: Vector3 = base_tangent.rotated(site_direction, offset)
			var candidate_direction: Vector3 = (site_direction + candidate_tangent * (30.0 / float(home.radius))).normalized()
			var candidate_position: Vector3 = home.surface_position(candidate_direction, 2.3)
			if _ship_parking_clear(candidate_position):
				parking_tangent = candidate_tangent
				ship_direction = candidate_direction
				ship_position = candidate_position
				break
	var lateral: Vector3 = site_direction.cross(parking_tangent).normalized()
	var spawn_direction: Vector3 = (site_direction + parking_tangent * (35.5 / float(home.radius)) + lateral * (3.2 / float(home.radius))).normalized()
	var spawn_position: Vector3 = home.surface_position(spawn_direction, 1.4)
	var village_center: Vector3 = home.surface_position(site_direction, 0.0)
	var look_direction: Vector3 = village_center - home.surface_position(spawn_direction, 0.0)
	look_direction = (look_direction - spawn_direction * look_direction.dot(spawn_direction)).normalized()
	player.position = spawn_position
	player.basis = Basis.looking_at(look_direction, spawn_direction)
	player.velocity = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.fuel = 100.0
	player.oxygen = 100.0
	player.visible = true
	if ship.get_parent() != home:
		ship.reparent(home, false)
	ship.position = ship_position
	ship.basis = Basis(Quaternion(Vector3.UP, ship_direction))
	ship.velocity = Vector3.ZERO
	ship.landed = true
	ship.landed_planet = home
	ship.autopilot = false
	ship.fuel = 100.0
	ship.hull = 100.0


func _ship_parking_clear(position: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 2.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var up: Vector3 = (position - home.global_position).normalized()
	query.transform = Transform3D(Basis.IDENTITY, position + up * 2.0)
	query.collision_mask = 1
	return space.intersect_shape(query, 1).is_empty()


func _process(delta: float) -> void:
	# 渐进式建场期间世界还不完整（home / menu_camera / 火焰都未创建），先不跑逐帧逻辑。
	if not world_ready:
		return
	visual_time += delta
	_update_guide(delta)
	_update_boat(delta)
	if attic_worlds != null:
		attic_worlds.update_bridge(delta)
		attic_worlds.update_airship(delta)
	_update_pocket_safety()
	if attic != null:
		attic.update_swallow(delta)
	_update_sky_pixel_angle()
	_animate_fire()
	_update_comet()
	_update_gargantua(delta)
	_update_distant_stations(delta)
	_update_sun_detail()
	if state == "menu":
		var center := home.global_position
		var angle := visual_time * 0.035
		menu_camera.global_position = center + Vector3(cos(angle) * 880.0, 520.0, sin(angle) * 880.0)
		menu_camera.look_at(center, Vector3.UP)
	if supernova_active:
		_update_supernova(delta)
		return
	if state == "dying":
		death_timer += delta
		_update_sun_visual(delta)
		if death_timer >= death_duration:
			reset_loop(death_reason + "。意识在篝火旁重新同步。")
		return
	if paused or state not in ["walk", "ship"]:
		return
	if in_station and player != null and active_station != null and not active_station.is_interior_position(player.global_position):
		_recover_from_station_void()
	# 阁楼是地面线，轮回不该在这里倒计时。
	if in_attic:
		elapsed += 0.0
		_update_fishing(delta)
		_update_dungeon(delta)
	else:
		elapsed += delta
	_update_sun_visual(delta)
	if elapsed >= LOOP_DURATION:
		_trigger_supernova()
		return
	_update_scanner(delta)


func _animate_fire() -> void:
	for i in range(fire_flames.size()):
		var flame: MeshInstance3D = fire_flames[i]
		var pulse := 1.0 + sin(visual_time * (5.0 + i) + i * 2.1) * 0.12 + sin(visual_time * (11.0 + i * 1.7)) * 0.035
		var base: Vector3 = fire_flame_bases[i] if i < fire_flame_bases.size() else Vector3.ONE
		var anchor: Vector3 = fire_flame_offsets[i] if i < fire_flame_offsets.size() else Vector3(0, 0.86, 0)
		flame.scale = base * Vector3(pulse, 1.0 + (pulse - 1.0) * 1.8, pulse)
		flame.position = anchor + Vector3(sin(visual_time * (2.3 + i * 0.4)) * 0.045, sin(visual_time * (3.1 + i * 0.6)) * 0.018, cos(visual_time * (1.9 + i * 0.5)) * 0.035)
	if fire_light != null:
		fire_light.light_energy = 2.05 + sin(visual_time * 9.3) * 0.16 + sin(visual_time * 17.7 + 1.0) * 0.08
		fire_light.position.x = sin(visual_time * 1.7) * 0.05
	if fire_coal_material != null:
		fire_coal_material.emission_energy_multiplier = 1.35 + sin(visual_time * 3.4) * 0.3


func _update_sun_detail() -> void:
	if sun_detail == null or sun_material == null:
		return
	var fade := 0.0
	var camera := get_viewport().get_camera_3d()
	if camera != null and not supernova_active:
		var distance := camera.global_position.length()
		fade = clampf((SUN_DETAIL_RANGE - distance) / SUN_DETAIL_FADE, 0.0, 1.0)
	sun_detail.visible = fade > 0.01
	sun_material.set_shader_parameter("detail_amount", fade)
	for material in prominence_materials:
		material.set_shader_parameter("fade", fade)


func _update_sun_visual(_delta: float) -> void:
	var ratio := clampf(elapsed / LOOP_DURATION, 0.0, 1.0)
	var heat := clampf((ratio - 0.78) / 0.22, 0.0, 1.0)
	sun_material.set_shader_parameter("heat", heat)
	sun_mesh.scale = Vector3.ONE * (1.0 + heat * 0.18)
	sun_light.light_energy = 3.0 + heat * 1.8
	var distance := get_active_position().length()
	solar_intensity = clampf((950.0 - distance) / 650.0, 0.0, 1.0)
	if solar_intensity > 0.0:
		sun_light.light_energy += solar_intensity * 5.0
	for i in range(corona_shells.size()):
		var shell: MeshInstance3D = corona_shells[i]
		var material := shell.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color.a = (0.09 - i * 0.018) * (1.0 + sin(visual_time * 1.7 + i) * 0.18)


func _trigger_supernova() -> void:
	if supernova_active:
		return
	previous_state = state
	state = "supernova"
	supernova_active = true
	supernova_timer = 0.0
	map_open = false
	ship.autopilot = false
	audio.play_supernova()


func _update_supernova(delta: float) -> void:
	supernova_timer += delta
	sun_mesh.scale = Vector3.ONE * (1.25 + supernova_timer * 5.5)
	sun_light.light_energy = 6.0 + supernova_timer * 9.0
	if supernova_timer >= 3.6:
		reset_loop("新的轮回。你带回了自己的记忆。")


func reset_loop(reason := "") -> void:
	loop_count += 1
	elapsed = 0.0
	if roast != null:
		roast.cancel(false)
	supernova_active = false
	supernova_timer = 0.0
	death_timer = 0.0
	death_duration = 3.8
	death_reason = ""
	solar_intensity = 0.0
	sun_mesh.scale = Vector3.ONE
	sun_material.set_shader_parameter("heat", 0.0)
	sun_light.light_energy = 3.0
	scan_progress = 0.0
	scan_target = null
	_reset_positions()
	state = "walk"
	paused = false
	journal_open = false
	map_open = false
	player.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_save_knowledge()
	if reason != "":
		hud.show_toast(reason, 4.5)


func die(reason: String) -> void:
	begin_death(reason, 3.0)


func begin_death(reason: String, duration := 3.0) -> void:
	if state in ["menu", "supernova", "end", "dying"]:
		return
	if roast != null:
		roast.cancel(false)
	previous_state = state
	state = "dying"
	death_timer = 0.0
	death_duration = duration
	death_reason = reason
	map_open = false
	journal_open = false
	paused = false
	ship.autopilot = false
	solar_intensity = 1.0
	audio.play_impact()
	audio.play_supernova()


func start_game() -> void:
	if state != "menu":
		return
	elapsed = 0.0
	if roast != null:
		roast.cancel(false)
	_reset_positions()
	state = "walk"
	paused = false
	journal_open = false
	map_open = false
	player.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		DisplayServer.window_set_ime_active(false)
	hud.show_toast("先扫描风车塔，再去看看宇宙。", 5.0)


func return_to_menu() -> void:
	if roast != null:
		roast.cancel(false)
	in_station = false
	if ship != null:
		ship.docked = false
		ship.docked_station = null
	state = "menu"
	paused = false
	journal_open = false
	map_open = false
	supernova_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_camera.current = true


func set_paused(value: bool) -> void:
	if state not in ["walk", "ship"]:
		return
	paused = value
	journal_open = false
	map_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func toggle_journal() -> void:
	if state not in ["walk", "ship"]:
		return
	journal_open = not journal_open
	paused = journal_open
	map_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if journal_open else Input.MOUSE_MODE_CAPTURED
	if journal_open:
		hud.rebuild_journal()


func toggle_map() -> void:
	if state not in ["walk", "ship"] or paused:
		return
	map_open = not map_open
	if map_open:
		map_dragging = false
		var nearest := current_planet()
		var index := planets.find(nearest)
		if index >= 0:
			map_selected = index


func map_max_orbit() -> float:
	var result := 4200.0
	for planet in planets:
		result = maxf(result, planet.orbit_radius)
	return result


func map_center_for(size: Vector2) -> Vector2:
	return size * 0.5 + Vector2(30, 24) + map_pan


func map_scale_for(size: Vector2) -> float:
	return minf(size.x * 0.33, size.y * 0.39) / map_max_orbit() * map_zoom


func map_screen_of(world: Vector3, size: Vector2) -> Vector2:
	return map_center_for(size) + Vector2(world.x, world.z) * map_scale_for(size)


func _handle_map_input(event: InputEvent) -> void:
	var size := get_viewport().get_visible_rect().size
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			map_zoom = clampf(map_zoom * 1.12, 0.45, 2.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			map_zoom = clampf(map_zoom / 1.12, 0.45, 2.8)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				map_dragging = true
				map_drag_distance = 0.0
			else:
				map_dragging = false
				if map_drag_distance < 6.0:
					_select_map_body(event.position, size)
	elif event is InputEventMouseMotion and map_dragging:
		map_pan += event.relative
		map_drag_distance += event.relative.length()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q, KEY_LEFT:
				_cycle_map_selection(-1)
			KEY_E, KEY_RIGHT, KEY_TAB:
				_cycle_map_selection(1)
			KEY_ENTER, KEY_T:
				_set_map_target()
			KEY_R, KEY_0:
				map_zoom = 1.0
				map_pan = Vector2.ZERO


func _select_map_body(position: Vector2, size: Vector2) -> void:
	var best := -1
	var best_distance := 34.0
	for i in range(planets.size()):
		var screen := map_screen_of(planets[i].global_position, size)
		var distance := screen.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best = i
	if best >= 0:
		map_selected = best
		audio.play_ui(520.0)


func _cycle_map_selection(direction: int) -> void:
	map_selected = wrapi(map_selected + direction, 0, planets.size())
	audio.play_ui(460.0)


func _set_map_target() -> void:
	ship.target = planets[map_selected]
	target_index = map_selected
	hud.show_toast("目的地：" + ship.target.display_name, 2.0)
	audio.play_ui(620.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	# 开发者按键排在最前面：它们不受「暂停 / 星图 / 仅行走飞船」这些闸门限制，
	# 否则在菜单里、暂停时和星图里就按不出开发者模式了。
	if event is InputEventKey and event.pressed and not event.echo:
		var dev_code: String = OS.get_keycode_string((event as InputEventKey).physical_keycode)
		if dev_handle_key(dev_code):
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var g_code: String = OS.get_keycode_string((event as InputEventKey).physical_keycode)
		if g_code == "G" and guide_card != null and guide_card.active:
			guide_card.skip()
			return
	if event.is_action_pressed("ui_cancel"):
		if demo_active:
			stop_demo()
			return
		if scope_active:
			_exit_scope()
			return
		if run_summary != null and run_summary.open:
			run_summary.close()
			return
		if journal_book_open:
			toggle_travel_journal()
		elif handbook_open:
			toggle_handbook()
		elif hud != null and hud.help.visible:
			hud.help.visible = false
		elif hud != null and hud.settings_panel.visible:
			hud.hide_settings()
		elif journal_open:
			toggle_journal()
		elif map_open:
			map_open = false
		elif state in ["walk", "ship"]:
			set_paused(not paused)
		return
	if map_open:
		_handle_map_input(event)
		return
	if state not in ["walk", "ship"] or paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# F5：飞船的第三人称视角切换。
		# 只在**驾驶飞船时**才有意义 —— 走路时按 F5 不该有任何反应。
		# 开发者模式的 F5（解锁全部条目）在上面已经被 dev_handle_key 吃掉了，
		# 所以两者不冲突：开了开发者模式时 F5 仍然是开发者功能。
		var ship_code: String = OS.get_keycode_string((event as InputEventKey).physical_keycode)
		if ship_code == "F5" and state == "ship":
			if ship.toggle_third_person():
				return
	if event.is_action_pressed("map"):
		toggle_map()
	elif event.is_action_pressed("journal"):
		toggle_journal()
	elif event.is_action_pressed("target") and state == "ship":
		cycle_target()
	elif event.is_action_pressed("autopilot") and state == "ship" and not ship.landed:
		ship.autopilot = not ship.autopilot
		if ship.autopilot and ship.target == null:
			ship.target = planets[target_index]
		hud.show_toast("自动航行已开启" if ship.autopilot else "已切换手动驾驶", 1.8)
	elif event.is_action_pressed("handbook"):
		toggle_handbook()
	elif handbook_open and event is InputEventKey and event.pressed and not event.echo:
		var hb_code: String = OS.get_keycode_string((event as InputEventKey).physical_keycode)
		if hb_code == "Left":
			handbook.step_section(-1)
		elif hb_code == "Right":
			handbook.step_section(1)
		elif hb_code == "R":
			replay_guide()
	elif event.is_action_pressed("bag"):
		toggle_bag()
	elif bag_open and event is InputEventKey and event.pressed and not event.echo:
		var code_name: String = OS.get_keycode_string((event as InputEventKey).physical_keycode)
		if code_name == "S":
			sell_fish_from_bag()
		elif code_name == "R":
			upgrade_rod_from_bag()
		elif code_name == "F":
			buy_bait_from_bag()
		elif code_name == "T":
			switch_bait_from_bag()
		elif code_name == "Left":
			bag_page_prev()
		elif code_name == "Right":
			bag_page_next()
		elif code_name == "Down":
			bag_scroll(1)
		elif code_name == "Up":
			bag_scroll(-1)
	elif dungeon_combat_active() and event is InputEventKey and event.is_action_pressed("jump"):
		# 镜牢里 Space 是闪避（原作：空格闪避）
		dungeon_dodge()
	elif dungeon_combat_active() and event is InputEventKey and event.pressed and not event.echo:
		# 1 / 2 / 3 换武器（原作：棱镜杖 / 镜刃 / 折光弩）
		var weapon_code: String = OS.get_keycode_string((event as InputEventKey).physical_keycode)
		match weapon_code:
			"1":
				dungeon_switch_weapon("wand")
			"2":
				dungeon_switch_weapon("blade")
			"3":
				dungeon_switch_weapon("crossbow")
	elif dungeon_combat_active() and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dungeon_attack("glow")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dungeon_attack("blast")
	elif event.is_action_pressed("interact"):
		if scope_active:
			_exit_scope()
			return
		if run_summary != null and run_summary.open:
			run_summary.close()
			return
		_interact()


func _interact() -> void:
	if map_open:
		return
	if state == "walk":
		if in_attic:
			# 阁楼本体：雨停后窗台的燕子
			if not in_pocket() and near_swallow():
				greet_swallow()
				return
			# 阁楼本体：先看茶几上的旅行小册
			if not in_pocket() and near_booklet():
				toggle_travel_journal()
				return
			# 小世界里：先看回程门，再看镜界的棱镜之心
			if in_pocket():
				if near_prism_heart():
					take_prism_heart()
					return
				# 云河：船上按 E 点灯 / 系舟；船下靠近云舟按 E 上船
				if pocket_key == "cloud":
					if attic_worlds != null and attic_worlds.boat_active:
						# 在船上：先看能不能点灯，再看能不能系舟
						var buoy_index: int = attic_worlds.near_buoy()
						if buoy_index >= 0:
							var light_result: Dictionary = attic_worlds.light_buoy(buoy_index)
							var light_text := String(light_result.get("message", ""))
							if light_text != "":
								hud.show_toast(light_text, 3.0)
							if bool(light_result.get("ok", false)):
								audio.play_ui(700.0)
								if progress != null:
									progress.save()
							return
						var dock_result: Dictionary = attic_worlds.leave_boat()
						if bool(dock_result.get("ok", false)):
							_leave_boat_seat(dock_result)
							return
						var dock_text := String(dock_result.get("message", ""))
						if dock_text != "":
							hud.show_toast(dock_text, 2.6)
						return
					elif attic_worlds != null:
						var board: Dictionary = attic_worlds.board_boat(player.global_position)
						if bool(board.get("ok", false)):
							_enter_boat_seat()
							hud.show_toast(String(board.get("message", "")), 3.2)
							audio.play_ui(420.0)
							return
						elif String(board.get("message", "")) != "" and _near_boat():
							hud.show_toast(String(board.get("message", "")), 2.2)
							return
				# 原作外围道具：木牌 / 风琴礁 / 各处小交互
				# 云桥：人还在桥那头时不能收（照原作「先回到观景台，再收起云桥」）
				if pocket_key == "cloud" and attic_worlds != null \
						and attic_worlds.bridge_down and player.global_position.z < _bridge_far_z():
					hud.show_toast("先回到观景台，再收起云桥", 2.6)
					return
				var prop_id := near_prop_interact()
				if prop_id != "":
					interact_prop(prop_id)
					return
				# 冰钓：收线阶段靠按住 E（逐帧读输入），这里只处理下竿与提前收杆
				if fishing_phase == "reel":
					return
				if fishing_phase == "wait":
					_end_fishing("提早收杆 · 鱼跑了", false)
					return
				if fishing_hole < 0:
					var hole := near_fishing_hole()
					if hole >= 0:
						start_fishing(hole)
						return
				# 静镜室：取一枚镜印
				if pocket_key == "dungeon":
					var boon_index := near_dungeon_boon()
					if boon_index >= 0:
						take_dungeon_boon(boon_index)
						return
				# 镜界里的镜牢门
				if pocket_key == "mirror" and near_dungeon_gate():
					enter_dungeon()
					return
				# 听雨院：先点灯，再坐下
				if pocket_key == "alley":
					var court_lamp := near_court_lamp()
					if court_lamp >= 0:
						var lit: int = attic_worlds.light_court_lamp(court_lamp)
						audio.play_ui(620.0 + float(lit) * 50.0)
						hud.show_toast("点亮一盏听雨灯 · %d / 3" % lit, 2.4)
						return
					if near_court_bench():
						if attic_worlds.rest_in_court():
							audio.play_ui(700.0)
							hud.show_toast("在檐下坐了一会儿 · 雨声把时间放慢了", 4.6)
							if progress != null:
								if progress.unlock("court_rest"):
									hud.show_toast("成就 · 檐下听雨 · 按 B 查看行囊", 4.0)
								progress.save()
						elif not attic_worlds.court_all_lit():
							hud.show_toast("檐下还暗着 · 先把三盏听雨灯点亮", 2.6)
						else:
							hud.show_toast("已经在这里坐过了", 2.2)
						return
				var mini_key := near_minigame()
				if mini_key != "":
					open_minigame(mini_key)
					return
				var device_index := near_world_device()
				if device_index >= 0:
					activate_world_device(device_index)
					return
				if near_pocket_return():
					leave_pocket()
					return
				hud.show_toast("走近发光的物件按 E；回程门在场地边上", 2.4)
				return
			# 茶席：站在茶壶前按 E，一步一步泡
			var tea_anchor: Node3D = attic.tea_anchor()
			if tea_anchor != null and player.global_position.distance_to(tea_anchor.global_position) < 2.0:
				var tea_result: Dictionary = attic.advance_tea()
				if bool(tea_result.get("changed", false)):
					audio.play_ui(520.0 + float(int(tea_result["step"])) * 60.0)
				hud.show_toast(String(tea_result["message"]), 3.2 if bool(tea_result["done"]) else 2.6)
				if bool(tea_result.get("done", false)) and progress != null:
					if progress.unlock("tea_full"):
						hud.show_toast("成就 · 一壶茶 · 按 B 查看行囊", 4.0)
					progress.save()
				return
			# 天气旋钮：站在旋钮前按 E 轮换窗外天气
			var dial_anchor: Node3D = attic.dial_anchor()
			if dial_anchor != null and player.global_position.distance_to(dial_anchor.global_position) < 2.2:
				guide_turned_dial = true
				var weather: Dictionary = attic.cycle_dial()
				audio.play_ui(480.0 + float(int(weather["index"])) * 60.0)
				hud.show_toast("黄铜旋钮转到「%s」· 窗外换了天气" % String(weather["title"]), 2.8)
				return
			# 阁楼本体：站在哪扇门前就进哪个世界
			var door_key := near_attic_door()
			if door_key != "":
				guide_opened_door = true
				enter_pocket(door_key)
				return
			hud.show_toast("走到门（或镜面）前再按 E", 2.2)
			return
		if in_station:
			if active_station != null and player.global_position.distance_to(active_station.airlock_position()) < 4.0:
				exit_station_to_ship()
			else:
				hud.show_toast("气闸在舱室中央 · 站到地面发光环上再按 E", 2.2)
			return
		if player.global_position.distance_to(ship.global_position) < 8.0:
			if roast != null:
				roast.cancel(false)
			state = "ship"
			player.visible = false
			ship.camera.current = true
			audio.play_ui(420.0)
			return
		if player.global_position.distance_to(campfire.global_position) < 5.0:
			if roast != null and roast.active:
				roast.finish()
			elif roast != null:
				roast.start()
			audio.play_ui(520.0)
	elif state == "ship":
		if ship.docked:
			# 远景站也有内部舱室了，按 E 进站；进站后再按 E（站在出口环上）回飞船。
			enter_station()
		elif ship.landed:
			exit_ship()
		else:
			ship.try_land()


func exit_ship() -> void:
	var planet: Node3D = ship.landed_planet
	if planet == null:
		return
	var normal := (ship.global_position - planet.global_position).normalized()
	var tangent := ship.global_transform.basis.x.normalized()
	if player.get_parent() != planet:
		player.reparent(planet, false)
	player.global_position = find_safe_surface_position(planet, normal, tangent)
	var rotation_to_surface := Quaternion(player.global_transform.basis.y.normalized(), normal)
	var transform := player.global_transform
	transform.basis = (Basis(rotation_to_surface) * transform.basis).orthonormalized()
	player.global_transform = transform
	player.velocity = Vector3.ZERO
	player.oxygen = 100.0
	player.visible = true
	state = "walk"
	player.camera.current = true
	audio.play_ui(360.0)


func enter_station() -> void:
	if not ship.docked or ship.docked_station == null:
		return
	# 用 docked_station 而不是写死的 station —— 远景站也能进。
	var target_station: Node3D = ship.docked_station
	active_station = target_station
	if roast != null:
		roast.cancel(false)
	in_station = true
	state = "walk"
	paused = false
	journal_open = false
	map_open = false
	player.reparent(target_station, false)
	player.global_transform = target_station.interior_spawn_transform()
	player.camera.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.oxygen = 100.0
	player.visible = true
	player.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	audio.play_ui(430.0)
	if target_station.has_method("is_distant_station"):
		hud.show_toast("已进入%s · 环形观景舱 · 站上地面发光环按 E 返回飞船" % target_station.display_name, 5.0)
	else:
		hud.show_toast("已进入归航站中央枢纽 · 六条放射走廊 A–F · 气闸控制台旁按 E 返回飞船", 5.0)


func _recover_from_station_void() -> void:
	var target_station: Node3D = active_station if active_station != null else station
	player.global_transform = target_station.interior_spawn_transform()
	player.camera.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	audio.play_ui(180.0)
	if hud != null:
		hud.show_toast("舱壁失压 · 紧急牵引回中央枢纽", 3.2)


func exit_station_to_ship() -> void:
	if not in_station:
		return
	in_station = false
	player.visible = false
	state = "ship"
	ship.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	audio.play_ui(360.0)
	hud.show_toast("已返回飞船 · Space 脱离对接", 3.0)


func cycle_target() -> void:
	target_index = (target_index + 1) % planets.size()
	ship.target = planets[target_index]
	hud.show_toast("目的地：" + ship.target.display_name, 1.8)
	audio.play_ui(600.0)


func get_active_position() -> Vector3:
	if state == "ship":
		return ship.global_position
	return player.global_position


func get_active_camera() -> Camera3D:
	if state == "ship":
		return ship.camera
	return player.camera


func nearest_planet(position: Vector3) -> Node3D:
	var result: Node3D = planets[0]
	var best := INF
	for planet in planets:
		var distance: float = position.distance_squared_to(planet.global_position) - planet.radius * planet.radius
		if distance < best:
			best = distance
			result = planet
	return result


func find_safe_surface_position(planet: Node3D, normal: Vector3, preferred_tangent := Vector3.ZERO) -> Vector3:
	var tangent := preferred_tangent - normal * preferred_tangent.dot(normal)
	if tangent.length_squared() < 0.01:
		tangent = normal.cross(Vector3.RIGHT)
	if tangent.length_squared() < 0.01:
		tangent = normal.cross(Vector3.FORWARD)
	tangent = tangent.normalized()
	for offset in [5.0, 9.0, 13.0, 17.0, -5.0, -9.0, -13.0, 21.0, -17.0, 0.0]:
		var direction: Vector3 = (normal + tangent * (offset / planet.radius)).normalized()
		var position: Vector3 = planet.global_position + planet.surface_position(direction, 1.4)
		if _safe_spawn_clear(position, direction):
			return position
	return planet.global_position + planet.surface_position(normal, 9.0)


func _safe_spawn_clear(position: Vector3, normal: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)), position + normal * 0.95)
	query.collision_mask = 1
	return space.intersect_shape(query, 1).is_empty()


func current_planet() -> Node3D:
	return nearest_planet(get_active_position())


func _near_cave_mouth() -> bool:
	if player == null or player.get_parent() == null:
		return false
	var planet := current_planet()
	if planet == null or not planet.cave_enabled:
		return false
	var normal: Vector3 = (player.global_position - planet.global_position).normalized()
	var altitude: float = player.global_position.distance_to(planet.global_position) - planet.terrain_height(normal)
	if altitude < -2.0:
		return false
	var mouth: Vector3 = planet.global_position + planet.surface_position(planet.cave_direction, 0.0)
	return player.global_position.distance_to(mouth) < 20.0


func _hidden_echo_progress() -> Array:
	var total := 0
	var found := 0
	for anomaly in anomalies:
		if anomaly.anomaly_id in ["qinglan", "zheya", "cangbo", "xuanjing", "xuanyuan"]:
			continue
		total += 1
		if discovered.has(anomaly.anomaly_id):
			found += 1
	return [found, total]


func touch_ui_active() -> bool:
	return touch_controls != null and touch_controls.is_active()


func has_touch_layer() -> bool:
	return touch_controls != null and touch_controls.has_touch_layer()


func get_prompt() -> String:
	if paused or journal_open or state not in ["walk", "ship"]:
		return ""
	# 阁楼线与小世界：用自己的一套提示，别继续显示星际原型的按键
	if in_attic:
		# 演示期间由演示层自己出字幕，别再叠一行按键提示
		if demo_active:
			return ""
		if in_pocket():
			if fishing_phase != "":
				return ""  # 冰钓时 HUD 自己有说明，别叠两层
			if touch_ui_active():
				return "「互动」交互 / 上下云舟 / 抛竿　·　「行囊」查看进度"
			return "WASD 移动 · E 互动 / 读木牌 / 推门 · B 行囊 · H 旅人手册 · Esc 菜单"
		if touch_ui_active():
			return "「互动」互动 / 推门　·　「行囊」查看进度"
		# 燕子特写：站在窗台/壁炉边时给出对应提示
		if near_swallow():
			if attic != null and attic.swallow_perched():
				return "E 看看壁炉边的燕子 · B 行囊 · H 旅人手册"
			return "E 招呼窗台的燕子 · B 行囊 · H 旅人手册"
		return "WASD 移动 · E 互动 / 推门 / 翻旅行小册 · B 行囊 · H 旅人手册 · Esc 菜单"
	if map_open:
		if has_touch_layer():
			return "右侧按钮缩放 · 关闭按钮收起星图 · 拖动平移"
		return "滚轮缩放 · 拖动平移 · 点击 / Q E 选择 · T 设为目标 · M / Esc 收起星图"
	if in_station:
		if player.global_position.distance_to(station.airlock_position()) < 4.0:
			if touch_ui_active():
				return "「互动」返回飞船 · 解除对接"
			return "E 返回飞船 · 解除对接"
		if touch_ui_active():
			return "左摇杆移动 · 拖动右侧视角 · 六条放射走廊 · 气闸在中央"
		return "WASD 移动 · 六条放射走廊 A–F · 气闸控制台在中央 · E 返回飞船 · 舷窗外是真实宇宙"
	if scan_target != null:
		if scan_target.anomaly_id == "xuanyuan" and not missing_clues().is_empty():
			return "信号被三层坐标加密 · 尚缺 %d 枚棱镜" % missing_clues().size()
		if discovered.has(scan_target.anomaly_id):
			return scan_target.title + " · 已写入航海日志"
		if touch_ui_active():
			return "按住「扫描」按钮扫描「%s」" % scan_target.title
		return "按住 F 扫描「%s」" % scan_target.title
	if state == "walk":
		if _near_cave_mouth():
			return "洞口敞开 · 沿螺旋石阶下到洞底，寻找可扫描的回声"
		if player.global_position.distance_to(ship.global_position) < 8.0:
			if touch_ui_active():
				return "「互动」按钮登船　·　靠近篝火可补给"
			return "E 登船　·　靠近篝火可补给"
		if player.global_position.distance_to(campfire.global_position) < 5.0:
			if roast != null and roast.active:
				return ""
			if touch_ui_active():
				return "「互动」按钮烤棉花糖　·　火候刚好时再按一次取下"
			return "E 烤棉花糖　·　在篝火边慢慢翻转，火候刚好时取回"
		if touch_ui_active():
			return "左摇杆移动 · 拖动右侧视角 · 圆钮跳跃 / 喷气 / 互动 / 扫描"
		return "WASD 移动 · Shift 喷气 · Ctrl 奔跑 · F 扫描 · R 脱困 · 右键信号镜 · 滚轮变焦"
	if ship.docked:
		if touch_ui_active():
			return "「进入」进入归航站 ·「脱离」解除对接"
		return "E 进入归航站 · Space 脱离对接 · 滚轮长焦"
	if station != null and station.docking_point().distance_to(ship.global_position) < 140.0:
		return "低速靠近对接口即可自动对接 · 距离 %d m · X 制动" % int(station.docking_point().distance_to(ship.global_position))
	if ship.landed:
		if touch_ui_active():
			return "「起飞」按钮升空 · 摇杆平移 · 拖动转向 · 圆钮离船"
		return "Space 起飞 · 升空后 Space 上升 / Ctrl 或 C 下降 · E 离船 · 滚轮长焦"
	if ship.fuel <= 0.01:
		return "推进剂耗尽 · Tab 选目的地后 T 自动航行求救 · X 制动"
	var planet := nearest_planet(ship.global_position)
	var normal := (ship.global_position - planet.global_position).normalized()
	var altitude: float = ship.global_position.distance_to(planet.global_position) - planet.terrain_height(normal)
	if altitude < 70.0:
		if touch_ui_active():
			return "「着陆」按钮降落 · 摇杆平移 · 拖动转向"
		return "E 自动着陆（70 米内 / 速度低于 45）· 滚轮长焦 · X 制动"
	if touch_ui_active():
		return "摇杆平移 · 拖动右侧转向 · 圆钮上升 / 下降 / 加力 / 制动"
	return "WASD / Space 上升 / Ctrl 或 C 下降 · 鼠标转向 · 滚轮长焦 · Tab 目的地 · T 自动航行 · F5 看飞船"


func _update_scanner(delta: float) -> void:
	var next_target := _find_scan_target()
	if next_target != scan_target:
		scan_target = next_target
		scan_progress = 0.0
	if scan_target == null:
		scan_progress = 0.0
		return
	if discovered.has(scan_target.anomaly_id):
		scan_progress = 1.0
		return
	if scan_target.anomaly_id == "xuanyuan" and not missing_clues().is_empty():
		scan_progress = 0.0
		return
	if Input.is_action_pressed("scan"):
		scan_progress += delta / scan_target.scan_time
		if scan_progress >= 1.0:
			discover(scan_target.anomaly_id)
	else:
		scan_progress = maxf(0.0, scan_progress - delta * 0.8)


func _find_scan_target() -> Node3D:
	if state not in ["walk", "ship"] or map_open:
		return null
	var camera := get_active_camera()
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var best_score := INF
	var result: Node3D = null
	for anomaly in anomalies:
		var offset: Vector3 = anomaly.global_position + anomaly.global_transform.basis.y * 3.0 - origin
		var distance := offset.length()
		var max_distance := 55.0 if state == "walk" else 190.0
		if "scan_range" in anomaly:
			max_distance = minf(max_distance, float(anomaly.scan_range))
		if distance > max_distance:
			continue
		var facing := forward.dot(offset.normalized())
		var minimum_facing := 0.62 if state == "walk" else 0.38
		if facing < minimum_facing and distance > 5.0:
			continue
		if not _has_line_of_sight(origin, anomaly.global_position + anomaly.global_transform.basis.y * 3.0):
			continue
		var score := distance * (2.0 - facing)
		if score < best_score:
			best_score = score
			result = anomaly
	return result


func _has_line_of_sight(origin: Vector3, target: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1)
	var hit := space.intersect_ray(query)
	return hit.is_empty() or origin.distance_to(hit.position) > origin.distance_to(target) - 0.9


func missing_clues() -> Array:
	var missing: Array = []
	for clue in ["zheya", "cangbo", "xuanjing"]:
		if not discovered.has(clue):
			missing.append(clue)
	return missing


func discover(id: String) -> void:
	if discovered.has(id):
		return
	discovered[id] = true
	scan_progress = 1.0
	_save_knowledge()
	audio.play_chime()
	var anomaly := _anomaly_by_id(id)
	if anomaly != null:
		hud.show_toast("新条目 · " + anomaly.title, 4.0)
	if id == "xuanyuan":
		end_text = anomaly.body
		previous_state = state
		state = "end"
		paused = false
		map_open = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


const AtticScript = preload("res://scripts/attic.gd")
const AtticWorldsScript = preload("res://scripts/attic_worlds.gd")
const MinigameScript = preload("res://scripts/minigame.gd")
const ProgressScript = preload("res://scripts/progress.gd")
const BagPanelScript = preload("res://scripts/bag_panel.gd")
const DungeonScript = preload("res://scripts/dungeon.gd")
const FishingHudScript = preload("res://scripts/fishing_hud.gd")
const HandbookScript = preload("res://scripts/handbook.gd")
const TravelJournalScript = preload("res://scripts/travel_journal.gd")
const GuideScript = preload("res://scripts/guide.gd")
const RunSummaryScript = preload("res://scripts/run_summary.gd")
const DemoScript = preload("res://scripts/demo.gd")

const ATTIC_ORIGIN := Vector3(0.0, -40000.0, 0.0)
const ATTIC_GRAVITY := 18.0
## 口袋世界（四扇门 + 镜界）里玩家站在哪个世界；空串表示在阁楼本体。
var pocket_key := ""
## 是否已经取到镜界回廊的棱镜之心。
var has_prism_heart := false
## 行囊里卖渔获
func sell_fish_from_bag() -> void:
	if progress == null:
		return
	var result: Dictionary = progress.sell_fish()
	if int(result["count"]) <= 0:
		hud.show_toast("鱼篓是空的", 2.0)
		return
	audio.play_ui(700.0)
	var lines: Array = []
	if progress.sold_total >= 10 and progress.unlock("merchant"):
		lines.append("成就 · 会过日子")
	if progress.coins >= 500 and progress.unlock("rich"):
		lines.append("成就 · 口袋沉沉")
	progress.save()
	hud.show_toast("卖出 %d 尾 · 得 %d 金%s" % [int(result["count"]), int(result["coins"]),
		(" · " + " / ".join(lines)) if not lines.is_empty() else ""], 3.6)


## 行囊里买鱼饵：先买萤光饵，再买星屑饵（面团饵免费）
func buy_bait_from_bag() -> void:
	if progress == null:
		return
	var order := ["glow", "star"]
	var target := ""
	for id in order:
		if progress.bait_charge(id) <= 0:
			target = id
			break
	if target == "":
		# 都有存货就继续补最贵的
		target = "star"
	var result: Dictionary = progress.buy_bait(target)
	if not bool(result["ok"]):
		hud.show_toast("金币不够 · %s 要 %d 金（现有 %d）" % [
			String(progress.BAITS[target][0]), int(progress.BAITS[target][1]), progress.coins], 3.0)
		return
	audio.play_ui(700.0)
	progress.save()
	hud.show_toast("买了 %s · 现有 %d 份 · 按 T 换上" % [
		String(result["name"]), int(result["count"])], 3.2)


## 行囊里换鱼饵：在面团饵与有存货的饵之间轮换
func switch_bait_from_bag() -> void:
	if progress == null:
		return
	var owned: Array = progress.owned_baits()
	if owned.size() <= 1:
		hud.show_toast("只有面团饵 · 先按 F 买点萤光饵或星屑饵", 3.0)
		return
	var index: int = owned.find(progress.bait)
	var next_id: String = String(owned[(index + 1) % owned.size()])
	if progress.switch_bait(next_id):
		audio.play_ui(640.0)
		progress.save()
		hud.show_toast("换上 %s · %s" % [progress.bait_name(), String(progress.BAITS[next_id][5])], 3.6)


## 行囊里升级鱼竿（竹节 → 黄铜海竿 → 极光冰竿）
func upgrade_rod_from_bag() -> void:
	if progress == null:
		return
	var order := ["bamboo", "brass", "aurora"]
	var index: int = order.find(progress.rod)
	var next_id := ""
	if index >= 0 and index + 1 < order.size():
		next_id = order[index + 1]
	if next_id == "":
		hud.show_toast("已经是最好的鱼竿了", 2.2)
		return
	var price: int = int(progress.RODS[next_id][1])
	if not progress.buy_rod(next_id):
		hud.show_toast("金币不够 · 换 %s 需要 %d 金（现有 %d）" % [String(progress.RODS[next_id][0]), price, progress.coins], 3.0)
		return
	audio.play_ui(760.0)
	progress.save()
	hud.show_toast("换上了 %s · 稀有鱼更容易靠近" % progress.rod_name(), 3.4)


## 阁楼茶几上的旅行小册：按 E 翻开 / 合上。
func toggle_travel_journal() -> void:
	if travel_journal == null:
		return
	if minigame_open:
		return
	travel_journal.toggle()
	journal_book_open = travel_journal.open
	if journal_book_open:
		if bag_open and bag != null:
			bag.close()
			bag_open = false
		if handbook_open and handbook != null:
			handbook.close()
			handbook_open = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## ---------------------------------------------------------------------------
## 自动演示用到的接口（demo.gd 调这些）
## ---------------------------------------------------------------------------

## 开始演示：进阁楼、把相机交出去
func start_demo() -> void:
	if demo == null:
		return
	if not in_attic:
		enter_attic()
	demo_active = true
	if player != null:
		player.set_physics_process(false)
		player.set_process_input(false)
	# 存下原相机状态，退出时恢复
	var cam := demo_camera()
	if cam != null:
		demo.saved_camera_transform = cam.global_transform
		demo.saved_camera_fov = cam.fov
		demo.has_saved_camera = true
	if hud != null:
		hud.hud_root.visible = false
	demo.start()


## 退出演示：相机还回去、恢复玩家
func stop_demo() -> void:
	if demo == null:
		return
	demo_active = false
	demo.stop()
	var cam := demo_camera()
	if cam != null and demo.has_saved_camera:
		cam.global_transform = demo.saved_camera_transform
		cam.fov = demo.saved_camera_fov
		demo.has_saved_camera = false
	# 回到阁楼，别把玩家留在演示最后那个世界
	if in_pocket():
		leave_pocket()
	if player != null:
		player.set_physics_process(true)
		player.set_process_input(true)
		player.velocity = Vector3.ZERO
	if hud != null and hud.hud_root != null:
		hud.hud_root.visible = true


func demo_finished() -> void:
	stop_demo()
	hud.show_toast("自动演示结束 · 想自己玩就从这里开始", 4.0)


## 演示用的相机
func demo_camera() -> Camera3D:
	if player != null and player.camera != null:
		return player.camera
	return null


## 演示相机要按哪个容器的坐标算（阁楼 / 当前口袋世界）
func demo_world_container() -> Node3D:
	if in_pocket() and attic_worlds != null:
		return attic_worlds.world_node(pocket_key)
	return attic


## 演示：把窗外天气切到指定档（不动玩家）
func demo_set_weather(target_key: String) -> void:
	if attic == null:
		return
	var order: Array = attic.WEATHER_ORDER
	var index := order.find(target_key)
	if index < 0:
		return
	attic.set_dial(index)


## 演示：进某个世界
func demo_enter_world(key: String) -> void:
	if in_pocket():
		leave_pocket()
	if attic == null:
		return
	var by_key := {"cloud": "cloud", "firefly": "firefly", "alley": "alley", "snow": "snow"}
	if not by_key.has(key):
		return
	if attic.current_weather() != key:
		demo_set_weather(key)
	enter_pocket(key)
	if player != null:
		player.set_physics_process(false)
		player.set_process_input(false)


## 演示：回阁楼
func demo_leave_to_attic() -> void:
	if in_pocket():
		leave_pocket()
	if not in_attic:
		enter_attic()
	if player != null:
		player.set_physics_process(false)
		player.set_process_input(false)


## 演示：用一次道具
func demo_use_prop(id: String) -> void:
	if attic_worlds == null:
		return
	attic_worlds.use_prop(id)


## 演示：转一下某个世界的第 index 个装置（走正常的设备流程，会顺带点亮/收集纪念）
func demo_turn_device(world_key: String, index: int) -> void:
	if attic_worlds == null:
		return
	var result: Dictionary = attic_worlds.activate_device(world_key, index)
	if not bool(result.get("changed", false)):
		return
	var message := String(result.get("message", ""))
	if bool(result.get("solved", false)):
		if message != "":
			hud.show_toast(message, 2.6)
		collect_keepsake(world_key)
		return
	if message != "":
		hud.show_toast("%s · %d / 3" % [message, int(result.get("aligned", 0))], 2.2)


## 演示：让燕子出现在窗台
func demo_show_swallow() -> void:
	if attic != null and attic.show_swallow():
		hud.show_toast("窗台上，一只避雨的燕子收起了翅膀", 3.0)


## 演示：招呼燕子
func demo_greet_swallow() -> void:
	if attic == null:
		return
	var result: Dictionary = attic.greet_swallow()
	if String(result.get("message", "")) != "":
		hud.show_toast(String(result.get("message", "")), 2.6)


## 站在阁楼窗台 / 壁炉边的燕子旁
func near_swallow() -> bool:
	if not in_attic or player == null or attic == null:
		return false
	if in_pocket():
		return false
	if attic.swallow_node == null or not attic.swallow_node.visible:
		return false
	return player.global_position.distance_to(attic.swallow_node.global_position) < 2.6


## 招呼燕子
func greet_swallow() -> void:
	if attic == null:
		return
	var result: Dictionary = attic.greet_swallow()
	var message := String(result.get("message", ""))
	if bool(result.get("ok", false)):
		if message != "":
			hud.show_toast(message, 3.4)
		audio.play_ui(1760.0)
	else:
		if message != "":
			hud.show_toast(message, 2.0)


## 站在阁楼茶几的旅行小册旁
func near_booklet() -> bool:
	if not in_attic or player == null or attic == null:
		return false
	if in_pocket():
		return false
	var anchor := attic.get_node_or_null("AtticAnchor_Booklet") as Node3D
	if anchor == null:
		return false
	return player.global_position.distance_to(anchor.global_position) < 2.2


## 云桥远端的 z（越过这里就说明人在桥那头）
func _bridge_far_z() -> float:
	if attic_worlds == null:
		return -999.0
	var anchor: Node3D = attic_worlds.prop_anchor("cloud_winch")
	if anchor == null:
		return -999.0
	return anchor.global_position.z + 2.0


## 望远镜：把相机拉到观景位置，暂时禁掉移动
func _enter_scope() -> void:
	if player == null or attic_worlds == null:
		return
	scope_return_transform = player.camera.global_transform
	scope_has_return = true
	scope_return_pitch = player.pitch if "pitch" in player else 0.0
	# 望向云海（云世界的西侧）
	var world: Node3D = attic_worlds.world_node("cloud")
	if world != null:
		var eye: Vector3 = world.to_global(Vector3(-13.0, 1.62, -33.2))
		player.global_position = eye
		player.look_at(world.to_global(Vector3(-26.0, 2.4, -40.0)), Vector3.UP)
	scope_active = true
	hud.show_toast("E / Esc 放下望远镜", 2.4)


func _exit_scope() -> void:
	scope_active = false
	if attic_worlds != null:
		attic_worlds.close_scope()
	if player != null and scope_has_return:
		player.camera.global_transform = scope_return_transform
		scope_has_return = false
	hud.show_toast("放下望远镜", 1.6)


## 口袋世界里掉出场地时的落点救援。
## 云海现在是窄栈桥，四周照原作不设围墙，掉下去不该是死局。
func _update_pocket_safety() -> void:
	if not in_pocket() or player == null or attic_worlds == null or boat_seated:
		return
	var world: Node3D = attic_worlds.world_node(pocket_key)
	if world == null:
		return
	# 场地平面在 world 原点附近；掉到 -12 以下就捞回出生点
	if player.global_position.y > world.global_position.y - 12.0:
		return
	player.global_position = attic_worlds.spawn_position(pocket_key)
	player.velocity = Vector3.ZERO
	hud.show_toast("风把你托了回来", 2.4)


## 玩家是否靠近云舟（船下时）
func _near_boat() -> bool:
	if attic_worlds == null or player == null:
		return false
	return attic_worlds.boat_distance_from(player.global_position) < 3.7


## 上船：把玩家挪到船上，相机跟着走
func _enter_boat_seat() -> void:
	if player == null or attic_worlds == null:
		return
	boat_seated = true
	player.velocity = Vector3.ZERO
	# 立刻把玩家挪到船上（云舟坐标在内容层，要走 world_point 换算）
	if attic_worlds != null and player != null and pocket_key != "":
		var flat: Vector2 = attic_worlds.boat_pos
		player.global_position = attic_worlds.world_point(pocket_key, Vector3(flat.x, 1.05, flat.y))


## 下船：把玩家放回栈桥
func _leave_boat_seat(result: Dictionary) -> void:
	boat_seated = false
	if player != null:
		var exit_pos: Vector3 = result.get("exit", Vector3.ZERO)
		var local_exit := exit_pos + Vector3(0, 1.05, 0)
		if attic_worlds != null and pocket_key != "":
			player.global_position = attic_worlds.world_point(pocket_key, local_exit)
		else:
			player.global_position = local_exit
		player.velocity = Vector3.ZERO
	hud.show_toast(String(result.get("message", "")), 3.2)
	audio.play_ui(520.0)


## 每帧：划桨推进 + 玩家跟着船走
func _update_boat(delta: float) -> void:
	if attic_worlds == null or not attic_worlds.boat_active:
		return
	var row := 0.0
	var turn := 0.0
	if Input.is_action_pressed("move_forward"):
		row += 1.0
	if Input.is_action_pressed("move_back"):
		row -= 1.0
	if Input.is_action_pressed("move_left"):
		turn -= 1.0
	if Input.is_action_pressed("move_right"):
		turn += 1.0
	attic_worlds.update_boat(row, turn, delta)
	# 玩家坐在船上：位置跟着船走。
	# 注意 boat_pos 是「世界容器」里的局部坐标，必须叠加容器原点，
	# 否则玩家会被丢到太阳系原点附近（那里是恒星，会直接判死）。
	if boat_seated and player != null and pocket_key != "":
		var flat: Vector2 = attic_worlds.boat_pos
		var local := Vector3(flat.x, 1.05 + sin(Time.get_ticks_msec() * 0.0016) * 0.05, flat.y)
		player.global_position = attic_worlds.world_point(pocket_key, local)
		player.velocity = Vector3.ZERO
		audio.set_jetpack(false)


## 站在口袋世界的某个原作道具旁：返回道具 id（空串表示没有）
func near_prop_interact() -> String:
	if attic_worlds == null or player == null or pocket_key == "":
		return ""
	return attic_worlds.near_prop(pocket_key, player.global_position)


## 用一次道具
func interact_prop(id: String) -> void:
	if attic_worlds == null:
		return
	var result: Dictionary = attic_worlds.use_prop(id)
	if not bool(result.get("ok", false)):
		var message := String(result.get("message", ""))
		if message != "":
			hud.show_toast(message, 2.2)
		return
	var text := String(result.get("message", ""))
	hud.show_toast(text, 3.6)
	# 望远镜：把相机拉到观景的位置，Esc 放下
	if id == "cloud_scope" and bool(result.get("scope", false)):
		_enter_scope()
		return
	# 风琴礁按来风换音高
	if id == "wind_organ":
		var wind := int(result.get("wind", -1))
		var pitches := [520.0, 440.0, 620.0]
		audio.play_ui(pitches[clampi(wind, 0, 2)] if wind >= 0 else 760.0)
		if bool(result.get("solved", false)) and progress != null:
			hud.show_toast(text + " · 按 H 看手册", 4.4)
	else:
		audio.play_ui(660.0)
	if progress != null:
		progress.save()


## H 键：开合旅人手册。
func toggle_handbook() -> void:
	if handbook == null:
		return
	if minigame_open:
		return
	handbook.toggle()
	handbook_open = handbook.open
	if handbook_open:
		# 手册盖住行囊，避免两层 UI 叠着
		if bag_open and bag != null:
			bag.close()
			bag_open = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 「下一件值得做的事」：照原作判定顺序给出当前该做什么。
func next_worth_doing() -> String:
	if attic_worlds == null:
		return "下一件值得做的事：回阁楼，转动黄铜天气旋钮。"
	var snow := keepsakes.has("snow")
	var cloud := keepsakes.has("cloud")
	var forest := keepsakes.has("firefly")
	var rain := keepsakes.has("alley")
	if not snow:
		return "下一件值得做的事：去雪夜小屋，让冰镜与炉火给你回应。"
	if not cloud:
		return "下一件值得做的事：去云海栈桥尽头登舟，点亮三盏浮标。"
	if not forest:
		return "下一件值得做的事：去萤火森林找到玻璃罐，收起三簇萤火。"
	if not rain:
		return "下一件值得做的事：去雨巷拨正三只檐口水兽，唤醒雨中的水钟。"
	# 四件纪念都归架之后
	var tea_step: int = attic.tea_step if attic != null else 0
	if tea_step < 3:
		return "四件纪念都归架了。回阁楼茶桌，慢慢泡完一壶茶。"
	if not dungeon_cleared():
		return "主线已经完成。阁楼的穿衣镜通向镜界回廊，那是一段自愿参加的凝光试炼。"
	# 三个小游戏都留过成绩
	var games_ok := true
	if progress != null:
		for kind in ["chime", "firefly", "rain"]:
			if int(progress.game_best.get(kind, 0)) <= 0:
				games_ok = false
	if not games_ok:
		return "主线已经完成。云海风律、森林萤火与雨巷檐雨各有一处独立小游戏，可以去留下成绩。"
	if attic_worlds != null and not attic_worlds.court_rested:
		return "主线已经完成。雨巷尽头的旧门后还藏着一座听雨院，点亮三盏听雨灯，在檐下坐一会儿。"
	var clears: int = int(progress.dungeon.get("clears", 0)) if progress != null else 0
	if clears < 1:
		return "主线已经完成。镜界东侧的镜牢门已经升起，去试试三种武器与三形态的镜心余影。"
	# 风琴礁：三种来风都听过没有
	if not wind_organ_solved():
		return "主线已经完成。云海栈桥东侧还有一座风琴礁，可以去听三种来风。"
	if progress != null and not bool(progress.dungeon.get("flawless", false)):
		return "主线已经完成。镜牢的最佳纪录已写进行囊；下一次可以试试无伤通关，结算会给出 S 评价与「毫发无伤」。"
	return "这趟旅程的主线已经完成，镜心与镜牢也都安静过了。可以继续刷镜印、填满鱼类图鉴，或只是回任意世界看看风景。"


func dungeon_cleared() -> bool:
	return has_prism_heart


func wind_organ_solved() -> bool:
	if progress == null:
		return false
	return bool(progress.wind_solved)


## B 键：开合行囊面板。
func toggle_bag() -> void:
	if bag == null or minigame_open:
		return
	if handbook_open:
		return
	bag.toggle()
	bag_open = bag.open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if bag_open else Input.MOUSE_MODE_CAPTURED
	if bag_open:
		audio.play_ui(520.0)


## 行囊 ←：成就总览 → 鱼类详情 → 总览；详情页里往前翻鱼，翻到第一条再按一次回总览。
func bag_page_prev() -> void:
	if bag == null or not bag_open:
		return
	if bag.page != "dex":
		bag.toggle_page()
		return
	if not bag.page_fish(-1):
		# 已经是第一条鱼：再按一次回到上一页（总览）
		bag.back_to_overview()


## 行囊 →：总览 → 鱼类详情 → 成就总览；详情页里往后翻鱼，翻到底再按一次进成就页。
func bag_page_next() -> void:
	if bag == null or not bag_open:
		return
	if bag.page != "dex":
		bag.toggle_page()
		return
	if not bag.page_fish(1):
		# 已经是最后一条鱼：再按一次去成就总览
		bag.toggle_page()


## 行囊 ↓：从鱼类详情 / 成就回总览
func bag_page_overview() -> void:
	if bag == null or not bag_open:
		return
	if not bag.back_to_overview():
		# 已经在总览：↓ 什么也不做
		pass


## 行囊 ↑ / ↓ 在成就页滚动（在其他页则回总览）
func bag_scroll(step: int) -> void:
	if bag == null or not bag_open:
		return
	if bag.page == "achievements":
		if not bag.scroll_achievements(step) and step < 0:
			bag.back_to_overview()
		return
	if step < 0:
		bag.back_to_overview()


## 读档后把进度还原到世界里：纪念、棱镜之心、茶席步数。
func _restore_progress() -> void:
	if progress == null:
		return
	var saved_keepsakes: Array = progress.achievements.keys()
	for key in ["snow", "cloud", "firefly", "alley"]:
		if saved_keepsakes.has("keepsake_" + key) and not keepsakes.has(key):
			keepsakes[key] = true
			if attic != null:
				attic.add_keepsake(key)
	if saved_keepsakes.has("prism_heart") and not has_prism_heart:
		has_prism_heart = true
		if attic != null:
			attic.show_prism_heart()


## 四个小世界带回的纪念：world_key -> true
var keepsakes: Dictionary = {}
## 小游戏层与「正在玩小游戏」标记
var minigames: CanvasLayer
var minigame_open := false
## 行囊：进度数据与 B 面板
var progress: Node
var bag: CanvasLayer
var bag_open := false
## 天空材质（按世界换天色用）
var sky_material: ShaderMaterial
## 旅人手册是否打开（H 键）
var handbook: CanvasLayer
var handbook_open := false
## 旅行小册（阁楼茶几上，按 E 翻开）
var travel_journal: CanvasLayer
var journal_book_open := false
## 镜牢结算画面
var run_summary: CanvasLayer
## 自动演示
var demo: CanvasLayer
var demo_active := false
## 是否坐在云舟上（相机与位置跟随船）
var boat_seated := false
## 望远镜：是否在看 / 看之前的相机变换
var scope_active := false
var scope_return_transform: Transform3D
var scope_has_return := false
var scope_return_pitch := 0.0
## 新手引导（旅人初记）
var guide_card: CanvasLayer
## 进入阁楼后延迟多久开始引导（照原作 0.9 秒）
var guide_start_timer := -1.0
## 引导进度相关的记忆：旋钮转过没有、推过门没有、进过世界没有
var guide_turned_dial := false
var guide_opened_door := false
var guide_entered_world := false
## 本次镜牢捡到的镜币（离开时结算进金币）
var dungeon_coins := 0
## 镜牢回廊状态
var dungeon_controller: Node3D
var dungeon_room := 0
var dungeon_time := 0.0
var dungeon_active := false
## 冰钓状态：-1 表示没在钓
##   phase: "" 空 / "wait" 等咬钩 / "reel" 收线中
var fishing_hole := -1
var fishing_timer := 0.0
var fishing_window := 0.0
var fishing_caught := 0
var fishing_phase := ""
var fishing_tension := 0.0
var fishing_reel := 0.0
## 鱼挣扎：正弦扰动的相位 / 频率（弧度每秒）。振幅由鱼的稀有度与收线进度决定。
var fishing_struggle_clock := 0.0
var fishing_struggle_rate := 6.0
## 咬钩那一刻就抽好这条鱼；收线挣扎强度与最终钓上的都是它
var fishing_fish_id := ""
## 是否按住 E 收线（由逐帧读输入；测试可直接赋值）
var fishing_reeling := false
var fishing_hud: CanvasLayer
var attic_worlds: Node3D


func _build_attic() -> void:
	attic = AtticScript.new()
	attic.name = "Attic"
	attic.position = ATTIC_ORIGIN
	add_child(attic)
	attic.build()
	# 四扇门与镜界回廊后面的口袋世界
	attic_worlds = AtticWorldsScript.new()
	attic_worlds.name = "AtticWorlds"
	attic_worlds.progress_ref = progress
	add_child(attic_worlds)
	attic_worlds.build()


## 手册里的「重播新手提示」
func replay_guide() -> void:
	if guide_card == null:
		return
	if handbook != null and handbook.open:
		handbook.close()
		handbook_open = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	guide_card.begin()


## 每帧：延迟开始引导 + 按玩家实际做过的事推进步骤
func _update_guide(delta: float) -> void:
	if guide_card == null:
		return
	if guide_start_timer > 0.0:
		guide_start_timer -= delta
		if guide_start_timer <= 0.0:
			guide_start_timer = -1.0
			if in_attic and not guide_card.active:
				var seen := progress != null and bool(progress.guide_done)
				if not seen:
					guide_card.begin()
	_sync_guide_step()


## 引导该走到第几步（按玩家实际做过的事推进）
func _sync_guide_step() -> void:
	if guide_card == null or not guide_card.active:
		return
	if guide_entered_world:
		guide_card.advance(3)
	elif guide_opened_door:
		guide_card.advance(2)
	elif guide_turned_dial:
		guide_card.advance(1)


func enter_attic() -> void:
	# 地面线入口：把玩家放进阁楼，暂停太阳系那套重力与光照。
	if attic == null or player == null:
		return
	in_attic = true
	in_station = false
	supernova_active = false
	state = "walk"
	if key_light != null:
		_sun_was_visible = key_light.visible
		key_light.visible = false
	player.reparent(attic, false)
	player.global_transform = Transform3D(Basis.IDENTITY, attic.to_global(Vector3(0.0, 1.05, 1.4)))
	player.velocity = Vector3.ZERO
	player.visible = true
	player.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	audio.set_jetpack(false)
	apply_sky("attic")
	# 新手引导：第一次进阁楼时排上，0.9 秒后开始（照原作）
	if guide_card != null and not guide_card.active:
		var seen := progress != null and bool(progress.guide_done)
		if not seen:
			guide_start_timer = 0.9


func leave_attic() -> void:
	# 离开阁楼：回到飞船旁边，恢复太阳系光照与轮计时。
	if not in_attic:
		return
	in_attic = false
	apply_sky("space")
	player.reparent(self, false)
	if key_light != null:
		key_light.visible = _sun_was_visible
	var landing: Vector3 = ship.global_position if ship != null else player.global_position
	player.global_transform = Transform3D(Basis.IDENTITY, landing + Vector3(0.0, 2.4, 0.0))
	player.velocity = Vector3.ZERO
	state = "walk"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func attic_up_direction() -> Vector3:
	# 口袋里的小世界都是平地，重力方向就是世界坐标的上。
	if pocket_key != "":
		return Vector3.UP
	return attic.up_direction() if attic != null else Vector3.UP


func in_pocket() -> bool:
	return pocket_key != ""


## 进入某扇门（或镜界）后面的小世界。
func enter_pocket(key: String) -> void:
	guide_entered_world = true
	if attic_worlds == null or player == null:
		return
	var world: Node3D = attic_worlds.world_node(key)
	if world == null:
		return
	if roast != null:
		roast.cancel(false)
	pocket_key = key
	in_attic = true
	state = "walk"
	apply_sky(key)
	player.reparent(world, true)
	player.global_position = attic_worlds.spawn_position(key)
	player.velocity = Vector3.ZERO
	player.visible = true
	player.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	audio.set_jetpack(false)
	audio.play_ui(560.0)
	var title: String = attic_worlds.worlds[key].get("title", key) if attic_worlds.worlds.has(key) else key
	hud.show_toast(title, 2.4)


## 从小世界回到阁楼：落在对应的门（或镜子）前。
func leave_pocket() -> void:
	if attic_worlds == null or player == null or pocket_key == "":
		return
	var key := pocket_key
	pocket_key = ""
	apply_sky("attic")
	player.reparent(attic, false)
	var back := Vector3(0.0, 1.05, 1.4)
	match key:
		"dungeon":
			# 从镜牢出来回镜界，不回阁楼
			var mirror: Node3D = attic_worlds.world_node("mirror")
			if mirror != null:
				dungeon_active = false
				pocket_key = "mirror"
				player.reparent(mirror, false)
				player.global_position = attic_worlds.spawn_position("mirror")
				player.velocity = Vector3.ZERO
				audio.play_ui(420.0)
				return
		"mirror":
			back = Vector3(-attic.ROOM_HALF_X + 1.5, 1.05, 0.9)
		_:
			for entry in attic.doors:
				if entry["key"] == key:
					var door_root: Node3D = entry["node"]
					back = attic.to_local(door_root.to_global(Vector3(0.0, 0.05, 1.15)))
					break
	player.global_position = attic.to_global(back)
	player.velocity = Vector3.ZERO
	player.visible = true
	player.camera.current = true
	audio.play_ui(420.0)


## 阁楼内：玩家站在哪扇门前（返回门的 key，没有则空串）。
func near_attic_door() -> String:
	if attic == null or player == null:
		return ""
	var position: Vector3 = player.global_position
	# 四扇门挨得很近（间距 1.4 米），必须取最近的一扇，否则站错门也会进第一扇
	var best_key := ""
	var best_distance := 2.4
	for entry in attic.doors:
		var anchor: Node3D = entry["anchor"]
		if anchor == null:
			continue
		var distance: float = position.distance_to(anchor.global_position)
		if distance < best_distance:
			best_distance = distance
			best_key = entry["key"]
	var mirror_anchor: Node3D = attic.anchors.get("AtticAnchor_Mirror")
	if mirror_anchor != null:
		var mirror_distance: float = position.distance_to(mirror_anchor.global_position)
		if mirror_distance < 2.2 and (best_key == "" or mirror_distance < best_distance):
			return "mirror"
	return best_key


## 小世界里：是否站在回程门旁边。
func near_pocket_return() -> bool:
	if pocket_key == "" or attic_worlds == null or player == null:
		return false
	var anchor = attic_worlds.return_anchor(pocket_key)
	if anchor == null:
		return false
	return player.global_position.distance_to((anchor as Node3D).global_position) < 2.4


## 小世界里：站在哪一处「小事」装置旁边（返回索引，-1 表示没有）。
func near_world_device() -> int:
	if pocket_key == "" or pocket_key == "mirror" or attic_worlds == null or player == null:
		return -1
	for i in range(3):
		var anchor = attic_worlds.device_anchor(pocket_key, i)
		if anchor == null or attic_worlds.device_done(pocket_key, i):
			continue
		if player.global_position.distance_to((anchor as Node3D).global_position) < 2.2:
			return i
	return -1


## 拨动装置；三处齐了就把纪念放上旅行架。
func activate_world_device(index: int) -> void:
	var key := pocket_key
	if key == "" or attic_worlds == null:
		return
	var result: Dictionary = attic_worlds.activate_device(key, index)
	if not bool(result.get("changed", false)):
		return
	audio.play_ui(560.0 + float(index) * 50.0 + float(int(result.get("aligned", 0))) * 40.0)
	var message: String = String(result.get("message", ""))
	var aligned: int = int(result.get("aligned", 0))
	if bool(result.get("solved", false)):
		if message != "":
			hud.show_toast(message, 3.0)
		collect_keepsake(key)
		return
	if message != "":
		hud.show_toast("%s · %d / 3" % [message, aligned], 2.6)


## 小事完成 → 把纪念放上阁楼旅行架。
func collect_keepsake(key: String) -> void:
	if keepsakes.has(key):
		return
	var titles := {
		"snow": "冰镜极光",
		"cloud": "云舟船灯",
		"firefly": "树屋萤火",
		"alley": "雨巷钟铃",
	}
	var title: String = titles.get(key, key)
	keepsakes[key] = true
	if attic != null:
		attic.add_keepsake(key)
		# 雨巷的纪念归架后，窗台会多一只避雨的燕子（照原作）
		if key == "alley" and attic.show_swallow():
			hud.show_toast("窗台上，一只避雨的燕子收起了翅膀", 4.0)
	hud.show_toast("%s · 已放上阁楼旅行架" % title, 4.2)
	audio.play_ui(720.0)
	var unlocked_lines: Array = []
	if progress != null and progress.unlock("keepsake_" + key):
		unlocked_lines.append("成就 · " + title)
	if keepsakes.size() >= 4 and progress != null and progress.unlock("keepsake_all"):
		unlocked_lines.append("成就 · 四件纪念")
	if progress != null:
		if not unlocked_lines.is_empty():
			hud.show_toast(" / ".join(unlocked_lines) + " · 按 B 查看行囊", 4.2)
		progress.save()


## 冰钓：抛竿 → 等咬钩 → 按住 E 收线（张力要待在窗口里）
func _update_fishing(delta: float) -> void:
	if fishing_hole < 0:
		return
	if fishing_phase == "wait":
		fishing_timer -= delta
		if fishing_timer <= 0.0:
			fishing_phase = "reel"
			fishing_tension = 0.3
			fishing_reel = 0.0
			fishing_struggle_clock = 0.0
			fishing_struggle_rate = randf_range(5.0, 8.0)
			# 咬钩的瞬间就把这条鱼定下来：挣扎强度要按它的稀有度算
			if progress != null:
				fishing_fish_id = progress.roll_fish()
			if fishing_hud != null:
				fishing_hud.show_hud()
			hud.show_toast("咬钩了 · 按住 E 收线，别让张力冲出去", 2.4)
		return
	if fishing_phase != "reel":
		return
	# 收线：按住 E 张力上升，松开回落
	fishing_reeling = Input.is_action_pressed("interact")
	if fishing_reeling:
		fishing_tension += 1.05 * delta
	else:
		fishing_tension -= 0.75 * delta
	# 鱼在水下挣扎：张力上叠一层起伏，越接近上岸闹得越凶
	fishing_struggle_clock += delta
	var struggle: float = fishing_struggle_amplitude()
	fishing_tension += sin(fishing_struggle_clock * fishing_struggle_rate) * struggle * delta
	fishing_tension = clampf(fishing_tension, 0.0, 1.2)
	var window_width := 0.30
	var reel_speed := 1.0
	if progress != null:
		window_width = progress.rod_tension_window()
		reel_speed = progress.rod_reel_speed()
	var low := 0.45 - window_width * 0.5
	var high := 0.45 + window_width * 0.5
	if fishing_tension > 1.0:
		# 张力冲出去：断线
		_end_fishing("张力太大 · 线断了，鱼跑了", false)
		return
	if fishing_tension >= low and fishing_tension <= high:
		fishing_reel += 0.55 * reel_speed * delta
		if fishing_reel >= 1.0:
			finish_fishing_catch()
			return


## 鱼挣扎：张力上叠加的正弦扰动幅度（每秒）。
## 越接近上岸闹得越凶；鱼越稀有越暴躁（0.0 表示不挣扎，测试里可置零）。
func fishing_struggle_amplitude() -> float:
	if fishing_fish_id == "":
		return 0.0
	var rarity := 1.0
	if progress != null:
		rarity = clampf(float(progress.fish_rarity(fishing_fish_id)) / 5.0, 0.0, 1.0)
	# 起手 0.10，满进度 0.34；稀有鱼最多再加 0.26
	var ramp: float = 0.10 + 0.24 * clampf(fishing_reel, 0.0, 1.0)
	return ramp + 0.26 * rarity


## 雪夜里站在冰洞旁，返回可下竿的洞序号（-1 表示没有）。
func near_fishing_hole() -> int:
	if pocket_key != "snow" or attic_worlds == null or player == null:
		return -1
	for i in range(3):
		if attic_worlds.hole_caught(i):
			continue
		var anchor = attic_worlds.hole_anchor(i)
		if anchor == null:
			continue
		if player.global_position.distance_to((anchor as Node3D).global_position) < 2.6:
			return i
	return -1


func start_fishing(index: int) -> void:
	fishing_hole = index
	fishing_phase = "wait"
	# 萤光饵 / 星屑饵咬钩更快（原作：咬钩也更快）
	var scale := 1.0
	if progress != null:
		scale = progress.bait_bite_scale()
	fishing_timer = randf_range(0.9, 2.2) * scale
	fishing_window = 0.0
	fishing_tension = 0.3
	fishing_reel = 0.0
	fishing_fish_id = ""
	fishing_struggle_clock = 0.0
	# 抛竿就把 HUD 亮起来：水面上的浮标按当前鱼饵换样子
	if fishing_hud != null:
		fishing_hud.show_hud()
	audio.play_ui(300.0)
	var bait_text := ""
	if progress != null and progress.bait != "plain":
		bait_text = " · %s" % progress.bait_name()
	hud.show_toast("抛竿%s · 等浮标沉下去" % bait_text, 2.8)


## 收线失败或提前收杆
func _end_fishing(message: String, _caught: bool) -> void:
	fishing_hole = -1
	fishing_phase = ""
	fishing_window = 0.0
	fishing_reel = 0.0
	fishing_tension = 0.0
	fishing_reeling = false
	fishing_fish_id = ""
	if fishing_hud != null:
		fishing_hud.hide_hud()
	hud.show_toast(message, 2.6)


func finish_fishing_catch() -> void:
	var index := fishing_hole
	fishing_hole = -1
	fishing_phase = ""
	fishing_window = 0.0
	fishing_reel = 0.0
	fishing_reeling = false
	if fishing_hud != null:
		fishing_hud.hide_hud()
	if index < 0:
		return
	var hole_name: String = attic_worlds.hole_name(index)
	var total: int = attic_worlds.catch_fish(index)
	fishing_caught = total
	audio.play_ui(720.0)
	# 用咬钩时抽好的那条；万一没抽（比如测试直接调），现抽一尾兜底
	var caught_id: String = fishing_fish_id
	if caught_id == "":
		caught_id = progress.roll_fish()
	fishing_fish_id = ""
	var info: Dictionary = progress.add_fish(caught_id)
	progress.consume_bait()
	var fish_name: String = String(info["name"])
	var unlocked_lines: Array = []
	if progress.unlock("first_fish"):
		unlocked_lines.append("成就 · 第一尾鱼")
	if total >= 3 and progress.unlock("three_fish"):
		unlocked_lines.append("成就 · 三盏冰灯")
	if total >= 3 and progress.unlock("ice-lanterns"):
		unlocked_lines.append("成就 · 三盏冰灯（三尾剧情鱼）")
	if progress.dex_count() >= 5 and progress.unlock("dex-half"):
		unlocked_lines.append("成就 · 半册鱼谱")
	if progress.dex_count() >= progress.FISH_TABLE.size() and progress.unlock("dex-all"):
		unlocked_lines.append("成就 · 湖底全书")
	if progress.fish_count() >= 10 and progress.unlock("angler"):
		unlocked_lines.append("成就 · 十尾渔获")
	if progress.coins >= 500 and progress.unlock("rich"):
		unlocked_lines.append("成就 · 口袋沉沉")
	if total >= 3:
		hud.show_toast("%s · %d 金 · 三盏冰灯同时亮起（%s）" % [fish_name, int(info["value"]), hole_name], 4.4)
	else:
		hud.show_toast("%s · %d 金 · 冰灯亮了一盏（%d / 3 · %s）" % [fish_name, int(info["value"]), total, hole_name], 3.6)
	if not unlocked_lines.is_empty():
		hud.show_toast(" / ".join(unlocked_lines) + " · 按 B 查看行囊", 4.2)
	progress.save()


## 雨巷：站在哪盏听雨灯旁边（-1 表示没有）。
func near_court_lamp() -> int:
	if pocket_key != "alley" or attic_worlds == null or player == null:
		return -1
	for i in range(3):
		if attic_worlds.court_lamp_lit(i):
			continue
		var anchor = attic_worlds.court_lamp_anchor(i)
		if anchor == null:
			continue
		if player.global_position.distance_to((anchor as Node3D).global_position) < 2.2:
			return i
	return -1


func near_court_bench() -> bool:
	if pocket_key != "alley" or attic_worlds == null or player == null:
		return false
	var anchor = attic_worlds.court_bench_anchor()
	if anchor == null:
		return false
	return player.global_position.distance_to((anchor as Node3D).global_position) < 2.2


## 镜界里：是否站在镜牢门前。
func near_dungeon_gate() -> bool:
	if pocket_key != "mirror" or attic_worlds == null or player == null:
		return false
	var anchor = attic_worlds.dungeon_gate_anchor()
	if anchor == null:
		return false
	return player.global_position.distance_to((anchor as Node3D).global_position) < 3.0


## 走进镜牢回廊。
func enter_dungeon() -> void:
	if attic_worlds == null or player == null:
		return
	var world: Node3D = attic_worlds.world_node("dungeon")
	if world == null:
		return
	pocket_key = "dungeon"
	apply_sky("dungeon")
	dungeon_active = true
	dungeon_room = 0
	dungeon_coins = 0
	dungeon_time = 0.0
	player.reparent(world, true)
	player.global_position = attic_worlds.spawn_position("dungeon")
	player.velocity = Vector3.ZERO
	player.camera.current = true
	audio.play_ui(420.0)
	if dungeon_controller != null and is_instance_valid(dungeon_controller):
		dungeon_controller.queue_free()
	dungeon_controller = DungeonScript.new()
	dungeon_controller.name = "DungeonCombat"
	world.add_child(dungeon_controller)
	dungeon_controller.start(self)
	if progress != null:
		if progress.unlock("dungeon_first"):
			hud.show_toast("成就 · 镜牢初探 · 按 B 查看行囊", 4.0)
		progress.save()
	hud.show_toast("镜牢回廊 · 往深处走，尽头是镜心内厅（%d 间）" % attic_worlds.dungeon_room_count(), 3.6)


## 逐帧：更新所在房间与用时，抵达尽头就结算。
func _update_dungeon(delta: float) -> void:
	if not dungeon_active or pocket_key != "dungeon" or player == null:
		return
	dungeon_time += delta
	var room: int = attic_worlds.dungeon_room_at(player.global_position)
	if room != dungeon_room:
		dungeon_room = room
		var kind: String = attic_worlds.dungeon_room_kind(room)
		var titles := {"combat": "镜室", "boon": "静镜室", "boss": "镜心内厅"}
		# 镜币：镜室 +12，镜心内厅 +60（原作口径）
		if kind == "combat":
			dungeon_coins += 12
		elif kind == "boss":
			dungeon_coins += 60
		hud.show_toast("第 %d 间 · %s" % [room + 1, String(titles.get(kind, kind))], 2.2)
	var finish = attic_worlds.dungeon_finish_anchor()
	if finish != null and player.global_position.distance_to((finish as Node3D).global_position) < 3.0:
		finish_dungeon(true)


## 结算镜牢：评价、最佳纪录、成就。
func finish_dungeon(cleared: bool) -> void:
	if not dungeon_active:
		return
	dungeon_active = false
	var seconds := dungeon_time
	var rooms := dungeon_room + 1
	var rank := "B"
	var rank_name := ""
	var best_text := ""
	var kills := 0
	var hits := 0
	var boons: Array = []
	if dungeon_controller != null and is_instance_valid(dungeon_controller):
		kills = int(dungeon_controller.kills)
		hits = int(dungeon_controller.hits_taken)
		boons = dungeon_controller.boons.duplicate()
	# 镜币结算：离开镜牢时存入行囊
	var coin_gain := dungeon_coins
	if progress != null and coin_gain > 0:
		progress.add_coins(coin_gain)
		progress.mirror_coins_total += coin_gain
		progress.mirror_coins = coin_gain
	dungeon_coins = 0
	if progress != null:
		var record: Dictionary = progress.record_dungeon(seconds, rooms, cleared, kills, hits, boons)
		rank = String(record["rank"])
		rank_name = String(record.get("rank_name", ""))
		if bool(record["is_best"]):
			best_text = " · 新的最好成绩"
		elif float(record["best_seconds"]) > 0.0:
			best_text = " · 最好 %s %s" % [String(record["best_rank"]), progress.time_text(float(record["best_seconds"]))]
		if cleared and progress.unlock("dungeon_clear"):
			hud.show_toast("成就 · 走到尽头 · 按 B 查看行囊", 4.0)
		if cleared and hits == 0 and progress.unlock("dungeon_flawless"):
			hud.show_toast("成就 · 毫发无伤 · 按 B 查看行囊", 4.0)
		progress.save()
	# 结算画面（照原作 run-summary 版式）
	var record_for_summary: Dictionary = {}
	if progress != null:
		record_for_summary = progress.dungeon.duplicate()
		progress.push_recent_run(seconds, rooms, cleared, kills, hits, coin_gain, rank)
		progress.save()
	if run_summary != null:
		run_summary.show_summary({
			"cleared": cleared,
			"failed": not cleared,
			"rank": rank,
			"rank_name": rank_name,
			"rank_note": String(record_for_summary.get("rank_note", "")),
			"time_text": progress.time_text(seconds) if progress != null else "00:00",
			"hits": hits,
			"kills": kills,
			"coins": coin_gain,
			"rooms": rooms,
			"boons": boons.size(),
			"depth": rooms,
			"best_rank": String(record_for_summary.get("best_rank", "")),
			"best_seconds": float(record_for_summary.get("best_seconds", 0.0)),
			"is_best": best_text.contains("新的最好成绩"),
			"has_best": float(record_for_summary.get("best_seconds", 0.0)) > 0.0,
		})
	hud.show_toast("镜牢回廊 · %s · %s %s · %s · 镜币 +%d · %d 间 · 击退 %d · 受击 %d · 镜印 %d%s" % [
		"抵达尽头" if cleared else "中途退出",
		rank, rank_name, progress.time_text(seconds) if progress != null else "",
		coin_gain, rooms, kills, hits, boons.size(), best_text], 5.6)
	audio.play_ui(780.0 if cleared else 340.0)
	if dungeon_controller != null and is_instance_valid(dungeon_controller):
		dungeon_controller.stop()
	# 回到镜界
	pocket_key = ""
	var mirror: Node3D = attic_worlds.world_node("mirror")
	if mirror != null:
		player.reparent(mirror, false)
		player.global_position = attic_worlds.spawn_position("mirror")
		pocket_key = "mirror"
		apply_sky("mirror")
	player.velocity = Vector3.ZERO


## 静镜室里：站在哪枚镜印旁（返回序号，-1 表示没有）
func near_dungeon_boon() -> int:
	if pocket_key != "dungeon" or attic_worlds == null or player == null or dungeon_controller == null:
		return -1
	if attic_worlds.dungeon_room_kind(dungeon_room) != "boon":
		return -1
	for i in range(attic_worlds.dungeon_boon_count(dungeon_room)):
		var anchor = attic_worlds.dungeon_boon_anchor(dungeon_room, i)
		if anchor == null:
			continue
		if player.global_position.distance_to((anchor as Node3D).global_position) < 2.2:
			return i
	return -1


## 取走一枚镜印
func take_dungeon_boon(index: int) -> void:
	if dungeon_controller == null or not is_instance_valid(dungeon_controller):
		return
	var info: Dictionary = dungeon_controller.pick_boon(dungeon_room, index)
	if info.is_empty():
		return
	audio.play_ui(680.0)
	hud.show_toast("镜印 · %s · %s" % [String(info["name"]), String(info["desc"])], 5.0)


## 镜牢战斗是否可用
func dungeon_combat_active() -> bool:
	return pocket_key == "dungeon" and dungeon_controller != null and is_instance_valid(dungeon_controller) and dungeon_controller.active


## 镜牢里被镜影打空生命：按失败结算并退出
func on_dungeon_defeat() -> void:
	if not dungeon_active:
		return
	hud.show_toast("镜影涌上来 · 你被推出了镜牢", 4.0)
	finish_dungeon(false)


## 镜牢里换武器
func dungeon_switch_weapon(id: String) -> void:
	if not dungeon_combat_active():
		return
	if dungeon_controller.set_weapon(id):
		audio.play_ui(620.0)


## 镜牢里闪避
func dungeon_dodge() -> void:
	if not dungeon_combat_active() or player == null:
		return
	var forward := -player.global_transform.basis.z
	if dungeon_controller.dodge(forward):
		audio.play_ui(500.0)


## 三种武器的输入入口：kind = glow / blast / special
func dungeon_attack(kind: String) -> void:
	if not dungeon_combat_active() or player == null:
		return
	var camera: Camera3D = get_active_camera()
	var aim := Vector3.FORWARD
	if camera != null:
		aim = -camera.global_transform.basis.z
	var origin: Vector3 = player.global_position + Vector3(0, 1.2, 0)
	match kind:
		"glow":
			dungeon_controller.attack_glow(aim, origin)
		"blast":
			dungeon_controller.attack_blast(origin)
		"special":
			dungeon_controller.attack_special(origin)


## 小世界里：站在哪个小游戏入口旁边（返回 chime / firefly / rain，空串表示没有）。
func near_minigame() -> String:
	if pocket_key == "" or pocket_key == "mirror" or pocket_key == "snow" or attic_worlds == null or player == null:
		return ""
	var anchor = attic_worlds.minigame_anchor(pocket_key)
	if anchor == null:
		return ""
	if player.global_position.distance_to((anchor as Node3D).global_position) < 2.8:
		return pocket_key
	return ""


## 世界 key -> 小游戏 kind：云海风琴礁=风律，萤火树根=萤火引路，雨巷水槽=檐雨合拍
const MINIGAME_KIND := {"cloud": "chime", "firefly": "firefly", "alley": "rain"}


func open_minigame(key: String) -> void:
	if minigames == null or minigame_open:
		return
	var kind: String = String(MINIGAME_KIND.get(key, key))
	if minigames.open(kind):
		minigame_open = true
		if roast != null:
			roast.cancel(false)
		audio.play_ui(640.0)


## 小游戏结束时回调：记最高分并给提示。
func on_minigame_finished(kind: String, score: int, complete: bool, message: String, previous_best: int) -> void:
	var titles := {"chime": "风律回响", "firefly": "萤火引路", "rain": "檐雨合拍"}
	var title: String = titles.get(kind, kind)
	var suffix: String = ""
	if score > previous_best and previous_best > 0:
		suffix = " · 新纪录（上次 %d）" % previous_best
	elif previous_best > 0:
		suffix = " · 最好 %d" % previous_best
	var record: Dictionary = progress.record_game(kind, score) if progress != null else {}
	if progress != null and not record.is_empty() and bool(record.get("is_best", false)) and int(record.get("best", 0)) == score:
		suffix = " · 新纪录" + ("（上次 %d）" % previous_best if previous_best > 0 else "")
	hud.show_toast("%s · %d 分%s · %s" % [title, score, suffix, message], 5.0)
	audio.play_ui(760.0 if complete else 320.0)
	if progress != null:
		if progress.games_played() >= 3 and progress.unlock("games_all"):
			hud.show_toast("成就 · 三段小游戏 · 按 B 查看行囊", 4.0)
		progress.save()


## 镜界里：是否站在棱镜之心旁边，以及能否拾取。
func near_prism_heart() -> bool:
	if pocket_key != "mirror" or attic_worlds == null or player == null:
		return false
	var anchor = attic_worlds.heart_anchor("mirror")
	if anchor == null:
		return false
	return player.global_position.distance_to((anchor as Node3D).global_position) < 2.2


func take_prism_heart() -> void:
	if has_prism_heart:
		return
	has_prism_heart = true
	var heart = attic_worlds.heart_node("mirror")
	if heart != null:
		(heart as Node3D).visible = false
	if attic != null:
		attic.show_prism_heart()
	hud.show_toast("棱镜之心 · 已带回阁楼（放在旅行架第三层）", 4.0)
	audio.play_ui(660.0)
	if progress != null:
		if progress.unlock("prism_heart"):
			hud.show_toast("成就 · 棱镜之心 · 按 B 查看行囊", 4.0)
		progress.save()


func continue_after_end() -> void:
	state = previous_state if previous_state in ["walk", "ship"] else "walk"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_active_camera().current = true


func _anomaly_by_id(id: String) -> Node3D:
	for anomaly in anomalies:
		if anomaly.anomaly_id == id:
			return anomaly
	return null


func objective_text() -> String:
	if not discovered.has("qinglan"):
		return "01 / 醒来\n\n前往附近的风车塔，对准悬浮符文并按住 F 扫描。\n\n飞船就在篝火另一边。你可以随时打开 M 星图。"
	var missing := missing_clues()
	if not missing.is_empty():
		return "02 / 收集棱镜坐标\n\n驾驶飞船探索赭崖星、沧波星和悬晶星。找到每颗星球上的古老信号。\n\n剩余坐标：%d / 3\n\n提示：Tab 选择天体，T 开启自动航行。" % missing.size()
	if not discovered.has("xuanyuan"):
		return "03 / 玄渊星\n\n三枚棱镜已经拼出完整坐标。前往星图最外侧的玄渊星，降落后扫描玄渊之核。\n\n恒星还能燃烧多久，并不是最重要的。"
	var hidden := _hidden_echo_progress()
	return "尾声 / 自由探索\n\n你已经见过黑洞前奏。洞窟、建筑内部与悬晶星的量子碎岩里，还藏着 %d / %d 处回声。\n\n现在，去任何你还想看一眼的地方。" % [hidden[0], hidden[1]]


func _save_knowledge() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"logs": discovered, "loops": loop_count}, "\t"))


func _load_knowledge() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		if data.get("logs", {}) is Dictionary:
			var logs: Dictionary = data.logs
			discovered = {}
			for key in logs:
				# 改造前的存档键带着旧天体 id（home/ember/…），加载时迁到新命名，老进度不丢。
				discovered[_migrate_legacy_knowledge_key(String(key))] = logs[key]
		loop_count = maxi(1, int(data.get("loops", 1)))


const LEGACY_PLANET_IDS := {
	"home": "qinglan", "ember": "zheya", "tide": "cangbo", "shard": "xuanjing", "eye": "xuanyuan",
}


func _migrate_legacy_knowledge_key(key: String) -> String:
	if LEGACY_PLANET_IDS.has(key):
		return LEGACY_PLANET_IDS[key]
	for old_id in LEGACY_PLANET_IDS:
		if key.begins_with(old_id + "_"):
			return String(LEGACY_PLANET_IDS[old_id]) + key.substr(old_id.length())
	return key


func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material
