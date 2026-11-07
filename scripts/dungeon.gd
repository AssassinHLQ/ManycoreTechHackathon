extends Node3D

## 镜牢回廊的战斗控制器（照同伴版原作）：
##   玩家：左键「凝光」近程光刃 / 右键「镜爆」环身爆发 / Space「武器绝技」（需蓄能）
##   敌人：镜影（战斗室 2~3 只，清空才开门）
##   BOSS：镜心余影，三相依次苏醒 —— 初相 / 折光相 / 逆光相
## 只做战斗本身，进度与结算由 main 负责。

const ENEMY_HP := 30.0
const ENEMY_SPEED := 2.6
const ENEMY_TOUCH_DAMAGE := 8
const ENEMY_TOUCH_COOLDOWN := 1.2
const BOSS_HP := 300.0
const BOSS_PHASES := ["初相", "折光相", "逆光相"]
const PLAYER_HP_MAX := 100
const GLOW_COST := 12.0        # 凝光的能量消耗（原作「凝光消耗 -12%」）
const BLAST_COST := 26.0       # 镜爆
const GLOW_DAMAGE := 15.0
const BLAST_DAMAGE := 22.0
const GLOW_RANGE := 9.0
const BLAST_RADIUS := 4.5
const SPECIAL_RADIUS := 8.0
const SPECIAL_DAMAGE := 60.0
const SPECIAL_CHARGE_MAX := 100.0

var game
var enemies: Array = []
var boss = null
var boss_stage := 0            # 1..3，0 表示未开战
var active := false

var player_hp := PLAYER_HP_MAX
var energy := 100.0
var special_charge := 0.0
var kills := 0
var hits_taken := 0
var door_open: Array = []
var hud: CanvasLayer
var hud_painter: HudPainter
## 原作镜印表（id -> [名称, 效果说明, 备注]）
const BOONS := {
	"edge": ["锋面镜印", "所有武器伤害 +18%", "刃口映着一线冷光，握久了会听见极轻的磨镜声。"],
	"vitality": ["宽息镜印", "镜息上限 +20，并立即回复 20", "像把一口很深的呼吸封进薄薄的镜片。"],
	"flow": ["流光镜印", "凝光消耗 -12%", "光在印面里走得比别处快，抬手时几乎不费力。"],
	"guard": ["镜壁镜印", "受到的伤害 -12%", "一触即碎的薄壁，偏偏愿意替你挡下最重的一击。"],
	"regen": ["回息镜印", "镜息自然回复 +30%", "碎裂的边角会慢慢长回去，像镜牢自己在呼吸。"],
}
const BOON_IDS := ["edge", "vitality", "flow", "guard", "regen"]

## 原作镜牢三武器（1 / 2 / 3 切换）：棱镜杖均衡、镜刃近战、折光弩贯穿
## id -> [名称, 定位, 伤害, 消耗, 射程, 夹角余弦(越大越窄), 命中方式]
const WEAPONS := {
	"wand": ["棱镜杖", "均衡", 15.0, 12.0, 9.0, 0.72, "single"],
	"blade": ["镜刃", "近战", 34.0, 10.0, 3.4, 0.15, "cleave"],
	"crossbow": ["折光弩", "贯穿", 20.0, 16.0, 18.0, 0.93, "pierce"],
}
const WEAPON_ORDER := ["wand", "blade", "crossbow"]

var boons: Array = []
var weapon_id := "wand"
var dodge_cooldown := 0.0
var dodge_invuln := 0.0
var damage_mult := 1.0
var glow_cost_mult := 1.0
var incoming_mult := 1.0
var breath_regen := 1.5
var hp_max := PLAYER_HP_MAX
var message := ""
var message_timer := 0.0
var _attack_cooldown := 0.0


class HudPainter extends Control:
	var layer

	func _draw() -> void:
		if layer != null:
			layer.draw_hud(self)


func start(host) -> void:
	game = host
	active = true
	player_hp = PLAYER_HP_MAX
	hp_max = PLAYER_HP_MAX
	energy = 100.0
	special_charge = 0.0
	kills = 0
	hits_taken = 0
	boons.clear()
	weapon_id = "wand"
	dodge_cooldown = 0.0
	dodge_invuln = 0.0
	damage_mult = 1.0
	glow_cost_mult = 1.0
	incoming_mult = 1.0
	breath_regen = 1.5
	boss = null
	boss_stage = 0
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	door_open.clear()
	_build_hud()
	_spawn_room_enemies(0)
	_update_doors()


func stop() -> void:
	active = false
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
	boss = null
	boss_stage = 0
	if hud != null:
		hud.visible = false


func _build_hud() -> void:
	if hud != null:
		hud.visible = true
		return
	hud = CanvasLayer.new()
	hud.name = "DungeonHud"
	hud.layer = 3
	add_child(hud)
	hud_painter = HudPainter.new()
	hud_painter.layer = self
	hud_painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_painter)


func _process(delta: float) -> void:
	if not active or game == null:
		return
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if dodge_cooldown > 0.0:
		dodge_cooldown -= delta
	if dodge_invuln > 0.0:
		dodge_invuln -= delta
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message = ""
	energy = minf(100.0, energy + delta * 9.0)
	# 镜息（生命）自然回复：回息镜印 +30%
	if player_hp > 0 and player_hp < hp_max:
		player_hp = mini(hp_max, player_hp + int(ceil(breath_regen * delta)))
	var player: Node3D = game.player
	if player == null:
		return
	# 镜影：朝玩家漂移，接触扣血
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		_tick_enemy(enemy, player, delta)
	enemies = enemies.filter(func(e): return is_instance_valid(e))
	# BOSS：三相
	if boss != null and is_instance_valid(boss):
		_tick_boss(boss, player, delta)
	_update_doors()
	if hud_painter != null:
		hud_painter.queue_redraw()


# --- 敌人生成 ---------------------------------------------------------------

func _spawn_room_enemies(room: int) -> void:
	var kind: String = game.attic_worlds.dungeon_room_kind(room)
	if kind == "boss":
		_spawn_boss(room)
		return
	if kind != "combat":
		return
	var count := 2 + (room % 2)
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var offset := Vector3(cos(angle) * 2.6, 0.0, sin(angle) * 2.6)
		_spawn_enemy(room, offset)


func enemy_alive_in_room(room: int) -> int:
	var total := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and int(enemy.get_meta("room", -1)) == room:
			total += 1
	return total


func _spawn_enemy(room: int, offset: Vector3) -> void:
	var anchor = game.attic_worlds.dungeon_room_anchor(room)
	if anchor == null:
		return
	var root := Node3D.new()
	root.name = "MirrorShade"
	var world: Node3D = game.attic_worlds.world_node("dungeon")
	world.add_child(root)
	root.global_position = (anchor as Node3D).global_position + offset
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8fa4b8")
	material.emission_enabled = true
	material.emission = Color("9fc0d8")
	material.emission_energy_multiplier = 0.8
	var mesh := MeshInstance3D.new()
	var body := CylinderMesh.new()
	body.top_radius = 0.28
	body.bottom_radius = 0.42
	body.height = 1.5
	body.radial_segments = 8
	mesh.mesh = body
	mesh.position.y = 0.75
	mesh.material_override = material
	root.add_child(mesh)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.26
	sphere.height = 0.52
	sphere.radial_segments = 10
	sphere.rings = 6
	head.mesh = sphere
	head.position.y = 1.62
	head.material_override = material
	root.add_child(head)
	root.set_meta("room", room)
	root.set_meta("hp", ENEMY_HP)
	root.set_meta("touch_cd", 0.0)
	root.set_meta("boss", false)
	enemies.append(root)


func _spawn_boss(room: int) -> void:
	var anchor = game.attic_worlds.dungeon_room_anchor(room)
	if anchor == null:
		return
	var root := Node3D.new()
	root.name = "MirrorHeartEcho"
	var world: Node3D = game.attic_worlds.world_node("dungeon")
	world.add_child(root)
	root.global_position = (anchor as Node3D).global_position + Vector3(0, 0, -3.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c8a0d8")
	material.emission_enabled = true
	material.emission = Color("d8b0f0")
	material.emission_energy_multiplier = 1.4
	var mesh := MeshInstance3D.new()
	var core := SphereMesh.new()
	core.radius = 0.85
	core.height = 1.7
	core.radial_segments = 14
	core.rings = 8
	mesh.mesh = core
	mesh.position.y = 1.5
	mesh.material_override = material
	root.add_child(mesh)
	var halo := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.1
	torus.outer_radius = 1.35
	torus.rings = 16
	torus.ring_segments = 8
	halo.mesh = torus
	halo.position.y = 1.5
	halo.material_override = material
	root.add_child(halo)
	root.set_meta("room", room)
	root.set_meta("hp", BOSS_HP)
	root.set_meta("touch_cd", 0.0)
	root.set_meta("boss", true)
	boss = root
	boss_stage = 1
	message = "镜心余影 · %s" % BOSS_PHASES[0]
	message_timer = 3.0


# --- 逐帧 -------------------------------------------------------------------

func _tick_enemy(enemy: Node3D, player: Node3D, delta: float) -> void:
	var to_player := player.global_position - enemy.global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > 0.7:
		enemy.global_position += to_player.normalized() * ENEMY_SPEED * delta
	enemy.look_at(player.global_position, Vector3.UP)
	var cooldown: float = float(enemy.get_meta("touch_cd", 0.0)) - delta
	if distance < 1.5 and cooldown <= 0.0:
		cooldown = ENEMY_TOUCH_COOLDOWN
		damage_player(ENEMY_TOUCH_DAMAGE)
	enemy.set_meta("touch_cd", cooldown)


func _tick_boss(boss_node: Node3D, player: Node3D, delta: float) -> void:
	var stage: int = _boss_stage_for(float(boss_node.get_meta("hp", BOSS_HP)))
	_set_boss_stage(stage)
	# 三形态行为：初相缓慢逼近；折光相更快并绕行；逆光相绕行 + 周期性冲击
	var speed: float = [2.0, 2.8, 3.4][stage - 1]
	var to_player := player.global_position - boss_node.global_position
	to_player.y = 0.0
	var distance := to_player.length()
	var tangent := Vector3(-to_player.z, 0.0, to_player.x).normalized()
	var desired := to_player.normalized() * (0.7 if distance > 4.0 else -0.5) + tangent * (0.0 if stage == 1 else 0.7)
	if desired.length() > 0.01:
		boss_node.global_position += desired.normalized() * speed * delta
	boss_node.rotate_y(delta * 0.8 * float(stage))
	var cooldown: float = float(boss_node.get_meta("touch_cd", 0.0)) - delta
	if distance < 2.4 and cooldown <= 0.0:
		cooldown = 1.1
		damage_player(12 + stage * 3)
	boss_node.set_meta("touch_cd", cooldown)


# --- 玩家攻击 ---------------------------------------------------------------

## 切换武器（1 / 2 / 3）
func set_weapon(id: String) -> bool:
	if not WEAPONS.has(id) or weapon_id == id:
		return false
	weapon_id = id
	var row: Array = WEAPONS[id]
	message = "%s · %s" % [String(row[0]), String(row[1])]
	message_timer = 2.0
	return true


func weapon_name() -> String:
	return String((WEAPONS[weapon_id] as Array)[0])


## 左键「凝光」：按当前武器结算。
##   棱镜杖：均衡，只打最近的一个目标
##   镜刃：近战，短射程但一次劈到范围内所有目标
##   折光弩：贯穿，细长光矢，穿透命中的全部目标
## 蓄能满时这一击升级为「武器绝技」（伤害翻倍、射程与范围加大，并清空蓄能）。
func attack_glow(aim: Vector3, origin: Vector3) -> Dictionary:
	if not active or _attack_cooldown > 0.0:
		return {"hit": 0, "killed": 0}
	var row: Array = WEAPONS[weapon_id]
	var base_damage: float = float(row[2])
	var base_cost: float = float(row[3])
	var base_range: float = float(row[4])
	var arc: float = float(row[5])
	var mode: String = String(row[6])
	var empowered: bool = special_charge >= SPECIAL_CHARGE_MAX
	if empowered:
		base_damage *= 2.0
		base_range += 3.0
		arc = maxf(0.05, arc - 0.25)
	if energy < base_cost * glow_cost_mult:
		return {"hit": 0, "killed": 0}
	_attack_cooldown = 0.18 if not empowered else 0.34
	energy -= base_cost * glow_cost_mult
	if empowered:
		special_charge = 0.0
	var flat_aim := Vector3(aim.x, 0.0, aim.z).normalized()
	var hit := 0
	var killed := 0
	# 候选目标：镜影 + BOSS
	var targets: Array = []
	for enemy in enemies:
		if is_instance_valid(enemy):
			targets.append(enemy)
	if boss != null and is_instance_valid(boss):
		targets.append(boss)
	# 按距离排序，便于「只打最近」的武器取第一个
	targets.sort_custom(func(a, b):
		return Vector3(a.global_position - origin).length() < Vector3(b.global_position - origin).length())
	for enemy in targets:
		var to_enemy: Vector3 = enemy.global_position - origin
		var flat := Vector3(to_enemy.x, 0.0, to_enemy.z)
		if flat.length() > base_range:
			continue
		if flat.normalized().dot(flat_aim) < arc:
			continue
		hit += 1
		if damage_enemy(enemy, base_damage * damage_mult):
			killed += 1
		if mode == "single":
			break
	message = "%s%s · 命中 %d" % ["绝技 · " if empowered else "", weapon_name(), hit] if hit > 0 \
		else "%s%s · 落空" % ["绝技 · " if empowered else "", weapon_name()]
	message_timer = 1.4
	return {"hit": hit, "killed": killed, "empowered": empowered}


## 右键「镜爆」：以自身为中心的环身爆发。
func attack_blast(origin: Vector3) -> Dictionary:
	if not active or _attack_cooldown > 0.0 or energy < BLAST_COST:
		return {"hit": 0, "killed": 0}
	_attack_cooldown = 0.35
	energy -= BLAST_COST
	var hit := 0
	var killed := 0
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(origin) <= BLAST_RADIUS:
			hit += 1
			if damage_enemy(enemy, BLAST_DAMAGE * damage_mult):
				killed += 1
	if boss != null and is_instance_valid(boss) and boss.global_position.distance_to(origin) <= BLAST_RADIUS:
		hit += 1
		if damage_enemy(boss, BLAST_DAMAGE * damage_mult):
			killed += 1
	message = "镜爆 · 命中 %d" % hit
	message_timer = 1.2
	return {"hit": hit, "killed": killed}


## Space「武器绝技」：需要蓄能满，清掉一圈。
func attack_special(origin: Vector3) -> Dictionary:
	if not active or special_charge < SPECIAL_CHARGE_MAX:
		message = "绝技还没蓄满（%d%%）" % int(special_charge)
		message_timer = 1.2
		return {"hit": 0, "killed": 0, "ready": false}
	special_charge = 0.0
	_attack_cooldown = 0.5
	var hit := 0
	var killed := 0
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(origin) <= SPECIAL_RADIUS:
			hit += 1
			if damage_enemy(enemy, SPECIAL_DAMAGE * damage_mult):
				killed += 1
	if boss != null and is_instance_valid(boss) and boss.global_position.distance_to(origin) <= SPECIAL_RADIUS:
		hit += 1
		if damage_enemy(boss, SPECIAL_DAMAGE * damage_mult):
			killed += 1
	message = "武器绝技 · 命中 %d" % hit
	message_timer = 1.6
	return {"hit": hit, "killed": killed, "ready": true}


## 血量比例 -> 形态（1 初相 / 2 折光相 / 3 逆光相）
func _boss_stage_for(hp: float) -> int:
	var ratio: float = hp / BOSS_HP
	if ratio <= 0.34:
		return 3
	if ratio <= 0.67:
		return 2
	return 1


## 切换镜心形态（受击与逐帧都会走到这里，保证立刻同步）
func _set_boss_stage(stage: int) -> void:
	if stage == boss_stage or boss == null or not is_instance_valid(boss):
		return
	boss_stage = stage
	message = "镜心余影 · %s" % BOSS_PHASES[stage - 1]
	message_timer = 3.0
	var mat := (boss.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	if mat != null:
		mat.emission = [Color("d8b0f0"), Color("f0c0a0"), Color("f0a0a0")][stage - 1]


## 空格「闪避」：向前一冲并获得短暂无敌
func dodge(direction: Vector3) -> bool:
	if not active or dodge_cooldown > 0.0 or energy < 8.0:
		return false
	dodge_cooldown = 1.2
	dodge_invuln = 0.45
	energy -= 8.0
	if game != null and game.player != null:
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		if flat.length_squared() < 0.01:
			flat = -game.player.global_transform.basis.z
		(game.player as CharacterBody3D).velocity += flat * 9.0
	message = "闪避"
	message_timer = 0.8
	return true


## 静镜室的候选镜印（原作五枚按房间轮换出三枚）
func boon_options(room: int) -> Array:
	var options: Array = []
	for i in range(3):
		options.append(BOON_IDS[(room + i) % BOON_IDS.size()])
	return options


## 取走一枚镜印并生效；返回 {id, name, desc, note}
func pick_boon(room: int, index: int) -> Dictionary:
	if not active or game == null or game.attic_worlds == null:
		return {}
	var options: Array = boon_options(room)
	if index < 0 or index >= options.size():
		return {}
	if not game.attic_worlds.dungeon_take_boon(room, index):
		return {}
	var id: String = options[index]
	apply_boon(id)
	var info: Array = BOONS[id]
	return {"id": id, "name": String(info[0]), "desc": String(info[1]), "note": String(info[2])}


## 让一枚镜印生效
func apply_boon(id: String) -> void:
	if boons.has(id):
		return
	boons.append(id)
	match id:
		"edge":
			damage_mult *= 1.18
		"vitality":
			hp_max += 20
			player_hp = mini(hp_max, player_hp + 20)
		"flow":
			glow_cost_mult *= 0.88
		"guard":
			incoming_mult *= 0.88
		"regen":
			breath_regen *= 1.3


## 对敌人造成伤害；返回是否被击倒。
func damage_enemy(enemy: Node3D, amount: float) -> bool:
	var hp: float = float(enemy.get_meta("hp", 1.0)) - amount
	enemy.set_meta("hp", hp)
	if bool(enemy.get_meta("boss", false)) and hp > 0.0:
		_set_boss_stage(_boss_stage_for(hp))
	if hp > 0.0:
		return false
	var is_boss: bool = bool(enemy.get_meta("boss", false))
	if is_boss:
		boss = null
		boss_stage = 0
		message = "镜心余影 · 已散"
		message_timer = 3.0
	enemies.erase(enemy)
	enemy.queue_free()
	kills += 1
	special_charge = minf(SPECIAL_CHARGE_MAX, special_charge + (40.0 if is_boss else 20.0))
	return true


func damage_player(amount: int) -> void:
	if not active:
		return
	if dodge_invuln > 0.0:
		return
	# 镜壁镜印：受到的伤害 -12%
	var taken := maxi(1, int(round(float(amount) * incoming_mult)))
	player_hp = maxi(0, player_hp - taken)
	hits_taken += 1
	if player_hp <= 0 and game != null:
		message = "镜影涌上来 · 你被推出了镜牢"
		message_timer = 3.0
		game.on_dungeon_defeat()


# --- 门禁 -------------------------------------------------------------------

## 战斗室还有镜影时，通往下一间的门是关着的。
func _update_doors() -> void:
	if game == null or game.attic_worlds == null:
		return
	for room in range(game.attic_worlds.dungeon_room_count() - 1):
		var blocked: bool = enemy_alive_in_room(room) > 0
		var blocker = game.attic_worlds.dungeon_door_blocker(room)
		if blocker == null:
			continue
		(blocker as CollisionShape3D).disabled = not blocked
		var index := room
		if blocked and (index >= door_open.size() or door_open[index] != true):
			if index >= door_open.size():
				door_open.resize(index + 1)
			door_open[index] = true
			message = "门关着 · 先让这一间的镜影安静下来"
			message_timer = 2.4
		elif not blocked:
			if index >= door_open.size():
				door_open.resize(index + 1)
			door_open[index] = false


func room_cleared(room: int) -> bool:
	return enemy_alive_in_room(room) == 0 and not (boss != null and is_instance_valid(boss) and int(boss.get_meta("room", -1)) == room)


# --- HUD 绘制 ---------------------------------------------------------------

func draw_hud(control: Control) -> void:
	var font: Font = null
	if game != null and game.hud != null:
		font = game.hud.font
	if font == null:
		return
	var center := Vector2(control.size.x * 0.5, 0)
	# 生命与能量
	var bar_w := 240.0
	control.draw_rect(Rect2(Vector2(28, 26), Vector2(bar_w, 12)), Color(0.1, 0.12, 0.16, 0.8))
	control.draw_rect(Rect2(Vector2(28, 26), Vector2(bar_w * float(player_hp) / float(hp_max), 12)),
		Color(0.86, 0.42, 0.42, 0.95))
	control.draw_rect(Rect2(Vector2(28, 46), Vector2(bar_w, 8)), Color(0.1, 0.12, 0.16, 0.8))
	control.draw_rect(Rect2(Vector2(28, 46), Vector2(bar_w * energy / 100.0, 8)), Color(0.48, 0.82, 0.9, 0.95))
	control.draw_rect(Rect2(Vector2(28, 60), Vector2(bar_w, 6)), Color(0.1, 0.12, 0.16, 0.8))
	control.draw_rect(Rect2(Vector2(28, 60), Vector2(bar_w * special_charge / SPECIAL_CHARGE_MAX, 6)),
		Color(0.86, 0.78, 0.4, 0.95))
	control.draw_string(font, Vector2(28, 92), "镜牢 · 击退 %d · 受击 %d" % [kills, hits_taken],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.86, 0.92, 0.9))
	control.draw_string(font, Vector2(28, 112), "左键 凝光 · 右键 镜爆 · Space 闪避 · 1/2/3 换武器",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.82, 0.84, 0.8))
	# 三把武器：当前那把高亮
	var wx := 28.0
	for id in WEAPON_ORDER:
		var row: Array = WEAPONS[id]
		var active: bool = id == weapon_id
		var label := "%d %s" % [WEAPON_ORDER.find(id) + 1, String(row[0])]
		var width := 92.0
		control.draw_rect(Rect2(Vector2(wx, 140), Vector2(width, 22)),
			Color(0.5, 0.7, 0.75, 0.28) if active else Color(0.2, 0.26, 0.3, 0.35))
		control.draw_string(font, Vector2(wx + 8, 156), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.94, 0.96, 0.92) if active else Color(0.62, 0.7, 0.72, 0.8))
		wx += width + 6.0
	var boon_text := "镜印 0"
	if not boons.is_empty():
		var names: Array = []
		for id in boons:
			names.append(String(BOONS[id][0]))
		boon_text = "镜印 %d · %s" % [boons.size(), " / ".join(names)]
	control.draw_string(font, Vector2(28, 176), boon_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.86, 0.86, 0.62, 0.9))
	if boss != null and is_instance_valid(boss):
		var hp: float = float(boss.get_meta("hp", BOSS_HP))
		control.draw_rect(Rect2(Vector2(center.x - 180.0, 30.0), Vector2(360, 10)), Color(0.1, 0.1, 0.14, 0.85))
		control.draw_rect(Rect2(Vector2(center.x - 180.0, 30.0), Vector2(360.0 * hp / BOSS_HP, 10)),
			Color(0.8, 0.6, 0.9, 0.95))
		control.draw_string(font, Vector2(center.x - 180.0, 24.0),
			"镜心余影 · %s" % BOSS_PHASES[maxi(0, boss_stage - 1)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.84, 0.95))
	if message != "":
		control.draw_string(font, Vector2(center.x - 150.0, control.size.y - 60.0), message,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.92, 0.9, 0.8, 0.92))
