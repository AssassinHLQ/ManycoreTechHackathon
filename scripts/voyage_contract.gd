extends RefCounted

## A short, repeatable loop that turns the existing scan, landing, beacon and
## homecoming-station systems into one readable voyage.
const ROUTES := [
	{"id": "zheya", "name": "赭崖星", "reward": 140, "line": "盐壳裂谷的旧信号需要一枚新的回声"},
	{"id": "cangbo", "name": "沧波星", "reward": 170, "line": "潮汐研究站还在等一盏返航灯"},
	{"id": "xuanjing", "name": "悬晶星", "reward": 200, "line": "碎晶场里有一段不能丢的坐标"},
	{"id": "baiyao", "name": "白曜星", "reward": 230, "line": "冰棱塔保存着最后一枚冷光样本"},
	{"id": "xuanpu", "name": "玄圃星", "reward": 260, "line": "暗处的微光正在呼叫下一位旅人"},
]

var active := false
var phase := "idle"
var target_id := ""
var target_name := ""
var target_line := ""
var reward := 0
var completed_count := 0


func load_data(value) -> void:
	active = false
	phase = "idle"
	target_id = ""
	target_name = ""
	target_line = ""
	reward = 0
	completed_count = 0
	if not (value is Dictionary):
		return
	var data: Dictionary = value
	completed_count = maxi(0, int(data.get("completed_count", 0)))
	active = bool(data.get("active", false))
	phase = String(data.get("phase", "idle"))
	target_id = String(data.get("target_id", ""))
	var route := _route_for(target_id)
	target_name = String(data.get("target_name", route.get("name", "")))
	target_line = String(data.get("target_line", route.get("line", "")))
	reward = int(data.get("reward", route.get("reward", 0)))
	if not active or not _valid_phase(phase) or route.is_empty():
		active = false
		phase = "idle"


func save_data() -> Dictionary:
	return {
		"active": active,
		"phase": phase,
		"target_id": target_id,
		"target_name": target_name,
		"target_line": target_line,
		"reward": reward,
		"completed_count": completed_count,
	}


func start(discovered: Dictionary) -> bool:
	if active:
		return false
	var route: Dictionary = {}
	for offset in range(ROUTES.size()):
		var candidate: Dictionary = ROUTES[(completed_count + offset) % ROUTES.size()]
		if not discovered.has(String(candidate.id)):
			route = candidate
			break
	if route.is_empty():
		route = ROUTES[completed_count % ROUTES.size()]
	target_id = String(route.id)
	target_name = String(route.name)
	target_line = String(route.line)
	reward = int(route.reward) + completed_count * 20
	active = true
	phase = "scan_home" if not discovered.has("qinglan") else "scan_target"
	return true


func on_discovered(id: String) -> bool:
	if not active:
		return false
	if phase == "scan_home" and id == "qinglan":
		phase = "scan_target"
		return true
	if phase == "scan_target" and id == target_id:
		phase = "recover"
		return true
	return false


func on_beacon(planet_id: String) -> bool:
	if active and phase == "recover" and planet_id == target_id:
		phase = "return"
		return true
	return false


func complete_at_home() -> bool:
	if not active or phase != "return":
		return false
	active = false
	phase = "idle"
	completed_count += 1
	return true


func status(discovered: Dictionary, in_attic := false) -> Dictionary:
	if not active:
		return {"active": false, "title": "下一次航行委托", "progress": "按开始探索接下一份委托",
			"hint": "每次出发都会给你一个有去有回的小目标。"}
	var done := 0
	var total := 3
	var progress := ""
	var hint := ""
	match phase:
		"scan_home":
			progress = "扫描青岚星风车塔　0/1"
			hint = "回头看见悬浮符文时按住 F。"
		"scan_target":
			progress = "扫描%s主信号　1/3" % target_name
			done = 1
			hint = target_line + "。星图已把目标标成目的地。"
		"recover":
			progress = "点亮%s地表信标　2/3" % target_name
			done = 2
			hint = "着陆后走出飞船，靠近发光信标按 E。"
		"return":
			progress = "回归归航站并完成对接　3/3"
			done = 3
			hint = "飞回归航站，对准塔顶的青色对接口。"
		_:
			progress = "准备出发"
	if in_attic:
		hint = "先回到飞船；这份委托会在宇宙里继续。"
	return {"active": true, "title": "航行委托 %02d" % (completed_count + 1),
		"progress": progress, "hint": hint, "done": done, "total": total,
		"target_id": target_id, "reward": reward}


func _route_for(id: String) -> Dictionary:
	for route in ROUTES:
		if String(route.id) == id:
			return route
	return {}


func _valid_phase(value: String) -> bool:
	return value in ["scan_home", "scan_target", "recover", "return"]
