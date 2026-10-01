extends RefCounted
## Frog spells share the same simulation and paid cast path for human and AI.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")

static func mist_defense_bonus(game: Node3D, building: Node3D) -> float:
	# Derive coverage from the same fields on host and replica. Allegiance is
	# checked against the current owner, so capture cannot retain an old curse.
	for faction: int in game.marches.weak_zones:
		if FACTIONS.hostile(faction, building.faction) and game.marches._inside_mist(building.global_position, game.marches.weak_zones[faction]):
			return RULES.FROG_BUILDING_DEFENSE
	return 0.0

static func strike_loss(building: WarBuilding) -> int:
	return floori(building.population * RULES.FROG_STRIKE_FRACTION + 0.000001)

static func valid_target(_game: Node3D, index: int, target: WarBuilding, faction: int) -> bool:
	return index == 3 and not FACTIONS.allied(target.faction, faction) and (strike_loss(target) > 0 or target.level > 1 or target.is_constructing)

static func strike(game: Node3D, target: WarBuilding, faction: int) -> void:
	# Direct population loss bypasses defense and the bear's link.
	# Ownership and actual marching soldiers stay put.
	var loss := strike_loss(target)
	target.population -= loss
	game.world_effects.garrison_blast(target, loss)
	target.cancel_construction()
	target.level = 1
	if target.queued_population > floori(target.population):
		game.marches.trim_departures(target.building_id, target.faction, floori(target.population))
	target.refresh_visual()
	game.world_effects.get_node("Frog").release(3, faction, target.global_position)
	game.audio.play_world(&"war_frog_strike", target.global_position)
