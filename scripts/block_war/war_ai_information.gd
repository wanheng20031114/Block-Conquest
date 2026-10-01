extends RefCounted
## Decisions use public army totals, buildings and observed armies, never hidden garrison distributions.

class IncomingSnapshot extends RefCounted:
	var counts: Dictionary[Vector2i, int] = {}
	var damage: Dictionary[int, float] = {}

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
	# A visible airlift announces its destination and remaining soldiers. They
	# are incoming until they land, then the ordinary garrison owns them once.
	for airlift: Dictionary in game.pig.airlifts:
		var count: int = game.SKILL_RULES.PIG_AIRLIFT_COUNT - int(airlift.landed)
		if count > 0:
			var key := Vector2i(int(airlift.target), int(airlift.faction))
			result[key] = result.get(key, 0) + count
	return result

static func incoming_damage(game: Node3D, building: WarBuilding, incoming: Dictionary[Vector2i, int], faction: int) -> float:
	var attackers: Array[WarMarches.MarchUnit] = []
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.order.target_id == building.building_id and is_unit_known(game, unit, faction) and game.FACTIONS.hostile(building.faction, unit.order.faction):
			attackers.append(unit)
	return _observed_damage(game, building, incoming, attackers)

static func airlift_threats(game: Node3D, faction: int) -> Dictionary[int, float]:
	# Skill planners that independently sample nearby walking troops add only
	# this public falling population, rather than counting all incoming twice.
	var result: Dictionary[int, float] = {}
	for airlift: Dictionary in game.pig.airlifts:
		var target: WarBuilding = game.by_id[int(airlift.target)]
		if game.FACTIONS.hostile(int(airlift.faction), faction) and game.FACTIONS.allied(target.faction, faction):
			var count: int = game.SKILL_RULES.PIG_AIRLIFT_COUNT - int(airlift.landed)
			if count > 0:
				result[target.building_id] = result.get(target.building_id, 0.0) + count * game.combat_multiplier(int(airlift.faction), target)
	return result

static func snapshot_defense(game: Node3D, faction: int) -> IncomingSnapshot:
	# This observation ends before a skill/order changes the battlefield. Keep
	# each target's original soldier order so damage additions remain identical.
	var result := IncomingSnapshot.new()
	var attackers_by_target: Dictionary[int, Array] = {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not is_unit_known(game, unit, faction):
			continue
		var key := Vector2i(unit.order.target_id, unit.order.faction)
		result.counts[key] = result.counts.get(key, 0) + 1
		if not game.FACTIONS.hostile(unit.order.faction, faction):
			continue
		var target: WarBuilding = game.by_id[unit.order.target_id]
		if not game.FACTIONS.allied(target.faction, faction):
			continue
		if not attackers_by_target.has(key.x):
			attackers_by_target[key.x] = []
		attackers_by_target[key.x].append(unit)
	for airlift: Dictionary in game.pig.airlifts:
		var count: int = game.SKILL_RULES.PIG_AIRLIFT_COUNT - int(airlift.landed)
		if count <= 0:
			continue
		var key := Vector2i(int(airlift.target), int(airlift.faction))
		result.counts[key] = result.counts.get(key, 0) + count
		var target: WarBuilding = game.by_id[key.x]
		if game.FACTIONS.hostile(key.y, faction) and game.FACTIONS.allied(target.faction, faction) and not attackers_by_target.has(key.x):
			attackers_by_target[key.x] = []
	for target_id: int in attackers_by_target:
		result.damage[target_id] = _observed_damage(game, game.by_id[target_id], result.counts, attackers_by_target[target_id])
	return result

static func _observed_damage(game: Node3D, building: WarBuilding, incoming: Dictionary[Vector2i, int], attackers: Array) -> float:
	var damage := 0.0
	# Calculate only factions actually attacking this building, and reuse each
	# distinct temporary bonus. All values are local to this unchanged observation.
	var bases := PackedFloat64Array()
	bases.resize(game.faction_count)
	var adjusted_by_attacker: Array[Dictionary] = []
	for attacker: int in game.faction_count:
		adjusted_by_attacker.append({})
		if game.FACTIONS.hostile(building.faction, attacker):
			var count: int = incoming.get(Vector2i(building.building_id, attacker), 0)
			if count == 0:
				continue
			bases[attacker] = game.combat_multiplier(attacker, building)
			damage += count * bases[attacker]
	# The snapshot counts soldiers. Apply strength and temporary attack bonuses
	# only to those same observed soldiers, including their visible levitation.
	for unit: WarMarches.MarchUnit in attackers:
		var base: float = bases[unit.order.faction]
		damage += (unit.order.strength - 1.0) * base
		var bonus: float = game.marches.projected_attack_bonus(unit)
		# Keep the original multiply/divide order when a skill changes attack.
		var adjusted := base
		if bonus != 0.0:
			var values := adjusted_by_attacker[unit.order.faction]
			if not values.has(bonus):
				values[bonus] = game.combat_multiplier(unit.order.faction, building, bonus)
			adjusted = values[bonus]
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
