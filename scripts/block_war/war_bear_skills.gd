extends RefCounted
## Bear state belongs to the simulation; authored scenes only display it.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
var links: Dictionary[int, Dictionary] = {}
var wards: Dictionary[int, Dictionary] = {}
var shots: Array[Dictionary] = []
# Sub-unit attack coefficients accrue until a whole casualty can be settled.
# On unlink, the next ordinary hit settles any outstanding fraction normally.
var damage_remainders: Dictionary[int, float] = {}

func participates(id: int) -> bool:
	for link: Dictionary in links.values():
		if id == link.target or id == link.support:
			return true
	return false

func partner(game: Node3D, target: WarBuilding) -> WarBuilding:
	if target == null or participates(target.building_id):
		return null
	var closest: WarBuilding
	var distance := RULES.BEAR_LINK_RADIUS * RULES.BEAR_LINK_RADIUS
	for candidate: WarBuilding in game.buildings:
		if candidate == target or candidate.faction != target.faction or candidate.population < 1.0 or participates(candidate.building_id):
			continue
		var squared := target.global_position.distance_squared_to(candidate.global_position)
		if squared <= distance and (closest == null or squared < distance or candidate.building_id < closest.building_id):
			distance = squared
			closest = candidate
	return closest

func valid_target(game: Node3D, index: int, target: WarBuilding, faction: int) -> bool:
	if target.faction != faction:
		return false
	match index:
		0: return target.is_constructing and target.construction_cost > 0
		2: return partner(game, target) != null
		3: return not wards.has(target.building_id)
	return false

func cast(game: Node3D, index: int, target: WarBuilding, faction: int) -> void:
	match index:
		0:
			var refund := target.construction_cost / 2
			var converting := target.conversion_target >= 0
			target.advance_construction(WarBuilding.CONSTRUCTION_DURATION)
			target.population += refund
			if converting and target.kind != 0:
				game._cancel_building_recruitment(target.building_id)
			game.world_effects.get_node("Bear").toolbox(faction, target.global_position)
			game.audio.play_world(&"war_bear_toolbox", target.global_position)
		2:
			var support := partner(game, target)
			links[target.building_id] = {"target": target.building_id, "support": support.building_id,
				"faction": faction, "remaining": RULES.BEAR_DURATIONS[2], "settled": 0, "pulse": 0.0}
			game.audio.play_world(&"war_bear_link", target.global_position)
		3:
			wards[target.building_id] = {"faction": faction, "remaining": RULES.BEAR_DURATIONS[3], "shot_clock": RULES.BEAR_ORB_INTERVAL, "pulse": 0.0}
			game.marches.blocked_destinations[target.building_id] = faction
			fire_orb(game, target)
			game.audio.play_world(&"war_bear_ward", target.global_position)
	game.world_effects.get_node("Bear").sync(self, game.marches, game.by_id, 0.0)

func is_invulnerable(id: int) -> bool:
	return wards.has(id)

func damage_for(game: Node3D, target: WarBuilding, damage: float) -> float:
	if is_invulnerable(target.building_id):
		return 0.0
	var id := target.building_id
	var accrued: float = damage + damage_remainders.get(id, 0.0)
	if not links.has(id):
		damage_remainders.erase(id)
		return accrued
	var link := links[id]
	var support: WarBuilding = game.by_id[link.support]
	if target.faction != link.faction or support.faction != link.faction or support.population < 1.0:
		_end_link(game, id)
		damage_remainders.erase(id)
		return accrued
	var whole := floori(accrued + 0.000001)
	damage_remainders[id] = maxf(0.0, accrued - whole)
	# Cumulative ceil-half gives 21 -> 11/10 even when 21 arrives one at a time.
	var previous_support := ceili(float(link.settled) * 0.5)
	link.settled += whole
	var shared := ceili(float(link.settled) * 0.5) - previous_support
	var absorbed := shared if is_invulnerable(support.building_id) else mini(shared, floori(support.population))
	if not is_invulnerable(support.building_id):
		support.population -= absorbed
		if support.queued_population > floori(support.population):
			game.marches.trim_departures(support.building_id, support.faction, floori(support.population))
		support.refresh_visual()
	if absorbed > 0:
		link.pulse = 1.0
	if support.population < 1.0:
		_end_link(game, id)
	return float(whole - absorbed)

func _end_link(game: Node3D, id: int) -> void:
	game.faction_skills[links[id].faction].durations[2] = 0.0
	links.erase(id)

func clear_building(game: Node3D, id: int) -> void:
	for key: int in links.keys():
		if links[key].target == id or links[key].support == id:
			_end_link(game, key)
	if wards.has(id):
		game.faction_skills[wards[id].faction].durations[3] = 0.0
	wards.erase(id)
	damage_remainders.erase(id)
	game.marches.blocked_destinations.erase(id)

func step_limit() -> float:
	var limit := 0.05 if not shots.is_empty() else INF
	for link: Dictionary in links.values():
		limit = minf(limit, link.remaining)
	for ward: Dictionary in wards.values():
		limit = minf(limit, minf(ward.remaining, ward.shot_clock))
	return maxf(0.000001, limit)

func advance(game: Node3D, delta: float) -> void:
	for id: int in links.keys():
		var link := links[id]
		link.remaining = maxf(0.0, link.remaining - delta)
		link.pulse = maxf(0.0, link.pulse - delta * 3.0)
		if link.remaining < 0.000001 or game.by_id[link.target].faction != link.faction or game.by_id[link.support].faction != link.faction or game.by_id[link.support].population < 1.0:
			_end_link(game, id)
	for id: int in wards.keys():
		var ward := wards[id]
		ward.remaining = maxf(0.0, ward.remaining - delta)
		ward.pulse = maxf(0.0, ward.pulse - delta * 5.0)
		ward.shot_clock -= delta
		if ward.remaining < 0.000001 or game.by_id[id].faction != ward.faction:
			game.faction_skills[ward.faction].durations[3] = 0.0
			wards.erase(id)
			game.marches.blocked_destinations.erase(id)
		elif ward.shot_clock < 0.000001:
			ward.shot_clock += RULES.BEAR_ORB_INTERVAL
			fire_orb(game, game.by_id[id])
	game.world_effects.get_node("Bear").sync(self, game.marches, game.by_id, delta)

func fire_orb(game: Node3D, building: WarBuilding) -> void:
	var targets: Array[WarMarches.MarchUnit] = game.marches.acquire_targets(building.global_position, building.faction, RULES.BEAR_ORB_RANGE, 1, true)
	if targets.is_empty():
		return
	var target := targets[0]
	var origin := building.global_position + Vector3(0, 6.1, 0)
	shots.append({"target": target, "origin": origin, "position": origin, "previous": origin,
		"to": target.position + Vector3.UP * 0.65, "age": 0.0, "duration": clampf(origin.distance_to(target.position) / 38.0, 0.09, 0.42)})
	game.presentation_event.emit("bear_shot", {"building": building.building_id, "faction": building.faction, "unit": target.unit_id, "at": game._vector_values(origin), "to": game._vector_values(target.position + Vector3.UP * 0.65), "duration": shots[-1].duration})
	wards[building.building_id].pulse = 1.0

func tick_projectiles(game: Node3D, delta: float) -> void:
	for index: int in range(shots.size() - 1, -1, -1):
		var shot := shots[index]
		var unit: WarMarches.MarchUnit = shot.target
		shot.age += delta
		shot.previous = shot.position
		if unit.alive:
			shot.to = unit.position + Vector3.UP * 0.65
		var progress := minf(1.0, shot.age / shot.duration)
		shot.position = shot.origin.lerp(shot.to, progress)
		if progress >= 1.0:
			if game.marches.hit_target(unit, (shot.to - shot.origin).normalized()):
				game.world_effects.get_node("Bear").spark(shot.to)
				game.audio.play_world(&"war_projectile_hit", shot.to)
			shots.remove_at(index)
