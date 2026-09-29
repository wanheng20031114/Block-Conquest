extends RefCounted
## Host-owned next-departure orders and delayed, indiscriminate impact.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const CAST_SOUNDS: Array[StringName] = [&"war_pig_charge", &"war_pig_fly", &"war_pig_formation", &"war_pig_drop"]
const IMPACT_SOUND := &"war_pig_impact"
var ready: Dictionary[int, Vector3] = {}
var ready_owners: Dictionary[int, int] = {}
var drops: Array[Dictionary] = []
var next_drop_id := 1

func valid_target(index: int, target: WarBuilding, faction: int) -> bool:
	return index >= 0 and index < 3 and target.faction == faction and flags_for(target.building_id)[index] <= 0.0

func flags_for(id: int) -> Vector3:
	return ready.get(id, Vector3.ZERO)

func limit_for(id: int) -> int:
	var flags := flags_for(id)
	if flags.y > 0.0: return RULES.PIG_FLIGHT_LIMIT
	return RULES.PIG_FORMATION_LIMIT if flags.z > 0.0 else 2147483647

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
		for index: int in 3:
			state.durations[index] = maxf(state.durations[index], ready[id][index])

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
	_sync_durations(game)
	game.world_effects.pig_ready(game.buildings, ready)
	game.world_effects.sync_pig_drops(drops)

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
		building.population *= 0.5
		game.marches.trim_departures(building.building_id, building.faction, floori(building.population))
		building.refresh_visual()
	game.marches._render()
	game.audio.play_world(IMPACT_SOUND, at)
	game.presentation_event.emit("pig_impact", {"at": game._vector_values(at)})
	game.update_hud()

static func _xz(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)
