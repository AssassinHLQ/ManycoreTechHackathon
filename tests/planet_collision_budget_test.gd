extends SceneTree
const Budget = preload("res://scripts/planet_collision_budget.gd")
var failures := 0

class Game extends Node3D:
	var planets := []
	var player := Node3D.new()
	var ship := Node3D.new()
class Planet extends Node3D:
	var radius := 100.0

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _run() -> void:
	var game := Game.new()
	root.add_child(game)
	game.add_child(game.player)
	game.add_child(game.ship)
	var planet := Planet.new()
	game.add_child(planet)
	game.planets.append(planet)
	var body := StaticBody3D.new()
	planet.add_child(body)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	var budget := Budget.new()
	budget.game = game
	game.add_child(budget)
	budget.set_physics_process(false)
	budget._physics_process(0.0)
	_check(body.process_mode == Node.PROCESS_MODE_INHERIT, "nearby buildings keep collision")
	planet.position.x = 10000.0
	budget._physics_process(0.0)
	_check(body.process_mode == Node.PROCESS_MODE_DISABLED, "distant moving buildings leave the physics space")
	var terrain := StaticBody3D.new()
	terrain.name = "TerrainCollision"
	planet.add_child(terrain)
	budget._physics_process(0.0)
	_check(terrain.process_mode == Node.PROCESS_MODE_DISABLED, "late-loaded terrain follows the same budget")
	game.player.position.x = 5000.0
	budget._physics_process(0.0)
	_check(body.process_mode == Node.PROCESS_MODE_INHERIT and terrain.process_mode == Node.PROCESS_MODE_INHERIT, "player approach restores buildings and terrain before landing")
	game.player.position = Vector3.ZERO
	game.ship.position.x = 5000.0
	budget._physics_process(0.0)
	_check(body.process_mode == Node.PROCESS_MODE_INHERIT, "a nearby ship also keeps collision awake")
	game.ship.position = Vector3.ZERO
	budget._physics_process(0.0)
	game.player.position.x = 4100.0
	budget._physics_process(0.0)
	_check(body.process_mode == Node.PROCESS_MODE_DISABLED, "hysteresis prevents repeated physics activation at the boundary")
	game.player.position.x = 9000.0
	budget._physics_process(0.0)
	await physics_frame
	await physics_frame
	var hit := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(10000, 5, 0), Vector3(10000, -5, 0)))
	_check(hit.get("collider") == body, "restored collision really blocks a physics ray")
	game.free()
	print("PLANET COLLISION BUDGET TEST COMPLETE: ", failures, " failures")
	quit(0 if failures == 0 else 1)
