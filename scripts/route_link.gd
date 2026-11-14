extends RefCounted

const EchoScript = preload("res://scripts/route_echo.gd")
const ROUTES := {
	"cloud": {"planet": "qinglan", "place": "青岚星", "memory": "云舟船灯", "title": "同一阵风",
		"hint": "云舟灯的摆动和风车塔的风向记录有相同的周期。",
		"reply": "风车塔的第二段脉冲回应了云海浮标。阁楼窗外的风，来自同一个宇宙。"},
	"snow": {"planet": "baiyao", "place": "白曜星", "memory": "冰镜极光", "title": "冰里的折光",
		"hint": "冰镜留下的色带，能分开白曜冰原信号中重叠的光。",
		"reply": "白曜冰原的折光与雪夜冰镜重合。寒夜保存的，是星光穿过空间的方向。"},
	"alley": {"planet": "cangbo", "place": "沧波星", "memory": "雨巷钟铃", "title": "雨与潮的拍子",
		"hint": "雨巷水钟的三拍间隔，能辨认沧波水声中被潮汐藏起的一拍。",
		"reply": "潮汐补齐了雨巷水钟的停顿。雨水与海洋，用同一种节律计时。"},
	"firefly": {"planet": "xuanpu", "place": "玄圃星", "memory": "树屋萤火", "title": "暗处的微光",
		"hint": "萤火罐里的明暗节律，和玄圃植被的微光呼应。",
		"reply": "玄圃暗处的光回应了树屋萤火。那些微光不是路标，而是仍在生长的记忆。"},
}

var decoded: Dictionary = {}
var completed := false
var tracked := ""
var echoes: Dictionary = {}


func echo_id(key: String) -> String:
	return "attic_echo_" + key


func key_for(id: String) -> String:
	for key in ROUTES:
		if echo_id(key) == id:
			return key
	return ""


func unlocked(game) -> bool:
	return game.discovered.has("qinglan") or game.discovered.has("xuanyuan")


func verified(game, key: String) -> bool:
	return game.discovered.has(echo_id(key))


func verified_count(game) -> int:
	var count := 0
	for key in ROUTES:
		if verified(game, key):
			count += 1
	return count


func can_decode(game, key: String) -> bool:
	return ROUTES.has(key) and game.in_attic and not game.in_pocket() \
		and game.keepsakes.has(key) and game.discovered.has(ROUTES[key].planet) \
		and not decoded.has(key)


func decode(game, key: String) -> bool:
	if not can_decode(game, key):
		return false
	decoded[key] = true
	refresh()
	game._save_knowledge()
	game.hud.show_toast("已解读「%s」：返航后前往%s扫描新的回声。" % [ROUTES[key].title, ROUTES[key].place], 6.0)
	return true


func can_scan(id: String) -> bool:
	var key := key_for(id)
	return key == "" or decoded.has(key)


func build_echo(game, planet, source: Node3D) -> void:
	for key in ROUTES:
		if ROUTES[key].planet != planet.planet_id:
			continue
		var echo := EchoScript.new()
		echo.name = "AtticEcho_" + key
		echo.anomaly_id = echo_id(key)
		echo.title = "阁楼回声 · " + ROUTES[key].title
		echo.body = ROUTES[key].reply
		echo.accent_color = planet.accent_color
		# A separate signal beside the known monument, following the planet's local surface.
		var up := source.position.normalized()
		var direction := (up + source.basis.x * (38.0 / float(planet.radius))).normalized()
		echo.position = planet.surface_position(direction, 0.4)
		echo.basis = Basis(Quaternion(Vector3.UP, direction))
		echo.visible = decoded.has(key)
		planet.add_child(echo)
		echoes[key] = echo
		game.anomalies.append(echo)
		restore_target(game)


func refresh() -> void:
	for key in echoes:
		if is_instance_valid(echoes[key]):
			echoes[key].visible = decoded.has(key)


func restore_target(game) -> void:
	if tracked == "" or game.ship == null:
		return
	if verified(game, tracked):
		tracked = ""
		return
	for i in range(game.planets.size()):
		if game.planets[i].planet_id == ROUTES[tracked].planet:
			game.target_index = i
			game.map_selected = i
			game.ship.target = game.planets[i]
			return


func navigate(game, key: String) -> bool:
	if not ROUTES.has(key):
		return false
	for i in range(game.planets.size()):
		var planet = game.planets[i]
		if planet.planet_id != ROUTES[key].planet:
			continue
		game.target_index = i
		game.map_selected = i
		game.ship.target = planet
		tracked = key if decoded.has(key) and not verified(game, key) else ""
		game._save_knowledge()
		game.hud.show_toast("目的地已设为%s。%s" % [ROUTES[key].place,
			"返航后在地表寻找金色回声标记，按住 F 扫描。" if tracked != "" else "先在地表扫描原有信号，再回阁楼解读。"], 6.0)
		return true
	game.hud.show_toast("目标星球仍在生成，请稍候再设定。", 3.0)
	return false


func finale_missing(game) -> String:
	var missing: Array[String] = []
	if verified_count(game) < 4:
		missing.append("宇宙回声 %d/4" % verified_count(game))
	if not game.has_prism_heart:
		missing.append("镜界中央的棱镜之心")
	if not game.discovered.has("xuanyuan"):
		missing.append("玄渊之核的宇宙记录")
	return "、".join(missing)


func finish(game) -> bool:
	if completed or not game.in_attic or game.in_pocket() or finale_missing(game) != "":
		return false
	completed = true
	game._save_knowledge()
	game.close_route_board()
	game.previous_state = "walk"
	game.end_text = "四段回声在棱镜之心里合成一张完整的归航图。\n\n风、冰光、潮声和萤火都来自你亲自走过的地方。阁楼把宇宙里零散的记录保存下来；你的返航，又让这些小小的纪念有了可以回应的远方。\n\n恒星仍会老去，知识和家不会随轮回消失。你现在知道，两条路通向同一个世界。"
	game.state = "end"
	game.paused = false
	game.audio.play_chime()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


func status(game, key: String) -> String:
	if verified(game, key):
		return "已验证 · " + ROUTES[key].reply
	if decoded.has(key):
		return "已解读 · 返航到%s，在原信号附近扫描新的回声。" % ROUTES[key].place
	var needs: Array[String] = []
	if not game.keepsakes.has(key):
		needs.append("阁楼纪念「%s」" % ROUTES[key].memory)
	if not game.discovered.has(ROUTES[key].planet):
		needs.append("%s的原始扫描记录" % ROUTES[key].place)
	if needs.is_empty():
		return "线索齐全 · 回阁楼唱片柜旁解读，解锁宇宙中的第二段信号。"
	return "还需要：" + "、".join(needs)


func save_data() -> Dictionary:
	return {"decoded": decoded, "completed": completed, "tracked": tracked}


func load_data(value) -> void:
	decoded.clear()
	completed = false
	tracked = ""
	if value is Dictionary:
		var saved = value.get("decoded", {})
		if saved is Dictionary:
			for key in ROUTES:
				if saved.get(key, false) == true:
					decoded[key] = true
		completed = value.get("completed", false) == true
		var target := String(value.get("tracked", ""))
		if ROUTES.has(target) and decoded.has(target):
			tracked = target
	refresh()
