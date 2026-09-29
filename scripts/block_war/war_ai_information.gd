extends RefCounted
## Decisions use public buildings and observed armies, never hidden enemy stockpiles.

static func garrison_estimate(game: Node3D, building: WarBuilding, faction: int) -> float:
	if building.faction < 0 or game.FACTIONS.allied(building.faction, faction):
		return building.population
	# Non-producing buildings have no population cap. Their estimate must depend
	# on their visible type/level rather than their hidden reinforcement history.
	match building.kind:
		0: return building.capacity * 0.5
		1: return 20.0 + 10.0 * (building.level - 1)
		_: return 20.0

static func is_unit_known(game: Node3D, unit: WarMarches.MarchUnit, faction: int) -> bool:
	return unit.alive and (game.FACTIONS.allied(unit.order.faction, faction) or (unit.is_exposed() and not unit.cloaked))

static func snapshot_incoming(game: Node3D, faction: int) -> Dictionary[Vector2i, int]:
	var result: Dictionary[Vector2i, int] = {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if is_unit_known(game, unit, faction):
			var key := Vector2i(unit.order.target_id, unit.order.faction)
			result[key] = result.get(key, 0) + 1
	return result

static func incoming_damage(game: Node3D, building: WarBuilding, incoming: Dictionary[Vector2i, int], faction: int) -> float:
	var damage := 0.0
	for attacker: int in game.faction_count:
		if game.FACTIONS.hostile(building.faction, attacker):
			damage += incoming.get(Vector2i(building.building_id, attacker), 0) * game.combat_multiplier(attacker, building)
	# The snapshot counts soldiers. Apply strength and temporary attack bonuses
	# only to those same observed soldiers, including their visible levitation.
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not is_unit_known(game, unit, faction) or unit.order.target_id != building.building_id or not game.FACTIONS.hostile(building.faction, unit.order.faction):
			continue
		damage += (unit.order.strength - 1.0) * game.combat_multiplier(unit.order.faction, building)
		damage += unit.order.strength * (game.combat_multiplier(unit.order.faction, building, game.marches.projected_attack_bonus(unit)) - game.combat_multiplier(unit.order.faction, building))
	return damage

static func team_strength(game: Node3D, team: int, faction: int) -> float:
	var result := 0.0
	for building: WarBuilding in game.buildings:
		if game.FACTIONS.allied(building.faction, team):
			# Known reservations are counted as units below, once rather than again
			# inside their source. Enemy queues remain part of an estimated garrison.
			result += building.available_population if game.FACTIONS.allied(building.faction, faction) else garrison_estimate(game, building, faction)
	for unit: WarMarches.MarchUnit in game.marches._units:
		if game.FACTIONS.allied(unit.order.faction, team) and is_unit_known(game, unit, faction):
			result += unit.order.strength
	return result
