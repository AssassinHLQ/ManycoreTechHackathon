extends SceneTree

## Exercise the real ending button, interaction dispatch, reload, and title restart.
const KNOWLEDGE_PATH := "user://attic_flow_test_knowledge.json"
const PROGRESS_PATH := "user://attic_flow_test_progress.json"
var game
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS  ", label)
	else:
		failures += 1
		push_error("FAIL  " + label)


func _cleanup() -> void:
	for path in [KNOWLEDGE_PATH, PROGRESS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	_cleanup()
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = KNOWLEDGE_PATH
	game.progress_path = PROGRESS_PATH
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	while game.world_build_remaining:
		await process_frame
	game.start_game()
	_check(not game.in_attic and game.player.get_parent() == game.home,
		"normal start enters the solar system")
	_check(game.missing_clues().size() == 3, "three universe coordinates initially missing")
	# Drive the same discovery events as completed scans; no developer shortcuts.
	for id in ["qinglan", "zheya", "cangbo", "xuanjing"]:
		game.discover(id)
	_check(game.missing_clues().is_empty(), "three coordinates satisfy universe encryption")
	game.discover("xuanyuan")
	_check(game.state == "end", "final universe discovery opens the ending")
	var entry: Button
	for node in game.hud.ending.find_children("*", "Button", true, false):
		if node.text.begins_with("继续航行 · 前往归航站"):
			entry = node
	_check(entry != null, "universe ending guides the player to the station")
	if entry == null:
		game.queue_free()
		await process_frame
		_cleanup()
		quit(1)
		return
	entry.pressed.emit()
	_check(not game.in_attic and game.state == "walk", "ending resumes the universe without teleporting")
	preload("res://tests/home_fixture.gd").enter(game)
	_check(game.in_attic and game.state == "walk" and game.player.get_parent() == game.attic,
		"station door interaction enters the attic after the ending")
	var before: float = game.elapsed
	await process_frame
	_check(is_equal_approx(before, game.elapsed), "universe timer pauses in the attic")
	# Complete and reload all four keepsakes, including the two old mismatched IDs.
	for key in ["snow", "cloud", "firefly", "alley"]:
		game.collect_keepsake(key)
	_check(game.progress.is_unlocked("keepsake_forest"), "forest reward matches achievement catalogue")
	_check(game.progress.is_unlocked("keepsake_rain"), "alley reward matches achievement catalogue")
	game.enter_pocket("mirror")
	game.player.global_position = game.attic_worlds.heart_anchor("mirror").global_position
	game._interact()
	_check(game.has_prism_heart, "E at the mirror centre collects the heart without a combat gate")
	var heart_model = game.attic_worlds.world_node("mirror").find_child("PrismHeartModel", true, false)
	_check(heart_model != null and not heart_model.is_visible_in_tree(), "pickup hides the generated heart model")
	_check(not game.near_prism_heart(), "a collected heart is no longer offered for interaction")
	game.leave_pocket()
	for i in range(3):
		game.attic.advance_tea()
	game.progress.unlock("tea_full")
	game.progress.save()
	# Simulate restarting with an old save as well as canonical achievements.
	game.progress.achievements.erase("keepsake_rain")
	game.progress.achievements["keepsake_firefly"] = true
	game.progress.achievements["keepsake_alley"] = true
	game.progress.save()
	game.queue_free()
	await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = KNOWLEDGE_PATH
	game.progress_path = PROGRESS_PATH
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	while game.world_build_remaining:
		await process_frame
	_check(game.progress.is_unlocked("keepsake_forest") and game.progress.is_unlocked("keepsake_rain"),
		"legacy keepsake IDs migrate to catalogue IDs")
	_check(not game.progress.achievements.has("keepsake_firefly")
		and not game.progress.achievements.has("keepsake_alley"), "migration avoids duplicate achievements")
	_check(game.keepsakes.size() == 4, "all four keepsakes survive reload")
	_check(game.attic.tea_step == 3, "finished tea and its visuals survive reload")
	_check(game.attic.tea_steam.visible and game.attic.tea_cups.all(func(cup): return cup.visible),
		"restored tea includes steam and filled cups")
	_check(game.attic.swallow_node.visible, "alley keepsake restores the windowsill swallow")
	_check(game.has_prism_heart and not game.attic_worlds.heart_node("mirror").visible,
		"reload restores the shelf heart and hides the entire original")
	_check(game.next_worth_doing().contains("航海回声台"), "reload directs completed keepsakes into the linked universe route")
	game.start_game()
	preload("res://tests/home_fixture.gd").enter(game)
	# Check dispatch rather than entering pocket worlds by directly calling their API.
	for door in game.attic.doors:
		var key: String = door["key"]
		game.player.global_position = door["anchor"].global_position
		game._interact()
		_check(game.pocket_key == key, "E enters the %s door regardless of window weather" % key)
		if game.in_pocket():
			game.leave_pocket()
	# Returning through the title must clear both container and gravity state.
	game.enter_pocket("cloud")
	game.guide_card.begin()
	game.guide_card.advance(1)
	game.set_paused(true)
	for node in game.hud.pause_menu.find_children("*", "Button", true, false):
		if node.text == "返回标题":
			node.pressed.emit()
			break
	_check(not game.in_attic and game.pocket_key == "", "return to title clears attic and pocket state")
	_check(game.key_light.visible, "return to title restores the universe key light")
	_check(not game.guide_card.active and not game.progress.guide_done,
		"return to title dismisses a partial guide without marking it complete")
	game.start_game()
	_check(not game.in_attic and game.pocket_key == "" and game.player.get_parent() == game.home,
		"restart uses universe gravity and the universe player parent")
	var clock: float = game.elapsed
	await process_frame
	await process_frame
	_check(game.elapsed > clock, "universe timer resumes after title restart")
	game.return_to_menu()
	var has_demo_button := false
	for node in game.hud.menu.find_children("*", "Button", true, false):
		if (node as Button).text.contains("演示"):
			has_demo_button = true
	_check(not has_demo_button, "title menu no longer offers a timed demo")
	_check(not game.in_attic and game.state == "menu", "return to title stays in the menu")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "all transitions respect --no-capture")
	game.queue_free()
	await process_frame
	_cleanup()
	print("ATTIC FLOW TEST COMPLETE: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
