extends RefCounted
## Host-owned departure buffs, generated reinforcements and giant-pig impact.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const CAST_SOUNDS: Array[StringName] = [&"war_pig_charge", &"war_pig_fly", &"war_pig_airlift", &"war_pig_drop"]
const IMPACT_SOUND := &"war_pig_impact"
var ready: Dictionary[int, Vector3] = {}
var ready_owners: Dictionary[int, int] = {}
var drops: Array[Dictionary] = []
var next_drop_id := 1
var airlifts: Array[Dictionary] = []
var next_airlift_id := 1

func valid_target(index: int, target: WarBuilding, faction: int) -> bool:
	if index == 2: return true
	return index >= 0 and index < 2 and target.faction == faction and flags_for(target.building_id)[index] <= 0.0

func flags_for(id: int) -> Vector3:
	return ready.get(id, Vector3.ZERO)

func limit_for(id: int) -> int:
	var flags := flags_for(id)
	if flags.x > 0.0: return RULES.PIG_CHARGE_LIMIT
	if flags.y > 0.0: return RULES.PIG_FLIGHT_LIMIT
	return 2147483647

func pending_for(faction: int) -> int:
	var result := 0
	for airlift: Dictionary in airlifts:
		if airlift.faction == faction:
			result += RULES.PIG_AIRLIFT_COUNT - int(airlift.landed)
	return result

func start_airlift(game: Node3D, target: WarBuilding, faction: int) -> void:
	airlifts.append({"id": next_airlift_id, "faction": faction, "target": target.building_id, "age": 0.0, "landed": 0})
	next_airlift_id += 1
	_sync_durations(game)
	game.world_effects.get_node("PigEffects").sync_airlifts(airlifts, game.by_id)

func arm(game: Node3D, index: int, target: WarBuilding, faction: int) -> void:
	var flags := flags_for(target.building_id)
	flags[index] = RULES.PIG_READY_DURATION
	ready[target.building_id] = flags
	ready_owners[target.building_id] = faction
	_sync_durations(game)
	game.world_effects.pig_ready(game.buildings, ready)

func clear_building(game: Node3D, id: int) -> void:
	ready.erase(id)
	ready_owners.erase(id)
	_sync_durations(game)
	game.world_effects.pig_ready(game.buildings, ready)

func _sync_durations(game: Node3D) -> void:
	for state: RefCounted in game.faction_skills:
		if state.commander == RULES.PIG:
			for index: int in 3: state.durations[index] = 0.0
	for id: int in ready:
		var state: RefCounted = game.faction_skills[ready_owners[id]]
		for index: int in 2:
			state.durations[index] = maxf(state.durations[index], ready[id][index])
	for airlift: Dictionary in airlifts:
		var state: RefCounted = game.faction_skills[airlift.faction]
		if state.commander == RULES.PIG:
			state.durations[2] = maxf(state.durations[2], maxf(0.0, RULES.PIG_AIRLIFT_DURATION - float(airlift.age)))

func start_drop(game: Node3D, at: Vector3, faction: int) -> void:
	drops.append({"id": next_drop_id, "faction": faction, "at": at, "age": 0.0, "impacted": false})
	next_drop_id += 1
	game.world_effects.pig_ready(game.buildings, ready)
	game.world_effects.sync_pig_drops(drops)

func step_limit() -> float:
	var result := INF
	for flags: Vector3 in ready.values():
		for index: int in 3:
			if flags[index] > 0.0: result = minf(result, flags[index])
	for drop: Dictionary in drops:
		var boundary: float = RULES.PIG_DROP_LIFETIME if drop.impacted else RULES.PIG_DROP_FALL_TIME
		result = minf(result, maxf(0.000001, boundary - float(drop.age)))
	for airlift: Dictionary in airlifts:
		var boundary: float = RULES.PIG_AIRLIFT_LIFETIME
		if airlift.landed < RULES.PIG_AIRLIFT_COUNT:
			boundary = (int(airlift.landed) / RULES.PIG_AIRLIFT_BATCH_SIZE + 1) * RULES.PIG_AIRLIFT_BATCH_INTERVAL
		result = minf(result, maxf(0.000001, boundary - float(airlift.age)))
	return result

func advance(game: Node3D, delta: float) -> void:
	for id: int in ready.keys():
		if game.by_id[id].faction != ready_owners[id]:
			ready.erase(id)
			ready_owners.erase(id)
			continue
		var flags := flags_for(id)
		for index: int in 3: flags[index] = maxf(0.0, flags[index] - delta)
		if flags == Vector3.ZERO:
			ready.erase(id)
			ready_owners.erase(id)
		else:
			ready[id] = flags
	for index: int in range(drops.size() - 1, -1, -1):
		var drop := drops[index]
		drop.age += delta
		if not drop.impacted and drop.age >= RULES.PIG_DROP_FALL_TIME - 0.000001:
			drop.impacted = true
			_impact(game, drop.at, drop.faction)
		if drop.age >= RULES.PIG_DROP_LIFETIME: drops.remove_at(index)
	for index: int in range(airlifts.size() - 1, -1, -1):
		var airlift := airlifts[index]
		airlift.age += delta
		var due := mini(RULES.PIG_AIRLIFT_COUNT, floori((float(airlift.age) + 0.000001) / RULES.PIG_AIRLIFT_BATCH_INTERVAL) * RULES.PIG_AIRLIFT_BATCH_SIZE)
		# Resolve individual arrivals against the building's current owner. Capture
		# can happen within a batch; the remaining soldiers then enter normally.
		while airlift.landed < due:
			airlift.landed += 1
			game._on_unit_arrived(airlift.target, airlift.faction, 1.0)
		if airlift.age >= RULES.PIG_AIRLIFT_LIFETIME: airlifts.remove_at(index)
	_sync_durations(game)
	game.world_effects.pig_ready(game.buildings, ready)
	game.world_effects.sync_pig_drops(drops)
	game.world_effects.get_node("PigEffects").sync_airlifts(airlifts, game.by_id)

func _impact(game: Node3D, at: Vector3, faction: int) -> void:
	var radius_squared := RULES.PIG_DROP_RADIUS * RULES.PIG_DROP_RADIUS
	for index: int in range(game.marches._units.size() - 1, -1, -1):
		var unit: WarMarches.MarchUnit = game.marches._units[index]
		if unit.is_exposed() and _xz(unit.position).distance_squared_to(_xz(at)) <= radius_squared:
			game.marches._defeat(index, (unit.position - at).normalized() + Vector3.UP, false, faction)
	# Reserved soldiers are still in this garrison. Halve once, then release
	# reservations that no longer fit; do not also treat them as exposed armies.
	# This is a direct population effect, independent of armor/wards/links.
	for building: WarBuilding in game.buildings:
		if _xz(building.global_position).distance_squared_to(_xz(at)) > radius_squared: continue
		var before := building.population
		building.population *= 0.5
		game.world_effects.garrison_blast(building, before - building.population)
		game.marches.trim_departures(building.building_id, building.faction, floori(building.population))
		building.refresh_visual()
	game.marches._render()
	game.audio.play_world(IMPACT_SOUND, at)
	game.presentation_event.emit("pig_impact", {"at": game._vector_values(at)})
	game.update_hud()

static func _xz(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)
