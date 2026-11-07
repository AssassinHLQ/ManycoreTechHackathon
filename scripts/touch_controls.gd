extends CanvasLayer

## 触屏操作层：左摇杆 + 右侧圆钮 + 空白拖动视角。仅在触屏设备或 --touch 下启用。

class TouchCanvas extends Control:
	var host
	func _draw() -> void:
		if host != null:
			host.draw_overlay(self)


var game
var enabled := false
var overlay: TouchCanvas
var font: Font
var portrait := false
var current_mode := ""
var layout_size := Vector2.ZERO
var buttons: Array = []
var pressed_buttons: Dictionary = {}
var touches: Dictionary = {}
var joystick_touch := -1
var joystick_center := Vector2.ZERO
var joystick_vector := Vector2.ZERO
var look_last := Vector2.ZERO
var touch_holds: Dictionary = {}

const JOYSTICK_RADIUS := 118.0
const KNOB_RADIUS := 50.0
const DEADZONE := 0.16
const MOVE_ACTIONS := ["move_forward", "move_back", "move_left", "move_right"]


func _ready() -> void:
	layer = 11
	font = _load_font()
	enabled = _touch_available()
	overlay = TouchCanvas.new()
	overlay.host = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(enabled)


func _load_font() -> Font:
	var embedded: Font = load("res://assets/ui_font.ttf")
	if embedded != null:
		var symbols: Font = load("res://assets/ui_symbols.ttf")
		if symbols != null:
			embedded.set("fallbacks", [symbols])
		return embedded
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC", "sans-serif"])
	return system_font


func _touch_available() -> bool:
	if OS.has_feature("mobile"):
		return true
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true))
		if query.contains("touch=1"):
			return true
	if DisplayServer.is_touchscreen_available():
		return true
	return OS.get_cmdline_args().has("--touch")


func is_active() -> bool:
	return enabled and visible and not portrait and game != null and game.state in ["walk", "ship"] and not game.map_open


func has_touch_layer() -> bool:
	return enabled and not portrait and game != null and game.state in ["walk", "ship"]


func _process(_delta: float) -> void:
	if not enabled or game == null or overlay == null:
		return
	var window := DisplayServer.window_get_size()
	portrait = window.x < window.y
	if portrait:
		visible = true
		_release_all()
		overlay.queue_redraw()
		return
	var playing: bool = game.state in ["walk", "ship"] and not game.paused and not game.journal_open and not game.supernova_active
	if not playing:
		visible = false
		_release_all()
		return
	visible = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var mode: String = "map" if game.map_open else str(game.state)
	if game.state == "ship" and game.ship.landed:
		mode += ":landed"
	elif game.state == "ship" and game.ship.docked:
		mode += ":docked"
	if mode != current_mode or overlay.size != layout_size:
		_release_all()
		current_mode = mode
		layout_size = overlay.size
		_build_buttons()
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not visible or portrait or game == null:
		return
	if event is InputEventScreenTouch:
		var handled := false
		if event.pressed:
			handled = _touch_start(event.index, event.position)
		else:
			handled = _touch_end(event.index)
		if handled:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if _touch_drag(event.index, event.position):
			get_viewport().set_input_as_handled()


func _touch_start(index: int, position: Vector2) -> bool:
	if game.map_open:
		for button in buttons:
			if position.distance_to(button.pos) <= button.radius * 1.15:
				touches[index] = {"kind": "button", "id": button.id}
				pressed_buttons[button.id] = true
				_press_button(button)
				return true
		touches[index] = {"kind": "map", "last": position, "moved": 0.0}
		return true
	for button in buttons:
		if position.distance_to(button.pos) <= button.radius * 1.15:
			touches[index] = {"kind": "button", "id": button.id}
			pressed_buttons[button.id] = true
			_press_button(button)
			return true
	if position.distance_to(joystick_center) <= JOYSTICK_RADIUS * 1.35:
		touches[index] = {"kind": "joystick"}
		joystick_touch = index
		_update_joystick(position)
		return true
	touches[index] = {"kind": "look"}
	look_last = position
	return true


func _touch_drag(index: int, position: Vector2) -> bool:
	if not touches.has(index):
		return false
	var role: Dictionary = touches[index]
	match role.kind:
		"joystick":
			_update_joystick(position)
			return true
		"look":
			var delta := position - look_last
			look_last = position
			_apply_look(delta)
			return true
		"button":
			return true
		"map":
			var delta: Vector2 = position - role.last
			role.last = position
			role.moved += delta.length()
			game.map_pan += delta
			return true
	return false


func _touch_end(index: int) -> bool:
	if not touches.has(index):
		return false
	var role: Dictionary = touches[index]
	if role.kind == "joystick":
		joystick_vector = Vector2.ZERO
		_apply_move_actions()
		joystick_touch = -1
	elif role.kind == "button":
		_release_button(role.id)
	elif role.kind == "map":
		if role.moved < 8.0:
			game._select_map_body(role.last, game.get_viewport().get_visible_rect().size)
	touches.erase(index)
	return true


func _update_joystick(position: Vector2) -> void:
	var offset := position - joystick_center
	var distance := offset.length()
	if distance < 1.0:
		joystick_vector = Vector2.ZERO
	else:
		var strength := clampf(distance / JOYSTICK_RADIUS, 0.0, 1.0)
		if strength < DEADZONE:
			joystick_vector = Vector2.ZERO
		else:
			joystick_vector = offset / distance * ((strength - DEADZONE) / (1.0 - DEADZONE))
	_apply_move_actions()


func _apply_move_actions() -> void:
	_set_action("move_forward", maxf(-joystick_vector.y, 0.0))
	_set_action("move_back", maxf(joystick_vector.y, 0.0))
	_set_action("move_left", maxf(-joystick_vector.x, 0.0))
	_set_action("move_right", maxf(joystick_vector.x, 0.0))


func _set_action(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _apply_look(delta: Vector2) -> void:
	if game.state == "ship":
		game.ship.apply_look(delta)
	elif game.state == "walk":
		game.player.apply_look(delta)


func _press_button(button: Dictionary) -> void:
	match button.action:
		"jump":
			_pulse_action("jump")
		"jetpack":
			_hold_action("jetpack")
		"scan":
			_hold_action("scan")
		"up":
			_hold_action("jump")
		"down":
			_hold_action("thrust_down")
		"boost":
			_hold_action("jetpack")
		"brake":
			_hold_action("brake")
		"interact":
			game._interact()
		"lamp":
			game.player.toggle_lamp()
		"autopilot":
			game.ship.autopilot = not game.ship.autopilot
			if game.ship.autopilot and game.ship.target == null:
				game.ship.target = game.planets[game.target_index]
			game.hud.show_toast("自动航行已开启" if game.ship.autopilot else "已切换手动驾驶", 1.8)
			game.audio.play_ui(600.0)
		"map":
			game.toggle_map()
		"journal":
			game.toggle_journal()
		"menu":
			game.set_paused(true)
		"context":
			if game.ship.docked:
				game.enter_station()
			elif game.ship.landed:
				game.ship.takeoff()
			else:
				game._interact()
		"exit":
			if game.ship.docked:
				game.ship.undock()
			else:
				game.exit_ship()
		"map_close":
			game.toggle_map()
		"map_target":
			game._set_map_target()
		"map_zoom_in":
			game.map_zoom = clampf(game.map_zoom * 1.12, 0.45, 2.8)
			game.audio.play_ui(520.0)
		"map_zoom_out":
			game.map_zoom = clampf(game.map_zoom / 1.12, 0.45, 2.8)
			game.audio.play_ui(420.0)


func _release_button(id: String) -> void:
	pressed_buttons.erase(id)
	for button in buttons:
		if button.id != id:
			continue
		match button.action:
			"jetpack", "boost":
				_release_hold("jetpack")
			"scan":
				_release_hold("scan")
			"up":
				_release_hold("jump")
			"down":
				_release_hold("thrust_down")
			"brake":
				_release_hold("brake")
		return


func _hold_action(action: String) -> void:
	if not touch_holds.has(action):
		touch_holds[action] = true
		Input.action_press(action)


func _release_hold(action: String) -> void:
	if touch_holds.has(action):
		touch_holds.erase(action)
		Input.action_release(action)


func _pulse_action(action: String) -> void:
	Input.action_press(action)
	await get_tree().create_timer(0.14).timeout
	if is_inside_tree():
		Input.action_release(action)


func _release_all() -> void:
	joystick_vector = Vector2.ZERO
	if joystick_touch >= 0 or not touches.is_empty():
		_apply_move_actions()
	for action in touch_holds.keys():
		Input.action_release(action)
	touch_holds.clear()
	pressed_buttons.clear()
	touches.clear()
	joystick_touch = -1


func _build_buttons() -> void:
	buttons.clear()
	if game == null or game.map_open:
		if game != null and game.map_open:
			_build_map_buttons()
		return
	var w := overlay.size.x
	var h := overlay.size.y
	if w < 100.0 or h < 100.0:
		return
	joystick_center = Vector2(220.0, h - 300.0)
	if game.state == "walk":
		_add_button("jump", "跳跃", Vector2(w - 190.0, h - 330.0), 76.0, "tap", "jump", true)
		_add_button("jetpack", "喷气", Vector2(w - 390.0, h - 300.0), 62.0, "hold", "jetpack")
		_add_button("interact", "互动", Vector2(w - 190.0, h - 540.0), 62.0, "tap", "interact", true)
		_add_button("scan", "扫描", Vector2(w - 390.0, h - 450.0), 62.0, "hold", "scan")
		_add_button("map", "星图", Vector2(w - 80.0, h - 450.0), 44.0, "tap", "map")
		_add_button("journal", "日志", Vector2(w - 80.0, h - 260.0), 44.0, "tap", "journal")
		_add_button("lamp", "头灯", Vector2(w - 400.0, h - 580.0), 48.0, "tap", "lamp")
		_add_button("menu", "菜单", Vector2(w - 80.0, 110.0), 40.0, "tap", "menu")
	else:
		var takeoff_text := "进入" if game.ship.docked else ("起飞" if game.ship.landed else "着陆")
		_add_button("context", takeoff_text, Vector2(w - 190.0, h - 330.0), 76.0, "tap", "context", true)
		if game.ship.docked:
			_add_button("exit", "脱离", Vector2(w - 390.0, h - 450.0), 62.0, "tap", "exit")
		else:
			_add_button("up", "上升", Vector2(w - 390.0, h - 300.0), 62.0, "hold", "up")
			if game.ship.landed:
				_add_button("exit", "离船", Vector2(w - 390.0, h - 450.0), 62.0, "tap", "exit")
			else:
				_add_button("down", "下降", Vector2(w - 390.0, h - 450.0), 62.0, "hold", "down")
				_add_button("boost", "加力", Vector2(w - 190.0, h - 540.0), 62.0, "hold", "boost")
				_add_button("brake", "制动", Vector2(w - 400.0, h - 580.0), 48.0, "hold", "brake")
				_add_button("autopilot", "自动航行", Vector2(w - 190.0, h - 670.0), 54.0, "tap", "autopilot", true)
		_add_button("map", "星图", Vector2(w - 80.0, h - 450.0), 44.0, "tap", "map")
		_add_button("journal", "日志", Vector2(w - 80.0, h - 260.0), 44.0, "tap", "journal")
		_add_button("menu", "菜单", Vector2(w - 80.0, 110.0), 40.0, "tap", "menu")


func _build_map_buttons() -> void:
	var w := overlay.size.x
	var h := overlay.size.y
	_add_button("map_close", "关闭", Vector2(w - 90.0, h - 100.0), 46.0, "tap", "map_close", true)
	_add_button("map_target", "设为目标", Vector2(w - 90.0, h - 195.0), 44.0, "tap", "map_target", true)
	_add_button("map_zoom_in", "+", Vector2(w - 90.0, h - 375.0), 36.0, "tap", "map_zoom_in")
	_add_button("map_zoom_out", "-", Vector2(w - 90.0, h - 290.0), 36.0, "tap", "map_zoom_out")


func _add_button(id: String, label: String, pos: Vector2, radius: float, mode: String, action: String, accent := false) -> void:
	buttons.append({"id": id, "label": label, "pos": pos, "radius": radius, "mode": mode, "action": action, "accent": accent})


func draw_overlay(canvas: Control) -> void:
	if not enabled or not visible:
		return
	if portrait:
		canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.01, 0.02, 0.035, 0.94))
		_draw_text(canvas, "请横屏游玩", canvas.size * 0.5, 34, Color(0.85, 0.94, 0.9))
		_draw_text(canvas, "旋转手机后触屏按键会自动出现", canvas.size * 0.5 + Vector2(0.0, 54.0), 18, Color(0.55, 0.72, 0.7))
		return
	var border := Color(0.5, 0.82, 0.78, 0.55)
	var ring := Color(0.95, 0.75, 0.4, 0.7)
	if not game.map_open:
		canvas.draw_circle(joystick_center, JOYSTICK_RADIUS, Color(0.02, 0.06, 0.08, 0.38))
		canvas.draw_arc(joystick_center, JOYSTICK_RADIUS, 0.0, TAU, 48, border, 2.0, true)
		var knob := joystick_center + joystick_vector * JOYSTICK_RADIUS
		canvas.draw_circle(knob, KNOB_RADIUS, Color(0.2, 0.55, 0.52, 0.5))
		canvas.draw_arc(knob, KNOB_RADIUS, 0.0, TAU, 32, Color(0.7, 0.95, 0.9, 0.65), 2.0, true)
		var hint := "移动" if game.state == "walk" else "平移"
		_draw_text(canvas, hint, joystick_center + Vector2(0.0, -JOYSTICK_RADIUS - 18.0), 16, Color(0.7, 0.85, 0.82))
	for button in buttons:
		var pressed := pressed_buttons.has(button.id)
		var fill := Color(0.18, 0.55, 0.5, 0.68) if pressed else Color(0.02, 0.06, 0.08, 0.46)
		canvas.draw_circle(button.pos, button.radius, fill)
		var outline: Color = ring if button.accent else border
		canvas.draw_arc(button.pos, button.radius, 0.0, TAU, 48, outline, 2.0 if not pressed else 3.0, true)
		var font_size := 22 if button.radius >= 70.0 else (19 if button.radius >= 55.0 else 16)
		_draw_text(canvas, button.label, button.pos, font_size, Color(0.9, 0.97, 0.93))


func _draw_text(canvas: Control, text: String, center: Vector2, font_size: int, color: Color) -> void:
	if font == null:
		return
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	canvas.draw_string(font, center - Vector2(extent.x * 0.5, -extent.y * 0.28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
