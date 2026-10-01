extends RefCounted
## A garrison stays in its building until departure; exposed orders are armies.

static func transfer(game: Node3D, faction: int, recipients: Array[int]) -> Dictionary:
	assert(not recipients.is_empty() and game.is_authority())
	var owners: Dictionary[int, int] = {}
	var cancelled := 0
	for building: WarBuilding in game.buildings:
		if building.faction != faction: continue
		owners[building.building_id] = recipients.pick_random()
		building.population *= 0.6
		var old_queue := building.queued_population
		# Trim before ownership changes: the ordinary signal validates its source.
		game.marches.trim_departures(building.building_id, faction, floori(building.population))
		cancelled += old_queue - building.queued_population
		game.bear.clear_building(game, building.building_id)
		game._clear_building_burrow(building)
		game.pig.clear_building(game, building.building_id)
		building.faction = owners[building.building_id]
		building.refresh_visual()
	# Caster-bound fields expire without replacing a receiver's skill account.
	# Paid construction, hostile disruption and building shields remain intact.
	game._cancel_recruitment(faction)
	game.faction_skills[faction].durations.fill(0.0)
	# A bear may have cast on buildings owned by teammates or enemies. Clear
	# those caster-owned effects as well as the transferred buildings above.
	for id: int in game.bear.links.keys():
		if game.bear.links[id].faction == faction: game.bear.links.erase(id)
	for id: int in game.bear.locks.keys():
		if game.bear.locks[id].faction == faction: game.bear.locks.erase(id)
	for id: int in game.bear.wards.keys():
		if game.bear.wards[id].faction == faction: game.bear.wards.erase(id)
	game.marches.haste_zones.erase(faction)
	game.marches.slow_zones.erase(faction)
	game.marches.weak_zones.erase(faction)
	var orders: Dictionary[Vector2i, WarMarches.MarchOrder] = {}
	var army_owners: Dictionary[int, int] = {}
	var transferred := 0
	for unit: WarMarches.MarchUnit in game.marches._units:
		# Keep projectile targets alive and preserve their exact object identity.
		if unit.intercepted_by == faction: unit.intercepted_by = recipients[0]
		if unit.order.faction != faction: continue
		var original := unit.order
		var receiver: int
		if unit.pending_departure:
			receiver = owners[original.source_id]
		else:
			if not army_owners.has(original.order_id): army_owners[original.order_id] = recipients.pick_random()
			receiver = army_owners[original.order_id]
		var key := Vector2i(original.order_id, receiver)
		if not orders.has(key): orders[key] = game.marches.transfer_order(original, receiver)
		unit.order = orders[key]
		transferred += 1
	for fire: RefCounted in game.fire_states:
		if fire.faction == faction: fire.faction = recipients.pick_random()
	for drop: Dictionary in game.pig.drops:
		if drop.faction == faction: drop.faction = recipients.pick_random()
	# Airborne reinforcements are already committed soldiers, not garrisons.
	# Keep each wave together and preserve its settled batches and destination.
	for airlift: Dictionary in game.pig.airlifts:
		if airlift.faction != faction: continue
		airlift.faction = recipients.pick_random()
		transferred += game.SKILL_RULES.PIG_AIRLIFT_COUNT - int(airlift.landed)
	game.marches._render()
	game.world_effects.update_skills(0.0, game.faction_skills, game.shields, game.by_id, game.marches)
	game.world_effects.get_node("Bear").sync(game.bear, game.marches, game.by_id, 0.0)
	game.world_effects.get_node("Frog").sync(game.marches, 0.0)
	game.world_effects.get_node("PigEffects").sync_airlifts(game.pig.airlifts, game.by_id)
	return {"buildings": owners.size(), "soldiers": transferred, "cancelled_reservations": cancelled}
