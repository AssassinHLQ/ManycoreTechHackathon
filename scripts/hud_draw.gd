extends Control

var game
var font: Font


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
		var diamond := PackedVector2Array([screen + Vector2(0, -6), screen + Vector2(6, 0), screen + Vector2(0, 6), screen + Vector2(-6, 0), screen + Vector2(0, -6)])
		draw_polyline(diamond, color, 1.4, true)
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
	draw_colored_polygon(PackedVector2Array([Vector2(0, h), Vector2(0, h * 0.76), Vector2(w * 0.1, h * 0.84), Vector2(w * 0.23, h), Vector2(0, h)]), frame)
	draw_colored_polygon(PackedVector2Array([Vector2(w, h), Vector2(w, h * 0.76), Vector2(w * 0.9, h * 0.84), Vector2(w * 0.77, h), Vector2(w, h)]), frame)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.2, 0), Vector2(w * 0.13, 18), Vector2(0, 54)]), frame)
	draw_colored_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w * 0.8, 0), Vector2(w * 0.87, 18), Vector2(w, 54)]), frame)
	draw_polyline(PackedVector2Array([Vector2(0, h * 0.76), Vector2(w * 0.1, h * 0.84), Vector2(w * 0.23, h)]), trim, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(w, h * 0.76), Vector2(w * 0.9, h * 0.84), Vector2(w * 0.77, h)]), trim, 2.0, true)
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


func _draw_map() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.005, 0.011, 0.026, 0.985))
	var center: Vector2 = game.map_center_for(size)
	var map_scale: float = game.map_scale_for(size)
	var ink := Color("75d9d4")
	var soft := Color(0.55, 0.74, 0.75, 0.62)
	var faint := Color(0.28, 0.52, 0.56, 0.16)

	for i in range(5):
		var angle := float(i) * 1.7 + 0.4
		var distance := (2400.0 + float(i) * 950.0) * map_scale
		var blob := center + Vector2(cos(angle), sin(angle)) * distance
		draw_circle(blob, (520.0 + float(i) * 280.0) * map_scale, Color(0.09 + 0.028 * i, 0.2, 0.3, 0.035))

	for ring in [2000.0, 4000.0, 6000.0, 8000.0]:
		var radius: float = ring * map_scale
		if radius < 40.0:
			continue
		draw_arc(center, radius, 0, TAU, 180, Color(faint, 0.8), 1.0, true)
		draw_string(font, center + Vector2(radius * 0.7071, -radius * 0.7071) + Vector2(8, -4), _distance(ring), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(soft, 0.55))

	for i in range(game.planets.size()):
		var planet = game.planets[i]
		var orbit_color: Color = planet.accent_color
		draw_arc(center, planet.orbit_radius * map_scale, 0, TAU, 160, Color(orbit_color, 0.17), 1.0, true)
		if i == game.map_selected:
			draw_arc(center, planet.orbit_radius * map_scale, 0, TAU, 160, Color(orbit_color, 0.6), 1.8, true)
		for k in range(8):
			var angle: float = TAU * float(k) / 8.0
			var tick: Vector2 = center + Vector2(cos(angle), sin(angle)) * float(planet.orbit_radius) * map_scale
			draw_line(tick, tick + Vector2(-sin(angle), cos(angle)) * 6.0, Color(orbit_color, 0.22), 1.0, true)
		for k in range(6, 0, -1):
			var t: float = float(game.elapsed) - float(k) * 12.0
			var angle: float = float(planet.orbit_phase) + float(planet.orbit_speed) * t
			var trail: Vector2 = center + Vector2(cos(angle), sin(angle)) * float(planet.orbit_radius) * map_scale
			draw_circle(trail, 2.3, Color(orbit_color, 0.035 + 0.02 * float(6 - k)))

	draw_circle(center, 30.0, Color(1.0, 0.6, 0.28, 0.06))
	draw_circle(center, 17.0, Color(1.0, 0.7, 0.35, 0.14))
	draw_circle(center, 8.0, Color("ffc56e"))
	draw_arc(center, 18.0, 0, TAU, 32, Color(1.0, 0.72, 0.35, 0.4), 1.0, true)
	draw_string(font, center + Vector2(24, 5), "恒星", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f2c47d"))

	if game.comet != null:
		var comet_path := PackedVector2Array()
		for k in range(97):
			var angle := TAU * float(k) / 96.0
			comet_path.append(center + Vector2(cos(angle) * 6600.0, sin(angle) * 5200.0) * map_scale)
		draw_polyline(comet_path, Color(0.55, 0.8, 1.0, 0.13), 1.0, true)
		var comet_world: Vector3 = game.comet.global_position
		var comet_screen: Vector2 = center + Vector2(comet_world.x, comet_world.z) * map_scale
		var away := Vector2(comet_world.x, comet_world.z).normalized()
		draw_line(comet_screen, comet_screen - away * 22.0, Color(0.7, 0.92, 1.0, 0.38), 2.0, true)
		draw_circle(comet_screen, 2.6, Color("bfe9ff"))
		draw_string(font, comet_screen + Vector2(10, 4), "彗星", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.92, 1.0, 0.8))

	if game.station != null:
		var station_screen: Vector2 = game.map_screen_of(game.station.global_position, size)
		var station_color := Color("ffd59a")
		draw_arc(station_screen, 10.0, 0, TAU, 28, Color(station_color, 0.85), 1.4, true)
		draw_arc(station_screen, 5.0, 0, TAU, 20, Color(station_color, 0.5), 1.0, true)
		draw_circle(station_screen, 1.8, station_color)
		draw_string(font, station_screen + Vector2(14, -4), "归航站", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, station_color)
		draw_string(font, station_screen + Vector2(14, 12), "已对接" if game.ship.docked else "可对接", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(station_color, 0.7))

	for i in range(game.planets.size()):
		var planet = game.planets[i]
		var screen: Vector2 = game.map_screen_of(planet.global_position, size)
		var color: Color = planet.accent_color
		var body_radius: float = maxf(5.0, float(planet.radius) * map_scale * 0.5)
		draw_circle(screen, body_radius + 7.0, Color(color, 0.07))
		draw_circle(screen, body_radius, Color(color, 0.32))
		draw_arc(screen, body_radius + 1.5, 0, TAU, 28, Color(color, 0.92), 1.4, true)
		draw_circle(screen, 2.0, color.lightened(0.45))
		if i == game.map_selected:
			var pulse := 0.65 + sin(game.visual_time * 2.2) * 0.2
			draw_arc(screen, body_radius + 13.0, 0, TAU, 40, Color(color, pulse), 1.6, true)
			var bracket := 5.0
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var start: Vector2 = screen + corner * (body_radius + 20.0)
				draw_line(start, start - Vector2(corner.x * bracket, 0), Color(color, 0.75), 1.4, true)
				draw_line(start, start - Vector2(0, corner.y * bracket), Color(color, 0.75), 1.4, true)
		var name: String = planet.display_name
		if planet.planet_id == "xuanyuan" and game.discovered.has("xuanyuan"):
			name = "玄渊之核"
		var flip: bool = screen.x + 210.0 > size.x - 372.0
		var label_x: float = 15.0 if not flip else -190.0
		var align := HORIZONTAL_ALIGNMENT_LEFT if not flip else HORIZONTAL_ALIGNMENT_RIGHT
		var label_width: float = -1.0 if not flip else 176.0
		draw_string(font, screen + Vector2(label_x, -7), name, align, label_width, 16, Color("e1eeeb"))
		var status := ""
		if game.discovered.has(planet.planet_id):
			status = "已记录"
		elif planet.planet_id in ["zheya", "cangbo", "xuanjing"]:
			status = "未探索信号"
		elif planet.planet_id == "xuanyuan":
			status = "加密坐标"
		if status != "":
			draw_string(font, screen + Vector2(label_x, 10), status, align, label_width, 11, Color(color, 0.72))
		if planet.cave_enabled:
			var cave_found: bool = game.discovered.has(planet.planet_id + "_cave") or game.discovered.has(planet.planet_id + "_vault")
			draw_string(font, screen + Vector2(label_x, 24), "◈ 洞窟 · " + ("已勘探" if cave_found else "未勘探"), align, label_width, 11, Color(color, 0.55))
		if game.ship.target == planet:
			draw_string(font, screen + Vector2(label_x, 38), "◎ 当前目的地", align, label_width, 11, Color("f0d7a2"))

	var active: Vector3 = game.get_active_position()
	var selected = game.planets[game.map_selected]
	var player_screen := center + Vector2(active.x, active.z) * map_scale
	var selected_screen: Vector2 = game.map_screen_of(selected.global_position, size)
	for k in range(0, 18, 2):
		var t0 := float(k) / 18.0
		var t1 := float(k + 1) / 18.0
		draw_line(player_screen.lerp(selected_screen, t0), player_screen.lerp(selected_screen, t1), Color(0.55, 0.9, 0.85, 0.24), 1.0, true)
	draw_circle(player_screen, 4.0, Color.WHITE)
	draw_arc(player_screen, 9.0, game.visual_time, game.visual_time + PI * 1.5, 24, Color.WHITE, 1.5, true)
	draw_string(font, player_screen + Vector2(9, 46), "你", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	if game.state == "walk":
		var ship_world: Vector3 = game.ship.global_position
		var ship_screen := center + Vector2(ship_world.x, ship_world.z) * map_scale
		draw_rect(Rect2(ship_screen - Vector2(4, 4), Vector2(8, 8)), Color("78dce8"), false, 1.4)

	draw_string(font, Vector2(38, 52), "青岚星系 / 实时星图", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("d9eee9"))
	draw_string(font, Vector2(40, 80), "轨道投影 · 北向上 · 所有位置实时更新", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.72, 0.73))
	if game.has_touch_layer():
		draw_string(font, Vector2(40, 102), "缩放 %.1f× · 拖动平移 · 右侧按钮缩放 / 设为目标" % game.map_zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.68, 0.7))
	else:
		draw_string(font, Vector2(40, 102), "缩放 %.1f× · 拖动平移 · Q / E 选择 · T 设为目标" % game.map_zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.68, 0.7))

	var panel := Rect2(size.x - 372.0, 104.0, 336.0, 398.0)
	draw_rect(panel, Color(0.012, 0.03, 0.05, 0.94))
	draw_rect(panel, Color(0.28, 0.58, 0.58, 0.4), false, 1.0)
	var panel_x := panel.position.x + 20.0
	var panel_y := panel.position.y + 34.0
	var accent: Color = selected.accent_color
	draw_string(font, Vector2(panel_x, panel_y), selected.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, accent)
	draw_string(font, Vector2(panel_x, panel_y + 22), "天体档案", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.72, 0.72))
	draw_multiline_string(font, Vector2(panel_x, panel_y + 54), selected.description, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40.0, 14, -1, Color("b8cbc7"))
	var distance: float = active.distance_to(selected.global_position) - float(selected.radius)
	var stats := [
		["重力", "%.2f G" % (selected.gravity_strength / 20.0)],
		["半径", _distance(selected.radius)],
		["轨道", _distance(selected.orbit_radius)],
		["距离你", _distance(distance)]
	]
	for i in range(stats.size()):
		var y := panel_y + 132.0 + i * 25.0
		draw_string(font, Vector2(panel_x, y), stats[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, soft)
		draw_string(font, Vector2(panel_x + 100.0, y), stats[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("dcece7"))
	var cave_text := "无"
	if selected.cave_enabled:
		var found: bool = game.discovered.has(selected.planet_id + "_cave") or game.discovered.has(selected.planet_id + "_vault")
		cave_text = "有 · " + ("已勘探" if found else "未勘探")
	var interior_text := "无"
	if selected.planet_id == "qinglan":
		interior_text = "风车塔"
	elif selected.planet_id == "cangbo":
		interior_text = "研究站实验舱"
	if selected.planet_id == "xuanjing":
		draw_string(font, Vector2(panel_x, panel_y + 250), "量子碎岩", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, soft)
		draw_string(font, Vector2(panel_x + 100.0, panel_y + 250), "仅在被观测时静止", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffab5e"))
	draw_string(font, Vector2(panel_x, panel_y + 276), "洞窟", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, soft)
	draw_string(font, Vector2(panel_x + 100.0, panel_y + 276), cave_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("dcece7"))
	draw_string(font, Vector2(panel_x, panel_y + 300), "内部空间", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, soft)
	draw_string(font, Vector2(panel_x + 100.0, panel_y + 300), interior_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("dcece7"))
	var record_text := "已记录" if game.discovered.has(selected.planet_id) else "未记录"
	if selected.planet_id == "xuanyuan" and not game.missing_clues().is_empty():
		record_text = "加密 · 尚缺 %d 枚棱镜" % game.missing_clues().size()
	draw_string(font, Vector2(panel_x, panel_y + 330), record_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f0d7a2"))
	var action_text := ("按钮「设为目标」" if game.has_touch_layer() else "T / Enter 设为目标") if game.ship.target != selected else "◎ 已是当前目的地"
	draw_string(font, Vector2(panel_x, panel_y + 354), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.85, 0.8))

	var left := Vector2(42, size.y - 160)
	draw_string(font, left, "当前目标", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	var objective := "收集三枚棱镜坐标"
	if game.missing_clues().is_empty():
		objective = "前往最外侧的玄渊星"
	if not game.discovered.has("qinglan"):
		objective = "扫描青岚星的风车塔"
	if game.discovered.has("xuanyuan"):
		objective = "自由探索"
	draw_string(font, left + Vector2(0, 30), objective, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("e8ddbd"))
	draw_string(font, left + Vector2(0, 62), "已记录 %d / %d　·　轮回 %02d" % [game.discovered.size(), game.anomalies.size(), game.loop_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.72, 0.73))
	draw_string(font, Vector2(42, size.y - 64), "图例　◎ 行星　◈ 洞窟　▬ 轨道　✦ 彗星　■ 飞船　● 你", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.68, 0.7))
	var map_hint := "右侧按钮缩放 / 设为目标 · 关闭按钮收起 · 拖动平移" if game.has_touch_layer() else "滚轮缩放 · 拖动平移 · 点击选择 · T 设为目标 · M / Esc 返回"
	draw_string(font, Vector2(size.x - 520.0, size.y - 36), map_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.84, 0.82))


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
