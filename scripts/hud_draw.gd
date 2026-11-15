extends Control

var game
var font: Font

## 星图星场：程序化撒点，预生成一次后复用。
##
## 为什么预生成：`_draw` 每帧都跑，如果在这里调 `randf()` 星星会疯狂跳动。
## 视口尺寸变化（改分辨率 / 全屏）时才重建。
var _sky_stars: Array = []
var _sky_stars_size := Vector2.ZERO
## 星云色块：同样是预生成的椭圆簇。
var _sky_nebula: Array = []

const SKY_BUCKETS := 3

## 星图配色（照 AI 参考图 `_tools/_star_map_ref/A_holo_grid.png` 定）
const MAP_BG := Color("050a14")
const MAP_INK := Color("6fdde0")
const MAP_SOFT := Color(0.52, 0.74, 0.75, 0.62)
const MAP_GOLD := Color("ffc56e")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null or font == null:
		return
	if game.state == "supernova":
		var flash := clampf((game.supernova_timer - 0.45) / 1.6, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.72, 0.84, 1.0, flash))
		return
	if game.state == "dying":
		var heat := clampf(game.death_timer / 1.2, 0.0, 1.0)
		var fade := clampf((game.death_timer - 1.2) / 1.6, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.28, 0.045, 0.55 * heat))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.005, 0.01, 0.02, 0.92 * fade))
		return
	if game.state not in ["walk", "ship"]:
		return
	if game.solar_intensity > 0.0:
		var glow: float = game.solar_intensity
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.22, 0.02, glow * 0.14))
		var edge := Color(1.0, 0.48, 0.15, 0.35 + 0.3 * sin(game.visual_time * 3.0))
		draw_rect(Rect2(18, 18, size.x - 36, size.y - 36), edge, false, 2.0 + glow * 3.0)
	if game.map_open:
		_draw_map()
		return
	if game.paused or game.journal_open:
		return
	if game.state == "ship":
		_draw_cockpit()
		_draw_docking_marker()
	_draw_markers()
	_draw_crosshair()
	if game.roast != null and game.roast.active:
		_draw_roast()
	if game.state == "walk" and game.player.focus:
		_draw_signal_scope()
	if game.scan_target != null:
		var center := size * 0.5
		var color: Color = game.scan_target.accent_color
		draw_arc(center, 34.0, -PI * 0.5, -PI * 0.5 + TAU * game.scan_progress, 64, Color(color, 0.9), 3.0, true)
		draw_arc(center, 40.0, 0, TAU, 64, Color(color, 0.18), 1.0, true)


func _draw_docking_marker() -> void:
	if game.ship.landed or game.ship.docked: return
	var approach: Dictionary = game.ship.nearby_docking_status(2000.0)
	if approach.is_empty(): return
	var camera: Camera3D = game.get_active_camera()
	var port: Vector3 = approach.station.docking_point()
	if camera == null or camera.is_position_behind(port): return
	var screen := camera.unproject_position(port)
	screen = screen.clamp(Vector2(60, 100), size - Vector2(320, 180))
	var color := Color("78dce8")
	draw_arc(screen, 16.0, 0.0, TAU, 32, color, 2.0, true)
	draw_line(screen + Vector2(-22, 0), screen + Vector2(22, 0), color, 1.0, true)
	draw_line(screen + Vector2(0, -22), screen + Vector2(0, 22), color, 1.0, true)
	draw_string(font, screen + Vector2(26, -8), "%s · 塔顶对接口" % approach.station.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	draw_string(font, screen + Vector2(26, 15), "%d m · 140 m 内低速按 E 对接" % int(approach.distance), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


func _draw_crosshair() -> void:
	var center := size * 0.5
	var color := Color(0.82, 0.95, 0.96, 0.72)
	var gap := 5.0
	var length := 6.0
	draw_line(center + Vector2(-gap - length, 0), center + Vector2(-gap, 0), color, 1.2, true)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + length, 0), color, 1.2, true)
	draw_line(center + Vector2(0, -gap - length), center + Vector2(0, -gap), color, 1.2, true)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + length), color, 1.2, true)
	draw_circle(center, 1.4, Color("f2d59b"))


## 射线遮挡检测：从相机到目标之间有没有东西挡住。
##
## 为什么需要它（2026-11-10 用户：「这些字要能被飞船挡住」）：
##   `_draw_markers()` 画在 2D CanvasLayer 上，**永远浮在 3D 场景之上** ——
##   飞船挡在相机和星球之间时，星球标签照样画在飞船身上，看起来像贴纸。
##   Canvas 层没法参与深度测试，所以只能**手动做一次射线检测**：
##   如果相机到目标之间被几何体挡住，就不画这个标签。
##
## 用 `intersect_ray` 打在 layer 1（场景里所有实体都在 layer 1）。
## 射线终点比目标略近一点（目标本身可能也是碰撞体），避免「自己挡自己」。
func _is_occluded(camera: Camera3D, target: Vector3, self_radius: float) -> bool:
	if game == null:
		return false
	var from: Vector3 = camera.global_position
	var to: Vector3 = target
	var dist: float = from.distance_to(to)
	if dist < self_radius + 1.0:
		return false
	# 终点收回到目标表面之前，避免命中目标自身
	var dir := (to - from).normalized()
	var end: Vector3 = to - dir * (self_radius + 0.5)
	var query := PhysicsRayQueryParameters3D.create(from, end, 1)
	query.hit_from_inside = false
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _draw_markers() -> void:
	if game.in_station:
		return
	var camera: Camera3D = game.get_active_camera()
	if camera == null:
		return
	var active_position: Vector3 = game.get_active_position()
	var nearest = game.nearest_planet(active_position)
	for planet in game.planets:
		if game.state == "walk" and planet == nearest:
			continue
		var point: Vector3 = planet.global_position
		if camera.is_position_behind(point):
			continue
		var screen := camera.unproject_position(point)
		if not Rect2(Vector2(45, 75), size - Vector2(90, 170)).has_point(screen):
			continue
		# 被飞船/星球挡住就不画（用户要求：字要能被飞船挡）
		if _is_occluded(camera, point, planet.radius):
			continue
		var color: Color = planet.accent_color
		color.a = 0.82
		draw_arc(screen, 10.0, 0, TAU, 32, color, 1.3, true)
		draw_circle(screen, 2.5, color)
		var distance: float = active_position.distance_to(point) - planet.radius
		draw_string(font, screen + Vector2(17, -3), planet.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
		draw_string(font, screen + Vector2(17, 17), _distance(distance), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(color, 0.72))
	if game.comet != null:
		var comet_point: Vector3 = game.comet.global_position
		if not camera.is_position_behind(comet_point):
			var comet_screen := camera.unproject_position(comet_point)
			if Rect2(Vector2(45, 75), size - Vector2(90, 170)).has_point(comet_screen) \
					and not _is_occluded(camera, comet_point, 6.0):
				var comet_color := Color(0.72, 0.9, 1.0, 0.9)
				draw_circle(comet_screen, 2.6, comet_color)
				draw_arc(comet_screen, 9.5, 0, TAU, 24, Color(comet_color, 0.45), 1.0, true)
				draw_string(font, comet_screen + Vector2(14, -2), "曳光彗星", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, comet_color)
				draw_string(font, comet_screen + Vector2(14, 16), _distance(active_position.distance_to(comet_point)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(comet_color, 0.7))
	if game.station != null and not game.in_station:
		var station_point: Vector3 = game.station.global_position
		if not camera.is_position_behind(station_point):
			var station_screen := camera.unproject_position(station_point)
			if Rect2(Vector2(45, 75), size - Vector2(90, 170)).has_point(station_screen) \
					and not _is_occluded(camera, station_point, 60.0):
				var station_color := Color("ffd59a")
				draw_arc(station_screen, 11.0, 0, TAU, 32, Color(station_color, 0.9), 1.3, true)
				draw_arc(station_screen, 6.0, 0, TAU, 24, Color(station_color, 0.5), 1.0, true)
				draw_circle(station_screen, 2.0, station_color)
				draw_string(font, station_screen + Vector2(16, -3), "归航站", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, station_color)
				draw_string(font, station_screen + Vector2(16, 15), _distance(active_position.distance_to(station_point)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(station_color, 0.7))
	for anomaly in game.anomalies:
		if not game.route_link.can_scan(anomaly.anomaly_id):
			continue
		var point: Vector3 = anomaly.global_position + anomaly.global_transform.basis.y * 5.8
		var distance := active_position.distance_to(point)
		if distance > (520.0 if game.state == "walk" else 1200.0) or camera.is_position_behind(point):
			continue
		var screen := camera.unproject_position(point)
		if not Rect2(Vector2(30, 70), size - Vector2(60, 150)).has_point(screen):
			continue
		if _is_occluded(camera, point, 3.0):
			continue
		var color: Color = anomaly.accent_color
		var tracked: bool = game.route_link.tracked != "" and anomaly.anomaly_id == game.route_link.echo_id(game.route_link.tracked)
		if tracked:
			color = Color("ffe0a0")
		var diamond := PackedVector2Array([screen + Vector2(0, -6), screen + Vector2(6, 0), screen + Vector2(0, 6), screen + Vector2(-6, 0), screen + Vector2(0, -6)])
		draw_polyline(diamond, color, 1.4, true)
		if tracked:
			draw_string(font, screen + Vector2(12, -12), anomaly.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
		if distance < 75.0:
			draw_string(font, screen + Vector2(12, 5), _distance(distance), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(color, 0.8))
	if game.state == "walk":
		var point: Vector3 = game.ship.global_position
		if active_position.distance_to(point) > 8.0 and not camera.is_position_behind(point):
			var screen := camera.unproject_position(point)
			if Rect2(Vector2(30, 70), size - Vector2(60, 150)).has_point(screen):
				draw_rect(Rect2(screen - Vector2(5, 5), Vector2(10, 10)), Color("78dce8"), false, 1.3)
				draw_string(font, screen + Vector2(12, 5), "飞船 · " + _distance(active_position.distance_to(point)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("9cebf2"))


func _draw_cockpit() -> void:
	var w := size.x
	var h := size.y
	var frame := Color(0.015, 0.028, 0.038, 0.94)
	var trim := Color(0.27, 0.55, 0.57, 0.48)
	# ⚠ 2026-11-11 用户：「左右两侧的三角形不需要，去掉这个 ui，
	#   做 ui 应该覆盖这些文字部分」。
	#
	#   这里原来画了四个填充多边形 + 两条描边：
	#     · 左下/右下 各一个「把屏幕底部两角切掉」的三角形（0.76h → 0.84h → h）
	#     · 左上/右上 各一个小切角
	#   其中**底部那两个大三角形是错的**：右下那个覆盖 x ∈ [0.77w, w]，
	#   而飞船的速度/地表高度/目的地/驾驶模式那组读数正好落在这一带，
	#   于是三角形盖住了文字。而且它是**实心填充**，在 3D 画面上就是一块
	#   深色方块，很不像边框。
	#
	#   现在只保留顶部两个小切角（它们不压任何读数）和底部中央那条短横线。
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.2, 0), Vector2(w * 0.13, 18), Vector2(0, 54)]), frame)
	draw_colored_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w * 0.8, 0), Vector2(w * 0.87, 18), Vector2(w, 54)]), frame)
	draw_line(Vector2(w * 0.36, h - 5), Vector2(w * 0.64, h - 5), trim, 2.0, true)


func _draw_signal_scope() -> void:
	var center := size * 0.5
	var color := Color(0.43, 0.86, 0.88, 0.38)
	for radius in [105.0, 132.0, 164.0]:
		draw_arc(center, radius, 0, TAU, 96, color, 1.0, true)
	for i in range(48):
		var angle := float(i) / 48.0 * TAU
		var inner := 153.0 if i % 4 == 0 else 159.0
		draw_line(center + Vector2(cos(angle), sin(angle)) * inner, center + Vector2(cos(angle), sin(angle)) * 164.0, color, 1.0, true)
	draw_string(font, center + Vector2(-96, 196), "信 号 镜 · %.1f×　滚轮变焦" % game.player.scope_magnification(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.9, 0.9, 0.65))


## 星图（M 键）。
##
## ⚠ 2026-11-13 重做（用户：「星图现在太丑了」）：
##   旧版是「同心正圆 + 纯色圆点 + 直线标注」—— 视觉上就是几张示意图，
##   没有天文学质感。这一版照 AI 出的参考图（`_tools/_star_map_ref/`）重画：
##
##     ① 星场：三层不同亮度的星点（大/中/小），预生成，不逐帧随机
##     ② 星云：几个大尺寸柔和椭圆叠色（青蓝 + 紫 + 一点暖色）
##     ③ 中心恒星：多层同心光晕 + 十字衍射芒
##     ④ 轨道：**椭圆**（不是正圆），细青色，选中项改虚线加粗
##     ⑤ 行星：有晨昏线的球体（分层配色 + 背光侧压暗 + 大气边缘光）
##     ⑥ 选中：四角括号 + 呼吸外环
##     ⑦ 右侧天体目录：小圆缩略 + 分隔线，当前项高亮
##     ⑧ 贯穿全图的细十字准线 + 边缘刻度尺
##
##   所有坐标接口（map_center_for / map_scale_for / map_screen_of）保持不变，
##   缩放、拖动、选择逻辑完全不动 —— 这次只改「怎么画」。
func _draw_map() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MAP_BG)
	_draw_sky()
	var center: Vector2 = game.map_center_for(size)
	var scale_k: float = game.map_scale_for(size)

	_draw_compass(center)
	_draw_orbits(center, scale_k)
	_draw_sun(center)
	_draw_planets(center, scale_k)
	_draw_extras(center, scale_k)
	_draw_player(center, scale_k)
	_draw_header()
	_draw_body_list()
	_draw_info_panel()
	_draw_footer()


## ① 星场 + ② 星云。预生成一次，视口尺寸不变就一直复用。
func _draw_sky() -> void:
	if _sky_stars_size != size or _sky_stars.is_empty():
		_rebuild_sky()
	# 星云先画（在最底层）
	for n in _sky_nebula:
		var c: Vector2 = n["pos"]
		var r: Vector2 = n["rad"]
		var col: Color = n["col"]
		var rot: float = n["rot"]
		# ⚠ 不能用「同心的多层圆」——实测会画出一圈圈水波纹，非常假。
		#   改成：多个**随机偏移、大小不一**的软圆打散堆叠，
		#   边缘自然毛糙，像真实的星云团块。
		var blobs: Array = n["blobs"]
		for b in blobs:
			var off: Vector2 = b[0]
			var br: float = float(b[1])
			var ba: float = float(b[2])
			draw_set_transform(c + off.rotated(rot), rot, Vector2(1.0, r.y / maxf(r.x, 0.001)))
			# 层数多一点、每层更淡，边缘才不会露出一圈圈硬圆边
			for k in range(10, 0, -1):
				var t: float = float(k) / 10.0
				draw_circle(Vector2.ZERO, br * t,
					Color(col.r, col.g, col.b, ba * (0.03 + 0.09 * (1.0 - t))))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 星点分三档，大的先画（带一圈微光）
	for bucket in range(SKY_BUCKETS):
		for s in _sky_stars:
			if int(s[2]) != bucket:
				continue
			var p: Vector2 = s[0]
			var col: Color = s[1]
			var rad: float = s[3]
			if bucket == 0:
				draw_circle(p, rad * 2.8, Color(col.r, col.g, col.b, col.a * 0.14))
				draw_circle(p, rad * 1.6, Color(col.r, col.g, col.b, col.a * 0.3))
			draw_circle(p, rad, col)


func _rebuild_sky() -> void:
	_sky_stars.clear()
	_sky_nebula.clear()
	_sky_stars_size = size
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113
	var count: int = int(size.x * size.y / 1900.0)
	for i in range(count):
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var roll := rng.randf()
		var bucket := 2
		var rad := 0.8
		var alpha := 0.30
		if roll > 0.975:
			bucket = 0
			rad = 1.75
			alpha = 0.95
		elif roll > 0.86:
			bucket = 1
			rad = 1.15
			alpha = 0.60
		# 少量偏暖 / 偏蓝的星，纯白会显得假
		var tint := rng.randf()
		var col := Color(0.86, 0.94, 1.0, alpha)
		if tint > 0.92:
			col = Color(1.0, 0.90, 0.74, alpha)
		elif tint < 0.12:
			col = Color(0.72, 0.84, 1.0, alpha)
		_sky_stars.append([p, col, bucket, rad])
	# 星云：五块，位置避开正中央的恒星。
	# 每块由 7~9 个随机偏移的软圆组成（不是同心圆，否则会出现水波纹）。
	for ni in range(5):
		var base_pt: Vector2
		var rad_v: Vector2
		var col: Color
		var rot: float
		match ni:
			0:
				base_pt = Vector2(0.16, 0.14)
				rad_v = Vector2(380.0, 200.0)
				col = Color(0.14, 0.50, 0.56, 0.55)
				rot = -0.35
			1:
				base_pt = Vector2(0.84, 0.80)
				rad_v = Vector2(340.0, 220.0)
				col = Color(0.32, 0.18, 0.50, 0.50)
				rot = 0.50
			2:
				base_pt = Vector2(0.60, 0.10)
				rad_v = Vector2(240.0, 130.0)
				col = Color(0.18, 0.28, 0.54, 0.30)
				rot = 0.20
			3:
				base_pt = Vector2(0.10, 0.76)
				rad_v = Vector2(210.0, 150.0)
				col = Color(0.40, 0.22, 0.40, 0.24)
				rot = -0.60
			_:
				base_pt = Vector2(0.93, 0.30)
				rad_v = Vector2(170.0, 250.0)
				col = Color(0.12, 0.38, 0.48, 0.20)
				rot = 1.20
		var blobs: Array = []
		var bn: int = 12 + (ni % 4)
		for _b in range(bn):
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(0.0, 0.72) * rad_v.x
			var off := Vector2(cos(ang), sin(ang)) * dist
			var br := rad_v.x * rng.randf_range(0.20, 0.44)
			var ba := rng.randf_range(0.45, 0.9)
			blobs.append([off, br, ba])
		_sky_nebula.append({
			"pos": Vector2(base_pt.x * size.x, base_pt.y * size.y),
			"rad": rad_v,
			"col": col,
			"rot": rot,
			"blobs": blobs,
		})


## ⑧ 贯穿准线 + 边缘刻度
func _draw_compass(center: Vector2) -> void:
	var faint := Color(MAP_INK, 0.07)
	draw_line(Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.5, size.y), faint, 1.0, true)
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), faint, 1.0, true)
	var tick := Color(MAP_INK, 0.16)
	for i in range(1, 12):
		var tx: float = size.x * float(i) / 12.0
		var th: float = 8.0 if i % 3 == 0 else 4.0
		draw_line(Vector2(tx, 0), Vector2(tx, th), tick, 1.0, true)
		draw_line(Vector2(tx, size.y - th), Vector2(tx, size.y), tick, 1.0, true)
	for i in range(1, 8):
		var ty: float = size.y * float(i) / 8.0
		var tw: float = 8.0 if i % 2 == 0 else 4.0
		draw_line(Vector2(0, ty), Vector2(tw, ty), tick, 1.0, true)
		draw_line(Vector2(size.x - tw, ty), Vector2(size.x, ty), tick, 1.0, true)


## ④ 轨道：椭圆，不是正圆。
func _draw_orbits(center: Vector2, scale_k: float) -> void:
	# 距离环（很淡，作为背景网格）
	for ring in [2000.0, 4000.0, 6000.0, 8000.0]:
		var r: float = ring * scale_k
		if r < 50.0:
			continue
		draw_arc(center, r, 0, TAU, 128, Color(MAP_INK, 0.075), 1.0, true)
		draw_string(font, center + Vector2(r * 0.7071, -r * 0.7071) + Vector2(8, -4),
			_distance(ring), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(MAP_SOFT, 0.42))

	var squash := 0.74   # 短轴 / 长轴 —— 让轨道看起来是「投影视角」而不是俯视示意图
	for i in range(game.planets.size()):
		var planet = game.planets[i]
		var orbit_color: Color = planet.accent_color
		var rr: float = float(planet.orbit_radius) * scale_k
		if rr < 8.0:
			continue
		var selected: bool = i == game.map_selected
		draw_set_transform(center, 0.0, Vector2(1.0, squash))
		var segs := 120
		# 选中的那条画成虚线（每 3 段空 2 段），其余实线
		for k in range(segs):
			if selected and (k % 5) >= 2:
				continue
			var a0: float = TAU * float(k) / float(segs)
			var a1: float = TAU * float(k + 1) / float(segs)
			var p0 := Vector2(cos(a0), sin(a0)) * rr
			var p1 := Vector2(cos(a1), sin(a1)) * rr
			var w: float = 1.9 if selected else 1.0
			var al: float = 0.45 if selected else 0.14
			draw_line(p0, p1, Color(orbit_color, al), w, true)
		# 轨道上的细微刻度
		for k in range(12):
			var ang: float = TAU * float(k) / 12.0
			var base := Vector2(cos(ang), sin(ang)) * rr
			var nrm := Vector2(-sin(ang), cos(ang))
			draw_line(base - nrm * 3.5, base + nrm * 3.5, Color(orbit_color, 0.16), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## ③ 中心恒星：多层光晕 + 十字衍射芒
func _draw_sun(center: Vector2) -> void:
	var t: float = game.visual_time
	for k in range(6, 0, -1):
		var rr: float = 16.0 + float(k) * 16.0
		var a: float = 0.030 + 0.018 * float(6 - k) / 6.0
		draw_circle(center, rr, Color(1.0, 0.62, 0.24, a))
	var pulse := 0.9 + sin(t * 1.7) * 0.06
	draw_circle(center, 13.0 * pulse, Color(1.0, 0.70, 0.34, 0.55))
	draw_circle(center, 8.0 * pulse, MAP_GOLD)
	draw_circle(center, 4.2, Color(1.0, 0.97, 0.86))
	# 十字衍射芒（长短两段，越远越淡）
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		for sign_k in [-1.0, 1.0]:
			var d: Vector2 = axis * sign_k
			draw_line(center + d * 14.0, center + d * 46.0, Color(1.0, 0.86, 0.60, 0.30), 1.3, true)
			draw_line(center + d * 46.0, center + d * 62.0, Color(1.0, 0.86, 0.60, 0.10), 1.0, true)
	# 斜向短芒
	for k in range(4):
		var ang: float = PI * 0.25 + float(k) * PI * 0.5
		var d2 := Vector2(cos(ang), sin(ang))
		draw_line(center + d2 * 13.0, center + d2 * 26.0, Color(1.0, 0.86, 0.60, 0.15), 1.0, true)
	draw_string(font, center + Vector2(52, 5), "恒星", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(1.0, 0.85, 0.60, 0.8))


## ⑤ 行星：有晨昏线的球体。
##
## ⚠ 2026-11-13 修：旧实现「从大到小、由亮到暗」逐层画圆，
##   等于先铺浅色再往上盖深色 —— 结果是**中心最暗、边缘最亮**的甜甜圈，
##   完全不像球。正确做法是：先铺整个暗面底色，再在**光源方向**上
##   叠几层逐渐收小、逐渐变亮的圆，亮面才会聚在左上角。
func _draw_planet_body(at: Vector2, body_radius: float, color: Color,
		selected: bool) -> void:
	var r := maxf(body_radius, 3.5)
	# 外层大气光
	draw_circle(at, r * 2.2, Color(color, 0.05))
	draw_circle(at, r * 1.55, Color(color, 0.085))
	# ① 整个球铺暗面底色（背光侧 = 该色的深色版）
	draw_circle(at, r, Color(color.darkened(0.72), 0.97))
	# ② 亮面：从大圆往左上加，逐层收小 + 提亮
	var light_dir := Vector2(-0.52, -0.58).normalized()
	var steps := 10
	for k in range(steps, 0, -1):
		var t: float = float(k) / float(steps)          # 1.0 -> 0.1
		var off: Vector2 = light_dir * r * (1.0 - t) * 0.62
		# 越靠内越亮：t 小 = 内圈 = 亮
		var lift: float = (1.0 - t) * 0.75
		var shade: Color = color.darkened(0.55).lightened(lift * 0.55)
		draw_circle(at + off, r * (0.35 + 0.65 * t), Color(shade, 0.9))
	# ③ 高光点（很小的一块，让球看起来是圆的）
	draw_circle(at + light_dir * r * 0.42, r * 0.20,
		Color(1.0, 1.0, 1.0, 0.22))
	draw_circle(at + light_dir * r * 0.46, r * 0.10,
		Color(1.0, 1.0, 1.0, 0.30))
	# ④ 大气边缘光（一圈细亮弧，只在受光侧）
	draw_arc(at, r + 0.7, 0, TAU, 44, Color(color.lightened(0.55), 0.42), 1.3, true)
	draw_arc(at, r + 1.3, PI * 0.82, PI * 1.72, 24,
		Color(color.lightened(0.35), 0.22), 1.8, true)
	# ⑤ 晨昏线：背光侧再压一层，模拟昼夜交界
	var term := PackedVector2Array()
	for k in range(13):
		var ang: float = -PI * 0.5 + PI * float(k) / 12.0
		term.append(at + Vector2(cos(ang), sin(ang)) * r)
	term.append(at + Vector2(0, r))
	term.append(at + Vector2(0, -r))
	# 用半个圆盖住右侧
	for k in range(9):
		var t2: float = float(k) / 8.0
		draw_circle(at + Vector2(r * 0.52, 0), r * (0.86 - 0.28 * t2),
			Color(0.015, 0.025, 0.05, 0.10))
	if selected:
		# ⑥ 四角括号 + 呼吸外环
		var pulse := 0.62 + sin(game.visual_time * 2.4) * 0.22
		draw_arc(at, r + 10.0 + sin(game.visual_time * 2.4) * 1.4, 0, TAU, 48,
			Color(color.lightened(0.35), pulse), 1.6, true)
		var arm := 7.0
		var gap := r + 6.0
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var c: Vector2 = at + corner * gap
			draw_line(c, c - Vector2(corner.x * arm, 0), Color(color.lightened(0.5), 0.95), 1.6, true)
			draw_line(c, c - Vector2(0, corner.y * arm), Color(color.lightened(0.5), 0.95), 1.6, true)


## 本帧已用掉的标签矩形（用于避让重叠）。
var _label_rects: Array = []


## 给标签找一个不跟已有标签打架的垂直偏移。
##
## 星图上 26 颗星的轨道半径挨得很近，标签很容易糊成一团。
## 这里做一个很朴素的贪心避让：从基准位置开始，撞了就往下挪一行，
## 挪满 4 行还没位置就往下挪半行再试，最多试 8 次。
## 比「算法式的最优化布置」简单得多，但对这种固定布局够用。
## ⚠ 只负责算位置，不登记 —— 登记由调用方做（旧版这里也 append 了一次，
##   调用方又 append 一次，同一块标签被占了两遍）。
func _avoid_label_rect(rect: Rect2) -> Rect2:
	var step := 13.0
	var out := rect
	for attempt in range(9):
		var hit := false
		for r in _label_rects:
			if (r as Rect2).intersects(out):
				hit = true
				break
		if not hit:
			break
		out.position.y += step if attempt < 4 else step * 0.5
	return out


func _draw_planets(center: Vector2, _scale_k: float) -> void:
	_label_rects.clear()
	# 右侧信息面板先占位，标签不许压上去
	_label_rects.append(Rect2(size.x - 372.0, size.y - 404.0, 336.0, 276.0))

	# 真实半径归一化：大的行星在图上明显更大，不再清一色被 clamp 成 22 px
	var r_lo := INF
	var r_hi := -INF
	for p in game.planets:
		r_lo = minf(r_lo, float(p.radius))
		r_hi = maxf(r_hi, float(p.radius))

	# 远（外圈）先画、近（内圈）后画；选中项最后画在最上层
	var order: Array = []
	for i in range(game.planets.size()):
		order.append(i)
	order.sort_custom(func(a, b):
		return float(game.planets[a].orbit_radius) > float(game.planets[b].orbit_radius)
	)
	var items: Array = []
	var sel_item: Dictionary = {}
	for idx in order:
		var it := _map_planet_item(int(idx), r_lo, r_hi)
		if it["selected"]:
			sel_item = it
		else:
			items.append(it)
	if not sel_item.is_empty():
		items.append(sel_item)

	# 第一遍排标签：选中项优先占位，其余按远→近依次避让
	if not sel_item.is_empty():
		_layout_label(sel_item)
	for it in items:
		if not it["selected"]:
			_layout_label(it)

	# 第二遍按顺序绘制
	for it in items:
		var planet = it["planet"]
		var scr: Vector2 = it["screen"]
		var color: Color = it["color"]
		var br: float = it["body_radius"]
		draw_circle(scr, br * 3.2, Color(color, 0.045))
		_draw_planet_body(scr, br, color, bool(it["selected"]))
		_draw_label_lines(it)


## 一颗行星在星图上的绘制数据（含标签排版结果）。
func _map_planet_item(i: int, r_lo: float, r_hi: float) -> Dictionary:
	var planet = game.planets[i]
	var t: float = 0.5
	if r_hi - r_lo > 1.0:
		t = (float(planet.radius) - r_lo) / (r_hi - r_lo)
	var body_radius: float = lerpf(8.0, 30.0, sqrt(clampf(t, 0.0, 1.0)))
	var item := {
		"planet": planet,
		"screen": game.map_screen_of(planet.global_position, size),
		"color": planet.accent_color,
		"body_radius": body_radius,
		"selected": i == game.map_selected,
	}
	item["label"] = _planet_label_layout(item)
	return item


## 计算标签块（名字 + 状态行）与基准位置；避让在 _layout_label 里做。
func _planet_label_layout(it: Dictionary) -> Dictionary:
	var planet = it["planet"]
	var screen: Vector2 = it["screen"]
	var body_radius: float = it["body_radius"]
	var color: Color = it["color"]
	var selected: bool = it["selected"]
	var title: String = planet.display_name
	if planet.planet_id == "xuanyuan" and game.discovered.has("xuanyuan"):
		title = "玄渊之核"
	var lines: Array = []
	lines.append([title, 15, Color(0.90, 0.96, 0.95) if selected else Color(0.70, 0.83, 0.83, 0.92)])
	var status := ""
	if game.discovered.has(planet.planet_id):
		status = "已记录"
	elif planet.planet_id in ["zheya", "cangbo", "xuanjing"]:
		status = "未探索信号"
	elif planet.planet_id == "xuanyuan":
		status = "加密坐标"
	if status != "":
		lines.append([status, 10, Color(color, 0.68)])
	if planet.cave_enabled:
		var cave_found: bool = game.discovered.has(planet.planet_id + "_cave") \
			or game.discovered.has(planet.planet_id + "_vault")
		lines.append(["◈ 洞窟 · " + ("已勘探" if cave_found else "未勘探"), 10, Color(color, 0.5)])
	if game.ship.target == planet:
		lines.append(["◎ 当前目的地", 10, Color(MAP_GOLD, 0.9)])

	# 靠近右侧面板就往左翻；选中项多留一点距离，别压住飞船/航道图标
	var flip: bool = screen.x + 210.0 > size.x - 372.0
	var pad: float = 26.0 if selected else 12.0
	var label_x: float = body_radius + pad if not flip else -(body_radius + pad)
	var base := screen + Vector2(label_x, -2)
	var width := 0.0
	for ln in lines:
		width = maxf(width, _text_width(String(ln[0]), int(ln[1])))
	var height: float = 17.0 + 12.0 * float(lines.size() - 1)
	return {
		"lines": lines,
		"flip": flip,
		"base": base,
		"rect": Rect2(
			Vector2(base.x if not flip else base.x - width, base.y - 13.0),
			Vector2(width + 2.0, height + 4.0)),
		"align": HORIZONTAL_ALIGNMENT_LEFT if not flip else HORIZONTAL_ALIGNMENT_RIGHT,
		"width": -1.0 if not flip else width,
	}


## 标签避让 + 登记占用。
func _layout_label(it: Dictionary) -> void:
	var label: Dictionary = it["label"]
	var rect: Rect2 = label["rect"]
	var fitted := _avoid_label_rect(rect)
	label["base"] = (label["base"] as Vector2) + Vector2(0.0, fitted.position.y - rect.position.y)
	label["rect"] = fitted
	_label_rects.append(fitted)


func _draw_label_lines(it: Dictionary) -> void:
	var label: Dictionary = it["label"]
	var base: Vector2 = label["base"]
	var align: int = label["align"]
	var wrap: float = label["width"]
	var dy := 0.0
	for ln in label["lines"]:
		draw_string(font, base + Vector2(0, dy), String(ln[0]), align, wrap, int(ln[1]), ln[2])
		dy += 15.0 if int(ln[1]) >= 13 else 12.0


func _text_width(text: String, font_size: int) -> float:
	if font == null:
		return float(text.length()) * float(font_size) * 0.6
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## 彗星、归航站
func _draw_extras(center: Vector2, scale_k: float) -> void:
	if game.comet != null:
		var path := PackedVector2Array()
		for k in range(129):
			var angle := TAU * float(k) / 128.0
			path.append(Vector2(cos(angle) * 6600.0, sin(angle) * 5200.0) * scale_k)
		draw_set_transform(center, 0.0, Vector2(1.0, 0.74))
		draw_polyline(path, Color(0.55, 0.80, 1.0, 0.10), 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var comet_world: Vector3 = game.comet.global_position
		var comet_screen: Vector2 = center + Vector2(comet_world.x, comet_world.z) * scale_k
		var away := Vector2(comet_world.x, comet_world.z).normalized()
		# 彗尾：由亮到暗的多段
		for k in range(6):
			var t0: float = float(k) / 6.0
			var t1: float = float(k + 1) / 6.0
			draw_line(comet_screen - away * (6.0 + t0 * 26.0),
				comet_screen - away * (6.0 + t1 * 26.0),
				Color(0.72, 0.92, 1.0, 0.42 * (1.0 - t0)), 1.8 - t0 * 1.2, true)
		draw_circle(comet_screen, 3.2, Color(0.02, 0.05, 0.10, 0.95))
		draw_circle(comet_screen, 2.4, Color("cfefff"))
		draw_circle(comet_screen, 1.0, Color.WHITE)
		draw_string(font, comet_screen + Vector2(12, 4), "曳光彗星",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.92, 1.0, 0.82))

	if game.station != null:
		var station_screen: Vector2 = game.map_screen_of(game.station.global_position, size)
		var sc := Color("ffd59a")
		var pulse := 0.5 + sin(game.visual_time * 1.9) * 0.2
		draw_arc(station_screen, 12.0, 0, TAU, 32, Color(sc, pulse), 1.2, true)
		draw_arc(station_screen, 6.5, 0, TAU, 24, Color(sc, 0.55), 1.0, true)
		# 四个方向的短刻度，像空间站的对接口
		for k in range(4):
			var ang: float = TAU * float(k) / 4.0
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(station_screen + dir * 6.5, station_screen + dir * 10.0, Color(sc, 0.85), 1.4, true)
		draw_circle(station_screen, 2.0, sc)
		draw_string(font, station_screen + Vector2(15, -3), "归航站",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sc)
		draw_string(font, station_screen + Vector2(15, 11),
			"已对接" if game.ship.docked else "可对接", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(sc, 0.68))


## 玩家位置 + 到目标的虚线
func _draw_player(center: Vector2, scale_k: float) -> void:
	var active: Vector3 = game.get_active_position()
	var player_screen: Vector2 = center + Vector2(active.x, active.z) * scale_k
	var selected = game.planets[game.map_selected]
	var selected_screen: Vector2 = game.map_screen_of(selected.global_position, size)
	for k in range(0, 26, 2):
		var t0 := float(k) / 26.0
		var t1 := float(k + 1) / 26.0
		draw_line(player_screen.lerp(selected_screen, t0), player_screen.lerp(selected_screen, t1),
			Color(MAP_INK, 0.28), 1.0, true)
	# 玩家标记：白点 + 旋转弧
	draw_circle(player_screen, 7.0, Color(1, 1, 1, 0.10))
	draw_circle(player_screen, 3.4, Color.WHITE)
	draw_arc(player_screen, 9.0, game.visual_time * 1.6, game.visual_time * 1.6 + PI * 1.4, 28,
		Color(1, 1, 1, 0.72), 1.4, true)
	draw_string(font, player_screen + Vector2(13, 5), "你", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(1, 1, 1, 0.88))
	if game.state == "walk":
		var ship_world: Vector3 = game.ship.global_position
		var ship_screen: Vector2 = center + Vector2(ship_world.x, ship_world.z) * scale_k
		draw_rect(Rect2(ship_screen - Vector2(4.5, 4.5), Vector2(9, 9)),
			Color("78dce8", 0.9), false, 1.4)
		draw_circle(ship_screen, 1.2, Color("9cebf2"))


func _draw_header() -> void:
	draw_string(font, Vector2(40, 50), "青岚星系", HORIZONTAL_ALIGNMENT_LEFT, -1, 27,
		Color(0.90, 0.95, 0.93))
	draw_string(font, Vector2(40, 74), "S T A R   C H A R T", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(MAP_INK, 0.5))
	draw_line(Vector2(40, 84), Vector2(216, 84), Color(MAP_INK, 0.28), 1.0, true)
	draw_string(font, Vector2(40, 102), "轨道投影 · 北向上 · 实时更新",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.72, 0.73, 0.9))
	if game.has_touch_layer():
		draw_string(font, Vector2(40, 122), "缩放 %.1f× · 拖动平移 · 右侧按钮缩放 / 设为目标" % game.map_zoom,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.68, 0.7, 0.8))
	else:
		draw_string(font, Vector2(40, 122), "缩放 %.1f× · 拖动平移 · Q / E 选择 · T 设为目标" % game.map_zoom,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.68, 0.7, 0.8))


## ⑦ 右侧天体目录：小圆缩略 + 分隔线，当前项高亮
func _draw_body_list() -> void:
	var row_h := 44.0
	var panel_w := 196.0
	var list_x := size.x - panel_w - 20.0
	var list_y := 108.0
	var count: int = game.planets.size()
	var total_h := row_h * float(count) + 42.0
	if list_y + total_h > size.y - 10.0:
		return   # 屏幕太矮就不画，避免压到信息面板
	draw_rect(Rect2(list_x, list_y, panel_w, total_h), Color(0.012, 0.030, 0.046, 0.90))
	draw_rect(Rect2(list_x, list_y, panel_w, total_h), Color(MAP_INK, 0.20), false, 1.0)
	draw_rect(Rect2(list_x, list_y, panel_w, 34.0), Color(MAP_INK, 0.07))
	draw_string(font, Vector2(list_x + 14, list_y + 22), "天 体 目 录",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(MAP_INK, 0.85))
	draw_string(font, Vector2(list_x + panel_w - 34, list_y + 22), "%d" % count,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(MAP_INK, 0.5))
	draw_line(Vector2(list_x, list_y + 34), Vector2(list_x + panel_w, list_y + 34),
		Color(MAP_INK, 0.22), 1.0, true)

	for i in range(count):
		var planet = game.planets[i]
		var ry: float = list_y + 40.0 + row_h * float(i)
		var selected: bool = i == game.map_selected
		if selected:
			draw_rect(Rect2(list_x + 2, ry - 1, panel_w - 4, row_h - 4),
				Color(MAP_INK, 0.11))
			draw_rect(Rect2(list_x + 2, ry - 1, 2.5, row_h - 4), Color(planet.accent_color, 0.95))
		var thumb_c := Vector2(list_x + 24.0, ry + row_h * 0.5 - 6.0)
		_draw_planet_body(thumb_c, 6.0, planet.accent_color, false)
		var tx := list_x + 42.0
		var found: bool = game.discovered.has(planet.planet_id)
		var nm: String = planet.display_name if found else "未知天体"
		if planet.planet_id == "xuanyuan" and found:
			nm = "玄渊之核"
		draw_string(font, Vector2(tx, ry + 16.0), nm, HORIZONTAL_ALIGNMENT_LEFT, panel_w - 60.0, 13,
			Color(0.88, 0.95, 0.94) if found else Color(0.46, 0.55, 0.58, 0.85))
		var sub := "信号未解析"
		if found:
			sub = "%.2f G　·　%s" % [float(planet.gravity_strength) / 20.0, _distance(float(planet.radius))]
		draw_string(font, Vector2(tx, ry + 30.0), sub, HORIZONTAL_ALIGNMENT_LEFT, panel_w - 60.0, 10,
			Color(0.52, 0.68, 0.70, 0.8))
		if i < count - 1:
			draw_line(Vector2(list_x + 10, ry + row_h - 4.0),
				Vector2(list_x + panel_w - 10, ry + row_h - 4.0), Color(MAP_INK, 0.10), 1.0, true)


func _draw_info_panel() -> void:
	var panel := Rect2(size.x - 372.0, size.y - 404.0, 336.0, 276.0)
	draw_rect(panel, Color(0.012, 0.030, 0.046, 0.94))
	draw_rect(panel, Color(MAP_INK, 0.22), false, 1.0)
	# 左上角装饰切角
	draw_line(panel.position, panel.position + Vector2(18, 0), Color(MAP_INK, 0.75), 1.6, true)
	draw_line(panel.position, panel.position + Vector2(0, 18), Color(MAP_INK, 0.75), 1.6, true)

	var selected = game.planets[game.map_selected]
	var accent: Color = selected.accent_color
	var px := panel.position.x + 20.0
	var py := panel.position.y + 30.0
	var active: Vector3 = game.get_active_position()
	draw_string(font, Vector2(px, py), selected.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, accent)
	draw_string(font, Vector2(px, py + 18), "天 体 档 案", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(MAP_INK, 0.5))
	draw_multiline_string(font, Vector2(px, py + 46), selected.description,
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40.0, 13, -1, Color(0.72, 0.80, 0.79))

	var dist_v: float = active.distance_to(selected.global_position) - float(selected.radius)
	var stats := [
		["重力", "%.2f G" % (selected.gravity_strength / 20.0)],
		["半径", _distance(selected.radius)],
		["轨道", _distance(selected.orbit_radius)],
		["距离你", _distance(dist_v)]
	]
	for i in range(stats.size()):
		var y := py + 114.0 + i * 22.0
		draw_line(Vector2(px, y + 6), Vector2(px + panel.size.x - 40.0, y + 6),
			Color(MAP_INK, 0.07), 1.0, true)
		draw_string(font, Vector2(px, y), stats[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.52, 0.70, 0.71))
		draw_string(font, Vector2(px + 92.0, y), stats[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.86, 0.92, 0.89))

	var cave_text := "无"
	if selected.cave_enabled:
		var found: bool = game.discovered.has(selected.planet_id + "_cave") \
			or game.discovered.has(selected.planet_id + "_vault")
		cave_text = "有 · " + ("已勘探" if found else "未勘探")
	draw_string(font, Vector2(px, py + 212.0), "洞窟", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.52, 0.70, 0.71))
	draw_string(font, Vector2(px + 92.0, py + 212.0), cave_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.86, 0.92, 0.89))

	var record_text := "已记录" if game.discovered.has(selected.planet_id) else "未记录"
	if selected.planet_id == "xuanyuan" and not game.missing_clues().is_empty():
		record_text = "加密 · 尚缺 %d 枚棱镜" % game.missing_clues().size()
	draw_string(font, Vector2(px, py + 236.0), record_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(MAP_GOLD, 0.92))
	var action_text := ("按钮「设为目标」" if game.has_touch_layer() else "T / Enter 设为目标") \
		if game.ship.target != selected else "◎ 已是当前目的地"
	draw_string(font, Vector2(px, py + 258.0), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(MAP_INK, 0.65))


func _draw_footer() -> void:
	var left := Vector2(42, size.y - 148)
	draw_string(font, left, "当前目标", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MAP_INK)
	var objective := "收集三枚棱镜坐标"
	if game.missing_clues().is_empty():
		objective = "前往最外侧的玄渊星"
	if not game.discovered.has("qinglan"):
		objective = "扫描青岚星的风车塔"
	if game.discovered.has("xuanyuan"):
		objective = "自由探索"
	draw_string(font, left + Vector2(0, 28), objective, HORIZONTAL_ALIGNMENT_LEFT, -1, 19,
		Color(0.90, 0.86, 0.74))
	draw_string(font, left + Vector2(0, 56),
		"已记录 %d / %d　·　轮回 %02d" % [game.discovered.size(), game.anomalies.size(), game.loop_count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.72, 0.73, 0.85))

	# 图例：图标 + 文字（照参考图左下角那块）
	var lx := 42.0
	var ly := size.y - 60.0
	draw_rect(Rect2(lx - 10, ly - 16, 430.0, 30.0), Color(0.012, 0.030, 0.046, 0.7))
	draw_rect(Rect2(lx - 10, ly - 16, 430.0, 30.0), Color(MAP_INK, 0.14), false, 1.0)
	var legend_col := Color(0.62, 0.78, 0.78, 0.85)
	draw_circle(Vector2(lx + 4, ly), 4.0, Color(0.75, 0.88, 0.87))
	draw_string(font, Vector2(lx + 14, ly + 4), "行星", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, legend_col)
	var dx := lx + 62.0
	var dia := PackedVector2Array([Vector2(dx + 4, ly - 5), Vector2(dx + 8, ly),
		Vector2(dx + 4, ly + 5), Vector2(dx, ly), Vector2(dx + 4, ly - 5)])
	draw_polyline(dia, Color(0.85, 0.72, 0.45), 1.2, true)
	draw_string(font, Vector2(dx + 14, ly + 4), "洞窟", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, legend_col)
	var ox := lx + 122.0
	draw_line(Vector2(ox, ly), Vector2(ox + 12, ly), Color(MAP_INK, 0.75), 1.4, true)
	draw_string(font, Vector2(ox + 18, ly + 4), "轨道", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, legend_col)
	var cx := lx + 180.0
	draw_circle(Vector2(cx + 5, ly), 2.4, Color(0.80, 0.94, 1.0))
	draw_line(Vector2(cx + 7, ly), Vector2(cx + 15, ly), Color(0.80, 0.94, 1.0, 0.5), 1.2, true)
	draw_string(font, Vector2(cx + 20, ly + 4), "彗星", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, legend_col)
	var sx := lx + 240.0
	draw_rect(Rect2(sx, ly - 4, 8, 8), Color("78dce8", 0.9), false, 1.3)
	draw_string(font, Vector2(sx + 14, ly + 4), "飞船", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, legend_col)
	var px2 := lx + 296.0
	draw_circle(Vector2(px2 + 4, ly), 3.2, Color.WHITE)
	draw_string(font, Vector2(px2 + 14, ly + 4), "你", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, legend_col)

	var map_hint := "右侧按钮缩放 / 设为目标 · 关闭按钮收起 · 拖动平移" \
		if game.has_touch_layer() else "滚轮缩放 · 拖动平移 · 点击选择 · T 设为目标 · M / Esc 返回"
	draw_string(font, Vector2(size.x - 520.0, size.y - 36), map_hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.62, 0.82, 0.80, 0.9))


func _distance(value: float) -> String:
	if value >= 1000.0:
		return "%.1f km" % (value / 1000.0)
	return "%d m" % maxi(0, int(value))


func _draw_roast() -> void:
	var roast = game.roast
	var p := clampf(roast.progress, 0.0, 1.25)
	var width := 300.0
	var origin := Vector2((size.x - width) * 0.5, size.y - 196.0)
	draw_rect(Rect2(origin - Vector2(18, 42), Vector2(width + 36, 88)), Color(0.008, 0.02, 0.035, 0.74))
	draw_rect(Rect2(origin - Vector2(18, 42), Vector2(width + 36, 88)), Color(0.3, 0.56, 0.54, 0.35), false, 1.0)
	var bands := [
		[0.0, 0.35, Color("e8dcc4")],
		[0.35, 0.62, Color("d9a45f")],
		[0.62, 0.86, Color("c88a3c")],
		[0.86, 1.0, Color("8a5426")],
		[1.0, 1.25, Color("2c2019")]
	]
	for band in bands:
		var x0: float = origin.x + width * float(band[0]) / 1.25
		var x1: float = origin.x + width * float(band[1]) / 1.25
		draw_rect(Rect2(x0, origin.y, x1 - x0, 12.0), Color(band[2], 0.9))
	var perfect_x0 := origin.x + width * 0.62 / 1.25
	var perfect_x1 := origin.x + width * 0.86 / 1.25
	draw_rect(Rect2(perfect_x0, origin.y - 4, perfect_x1 - perfect_x0, 20.0), Color("9be8a8"), false, 2.0)
	var marker_x := origin.x + width * p / 1.25
	draw_line(Vector2(marker_x, origin.y - 8), Vector2(marker_x, origin.y + 20), Color(1.0, 0.96, 0.84, 0.95), 2.0, true)
	draw_circle(Vector2(marker_x, origin.y - 10), 3.2, Color("fff4d0"))
	var perfect: bool = p >= 0.62 and p < 0.86
	var title_color := Color("b8e8b0") if perfect else Color("f0d7a2")
	draw_string(font, origin + Vector2(0, -14), "烤棉花糖　·　" + roast.quality_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, title_color)
	draw_string(font, Vector2(origin.x + width, origin.y + 33), "E 取下", HORIZONTAL_ALIGNMENT_RIGHT, -1, 13, Color(0.68, 0.82, 0.8))
	if perfect:
		draw_string(font, origin + Vector2(0, 33), "现在取回补得最多", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b8e8b0"))
	else:
		draw_string(font, origin + Vector2(0, 33), "别让边缘烧黑", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.62, 0.78, 0.76))
