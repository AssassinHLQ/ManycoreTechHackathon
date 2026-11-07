extends Node

## 行囊进度：金币、鱼类图鉴、成就、小游戏最好成绩、纪念与茶席等里程碑。
## 单独存一份 user://starward_progress.json，重启后恢复。

const SAVE_PATH_DEFAULT := "user://starward_progress.json"

## 原作鱼谱：id -> [名字, 基础价值, 稀有度权重]
## 九种鱼来自同伴版 Di 表：冰纹鲫 / 星鳞鱼 / 极光鳟 / 雪灯鱼 / 铜铃鲢 / 月白鳜 / 云纹鳐 / 银河鳗 / 镜心鲤
const FISH_TABLE := {
	"ice-crucian": ["冰纹鲫", 12, 30.0],
	"snow-lamp": ["雪灯鱼", 16, 24.0],
	"bell-carp": ["铜铃鲢", 20, 18.0],
	"star-scale": ["星鳞鱼", 28, 12.0],
	"moon-perch": ["月白鳜", 34, 9.0],
	"aurora-trout": ["极光鳟", 44, 5.0],
	"cloud-ray": ["云纹鳐", 52, 3.6],
	"galaxy-eel": ["银河鳗", 68, 2.2],
	"mirror-koi": ["镜心鲤", 90, 1.2],
}
## 鱼竿（原作：竹节鱼竿 / 黄铜海竿 / 极光冰竿）
## id -> [名称, 价格, 稀有度加成, 收线速度, 张力窗口宽度]
const RODS := {
	"bamboo": ["竹节鱼竿", 0, 1.0, 1.0, 0.30],
	"brass": ["黄铜海竿", 120, 1.35, 1.12, 0.38],
	"aurora": ["极光冰竿", 300, 1.8, 1.22, 0.46],
}

## 鱼饵（原作：面团饵 / 萤光饵 / 星屑饵）
## id -> [名称, 单价, 一次买几份, 稀有度加成, 咬钩提速倍率, 说明]
const BAITS := {
	"plain": ["面团饵", 0, 0, 1.0, 1.0, "最普通的饵，永远够用。浮标也是素的，慢慢等就好。"],
	"glow": ["萤光饵", 40, 5, 1.3, 0.75, "一点萤火揉进饵里，水面会泛绿光，少见的鱼游得更近、咬钩也更快。"],
	"star": ["星屑饵", 120, 3, 1.6, 0.6, "撒下星屑，浮标周围绕着碎星。传说中的鱼也愿意为一小片夜空咬钩。"],
}
## 只有星屑饵才引得上来的传说鱼
const LEGEND_FISH := ["galaxy-eel", "mirror-koi"]

## 成就表：id -> [名称, 说明]
const ACHIEVEMENTS := {
	"first_fish": ["第一尾鱼", "冰洞下的第一次回应"],
	"three_fish": ["三盏冰灯", "三尾齐了，冰面下像有极光游过"],
	"keepsake_snow": ["冰镜极光", "让三面冰镜找到共同的方向"],
	"keepsake_cloud": ["云舟船灯", "点亮三盏云灯浮标，放下云桥"],
	"keepsake_forest": ["树屋萤火", "把三簇萤火装进玻璃罐再放飞"],
	"keepsake_rain": ["雨巷钟铃", "对齐三只檐口水兽，唤醒水钟"],
	"keepsake_all": ["四件纪念", "四个世界的纪念都放上了旅行架"],
	"prism_heart": ["棱镜之心", "从镜界回廊带回那枚棱镜"],
	"tea_full": ["一壶茶", "在阁楼茶桌泡满一壶"],
	"court_rest": ["檐下听雨", "点亮相听雨灯，在檐下坐一会儿"],
	"games_all": ["三段小游戏", "风律、萤火、檐雨都玩过一次"],
	"dungeon_first": ["镜牢初探", "第一次走进镜牢回廊"],
	"dungeon_clear": ["走到尽头", "第一次抵达镜牢回廊的尽头"],
	"dungeon_flawless": ["毫发无伤", "一次都没有被镜影碰到就抵达尽头"],
	# 以下为同伴版原作成就表里的其余条目（名称与条件照抄）
	"ice-lanterns": ["三盏冰灯", "完成静冰湾的三尾剧情鱼"],
	"dex-half": ["半册鱼谱", "图鉴收集 5 种鱼"],
	"dex-all": ["湖底全书", "收集全部 9 种鱼"],
	"angler": ["十尾渔获", "累计钓上 10 尾鱼"],
	"merchant": ["会过日子", "卖出 10 尾鱼"],
	"rich": ["口袋沉沉", "持有 500 金币"],
	"wind-song": ["风律回响", "在「风律回响」中完成六轮"],
	"firefly-guide": ["萤火引路", "在「萤火引路」中取得 100 分"],
	"rain-tempo": ["檐雨合拍", "在「檐雨合拍」中取得 120 分"],
	"listening-court": ["听雨院", "点亮三盏听雨灯，并在檐下坐一会儿"],
	"deep-run": ["向深处走", "在镜牢中抵达第 3 层"],
	"three-faces": ["三相皆明", "击破镜心的三种形态"],
	"mirror-calm": ["镜心安静", "完成镜界试炼"],
	"wind_organ": ["三种来风", "在风琴礁把北风、西风、回风各听一次"],
}

var save_path := SAVE_PATH_DEFAULT
var coins := 0
## 图鉴：id -> {count, held, best_value}（count 是累计钓到，held 是还没卖的）
var fish: Dictionary = {}
## 已购鱼竿
var rod := "bamboo"
var sold_total := 0
## 鱼饵：当前使用的 + 各饵剩余份数（面团饵无限，不计数）
var bait := "plain"
var bait_charges: Dictionary = {}
var achievements: Dictionary = {}
## 小游戏最好成绩：kind -> score
var game_best: Dictionary = {}
## 风琴礁：三种来风（北风/西风/回风）是否各听过一次
var wind_heard: Array = [false, false, false]
var wind_solved := false
## 镜牢里捡到的镜币；离开镜牢时结算进 coins
var mirror_coins := 0
## 累计获得过的镜币（成就用）
var mirror_coins_total := 0

## 新手引导是否已经看过（看过就不再自动弹）
var guide_done := false
## 最近 5 次远行的记录（最新在前）：{seconds, rooms, cleared, kills, hits, coins, rank, at}
var recent_runs: Array = []

## 风琴礁：北风 / 西风 / 回风，三种各听一次即和鸣
const WIND_NAMES := ["北风", "西风", "回风"]
const WIND_LINES := [
	"北风穿过最高的音管，云海向远处让开",
	"西风放缓，低音把礁石烘得暖融融的",
	"回风绕岛一圈，每一根音管都轻轻相和",
]
const WIND_SOLVED_LINE := "三种来风在管间和鸣，风琴礁把整片云海染成了金色"
## 镜牢纪录：runs / clears / best_seconds / best_rank / best_rooms
var dungeon: Dictionary = {}
var last_unlocks: Array = []


## 风琴礁已经听过几种来风
func wind_heard_count() -> int:
	var total := 0
	for flag in wind_heard:
		if bool(flag):
			total += 1
	return total


## 奏响风琴：轮换到下一种还没听过的来风。返回 {ok, message, solved, wind}
func hear_wind() -> Dictionary:
	if wind_solved:
		return {"ok": true, "message": WIND_SOLVED_LINE, "solved": true, "wind": -1}
	var index := -1
	for i in range(3):
		if not bool(wind_heard[i]):
			index = i
			break
	if index < 0:
		wind_solved = true
		return {"ok": true, "message": WIND_SOLVED_LINE, "solved": true, "wind": -1}
	wind_heard[index] = true
	var heard := wind_heard_count()
	if heard >= 3:
		wind_solved = true
		unlock("wind_organ")
		return {"ok": true, "message": WIND_SOLVED_LINE, "solved": true, "wind": index}
	return {"ok": true, "message": "%s（来风 %d/3）" % [String(WIND_LINES[index]), heard],
		"solved": false, "wind": index}


func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)


func fish_name(id: String) -> String:
	var row: Array = FISH_TABLE.get(id, ["未知", 10, 1.0])
	return String(row[0])


func fish_value(id: String) -> int:
	var row: Array = FISH_TABLE.get(id, ["未知", 10, 1.0])
	return int(row[1])


## 按稀有度权重抽一尾鱼；鱼竿与鱼饵都会提升稀有鱼的机会。
## 传说鱼（银河鳗 / 镜心鲤）只有挂星屑饵时才在候选里。
func roll_fish() -> String:
	var rod_row: Array = RODS.get(rod, ["竹节鱼竿", 0, 1.0, 1.0, 0.3])
	var bait_row: Array = BAITS.get(bait, ["面团饵", 0, 0, 1.0, 1.0, ""])
	var bonus: float = float(rod_row[2]) * float(bait_row[3])
	var total := 0.0
	var weights: Array = []
	for id in FISH_TABLE:
		if LEGEND_FISH.has(id) and bait != "star":
			continue
		# 稀有度越低（权重越小）的鱼，受加成越明显
		var base: float = float(FISH_TABLE[id][2])
		var weighted: float = base if base >= 18.0 else base * bonus
		weights.append([id, weighted])
		total += weighted
	var pick := randf() * total
	for entry in weights:
		pick -= float(entry[1])
		if pick <= 0.0:
			return String(entry[0])
	return String(weights[0][0])


## 稀有度 1~5（5 最稀有）。按权重分档：权重越小越难得。
func fish_rarity(id: String) -> int:
	var row: Array = FISH_TABLE.get(id, ["未知", 10, 1.0])
	var weight: float = float(row[2])
	if weight <= 2.0:
		return 5
	if weight <= 4.5:
		return 4
	if weight <= 13.0:
		return 3
	if weight <= 22.0:
		return 2
	return 1


## 稀有度星标：1~5 星，与 fish_rarity 一致
func fish_stars(id: String) -> int:
	return fish_rarity(id)


func stars_text(id: String) -> String:
	var stars := fish_stars(id)
	var text := ""
	for i in range(5):
		text += "★" if i < stars else "☆"
	return text


## 记一尾鱼：返回 {id, name, value, is_new, count, dex, length, best_length}
func add_fish(id: String) -> Dictionary:
	var value: int = int(round(float(fish_value(id)) * randf_range(0.8, 1.4)))
	# 体长：越稀有的鱼越长（12~70 cm）
	var length: int = int(round(randf_range(12.0, 34.0) + float(fish_stars(id)) * 12.0))
	var is_new: bool = not fish.has(id)
	var entry: Dictionary = fish.get(id, {"count": 0, "held": 0, "best_value": 0, "best_length": 0})
	entry["count"] = int(entry["count"]) + 1
	entry["held"] = int(entry.get("held", 0)) + 1
	if value > int(entry.get("best_value", 0)):
		entry["best_value"] = value
	if length > int(entry.get("best_length", 0)):
		entry["best_length"] = length
	fish[id] = entry
	return {"id": id, "name": fish_name(id), "value": value, "is_new": is_new,
		"count": int(entry["count"]), "dex": fish.size(),
		"length": length, "best_length": int(entry["best_length"])}


## 图鉴里已有的鱼种数
func dex_count() -> int:
	return fish.size()


## 鱼篓里还没卖的尾数
func held_count() -> int:
	var total := 0
	for id in fish:
		total += int(fish[id].get("held", 0))
	return total


func fish_count() -> int:
	var total := 0
	for id in fish:
		total += int(fish[id]["count"])
	return total


func bait_name() -> String:
	return String((BAITS.get(bait, BAITS["plain"]) as Array)[0])


func bait_charge(id: String) -> int:
	if id == "plain":
		return -1  # 无限
	return int(bait_charges.get(id, 0))


## 买一份鱼饵；返回 {ok, id, name, count, coins}
func buy_bait(id: String) -> Dictionary:
	var result := {"ok": false, "id": id, "name": "", "count": 0, "coins": coins}
	if not BAITS.has(id) or id == "plain":
		return result
	var row: Array = BAITS[id]
	var price: int = int(row[1])
	var bundle: int = int(row[2])
	result["name"] = String(row[0])
	if coins < price:
		return result
	add_coins(-price)
	bait_charges[id] = bait_charge(id) + bundle
	result["ok"] = true
	result["count"] = int(bait_charges[id])
	result["coins"] = coins
	return result


## 换饵：只能在「面团饵 + 有存货的饵」之间切
func switch_bait(id: String) -> bool:
	if not BAITS.has(id) or bait == id:
		return false
	if id != "plain" and bait_charge(id) <= 0:
		return false
	bait = id
	return true


func owned_baits() -> Array:
	var list: Array = ["plain"]
	for id in ["glow", "star"]:
		if bait_charge(id) > 0:
			list.append(id)
	return list


## 咬钩等待时间倍率（萤光/星屑饵咬钩更快）
func bait_bite_scale() -> float:
	return float((BAITS.get(bait, BAITS["plain"]) as Array)[4])


## 收线速度与张力窗口宽度（由鱼竿决定）
func rod_reel_speed() -> float:
	return float((RODS.get(rod, RODS["bamboo"]) as Array)[3])


func rod_tension_window() -> float:
	return float((RODS.get(rod, RODS["bamboo"]) as Array)[4])


## 消耗一份当前鱼饵（面团饵不消耗）
func consume_bait() -> void:
	if bait == "plain":
		return
	var left: int = bait_charge(bait) - 1
	bait_charges[bait] = maxi(0, left)
	if left <= 0:
		bait = "plain"


## 卖出鱼篓里的全部渔获：返回 {count, coins}
func sell_fish() -> Dictionary:
	var count := 0
	var earned := 0
	for id in fish:
		var entry: Dictionary = fish[id]
		var held: int = int(entry.get("held", 0))
		if held <= 0:
			continue
		var value: int = int(round(float(fish_value(id)) * 0.9))
		earned += value * held
		count += held
		entry["held"] = 0
		fish[id] = entry
	if count > 0:
		add_coins(earned)
		sold_total += count
	return {"count": count, "coins": earned}


## 买一根鱼竿：返回 true 表示买成
func buy_rod(id: String) -> bool:
	if not RODS.has(id) or rod == id:
		return false
	var price: int = int(RODS[id][1])
	if coins < price:
		return false
	# 只能往上升级（价钱更高的那根）
	var current: int = int(RODS[rod][1])
	if price <= current:
		return false
	add_coins(-price)
	rod = id
	return true


func rod_name() -> String:
	var row: Array = RODS.get(rod, ["竹节鱼竿", 0, 1.0])
	return String(row[0])


## 解锁成就：返回 true 表示这次是新解锁。
func unlock(id: String) -> bool:
	if achievements.has(id):
		return false
	achievements[id] = true
	last_unlocks.append(id)
	return true


func is_unlocked(id: String) -> bool:
	return achievements.has(id)


func achievement_count() -> int:
	return achievements.size()


## 记录小游戏成绩；返回 {best, is_best}
func record_game(kind: String, score: int) -> Dictionary:
	var previous: int = int(game_best.get(kind, 0))
	var is_best: bool = score > previous
	if is_best:
		game_best[kind] = score
	return {"best": int(game_best.get(kind, 0)), "is_best": is_best}


func games_played() -> int:
	return game_best.size()


## 原作段位表：S 无瑕（无伤且 7 分钟内）/ A 稳镜（受击≤2 且 10 分钟内）/ B 初净
const DUNGEON_RANKS := {
	"S": ["无瑕", "无伤且 7 分钟内通关"],
	"A": ["稳镜", "受击不超过 2 次且 10 分钟内通关"],
	"B": ["初净", "完成一次镜牢"],
}


## 按原作规则给段位：先看受击次数与用时
static func dungeon_rank(seconds: float, hits := 0, cleared := true) -> String:
	if not cleared:
		return "B"
	if hits == 0 and seconds <= 420.0:
		return "S"
	if hits <= 2 and seconds <= 600.0:
		return "A"
	return "B"


static func dungeon_rank_name(rank: String) -> String:
	var entry: Array = DUNGEON_RANKS.get(rank, ["初净", ""])
	return String(entry[0])


static func dungeon_rank_note(rank: String) -> String:
	var entry: Array = DUNGEON_RANKS.get(rank, ["初净", ""])
	return String(entry[1])


## 记一次镜牢：返回 {rank, is_best, best_seconds, best_rank, clears, runs}
## 记一次镜牢远行（最近 5 次，最新在前）
func push_recent_run(seconds: float, rooms: int, cleared: bool, kills: int, hits: int,
		coins: int, rank: String) -> void:
	recent_runs.push_front({
		"seconds": seconds,
		"rooms": rooms,
		"cleared": cleared,
		"kills": kills,
		"hits": hits,
		"coins": coins,
		"rank": rank,
		"at": Time.get_datetime_string_from_system(),
	})
	while recent_runs.size() > 5:
		recent_runs.pop_back()


func record_dungeon(seconds: float, rooms: int, cleared: bool, kills := 0, hits := 0,
		boons: Array = []) -> Dictionary:
	var rank := dungeon_rank(seconds, hits, cleared)
	var previous_best: float = float(dungeon.get("best_seconds", 0.0))
	var is_best: bool = cleared and (previous_best <= 0.0 or seconds < previous_best)
	dungeon["runs"] = int(dungeon.get("runs", 0)) + 1
	if cleared:
		dungeon["clears"] = int(dungeon.get("clears", 0)) + 1
		if is_best:
			dungeon["best_seconds"] = seconds
			dungeon["best_rank"] = rank
			dungeon["best_rooms"] = rooms
		dungeon["total_kills"] = int(dungeon.get("total_kills", 0)) + kills
		dungeon["total_boons"] = int(dungeon.get("total_boons", 0)) + boons.size()
		dungeon["last_boons"] = boons.duplicate()
		if hits == 0:
			dungeon["flawless"] = true
	return {
		"rank": rank,
		"rank_name": dungeon_rank_name(rank),
		"rank_note": dungeon_rank_note(rank),
		"boons": boons,
		"is_best": is_best,
		"kills": kills,
		"hits": hits,
		"flawless": cleared and hits == 0,
		"best_seconds": float(dungeon.get("best_seconds", 0.0)),
		"best_rank": String(dungeon.get("best_rank", "")),
		"clears": int(dungeon.get("clears", 0)),
		"runs": int(dungeon.get("runs", 0)),
	}


func time_text(seconds: float) -> String:
	var whole := int(maxf(0.0, seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]


## 面板用的汇总
func summary() -> Dictionary:
	return {
		"coins": coins,
		"fish": fish,
		"fish_total": fish_count(),
		"achievements": achievements,
		"achievement_total": achievement_count(),
		"games": game_best,
	}


func save() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"coins": coins,
		"fish": fish,
		"achievements": achievements,
		"game_best": game_best,
		"wind_heard": wind_heard,
		"wind_solved": wind_solved,
		"mirror_coins": mirror_coins,
		"mirror_coins_total": mirror_coins_total,
		"guide_done": guide_done,
		"recent_runs": recent_runs,
		"dungeon": dungeon,
		"rod": rod,
		"sold_total": sold_total,
		"bait": bait,
		"bait_charges": bait_charges,
	}))
	file.close()


func load_progress() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	coins = int(data.get("coins", 0))
	fish = data.get("fish", {})
	achievements = data.get("achievements", {})
	game_best = data.get("game_best", {})
	wind_heard = data.get("wind_heard", [false, false, false])
	wind_solved = bool(data.get("wind_solved", false))
	mirror_coins = int(data.get("mirror_coins", 0))
	mirror_coins_total = int(data.get("mirror_coins_total", 0))
	guide_done = bool(data.get("guide_done", false))
	recent_runs = data.get("recent_runs", [])
	dungeon = data.get("dungeon", {})
	rod = String(data.get("rod", "bamboo"))
	sold_total = int(data.get("sold_total", 0))
	bait = String(data.get("bait", "plain"))
	bait_charges = data.get("bait_charges", {})


func reset() -> void:
	coins = 0
	fish = {}
	achievements = {}
	game_best = {}
	wind_heard = [false, false, false]
	wind_solved = false
	mirror_coins = 0
	mirror_coins_total = 0
	guide_done = false
	recent_runs = []
	dungeon = {}
	rod = "bamboo"
	sold_total = 0
	bait = "plain"
	bait_charges = {}
	last_unlocks.clear()
