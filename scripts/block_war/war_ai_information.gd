extends RefCounted
## Decisions use public army totals, buildings and observed armies, never hidden garrison distributions.

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
	# One evaluation observes an unchanged battlefield. Reuse each attacker's
	# base multiplier instead of rescanning every forge for each incoming soldier.
	var bases := PackedFloat64Array()
	bases.resize(game.faction_count)
	for attacker: int in game.faction_count:
		if game.FACTIONS.hostile(building.faction, attacker):
			bases[attacker] = game.combat_multiplier(attacker, building)
			damage += incoming.get(Vector2i(building.building_id, attacker), 0) * bases[attacker]
	# The snapshot counts soldiers. Apply strength and temporary attack bonuses
	# only to those same observed soldiers, including their visible levitation.
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.order.target_id != building.building_id or not is_unit_known(game, unit, faction) or not game.FACTIONS.hostile(building.faction, unit.order.faction):
			continue
		var base: float = bases[unit.order.faction]
		damage += (unit.order.strength - 1.0) * base
		var bonus: float = game.marches.projected_attack_bonus(unit)
		# Keep the original multiply/divide order when a skill changes attack.
		var adjusted: float = base if bonus == 0.0 else game.combat_multiplier(unit.order.faction, building, bonus)
		damage += unit.order.strength * (adjusted - base)
	return damage

static func team_strength(game: Node3D, team: int, faction: int) -> float:
	var result := 0.0
	for member: int in game.faction_count:
		if game.FACTIONS.allied(member, team):
			# Public totals already include garrisons, reservations and hidden armies
			# exactly once, without revealing where those soldiers are stationed.
			result += game.total_for(member)
	for unit: WarMarches.MarchUnit in game.marches._units:
		if game.FACTIONS.allied(unit.order.faction, team) and is_unit_known(game, unit, faction):
			# The base soldier is in the public total; only observed bonuses add strength.
			result += unit.order.strength - 1.0
	return result
