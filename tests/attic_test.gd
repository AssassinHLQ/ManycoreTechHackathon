extends SceneTree

## 阁楼（地面线）自测：结构、碰撞、交互锚点与朝向。

const AtticScript = preload("res://scripts/attic.gd")

var checks := 0
var failures := 0


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS  ", label)
	else:
		failures += 1
		push_error("FAIL  " + label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var attic = AtticScript.new()
	attic.name = "Attic"
	root.add_child(attic)
	attic.build()
	await process_frame

	var nodes: Array = attic.find_children("*", "", true, false)
	_check(nodes.size() > 150, "attic builds a body of geometry (%d nodes)" % nodes.size())

	var shapes: Array = attic.find_children("*", "CollisionShape3D", true, false)
	_check(shapes.size() >= 8, "attic has walkable collision (%d shapes)" % shapes.size())

	var expected_anchors := [
		"AtticAnchor_Window", "AtticAnchor_Mirror", "AtticAnchor_Booklet",
		"AtticAnchor_Kettle", "AtticAnchor_Tea", "AtticAnchor_Shelf",
		"AtticAnchor_Lantern", "AtticAnchor_Record",
		"AtticAnchor_Door_Snow", "AtticAnchor_Door_Cloud",
		"AtticAnchor_Door_Firefly", "AtticAnchor_Door_Alley",
	]
	var missing: Array = []
	for name in expected_anchors:
		if not attic.anchors.has(name):
			missing.append(name)
	_check(missing.is_empty(), "every interaction anchor exists %s" % str(missing))

	_check(attic.doors.size() == 4, "four doors to faraway places")
	var keys: Array = []
	for entry in attic.doors:
		keys.append(entry["key"])
	_check(keys.size() == 4 and keys.has("snow") and keys.has("cloud") and keys.has("firefly") and keys.has("alley"),
		"doors cover snow / cloud / firefly / alley %s" % str(keys))

	var up: Vector3 = attic.up_direction()
	_check(absf(up.length() - 1.0) < 0.001 and up.dot(Vector3.UP) > 0.99, "attic up direction is +Y")

	_check(attic.is_interior_position(attic.to_global(Vector3(0, 1.0, 0))), "room centre counts as interior")
	_check(not attic.is_interior_position(attic.to_global(Vector3(40, 1.0, 40))), "far point is outside the attic")

	var mirror: Array = attic.find_children("MirrorCorridor", "Node3D", true, false)
	_check(mirror.size() == 1, "mirror corridor frame exists")
	var shelf: Array = attic.find_children("TravelShelf", "Node3D", true, false)
	_check(shelf.size() == 1, "travel shelf exists")

	var lights: Array = attic.find_children("*", "OmniLight3D", true, false)
	_check(lights.size() >= 3, "attic is lit (%d lights)" % lights.size())

	print("ATTIC TEST COMPLETE: %d checks, %d failure(s)" % [checks, failures])
	attic.queue_free()
	await process_frame

	# ---- 第二段：接入游戏状态机 ----
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://attic_test_save.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	await process_frame
	game.start_game()
	await physics_frame

	game.enter_attic()
	await process_frame
	_check(game.in_attic and game.state == "walk", "enter_attic switches to attic walk state")
	_check(game.player.get_parent() == game.attic, "player is reparented into the attic")
	var local: Vector3 = game.attic.to_local(game.player.global_position)
	_check(absf(local.x) < 3.4 and local.y > 0.0 and local.y < 3.6 and absf(local.z) < 2.9,
		"player stands inside the attic bounds")

	await physics_frame
	await physics_frame
	_check(game.player.up_direction.dot(Vector3.UP) > 0.9, "player up aligns with the attic")

	var before_elapsed: float = game.elapsed
	await process_frame
	await process_frame
	_check(is_equal_approx(game.elapsed, before_elapsed), "loop clock pauses while in the attic")

	game.leave_attic()
	await process_frame
	_check(not game.in_attic and game.player.get_parent() == game, "leave_attic returns to the solar system")

	print("ATTIC TEST COMPLETE: %d checks, %d failure(s)" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
