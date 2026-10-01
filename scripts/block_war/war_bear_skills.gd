extends RefCounted
## Bear state belongs to the simulation; authored scenes only display it.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
# Active effects retain the caster's faction. A ward's allegiance is fixed at
# placement, so capturing its building clears it instead of reversing its role.
var links: Dictionary[int, Dictionary] = {}
var locks: Dictionary[int, Dictionary] = {}
var wards: Dictionary[int, Dictionary] = {}
var shots: Array[Dictionary] = []
# Sub-unit attack coefficients accrue until a whole casualty can be settled.
# On unlink, the next ordinary hit settles any outstanding fraction normally.
var damage_remainders: Dictionary[int, float] = {}
# The ordinary-combat portion of each pending fraction, separate from spells.
var combat_damage_remainders: Dictionary[int, float] = {}

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
		if candidate == target or not FACTIONS.allied(candidate.faction, target.faction) or candidate.population < 1.0 or participates(candidate.building_id):
			continue
		var offset := target.global_position - candidate.global_position
		var squared := Vector2(offset.x, offset.z).length_squared()
		if squared <= distance and (closest == null or squared < distance or candidate.building_id < closest.building_id):
			distance = squared
			closest = candidate
	return closest

func valid_target(game: Node3D, index: int, target: WarBuilding, faction: int) -> bool:
	if index == 1:
		return FACTIONS.hostile(target.faction, faction) and not is_locked(target.building_id)
	if index == 3:
		return target.faction >= 0 and not wards.has(target.building_id)
	if not FACTIONS.allied(target.faction, faction):
		return false
	match index:
		0: return target.level < target.max_level and target.conversion_target < 0
		2: return partner(game, target) != null
	return false

func is_locked(id: int) -> bool:
	return locks.has(id) and locks[id].remaining > 0.0

func orb_interval(ward: Dictionary) -> float:
	return RULES.BEAR_HOSTILE_ORB_INTERVAL if ward.hostile else RULES.BEAR_ORB_INTERVAL

func cast(game: Node3D, index: int, target: WarBuilding, faction: int) -> void:
	match index:
		0:
			# Reuse the native completion path for its model, morale and signals.
			# A paid upgrade finishes once; an idle building starts a free upgrade.
			if not target.is_constructing: target.begin_construction()
			target.advance_construction(target.construction_remaining)
			game.world_effects.get_node("Bear").toolbox(faction, target.global_position)
			game.audio.play_world(&"war_bear_toolbox", target.global_position)
		1:
			locks[target.building_id] = {"faction": faction, "remaining": RULES.BEAR_DURATIONS[1]}
			# Pending troops still belong to the garrison. Cancel reservations only;
			# soldiers already outside continue their original orders.
			game.marches.trim_departures(target.building_id, target.faction, 0)
			game.world_effects.get_node("Bear").lock(faction, target.global_position)
			game.audio.play_world(&"war_bear_stomp", target.global_position)
		2:
			var support := partner(game, target)
			links[target.building_id] = {"target": target.building_id, "support": support.building_id,
				"faction": faction, "remaining": RULES.BEAR_DURATIONS[2], "settled": 0, "pulse": 0.0}
			game.audio.play_world(&"war_bear_link", target.global_position)
		3:
			var hostile := FACTIONS.hostile(target.faction, faction)
			var ward := {"faction": faction, "remaining": RULES.BEAR_DURATIONS[3], "shot_clock": 0.0, "pulse": 0.0, "hostile": hostile}
			ward.shot_clock = orb_interval(ward)
			wards[target.building_id] = ward
			fire_orb(game, target)
			game.audio.play_world(&"war_bear_ward", target.global_position)
	game.world_effects.get_node("Bear").sync(self, game.marches, game.by_id, 0.0)

func apply_damage(game: Node3D, target: WarBuilding, damage: float, combat_damage: bool = false, whole_target_loss: bool = false) -> float:
	# Settle both garrisons here so energy follows actual casualties, including
	# transferred damage and overkill. Defense is applied by the damage source
	# before sharing; direct population effects retain their existing rules.
	var id := target.building_id
	var accrued: float = damage + damage_remainders.get(id, 0.0)
	var combat_accrued: float = (damage if combat_damage else 0.0) + combat_damage_remainders.get(id, 0.0)
	var combat_fraction := combat_accrued / accrued if accrued > 0.0 else 0.0
	var target_damage := accrued
	var settled_link := false
	if links.has(id):
		var link := links[id]
		var support: WarBuilding = game.by_id[link.support]
		if not FACTIONS.allied(target.faction, link.faction) or not FACTIONS.allied(support.faction, link.faction) or support.population < 1.0:
			_end_link(game, id)
		else:
			settled_link = true
			var whole := floori(accrued + 0.000001)
			damage_remainders[id] = maxf(0.0, accrued - whole)
			var combat_remaining: float = damage_remainders[id] * combat_fraction
			if combat_remaining > 0.0:
				combat_damage_remainders[id] = combat_remaining
			else:
				combat_damage_remainders.erase(id)
			# Cumulative ceil-half keeps the existing integer casualty distribution.
			var previous_support := ceili(float(link.settled) * 0.5)
			link.settled += whole
			var shared := ceili(float(link.settled) * 0.5) - previous_support
			var absorbed := mini(shared, floori(support.population))
			support.population -= absorbed
			game._restore_combat_energy(support.faction, float(absorbed) * combat_fraction)
			if support.queued_population > floori(support.population):
				game.marches.trim_departures(support.building_id, support.faction, floori(support.population))
			support.refresh_visual()
			if absorbed > 0:
				link.pulse = 1.0
			target_damage = float(whole - absorbed)
			if support.population < 1.0:
				_end_link(game, id)
	# An ended/exhausted link still owes its last sub-unit fraction. Clear only
	# when this hit actually settled the unrounded total outside a valid link.
	if not settled_link:
		damage_remainders.erase(id)
		combat_damage_remainders.erase(id)
	if whole_target_loss:
		target_damage = floorf(target_damage + 0.000001)
	var loss := minf(target.population, target_damage)
	target.population = maxf(0.0, target.population - loss)
	game._restore_combat_energy(target.faction, loss * combat_fraction)
	if target.queued_population > floori(target.population):
		game.marches.trim_departures(id, target.faction, floori(target.population))
	return target_damage

func _end_link(game: Node3D, id: int) -> void:
	game.faction_skills[links[id].faction].durations[2] = 0.0
	links.erase(id)

func clear_building(game: Node3D, id: int) -> void:
	for key: int in links.keys():
		if links[key].target == id or links[key].support == id:
			_end_link(game, key)
	if locks.has(id):
		game.faction_skills[locks[id].faction].durations[1] = 0.0
	locks.erase(id)
	if wards.has(id):
		game.faction_skills[wards[id].faction].durations[3] = 0.0
	wards.erase(id)
	damage_remainders.erase(id)
	combat_damage_remainders.erase(id)

func step_limit() -> float:
	var limit := 0.05 if not shots.is_empty() else INF
	for link: Dictionary in links.values():
		limit = minf(limit, link.remaining)
	for locked: Dictionary in locks.values():
		limit = minf(limit, locked.remaining)
	for ward: Dictionary in wards.values():
		limit = minf(limit, minf(ward.remaining, ward.shot_clock))
	return maxf(0.000001, limit)

func advance(game: Node3D, delta: float) -> void:
	for id: int in locks.keys():
		var locked := locks[id]
		locked.remaining = maxf(0.0, locked.remaining - delta)
		if locked.remaining < 0.000001 or not FACTIONS.hostile(game.by_id[id].faction, locked.faction):
			game.faction_skills[locked.faction].durations[1] = 0.0
			locks.erase(id)
	for id: int in links.keys():
		var link := links[id]
		link.remaining = maxf(0.0, link.remaining - delta)
		link.pulse = maxf(0.0, link.pulse - delta * 3.0)
		if link.remaining < 0.000001 or not FACTIONS.allied(game.by_id[link.target].faction, link.faction) or not FACTIONS.allied(game.by_id[link.support].faction, link.faction) or game.by_id[link.support].population < 1.0:
			_end_link(game, id)
	for id: int in wards.keys():
		var ward := wards[id]
		ward.remaining = maxf(0.0, ward.remaining - delta)
		ward.pulse = maxf(0.0, ward.pulse - delta * 5.0)
		ward.shot_clock -= delta
		var owner: int = game.by_id[id].faction
		var same_relation: bool = FACTIONS.hostile(owner, ward.faction) if ward.hostile else FACTIONS.allied(owner, ward.faction)
		if ward.remaining < 0.000001 or not same_relation:
			game.faction_skills[ward.faction].durations[3] = 0.0
			wards.erase(id)
		elif ward.shot_clock < 0.000001:
			ward.shot_clock += orb_interval(ward)
			fire_orb(game, game.by_id[id])
	game.world_effects.get_node("Bear").sync(self, game.marches, game.by_id, delta)

func fire_orb(game: Node3D, building: WarBuilding) -> void:
	var faction: int = wards[building.building_id].faction
	var targets: Array[WarMarches.MarchUnit] = game.marches.acquire_targets(building.global_position, faction, RULES.BEAR_ORB_RANGE, RULES.BEAR_ORB_TARGETS, true)
	if targets.is_empty():
		return
	var origin := building.global_position + Vector3(0, 6.1, 0)
	for target: WarMarches.MarchUnit in targets:
		shots.append({"target": target, "origin": origin, "position": origin, "previous": origin,
			"to": target.position + Vector3.UP * 0.65, "age": 0.0, "duration": clampf(origin.distance_to(target.position) / 38.0, 0.09, 0.42)})
		game.presentation_event.emit("bear_shot", {"building": building.building_id, "faction": faction, "unit": target.unit_id, "at": game._vector_values(origin), "to": game._vector_values(target.position + Vector3.UP * 0.65), "duration": shots[-1].duration})
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
