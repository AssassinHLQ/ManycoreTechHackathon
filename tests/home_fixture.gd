extends RefCounted

## Position a test voyage at the production station entrance, then use its E interaction.
static func enter(game) -> void:
	if game.in_attic:
		game.enter_attic()
		return
	arrive(game)
	game._interact()


static func arrive(game) -> void:
	if game.state == "menu":
		game.start_game()
	elif game.state == "end":
		game.continue_after_end()
	game.ship.landed = false
	game.ship.docked = false
	game.ship.dock_station(game.station)
	game.enter_station()
	game.player.global_position = game.station.home_door_position()
