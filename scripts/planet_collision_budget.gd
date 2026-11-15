extends Node
## Distant orbiting buildings do not need to update the physics broad phase.
## Restore them well before either traveller approaches the surface.
const WAKE_MARGIN := 5000.0
const SLEEP_MARGIN := 6500.0
var game
var entries := {}

func _ready() -> void:
	process_physics_priority = -100
	# Snapshots must retain the authored enabled state of every collision body.
	if "--rebake-runtime" in OS.get_cmdline_user_args():
		set_physics_process(false)

func _remember(entry: Dictionary, body: StaticBody3D) -> void:
	entry.bodies.append([body, body.process_mode, body.disable_mode])
	if not entry.active:
		body.disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
		body.process_mode = Node.PROCESS_MODE_DISABLED

func _physics_process(_delta: float) -> void:
	if game == null or game.player == null or game.ship == null:
		return
	for planet in game.planets:
		var id: int = planet.get_instance_id()
		if not entries.has(id):
			var entry := {"active": true, "bodies": [], "terrain": null}
			for body in planet.find_children("*", "StaticBody3D", true, false):
				_remember(entry, body)
			entries[id] = entry
		var entry: Dictionary = entries[id]
		# Terrain collision is loaded separately as the traveller approaches.
		var terrain: StaticBody3D = planet.get_node_or_null("TerrainCollision")
		if terrain != entry.terrain:
			entry.terrain = terrain
			if terrain != null:
				var known := false
				for saved in entry.bodies:
					if saved[0] == terrain: known = true
				if not known: _remember(entry, terrain)
		var distance: float = minf(planet.global_position.distance_to(game.player.global_position),
			planet.global_position.distance_to(game.ship.global_position))
		var margin: float = SLEEP_MARGIN if entry.active else WAKE_MARGIN
		var active: bool = distance <= planet.radius + margin
		if active == entry.active:
			continue
		entry.active = active
		for saved in entry.bodies:
			var body: StaticBody3D = saved[0]
			if not is_instance_valid(body): continue
			body.disable_mode = saved[2] if active else CollisionObject3D.DISABLE_MODE_REMOVE
			body.process_mode = saved[1] if active else Node.PROCESS_MODE_DISABLED
