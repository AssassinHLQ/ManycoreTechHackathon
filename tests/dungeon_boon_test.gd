extends SceneTree
# 镜印增益：静镜室取印、五枚镜印生效、每室一枚、结算带上镜印。
# 用法：godot --headless --path . --script res://tests/dungeon_boon_test.gd

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
	var save := "user://starward_boon_test.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = "user://starward_boon_progress.json"
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
	_check(combat != null and combat.active, "战斗控制器已启动")
	if combat == null:
		return_fail()

	# --- 原作的五枚镜印 ---
	_check(combat.BOON_IDS.size() == 5, "共五枚镜印")
	_check(String(combat.BOONS["edge"][0]) == "锋面镜印", "edge 是锋面镜印")
	_check(String(combat.BOONS["edge"][1]) == "所有武器伤害 +18%", "锋面镜印效果与原文一致")
	_check(String(combat.BOONS["vitality"][1]) == "镜息上限 +20，并立即回复 20", "宽息镜印效果一致")
	_check(String(combat.BOONS["flow"][1]) == "凝光消耗 -12%", "流光镜印效果一致")
	_check(String(combat.BOONS["guard"][1]) == "受到的伤害 -12%", "镜壁镜印效果一致")
	_check(String(combat.BOONS["regen"][1]) == "镜息自然回复 +30%", "回息镜印效果一致")
	var options: Array = combat.boon_options(1)
	_check(options.size() == 3, "每个静镜室给三枚候选")
	_check(not (options[0] == options[1] or options[1] == options[2] or options[0] == options[2]),
		"三枚候选互不相同")

	# --- 静镜室里有镜印台 ---
	_check(game.attic_worlds.dungeon_room_kind(1) == "boon", "第 2 间是静镜室")
	_check(game.attic_worlds.dungeon_boon_count(1) == 3, "静镜室有三枚镜印碎片")
	_check(game.attic_worlds.dungeon_boon_count(4) == 3, "第 5 间静镜室也有三枚")
	_check(game.attic_worlds.dungeon_boon_count(0) == 0, "战斗室没有镜印台")

	# --- 走到静镜室，取一枚 ---
	var room_anchor = game.attic_worlds.dungeon_room_anchor(1)
	game.player.global_position = (room_anchor as Node3D).global_position
	game._update_dungeon(0.016)
	await physics_frame
	_check(game.dungeon_room == 1, "已站在静镜室")
	var shard_anchor = game.attic_worlds.dungeon_boon_anchor(1, 0)
	_check(shard_anchor != null, "第一枚镜印可取")
	if shard_anchor != null:
		game.player.global_position = (shard_anchor as Node3D).global_position
		await physics_frame
		_check(game.near_dungeon_boon() == 0, "站在镜印旁能识别")
		game._interact()
		await physics_frame
		_check(combat.boons.size() == 1, "取走一枚镜印")
		_check(game.attic_worlds.dungeon_boon_room_taken(1), "本室其余镜印一并收起")
		_check(game.attic_worlds.dungeon_boon_anchor(1, 1) == null, "同室的第二枚不再可取")

	# --- 五枚镜印的效果（直接调 apply_boon，逐条核对） ---
	# 先清空状态：刚才取到的那枚恰好可能就是接下来要测的那一枚（静镜室候选按房间轮换）
	combat.boons.clear()
	combat.damage_mult = 1.0
	combat.glow_cost_mult = 1.0
	combat.incoming_mult = 1.0
	combat.breath_regen = 1.5
	combat.hp_max = 100
	combat.player_hp = 100
	# 锋面：武器伤害 +18%
	var before_mult: float = combat.damage_mult
	combat.apply_boon("edge")
	_check(absf(combat.damage_mult - before_mult * 1.18) < 0.001, "锋面镜印：武器伤害 ×1.18")
	# 用一只镜影验证实际伤害
	var room0 = game.attic_worlds.dungeon_room_anchor(0)
	combat._spawn_room_enemies(0)
	await physics_frame
	var target = null
	for enemy in combat.enemies:
		if int(enemy.get_meta("room", -1)) == 0:
			target = enemy
			break
	if target != null:
		var hp_before: float = float((target as Node3D).get_meta("hp", 0.0))
		var origin: Vector3 = (target as Node3D).global_position + Vector3(-3, 0, 0)
		combat._attack_cooldown = 0.0
		combat.energy = 100.0
		combat.attack_glow(Vector3(1, 0, 0), origin)
		var lost: float = hp_before - float((target as Node3D).get_meta("hp", 0.0))
		_check(absf(lost - 15.0 * 1.18) < 0.05, "锋面镜印让凝光伤害变成 %.1f" % lost)
	# 宽息：镜息上限 +20 并回复 20
	combat.player_hp = 50
	combat.apply_boon("vitality")
	_check(combat.hp_max == 120, "宽息镜印：镜息上限 120")
	_check(combat.player_hp == 70, "宽息镜印：立即回复 20")
	# 流光：凝光消耗 -12%
	combat.apply_boon("flow")
	_check(absf(combat.glow_cost_mult - 0.88) < 0.001, "流光镜印：凝光消耗 ×0.88")
	combat._attack_cooldown = 0.0
	combat.energy = 100.0
	combat.attack_glow(Vector3(1, 0, 0), Vector3(0, 0, 9999))
	_check(absf(combat.energy - (100.0 - 12.0 * 0.88)) < 0.01, "凝光实际消耗 10.56 能量")
	# 镜壁：受到伤害 -12%
	combat.apply_boon("guard")
	var hp_before_hit: int = combat.player_hp
	combat.damage_player(10)
	_check(hp_before_hit - combat.player_hp == 9, "镜壁镜印：10 点伤害只吃 9 点")
	# 回息：自然回复 +30%
	combat.apply_boon("regen")
	_check(absf(combat.breath_regen - 1.5 * 1.3) < 0.001, "回息镜印：回复速度 ×1.3")
	_check(combat.boons.size() == 5 or combat.boons.size() >= 4, "镜印会被记入本次携带")

	# --- 结算带上镜印 ---
	var finish = game.attic_worlds.dungeon_finish_anchor()
	game.player.global_position = (finish as Node3D).global_position
	game._update_dungeon(0.016)
	await physics_frame
	_check(int(game.progress.dungeon.get("total_boons", 0)) >= 5, "结算把携带的镜印记进总数")
	_check(game.progress.dungeon.get("last_boons", []).size() >= 5, "结算保存了本次携带的镜印")

	game.leave_pocket()
	await physics_frame
	game.leave_attic()
	await physics_frame
	print("DUNGEON BOON TEST COMPLETE: ", failures, " failure(s)")
	game.queue_free()
	await process_frame
	for path in [save, "user://starward_boon_progress.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if failures == 0 else 1)


func return_fail() -> void:
	failures += 1
	print("DUNGEON BOON TEST COMPLETE: ", failures, " failure(s)")
	quit(1)
