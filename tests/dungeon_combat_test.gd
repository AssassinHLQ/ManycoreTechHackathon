extends SceneTree
# 镜牢战斗：镜影、三种武器、门禁、镜心三相、受击与战败结算。
# 用法：godot --headless --path . --script res://tests/dungeon_combat_test.gd

var game
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _enter_dungeon() -> void:
	var gate = game.attic_worlds.dungeon_gate_anchor()
	game.player.global_position = (gate as Node3D).global_position
	game._interact()


func _run() -> void:
	var save := "user://starward_combat_test.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_combat_progress.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.enter_attic()
	await physics_frame
	game.enter_pocket("mirror")
	await physics_frame
	_enter_dungeon()
	await physics_frame

	var combat = game.dungeon_controller
	_check(combat != null and combat.active, "进入镜牢后战斗控制器已启动")
	if combat == null:
		quit(1)
		return
	_check(combat.player_hp == 100, "初始生命 100")
	_check(combat.kills == 0 and combat.hits_taken == 0, "初始击杀与受击为 0")

	# --- 战斗室 1 生成镜影，门是关的 ---
	var room0_enemies: int = combat.enemy_alive_in_room(0)
	_check(room0_enemies >= 2, "第 1 间生成了 %d 只镜影" % room0_enemies)
	var blocker = game.attic_worlds.dungeon_door_blocker(0)
	_check(blocker != null, "第 1 间与第 2 间之间有门禁")
	combat._update_doors()
	_check(blocker != null and not (blocker as CollisionShape3D).disabled,
		"还有镜影时门是关着的")

	# --- 凝光：耗能、命中、击杀 ---
	var energy_before: float = combat.energy
	var target = null
	for enemy in combat.enemies:
		if int(enemy.get_meta("room", -1)) == 0:
			target = enemy
			break
	_check(target != null, "找得到一间里的镜影")
	if target != null:
		var origin: Vector3 = (target as Node3D).global_position + Vector3(-3.0, 0.0, 0.0)
		var aim: Vector3 = Vector3(1, 0, 0)
		var result: Dictionary = combat.attack_glow(aim, origin)
		_check(int(result["hit"]) >= 1, "凝光朝目标打能命中")
		_check(absf(combat.energy - (energy_before - 12.0)) < 0.001, "凝光消耗 12 点能量")
		var hp_left: float = float((target as Node3D).get_meta("hp", 0.0))
		_check(hp_left < 30.0, "凝光造成伤害（剩 %.0f）" % hp_left)
		# 打到死
		var guard := 0
		while is_instance_valid(target) and guard < 6:
			combat._attack_cooldown = 0.0
			combat.energy = 100.0
			combat.attack_glow(aim, origin)
			guard += 1
		await process_frame
		_check(not is_instance_valid(target), "连续凝光可以击倒一只镜影")
		_check(combat.kills >= 1, "击杀数增加")

	# --- 镜爆：范围伤害 ---
	combat._attack_cooldown = 0.0
	var blast_energy: float = combat.energy
	var blast: Dictionary = combat.attack_blast(game.player.global_position)
	_check(absf(combat.energy - (blast_energy - 26.0)) < 0.001, "镜爆消耗 26 点能量")
	_check(blast.has("hit"), "镜爆返回命中数")

	# --- 绝技：需要蓄能 ---
	combat.special_charge = 0.0
	var not_ready: Dictionary = combat.attack_special(game.player.global_position)
	_check(not bool(not_ready["ready"]), "蓄能不足时绝技放不出")
	combat.special_charge = 100.0
	# 用一个远离所有敌人的原点，避免绝技打死敌人后回蓄能（击杀会补蓄能）
	var ready: Dictionary = combat.attack_special(Vector3(0, 0, 9999))
	_check(bool(ready["ready"]), "蓄能满了可以放绝技")
	_check(combat.special_charge == 0.0, "放完绝技蓄能清零")

	# --- 清空第 1 间后门打开 ---
	for enemy in combat.enemies.duplicate():
		combat.damage_enemy(enemy, 999.0)
	combat._update_doors()
	_check(combat.room_cleared(0), "第 1 间已清空")
	_check((blocker as CollisionShape3D).disabled, "清空后门禁打开")

	# --- 三把武器（原作：1 棱镜杖 均衡 / 2 镜刃 近战 / 3 折光弩 贯穿） ---
	_check(combat.WEAPONS.size() == 3, "共有三把武器")
	_check(String(combat.WEAPONS["wand"][0]) == "棱镜杖", "1 号是棱镜杖")
	_check(String(combat.WEAPONS["blade"][0]) == "镜刃", "2 号是镜刃")
	_check(String(combat.WEAPONS["crossbow"][0]) == "折光弩", "3 号是折光弩")
	_check(String(combat.WEAPONS["wand"][1]) == "均衡" and String(combat.WEAPONS["blade"][1]) == "近战"
		and String(combat.WEAPONS["crossbow"][1]) == "贯穿", "三把定位与原文一致")
	_check(combat.weapon_id == "wand", "默认拿棱镜杖")
	_check(combat.set_weapon("blade") and combat.weapon_name() == "镜刃", "可以换到镜刃")
	_check(not combat.set_weapon("blade"), "换成同一把不算变化")

	# 清一只空场，自己摆靶子
	for enemy in combat.enemies.duplicate():
		combat.damage_enemy(enemy, 9999.0)
	await process_frame
	var room0_anchor = game.attic_worlds.dungeon_room_anchor(0)
	var origin: Vector3 = (room0_anchor as Node3D).global_position + Vector3(0, 1.2, 0)

	# 镜刃：近战 —— 5 米外的目标打不到
	combat.set_weapon("blade")
	combat._spawn_enemy(0, Vector3(5.0, 0, 0))
	await process_frame
	combat._attack_cooldown = 0.0
	combat.energy = 100.0
	var far_hit: Dictionary = combat.attack_glow(Vector3(1, 0, 0), origin)
	_check(int(far_hit["hit"]) == 0, "镜刃打不到 5 米外的目标（近战）")
	for enemy in combat.enemies.duplicate():
		combat.damage_enemy(enemy, 9999.0)
	await process_frame
	# 镜刃：近距离能一次劈到两个
	combat._spawn_enemy(0, Vector3(1.6, 0, 0.4))
	combat._spawn_enemy(0, Vector3(1.6, 0, -0.4))
	await process_frame
	combat._attack_cooldown = 0.0
	combat.energy = 100.0
	var cleave: Dictionary = combat.attack_glow(Vector3(1, 0, 0), origin)
	_check(int(cleave["hit"]) == 2, "镜刃一次劈到两个近距离目标（劈砍）")
	for enemy in combat.enemies.duplicate():
		combat.damage_enemy(enemy, 9999.0)
	await process_frame

	# 折光弩：贯穿 —— 远处也能打到
	combat.set_weapon("crossbow")
	combat._spawn_enemy(0, Vector3(14.0, 0, 0))
	await process_frame
	combat._attack_cooldown = 0.0
	combat.energy = 100.0
	var pierce: Dictionary = combat.attack_glow(Vector3(1, 0, 0), origin)
	_check(int(pierce["hit"]) >= 1, "折光弩能打到 14 米外的目标（贯穿）")

	# 棱镜杖：均衡 —— 只打最近的一个
	combat.set_weapon("wand")
	combat._spawn_enemy(0, Vector3(3.0, 0, 0.2))
	combat._spawn_enemy(0, Vector3(6.0, 0, 0.2))
	await process_frame
	combat._attack_cooldown = 0.0
	combat.energy = 100.0
	var single: Dictionary = combat.attack_glow(Vector3(1, 0, 0), origin)
	_check(int(single["hit"]) == 1, "棱镜杖只打最近的一个（均衡）")

	# 蓄能满 -> 这一击变成武器绝技（朝没有目标的方向打，避免击杀回蓄能干扰断言）
	combat.special_charge = 100.0
	combat._attack_cooldown = 0.0
	combat.energy = 100.0
	var ult: Dictionary = combat.attack_glow(Vector3(0, 0, -1), origin)
	_check(bool(ult["empowered"]), "蓄能满时凝光升级为武器绝技")
	_check(combat.special_charge == 0.0, "绝技消耗掉蓄能")
	for enemy in combat.enemies.duplicate():
		combat.damage_enemy(enemy, 9999.0)
	await process_frame

	# --- 闪避（原作：空格闪避） ---
	combat.dodge_cooldown = 0.0
	combat.dodge_invuln = 0.0
	combat.energy = 100.0
	var dodged: bool = combat.dodge(Vector3(1, 0, 0))
	_check(dodged, "可以闪避")
	_check(combat.dodge_invuln > 0.0, "闪避期间有无敌帧")
	_check(combat.dodge_cooldown > 0.0, "闪避进入冷却")
	var hp_keep: int = combat.player_hp
	combat.damage_player(30)
	_check(combat.player_hp == hp_keep, "无敌帧内不吃伤害")
	_check(not combat.dodge(Vector3(1, 0, 0)), "冷却中不能再闪")

	# --- 受击与战败 ---
	combat.dodge_invuln = 0.0
	combat.damage_player(10)
	_check(combat.player_hp == 90 and combat.hits_taken == 1, "受击扣血并计数")
	combat.damage_player(200)
	await physics_frame
	_check(not combat.active, "生命归零后战斗结束")
	_check(game.pocket_key == "mirror", "战败后回到镜界")
	_check(int(game.progress.dungeon.get("runs", 0)) == 1, "战败也记一次探索")

	# --- 镜心三相 ---
	game.progress.dungeon = {}
	_enter_dungeon()
	await physics_frame
	combat = game.dungeon_controller
	# 直接推进到 BOSS 房
	var boss_anchor = game.attic_worlds.dungeon_room_anchor(5)
	game.player.global_position = (boss_anchor as Node3D).global_position
	combat._spawn_room_enemies(5)
	await physics_frame
	_check(combat.boss != null, "镜心内厅出现镜心余影")
	_check(combat.boss_stage == 1, "第一形态是初相")
	combat.damage_enemy(combat.boss, 120.0)
	_check(combat.boss_stage == 2, "掉到 2/3 血进入折光相")
	combat.damage_enemy(combat.boss, 120.0)
	_check(combat.boss_stage == 3, "掉到 1/3 血进入逆光相")
	combat.damage_enemy(combat.boss, 200.0)
	await physics_frame
	_check(combat.boss == null and combat.boss_stage == 0, "击破镜心余影")

	# --- 无伤通关结算 ---
	var finish = game.attic_worlds.dungeon_finish_anchor()
	game.player.global_position = (finish as Node3D).global_position
	game._update_dungeon(0.016)
	await physics_frame
	_check(not game.dungeon_active, "抵达尽头后结束")
	_check(int(game.progress.dungeon.get("clears", 0)) == 1, "记了一次通关")
	_check(bool(game.progress.dungeon.get("flawless", false)), "无伤记录已写入")
	_check(game.progress.is_unlocked("dungeon_flawless"), "解锁成就「毫发无伤」")

	game.leave_pocket()
	await physics_frame
	game.leave_attic()
	await physics_frame
	print("DUNGEON COMBAT TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_combat_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if failures == 0 else 1)
