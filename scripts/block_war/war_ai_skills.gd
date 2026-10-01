extends RefCounted
## Deliberate, paid skill decisions from the same visible battlefield as the player.

const DECISION_GAP := 6.0
const RABBIT_DECISION_GAP := 3.0
const FIRE_CELL := 4.0
const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const INFORMATION := preload("res://scripts/block_war/war_ai_information.gd")
var faction: int
var next_decision: float

static func _xz(point: Vector3) -> Vector2:
	# Skill and tower footprints are horizontal, even when their targets differ in height.
	return Vector2(point.x, point.z)

static func _combat_multiplier(game: Node3D, cache: Dictionary[Vector2i, Dictionary], attacker: int, target: WarBuilding, bonus: float = 0.0) -> float:
	# The caller owns this cache for one read-only evaluation, before any cast.
	# Keep the full float bonus and original formula; do not regroup its factors.
	var key := Vector2i(target.building_id, attacker)
	if not cache.has(key):
		cache[key] = {}
	var values: Dictionary = cache[key]
	if not values.has(bonus):
		values[bonus] = game.combat_multiplier(attacker, target, bonus)
	return values[bonus]

func _init(controlled_faction: int) -> void:
	faction = controlled_faction
	next_decision = 6.0 + 0.45 * (faction - 1)

func take_turn(game: Node3D) -> void:
	if game.finished or game.is_rule_paused() or game.elapsed < next_decision:
		return
	# Never chain four casts in one frame, including repeated calls at the same time.
	# Short marches can finish between six-second decisions. Rabbit's instant
	# squad selection needs a chance to act after the preceding turn's dispatch.
	next_decision = game.elapsed + (RABBIT_DECISION_GAP if game.faction_skills[faction].commander == SKILL_RULES.RABBIT else DECISION_GAP)
	# Keep the scheduled decision even when no paid action is available. These
	# checks are read-only; an unavailable decision needs no target forecasts.
	var available := false
	for index: int in 4:
		if game.can_cast_skill(index, faction):
			available = true
			break
	if not available:
		return
	if game.faction_skills[faction].commander == SKILL_RULES.PIG:
		_pig_turn(game)
		return
	if game.faction_skills[faction].commander == SKILL_RULES.FOX:
		_fox_turn(game)
		return
	if game.faction_skills[faction].commander == SKILL_RULES.FROG:
		_frog_turn(game)
		return
	if game.faction_skills[faction].commander == SKILL_RULES.BEAR:
		_bear_turn(game)
		return
	if game.faction_skills[faction].commander == SKILL_RULES.RABBIT:
		_rabbit_turn(game)
		return
	var can_shield: bool = game.can_cast_skill(2, faction)
	var can_recruit: bool = game.can_cast_skill(0, faction) and game.faction_skills[faction].energy >= SKILL_RULES.COSTS[0] + SKILL_RULES.COSTS[2]
	var can_haste: bool = game.can_cast_skill(1, faction) and game.faction_skills[faction].energy >= SKILL_RULES.COSTS[1] + 20.0
	var can_fire: bool = game.can_cast_skill(3, faction)
	if not can_shield and not can_recruit and not can_haste and not can_fire:
		return
	var visible: Array[WarMarches.MarchUnit] = []
	var threats := INFORMATION.airlift_threats(game, faction)
	var combat: Dictionary[Vector2i, Dictionary] = {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not unit.is_exposed() or not INFORMATION.is_unit_known(game, unit, faction):
			continue
		visible.append(unit)
		if not (can_shield or can_recruit) or not game.FACTIONS.hostile(unit.order.faction, faction):
			continue
		var target: WarBuilding = game.by_id[unit.order.target_id]
		if game.FACTIONS.allied(target.faction, faction) and game.marches.movement_distance(unit, 7.0) >= unit.order.length - unit.distance:
			threats[target.building_id] = threats.get(target.building_id, 0.0) + unit.order.strength * _combat_multiplier(game, combat, unit.order.faction, target, game.marches.projected_attack_bonus(unit))
	var best := {"index": -1, "score": 12.0, "target": null, "at": Vector3.ZERO}
	if can_shield:
		for id: int in threats:
			var building: WarBuilding = game.by_id[id]
			if not game._valid_skill_target(2, building, faction):
				continue
			var danger := threats[id]
			if danger < 8.0 or danger < building.population * 0.55:
				continue
			var score := minf(danger * SKILL_RULES.SHIELD_DEFENSE, 45.0) + (28.0 if danger >= building.population else 12.0)
			if score > best.score:
				best = {"index": 2, "score": score, "target": building, "at": Vector3.ZERO}
	if can_recruit:
		for building: WarBuilding in game.buildings:
			if not game._valid_skill_target(0, building, faction) or building.conversion_target in [1, 2]:
				continue
			# Supply an active front or a drained residence, not an unused giant stockpile.
			if building.available_population > maxf(building.capacity + SKILL_RULES.RECRUIT_RATE * SKILL_RULES.DURATIONS[0], 90.0):
				continue
			var danger: float = threats.get(building.building_id, 0.0)
			if danger > building.population + 20.0:
				continue # Six-second recruitment cannot rescue an immediately lost house.
			var score := 18.0 + maxf(0.0, 30.0 - building.available_population) * 0.25
			score += 5.0 if building.faction == faction else 0.0
			score += 8.0 if danger > building.population * 0.4 else 0.0
			if score > best.score:
				best = {"index": 0, "score": score, "target": building, "at": Vector3.ZERO}
	if can_haste:
		var haste := _haste_target(game, visible)
		if not haste.is_empty() and haste.score > best.score:
			best = {"index": 1, "score": haste.score, "target": null, "at": haste.at}
	if can_fire:
		var fire := _fire_target(game, visible)
		if not fire.is_empty() and fire.score > best.score:
			best = {"index": 3, "score": fire.score, "target": null, "at": fire.at}
	if best.index in [1, 3]:
		game.cast_ground_skill(best.index, best.at, faction)
	elif best.index >= 0:
		game.cast_skill(best.index, best.target, faction)

func _pig_turn(game: Node3D) -> void:
	var observation := INFORMATION.snapshot_defense(game, faction)
	var incoming: Dictionary[Vector2i, int] = observation.counts
	var threats: Dictionary[int, float] = observation.damage
	var reinforcements: Dictionary[int, int] = {}
	var combat: Dictionary[Vector2i, Dictionary] = {}
	var departure_times: Dictionary[Vector2i, float] = {}
	for key: Vector2i in incoming:
		if game.FACTIONS.allied(key.y, faction):
			reinforcements[key.x] = reinforcements.get(key.x, 0) + incoming[key]
	var best := {"index": -1, "score": 12.0}
	if game.can_cast_skill(3, faction):
		var drop := _pig_drop_target(game)
		if not drop.is_empty():
			best = {"index": 3, "score": drop.score, "at": drop.at}
	if game.can_cast_skill(2, faction):
		var airlift := _pig_airlift_plan(game, threats, reinforcements, incoming, combat)
		if not airlift.is_empty() and airlift.score > best.score:
			best = airlift
	for source: WarBuilding in game.buildings:
		if source.faction != faction:
			continue
		var reserve: float = 8.0 + (source.level - 1) * 2.0 + threats.get(source.building_id, 0.0)
		for index: int in 2:
			if not game.can_cast_skill(index, faction) or not game.pig.valid_target(index, source, faction):
				continue
			for target: WarBuilding in game.buildings:
				if target == source:
					continue
				var plan := _pig_dispatch_plan(game, source, target, index, reserve, threats, reinforcements, incoming, combat, departure_times)
				if not plan.is_empty() and plan.score > best.score:
					best = plan
	if best.index == 3:
		game.cast_ground_skill(3, best.at, faction)
	elif best.index == 2:
		game.cast_skill(2, best.target, faction)
	elif best.index >= 0:
		# The destination, real capped count and route are chosen before payment.
		# Consume the next-order enchantment immediately, within the same decision.
		if game.cast_skill(best.index, best.source, faction):
			game.issue_order(best.source, best.target, best.percent, faction)

func _pig_dispatch_plan(game: Node3D, source: WarBuilding, target: WarBuilding, index: int, reserve: float, threats: Dictionary[int, float], reinforcements: Dictionary[int, int], incoming: Dictionary[Vector2i, int], combat: Dictionary[Vector2i, Dictionary], departure_times: Dictionary[Vector2i, float]) -> Dictionary:
	var allied: bool = game.FACTIONS.allied(target.faction, faction)
	var missing: float = threats.get(target.building_id, 0.0) - target.available_population - reinforcements.get(target.building_id, 0) + 6.0 if allied else 0.0
	if allied and (missing <= 0.0 or threats.get(target.building_id, 0.0) < 8.0):
		return {}
	if not allied and reinforcements.get(target.building_id, 0) > 0:
		return {}
	if target.faction < 0:
		for attacker: int in game.faction_count:
			if game.FACTIONS.hostile(attacker, faction) and incoming.get(Vector2i(target.building_id, attacker), 0) > 0:
				return {} # Do not race an observed enemy wave to neutral territory.
	var flags: Vector3 = game.pig.ready.get(source.building_id, Vector3.ZERO)
	var flying := index == 1 or flags.y > 0.0
	var charge := index == 0 or flags.x > 0.0
	var limit: int = game.pig.limit_for(source.building_id)
	if index == 1:
		limit = mini(limit, SKILL_RULES.PIG_FLIGHT_LIMIT)
	elif index == 0:
		limit = mini(limit, SKILL_RULES.PIG_CHARGE_LIMIT)
	var ground_length: float = game.map.get_building_distance(source, target)
	var route: PackedVector3Array = game.flight_route(source, target) if flying else game.map.get_building_route(source, target)
	if route.size() < 2:
		return {}
	var length := 0.0
	for point: int in range(1, route.size()):
		length += route[point - 1].distance_to(route[point])
	# Flight is precious: choose a useful shortcut instead of a slower hop
	# between neighboring houses. An otherwise disconnected target is valid.
	if index == 1 and is_finite(ground_length) and ground_length - length < (2.0 if allied else 4.0):
		return {}
	var speed: float = game.marches.base_speed(faction)
	var attack_bonus := SKILL_RULES.PIG_CHARGE_ATTACK_BONUS if charge else 0.0
	for percent: int in [25, 50, 75, 100]:
		var count := mini(limit, floori(source.available_population * percent / 100.0))
		if count < 8 or source.available_population - count < reserve:
			continue
		# The source queue is unchanged until this decision casts and dispatches.
		var departure_key := Vector2i(source.building_id, count)
		if not departure_times.has(departure_key):
			departure_times[departure_key] = game.marches.estimate_arrival_time(source.building_id, 0.0, count, faction)
		var queue_time: float = departure_times[departure_key]
		var arrival := maxf(0.0, queue_time) + length / (speed * (1.0 + (SKILL_RULES.PIG_CHARGE_SPEED_BONUS if charge else 0.0)))
		var score := 0.0
		if allied:
			if count < minf(missing, 12.0):
				continue
			score = 28.0 + minf(missing, count) * 1.1 - arrival * 0.5
		else:
			var defenders := INFORMATION.garrison_estimate(game, target, faction)
			if target.faction >= 0:
				defenders += minf(maxf(0.0, target.capacity - defenders), target.production_rate * maxf(0.0, arrival - target.disruption_remaining))
				for defender: int in game.faction_count:
					if game.FACTIONS.allied(defender, target.faction):
						defenders += incoming.get(Vector2i(target.building_id, defender), 0)
			var damage: float = count * _combat_multiplier(game, combat, faction, target, attack_bonus)
			if damage < defenders * (1.0 if target.faction < 0 else 1.2) + 5.0:
				continue
			score = 22.0 + (8.0 if target.kind == 0 else 0.0) + minf(12.0, damage - defenders) * 0.5 - arrival * 0.45
		if index == 1:
			score += minf(18.0, maxf(0.0, ground_length - length)) if is_finite(ground_length) else 18.0
		else:
			score += count * SKILL_RULES.PIG_CHARGE_ATTACK_BONUS
		return {"index": index, "source": source, "target": target, "percent": percent, "score": score}
	return {}

func _pig_airlift_plan(game: Node3D, threats: Dictionary[int, float], reinforcements: Dictionary[int, int], incoming: Dictionary[Vector2i, int], combat: Dictionary[Vector2i, Dictionary]) -> Dictionary:
	var best := {}
	for target: WarBuilding in game.buildings:
		if not game.pig.valid_target(2, target, faction):
			continue
		var already_landing := false
		for airlift: Dictionary in game.pig.airlifts:
			if airlift.target == target.building_id and game.FACTIONS.allied(int(airlift.faction), faction):
				already_landing = true
		if already_landing:
			continue
		var score := 0.0
		var reinforcements_count: int = reinforcements.get(target.building_id, 0)
		if game.FACTIONS.allied(target.faction, faction):
			var danger: float = threats.get(target.building_id, 0.0)
			var missing: float = danger - target.population - reinforcements_count + 8.0
			if danger >= 8.0 and missing > 0.0 and missing <= SKILL_RULES.PIG_AIRLIFT_COUNT:
				score = 55.0 + missing
			elif target.faction == faction and target.kind == 0 and target.available_population + reinforcements_count < target.capacity:
				# Reinforce a depleted home when there is no useful capture or rescue.
				score = 18.0 + minf(12.0, target.capacity - target.available_population - reinforcements_count) * 0.5
		else:
			# The generated soldiers use normal attack/defense on landing. Enemy
			# troop distribution remains hidden, so only public type/level estimates
			# and known incoming armies contribute to this decision.
			var defenders := INFORMATION.garrison_estimate(game, target, faction)
			if target.faction >= 0:
				defenders += minf(maxf(0.0, target.capacity - defenders), target.production_rate * SKILL_RULES.PIG_AIRLIFT_DURATION)
				for defender: int in game.faction_count:
					if game.FACTIONS.allied(defender, target.faction):
						defenders += incoming.get(Vector2i(target.building_id, defender), 0)
			var damage: float = SKILL_RULES.PIG_AIRLIFT_COUNT * _combat_multiplier(game, combat, faction, target)
			if reinforcements_count > 0 or damage < defenders * (1.0 if target.faction < 0 else 1.2) + 5.0:
				continue
			var contested_neutral := false
			if target.faction < 0:
				for attacker: int in game.faction_count:
					if game.FACTIONS.hostile(attacker, faction) and incoming.get(Vector2i(target.building_id, attacker), 0) > 0:
						contested_neutral = true
			if contested_neutral:
				continue
			score = 35.0 + (8.0 if target.kind == 0 else 0.0) + minf(15.0, damage - defenders) * 0.5
		if score > 12.0 and (best.is_empty() or score > best.score):
			best = {"index": 2, "target": target, "score": score}
	return best

func _pig_drop_target(game: Node3D) -> Dictionary:
	var radius := SKILL_RULES.PIG_DROP_RADIUS
	var projected: Array[Dictionary] = []
	var departures: Dictionary[int, int] = {}
	var cells: Dictionary[Vector2i, Dictionary] = {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not INFORMATION.is_unit_known(game, unit, faction) or unit.spawn_delay > SKILL_RULES.PIG_DROP_FALL_TIME:
			continue
		var distance: float = unit.distance + game.marches.movement_distance(unit, SKILL_RULES.PIG_DROP_FALL_TIME)
		if distance < 0.0:
			continue # Still inside: included once in its building's population.
		if unit.pending_departure:
			departures[unit.order.source_id] = departures.get(unit.order.source_id, 0) + 1
		var friendly: bool = game.FACTIONS.allied(unit.order.faction, faction)
		var at := unit.order.sample(minf(distance, unit.order.length))
		if not unit.pending_departure:
			at += unit.position - unit.order.sample(unit.distance)
		var value := unit.order.strength
		if distance >= unit.order.length:
			var destination: WarBuilding = game.by_id[unit.order.target_id]
			# A known reinforcement is inside at impact, so only half is lost.
			# An enemy attack already reaching our gate is not a future free kill.
			if game.FACTIONS.allied(destination.faction, unit.order.faction):
				value *= 0.5
			elif not friendly:
				continue
		projected.append({"at": at, "value": value, "friendly": friendly})
		if not friendly:
			var cell := Vector2i(floori(at.x / radius), floori(at.z / radius))
			if not cells.has(cell):
				cells[cell] = {"sum": Vector3.ZERO, "count": 0}
			cells[cell].sum += at
			cells[cell].count += 1
	var candidates: Array[Vector3] = []
	var keys := cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i): return cells[a].count > cells[b].count)
	for key: Vector2i in keys.slice(0, 24):
		candidates.append(game.map.definition.surface_point(cells[key].sum / float(cells[key].count)))
	for building: WarBuilding in game.buildings:
		if game.FACTIONS.hostile(building.faction, faction):
			candidates.append(game.map.definition.surface_point(building.global_position))
	var best := {}
	for at: Vector3 in candidates:
		if not game._valid_ground_skill_target(at):
			continue
		var already_falling := false
		for drop: Dictionary in game.pig.drops:
			if not drop.impacted and _xz(drop.at).distance_to(_xz(at)) <= radius:
				already_falling = true
		if already_falling:
			continue
		var enemy_loss := 0.0
		var friendly_loss := 0.0
		for entry: Dictionary in projected:
			# Slight extra margin for allies avoids deliberately clipping a file
			# whose lane turns during the short visible falling animation.
			if _xz(entry.at).distance_to(_xz(at)) > radius + (0.5 if entry.friendly else 0.0):
				continue
			if entry.friendly:
				friendly_loss += entry.value
			else:
				enemy_loss += entry.value
		for building: WarBuilding in game.buildings:
			if _xz(building.global_position).distance_squared_to(_xz(at)) > radius * radius:
				continue
			var loss := maxf(0.0, INFORMATION.garrison_estimate(game, building, faction) - departures.get(building.building_id, 0)) * 0.5
			if game.FACTIONS.allied(building.faction, faction):
				friendly_loss += loss
			elif game.FACTIONS.hostile(building.faction, faction):
				enemy_loss += loss
		# Unlike fire this halves buildings regardless of defense; all allied seats
		# are real collateral. Hidden enemy garrisons never enter this estimate.
		var score := enemy_loss - friendly_loss * 2.0
		if score >= 24.0 and (best.is_empty() or score > best.score):
			best = {"at": at, "score": score}
	return best

func _fox_turn(game: Node3D) -> void:
	var best := {"index": -1, "score": 12.0, "target": null, "at": Vector3.ZERO}
	for building: WarBuilding in game.buildings:
		if game.FACTIONS.allied(building.faction, faction):
			continue
		var estimate: float = INFORMATION.garrison_estimate(game, building, faction)
		if game.can_cast_skill(0, faction):
			var score := minf(SKILL_RULES.FOX_BOMB_CAP, floorf(estimate * 0.5)) * (0.65 if building.faction < 0 else 1.0)
			if score > best.score:
				best = {"index": 0, "score": score, "target": building, "at": Vector3.ZERO}
		if game.can_cast_skill(1, faction):
			var amount: float = game.FOX_SKILLS.stolen_stars(game, building.faction, faction)
			var score := amount * 29.0
			if amount >= 0.35 and score > best.score:
				best = {"index": 1, "score": score, "target": building, "at": Vector3.ZERO}
		if game.can_cast_skill(3, faction) and game.FACTIONS.hostile(building.faction, faction) and not game.FOX_SKILLS.panic_routes(game, building).is_empty():
			# Emptying an irrelevant rear building merely redistributes enemy troops.
			# Prefer a defended destination we are already approaching.
			var incoming := 0
			for unit: WarMarches.MarchUnit in game.marches._units:
				if unit.order.faction == faction and unit.order.target_id == building.building_id and unit.is_exposed() and game.marches.movement_distance(unit, 8.0) >= unit.order.length - unit.distance:
					incoming += 1
			var score := minf(estimate * 0.65, 60.0)
			if incoming >= 5 and estimate >= 30 and score > best.score:
				best = {"index": 3, "score": score, "target": building, "at": Vector3.ZERO}
	if game.can_cast_skill(2, faction):
		var cells: Dictionary[Vector2i, Dictionary] = {}
		var known: Array[WarMarches.MarchUnit] = []
		for unit: WarMarches.MarchUnit in game.marches._units:
			if not unit.is_exposed() or not game.FACTIONS.hostile(unit.order.faction, faction) or not INFORMATION.is_unit_known(game, unit, faction):
				continue
			known.append(unit)
			var cell := Vector2i(floori(unit.position.x / 3.0), floori(unit.position.z / 3.0))
			if not cells.has(cell):
				cells[cell] = {"sum": Vector3.ZERO, "count": 0}
			cells[cell].sum += unit.position
			cells[cell].count += 1
		var keys := cells.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i): return cells[a].count > cells[b].count)
		for key: Vector2i in keys.slice(0, 20):
			var at: Vector3 = game.map.definition.surface_point(cells[key].sum / float(cells[key].count))
			var count := 0
			for unit: WarMarches.MarchUnit in known:
				if Vector2(unit.position.x - at.x, unit.position.z - at.z).length_squared() <= pow(SKILL_RULES.FOX_CONVERT_RADIUS, 2):
					count += 1
			var score := count * 2.2
			if count >= 6 and score > best.score:
				best = {"index": 2, "score": score, "target": null, "at": at}
	if best.index == 2:
		game.cast_ground_skill(2, best.at, faction)
	elif best.index >= 0:
		game.cast_skill(best.index, best.target, faction)

func _frog_turn(game: Node3D) -> void:
	var best := {"index": -1, "score": 12.0, "target": null, "at": Vector3.ZERO}
	var can_mist: bool = game.can_cast_skill(0, faction)
	var siege_damage: Dictionary[int, float] = {}
	var siege_targets: Array[WarBuilding] = []
	var siege_values := PackedFloat64Array()
	var combat: Dictionary[Vector2i, Dictionary] = {}
	var cells: Dictionary[Vector2i, Dictionary] = {}
	var positions: Array[Vector2] = []
	var q_values := PackedFloat64Array()
	var floating_values := PackedFloat64Array()
	var cloak_values := PackedFloat64Array()
	var towers: Array[WarBuilding] = []
	for building: WarBuilding in game.buildings:
		if building.kind == 1 and building.faction >= 0 and building.disruption_remaining <= 0.0:
			towers.append(building)
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not unit.is_exposed() or not INFORMATION.is_unit_known(game, unit, faction):
			continue
		var destination: WarBuilding = game.by_id[unit.order.target_id]
		var hostile: bool = game.FACTIONS.hostile(unit.order.faction, faction)
		var incoming: bool = game.FACTIONS.allied(destination.faction, faction) and hostile
		var friendly_attack: bool = not hostile and game.FACTIONS.hostile(unit.order.faction, destination.faction)
		var close: bool = (incoming or friendly_attack) and game.marches.movement_distance(unit, 3.0) > unit.order.length - unit.distance
		if can_mist and friendly_attack and close:
			# Only arrivals inside this short cloud can benefit from weaker walls.
			# Their damage uses public type/level and visible buffs, never the
			# enemy garrison or a hidden enemy departure queue.
			siege_damage[destination.building_id] = siege_damage.get(destination.building_id, 0.0) + unit.order.strength * _combat_multiplier(game, combat, unit.order.faction, destination, game.marches.projected_attack_bonus(unit))
		var q_value := SKILL_RULES.FROG_WEAKNESS if hostile and not unit.weakened and not game.FACTIONS.allied(unit.order.faction, destination.faction) else 0.0
		var floating := 1.3 if incoming and close else 0.0
		var can_cloak := unit.order.faction == faction and not unit.cloaked
		var cloak := 1.0 if can_cloak and destination.faction >= 0 and game.FACTIONS.hostile(faction, destination.faction) else 0.0
		if friendly_attack and close:
			floating -= 1.5
		var ahead := Vector3.ZERO
		var ahead_sampled := false
		for tower: WarBuilding in towers:
			if not game.FACTIONS.hostile(tower.faction, unit.order.faction):
				continue
			if _xz(tower.global_position).distance_to(_xz(unit.position)) < game.tower_range(tower) and game.marches.tower_can_target(unit):
				floating += (-1.8 if hostile else 1.8) * tower.level
				# A cloud also shields enemy soldiers from our cannons; account for it.
				q_value += (-0.25 if hostile else 0.30) * tower.level
			if can_cloak:
				if not ahead_sampled:
					ahead = unit.order.sample(minf(unit.order.length, unit.distance + 12.0))
					ahead_sampled = true
				if Geometry2D.get_closest_point_to_segment(_xz(tower.global_position), _xz(unit.position), _xz(ahead)).distance_to(_xz(tower.global_position)) < game.tower_range(tower):
					cloak = maxf(cloak, 1.5 * tower.level)
		var at := unit.position
		positions.append(_xz(at))
		q_values.append(q_value)
		floating_values.append(floating if unit.levitation_remaining <= 0.0 else 0.0)
		cloak_values.append(cloak)
		var cell := Vector2i(floori(at.x / 4.0), floori(at.z / 4.0))
		if not cells.has(cell):
			cells[cell] = {"at": Vector3.ZERO, "count": 0}
		cells[cell].at += at
		cells[cell].count += 1
	var candidates: Array[Vector3] = []
	var keys := cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i): return cells[a].count > cells[b].count)
	for key: Vector2i in keys.slice(0, 24):
		candidates.append(game.map.definition.surface_point(cells[key].at / float(cells[key].count)))
	for building: WarBuilding in game.buildings:
		if game.FACTIONS.allied(building.faction, faction):
			candidates.append(game.map.definition.surface_point(building.global_position))
		else:
			if can_mist and game.FACTIONS.hostile(building.faction, faction) and float(siege_damage.get(building.building_id, 0.0)) >= 8.0 and is_zero_approx(game.FROG_SKILLS.mist_defense_bonus(game, building)):
				var defense: float = 1.0 + game.skill_defense_bonus(building)
				var extra: float = siege_damage[building.building_id] * -SKILL_RULES.FROG_BUILDING_DEFENSE / (defense + SKILL_RULES.FROG_BUILDING_DEFENSE)
				siege_targets.append(building)
				siege_values.append(extra)
				candidates.append(game.map.definition.surface_point(building.global_position))
			if not game.can_cast_skill(3, faction):
				continue
			# Target choice uses the public garrison estimate. The paid cast path
			# still rejects a truly empty, level-one target without charging us.
			var loss := floori(INFORMATION.garrison_estimate(game, building, faction) * SKILL_RULES.FROG_STRIKE_FRACTION)
			var score := float(loss) + float(building.level - 1) * 14.0
			if building.faction < 0:
				score *= 0.45
			if score >= 28.0 and score > best.score:
				best = {"index": 3, "score": score, "target": building, "at": Vector3.ZERO}
	var available: Array[bool] = []
	var radii_squared := PackedFloat64Array()
	for index: int in 3:
		available.append(game.can_cast_skill(index, faction))
		radii_squared.append(pow(SKILL_RULES.FROG_RADII[index], 2))
	var any_available := available.has(true)
	for at: Vector3 in candidates:
		if not any_available:
			break
		if not game._valid_ground_skill_target(at):
			continue
		# Share the geometric test while keeping each skill's additions in the
		# original soldier order and its score in full scalar float precision.
		var q_total := 0.0
		var floating_total := 0.0
		var cloak_total := 0.0
		if available[0]:
			for target_index: int in siege_targets.size():
				if _xz(siege_targets[target_index].global_position).distance_squared_to(_xz(at)) <= radii_squared[0]:
					q_total += siege_values[target_index]
		for soldier: int in positions.size():
			var p := positions[soldier]
			var distance_squared := Vector2(p.x - at.x, p.y - at.z).length_squared()
			if available[0] and distance_squared <= radii_squared[0]:
				q_total += q_values[soldier]
			if available[1] and distance_squared <= radii_squared[1]:
				floating_total += floating_values[soldier]
			if available[2] and distance_squared <= radii_squared[2]:
				cloak_total += cloak_values[soldier]
		var values := PackedFloat64Array([q_total, floating_total, cloak_total])
		for index: int in 3:
			if not available[index]:
				continue
			var value := values[index]
			var threshold: float = [1.0, 6.0, 8.0][index]
			var score: float = 12.0 + minf(30.0, value * [5.0, 1.2, 0.5][index])
			if value >= threshold and score > best.score:
				best = {"index": index, "score": score, "target": null, "at": at}
	if best.index == 3:
		game.cast_skill(3, best.target, faction)
	elif best.index >= 0:
		game.cast_ground_skill(best.index, best.at, faction)

func _bear_turn(game: Node3D) -> void:
	var threats := INFORMATION.airlift_threats(game, faction)
	var assaults: Dictionary[int, float] = {}
	var departures: Dictionary[int, int] = {}
	var enemies: Array[WarMarches.MarchUnit] = []
	var combat: Dictionary[Vector2i, Dictionary] = {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not unit.is_exposed() or not INFORMATION.is_unit_known(game, unit, faction):
			continue
		var target: WarBuilding = game.by_id[unit.order.target_id]
		var reaches: bool = game.marches.movement_distance(unit, SKILL_RULES.BEAR_DURATIONS[3]) >= unit.order.length - unit.distance
		if game.FACTIONS.hostile(unit.order.faction, faction):
			enemies.append(unit)
			if game.FACTIONS.allied(target.faction, faction):
				if reaches:
					threats[target.building_id] = threats.get(target.building_id, 0.0) + unit.order.strength * _combat_multiplier(game, combat, unit.order.faction, target, game.marches.projected_attack_bonus(unit))
				# The queue and garrison are hidden. A visible column emerging from
				# its actual doorway is the fair cue for interrupting that source.
				if unit.order.source_id != unit.order.target_id and unit.distance < game.marches.movement_distance(unit, 2.0):
					departures[unit.order.source_id] = departures.get(unit.order.source_id, 0) + 1
		elif game.FACTIONS.hostile(target.faction, faction) and reaches:
			assaults[target.building_id] = assaults.get(target.building_id, 0.0) + unit.order.strength * _combat_multiplier(game, combat, unit.order.faction, target, game.marches.projected_attack_bonus(unit))
	var best := {"index": -1, "score": 12.0, "target": null, "at": Vector3.ZERO}
	for building: WarBuilding in game.buildings:
		if game.FACTIONS.hostile(building.faction, faction):
			var emerging: int = departures.get(building.building_id, 0)
			if game.can_cast_skill(1, faction) and game._valid_skill_target(1, building, faction) and emerging >= 4:
				var score := 22.0 + minf(30.0, emerging * 2.0)
				if score > best.score:
					best = {"index": 1, "score": score, "target": building, "at": Vector3.ZERO}
			if game.can_cast_skill(3, faction) and game._valid_skill_target(3, building, faction):
				var assault: float = assaults.get(building.building_id, 0.0)
				var targets := 0
				for enemy: WarMarches.MarchUnit in enemies:
					if enemy.intercepted_by < 0 and _xz(enemy.position).distance_to(_xz(building.global_position)) <= SKILL_RULES.BEAR_ORB_RANGE:
						targets += 1
				if assault >= 16.0 or targets >= 12:
					var score := 32.0 + minf(32.0, assault * 0.3) + minf(30.0, targets * 1.5)
					if score > best.score:
						best = {"index": 3, "score": score, "target": building, "at": Vector3.ZERO}
			continue
		if not game.FACTIONS.allied(building.faction, faction):
			continue
		var danger: float = threats.get(building.building_id, 0.0)
		if game.can_cast_skill(3, faction) and game._valid_skill_target(3, building, faction) and danger >= maxf(8.0, building.population * 0.7):
			var score := 45.0 + minf(45.0, danger) + (25.0 if danger > building.population else 0.0)
			if score > best.score:
				best = {"index": 3, "score": score, "target": building, "at": Vector3.ZERO}
		if game.can_cast_skill(2, faction) and game._valid_skill_target(2, building, faction) and danger >= 8.0:
			var support: WarBuilding = game.bear.partner(game, building)
			var spare: float = support.population - threats.get(support.building_id, 0.0)
			if spare >= ceili(danger * 0.5) and danger > building.population * 0.5:
				var score := 25.0 + minf(30.0, danger * 0.5)
				if score > best.score:
					best = {"index": 2, "score": score, "target": building, "at": Vector3.ZERO}
		if game.can_cast_skill(0, faction) and game._valid_skill_target(0, building, faction):
			# An idle upgrade saves its full population price. Already-paid work
			# only saves time; neither case invents refund soldiers for defense.
			var score := 15.0 + (minf(30.0, building.construction_remaining * 1.5) if building.is_constructing else building.upgrade_cost * 0.35)
			score += 8.0 if building.kind == 0 else 0.0
			score += 3.0 if building.faction == faction else 0.0
			if danger < maxf(1.0, building.population) and score > best.score:
				best = {"index": 0, "score": score, "target": building, "at": Vector3.ZERO}
	if best.index >= 0:
		game.cast_skill(best.index, best.target, faction)

func _haste_target(game: Node3D, visible: Array[WarMarches.MarchUnit], radius: float = SKILL_RULES.HASTE_RADIUS, minimum: int = 16) -> Dictionary:
	# Look ahead along actual routes. Distant armies do not contribute to a
	# single global score: one local field must cover a useful group of soldiers.
	var cells: Dictionary[Vector2i, Dictionary] = {}
	var projected: Array[Vector3] = []
	for unit: WarMarches.MarchUnit in visible:
		if not unit.is_exposed() or unit.order.faction != faction or unit.order.length - unit.distance < radius * 1.25:
			continue
		var at := unit.order.sample(unit.distance + radius * 0.6)
		projected.append(at)
		var cell := Vector2i(floori(at.x / FIRE_CELL), floori(at.z / FIRE_CELL))
		if not cells.has(cell):
			cells[cell] = {"count": 0, "sum": Vector3.ZERO}
		cells[cell].count += 1
		cells[cell].sum += at
	var candidates := cells.keys()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return cells[a].count > cells[b].count)
	var best := {}
	for cell: Vector2i in candidates.slice(0, 24):
		var at: Vector3 = game.map.definition.surface_point(cells[cell].sum / float(cells[cell].count))
		if not game._valid_ground_skill_target(at):
			continue
		var count := 0
		for ahead: Vector3 in projected:
			if _xz(ahead).distance_to(_xz(at)) <= radius - 0.7:
				count += 1
		if count >= minimum and (best.is_empty() or float(count) > best.score):
			best = {"at": at, "score": float(count)}
	return best

func _fire_target(game: Node3D, visible: Array[WarMarches.MarchUnit]) -> Dictionary:
	# Bin short-horizon estimates once. Evaluate at most 24 occupied cells and
	# their neighbors, rather than comparing every soldier against every other.
	var cells: Dictionary[Vector2i, Array] = {}
	var hostile_counts: Dictionary[Vector2i, int] = {}
	var friendly_paths: Array[Dictionary] = []
	var friendly_routes: Dictionary[WarMarches.MarchOrder, Vector3] = {}
	# Check the entire burn window, including known allied doorway queues. A
	# short-lived friendly near its destination must not disappear from this test.
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not game.FACTIONS.allied(unit.order.faction, faction) or not INFORMATION.is_unit_known(game, unit, faction):
			continue
		if unit.spawn_delay >= WarFireWave.BURN_TIME:
			continue
		var end := minf(unit.order.length, unit.distance + game.marches.movement_distance(unit, WarFireWave.BURN_TIME))
		if end < 0.0:
			continue
		var start := maxf(0.0, unit.distance)
		var span: Vector3 = friendly_routes.get(unit.order, Vector3(start, end, 0.0))
		friendly_routes[unit.order] = Vector3(minf(span.x, start), maxf(span.y, end), maxf(span.z, absf(unit.lane) + 0.7))
	# Ranks share one curve: test their combined corridor once per order, rather
	# than resampling the same route for hundreds of neighboring soldiers.
	for order: WarMarches.MarchOrder in friendly_routes:
		var span := friendly_routes[order]
		var previous := order.sample(span.x)
		var samples := maxi(1, ceili((span.y - span.x) / 1.5))
		for sample: int in samples:
			var point := order.sample(lerpf(span.x, span.y, float(sample + 1) / samples))
			friendly_paths.append({"from": _xz(previous), "to": _xz(point), "padding": span.z})
			previous = point
	for unit: WarMarches.MarchUnit in visible:
		if not unit.is_exposed() or not INFORMATION.is_unit_known(game, unit, faction) or not game.FACTIONS.hostile(unit.order.faction, faction):
			continue
		var lead: float = game.marches.movement_distance(unit, WarFireWave.EXPANSION_TIME * 0.5)
		if unit.distance + lead >= unit.order.length:
			continue
		var at := unit.order.sample(unit.distance + lead)
		var cell := Vector2i(floori(at.x / FIRE_CELL), floori(at.z / FIRE_CELL))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(at)
		hostile_counts[cell] = hostile_counts.get(cell, 0) + 1
	var candidates := hostile_counts.keys()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return hostile_counts[a] > hostile_counts[b])
	var best := {}
	for cell: Vector2i in candidates.slice(0, 24):
		var at: Vector3 = game.map.definition.surface_point(Vector3((cell.x + 0.5) * FIRE_CELL, 0.0, (cell.y + 0.5) * FIRE_CELL))
		if not game._valid_ground_skill_target(at):
			continue
		var at_xz := _xz(at)
		var threatened := false
		for fire: RefCounted in game.fire_states:
			if fire.age < WarFireWave.BURN_TIME and _xz(fire.global_position).distance_to(at_xz) < game.IMPACT_RADIUS * 1.5:
				threatened = true
				break
		if threatened:
			continue
		var enemies := 0
		var unsafe := false
		for path: Dictionary in friendly_paths:
			var closest := Geometry2D.get_closest_point_to_segment(at_xz, path.from, path.to)
			if closest.distance_to(at_xz) <= game.IMPACT_RADIUS + path.padding:
				unsafe = true
				break
		if unsafe:
			continue
		for x: int in range(-2, 3):
			for y: int in range(-2, 3):
				for point: Vector3 in cells.get(cell + Vector2i(x, y), []):
					enemies += int(_xz(point).distance_to(at_xz) <= game.IMPACT_RADIUS - 0.6)
		# Friendly fire remains real. Do not knowingly burn even a small allied escort.
		if enemies < 8:
			continue
		var score := float(enemies) * 2.2
		if best.is_empty() or score > best.score:
			best = {"at": at, "score": score}
	return best

func _rabbit_turn(game: Node3D) -> void:
	var visible: Array[WarMarches.MarchUnit] = []
	var threats: Dictionary[int, float] = {}
	var combat: Dictionary[Vector2i, Dictionary] = {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not unit.is_exposed() or not INFORMATION.is_unit_known(game, unit, faction):
			continue
		visible.append(unit)
		var target: WarBuilding = game.by_id[unit.order.target_id]
		if game.FACTIONS.hostile(unit.order.faction, faction) and game.FACTIONS.allied(target.faction, faction) and game.marches.movement_distance(unit, 6.0) >= unit.order.length - unit.distance:
			threats[target.building_id] = threats.get(target.building_id, 0.0) + unit.order.strength * _combat_multiplier(game, combat, unit.order.faction, target, game.marches.projected_attack_bonus(unit))
	var best := {"index": -1, "score": 12.0, "target": null, "at": Vector3.ZERO}
	if game.can_cast_skill(0, faction):
		var rush := _rush_target(game, visible)
		if not rush.is_empty() and rush.score > best.score:
			best = {"index": 0, "score": rush.score, "target": null, "at": rush.at}
	if game.can_cast_skill(1, faction):
		var future_positions: Dictionary[WarMarches.MarchUnit, Vector3] = {}
		for building: WarBuilding in game.buildings:
			if not game._valid_skill_target(1, building, faction):
				continue
			var score := _disable_score(game, building, visible, future_positions)
			if score > best.score:
				best = {"index": 1, "score": score, "target": building, "at": Vector3.ZERO}
	if game.can_cast_skill(2, faction):
		# A whistle affects both teams. Score the whole local group so saving a
		# building does not accidentally pull back a larger winning allied attack.
		var cells: Dictionary[Vector2i, Dictionary] = {}
		for unit: WarMarches.MarchUnit in visible:
			if unit.order.target_id == unit.order.source_id:
				continue
			var cell := Vector2i(floori(unit.position.x / FIRE_CELL), floori(unit.position.z / FIRE_CELL))
			if not cells.has(cell):
				cells[cell] = {"at": unit.position, "count": 0}
			cells[cell].count += 1
		var candidates := cells.values()
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.count > b.count)
		for candidate: Dictionary in candidates.slice(0, 24):
			var at: Vector3 = game.map.definition.surface_point(candidate.at)
			if not game._valid_ground_skill_target(at):
				continue
			var score := 0.0
			for unit: WarMarches.MarchUnit in visible:
				if unit.order.target_id == unit.order.source_id or _xz(unit.position).distance_squared_to(_xz(at)) > SKILL_RULES.RECALL_RADIUS * SKILL_RULES.RECALL_RADIUS:
					continue
				var destination: WarBuilding = game.by_id[unit.order.target_id]
				if game.FACTIONS.hostile(unit.order.faction, faction):
					score += 2.0 if game.FACTIONS.allied(destination.faction, faction) else 0.25
				else:
					var home: WarBuilding = game.by_id[unit.order.source_id]
					var danger: float = threats.get(home.building_id, 0.0)
					var defending: bool = game.FACTIONS.allied(home.faction, faction) and danger >= home.population * 0.65 and danger > 0.0 and _xz(unit.position).distance_to(_xz(home.global_position)) < game.marches.base_speed(unit.order.faction) * 4.0
					score += 2.0 if defending else -2.5
			if score > best.score:
				best = {"index": 2, "score": score, "target": null, "at": at}
	if game.can_cast_skill(3, faction):
		# Existing allied commitments depend on the target, not the burrow source.
		var incoming_by_target: Dictionary[int, int] = {}
		for source: WarBuilding in game.buildings:
			if not game._valid_skill_target(3, source, faction):
				continue
			var percent := 0
			for option: int in [25, 50, 75, 100]:
				var count := mini(SKILL_RULES.BURROW_LIMIT, floori(source.available_population * option / 100.0))
				if count >= 12 and source.available_population - count >= threats.get(source.building_id, 0.0) + 6.0:
					percent = option
			if percent == 0:
				continue
			for building: WarBuilding in game.buildings:
				var plan: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, source, building, percent)
				if plan.is_empty():
					continue
				var burning := false
				for fire: RefCounted in game.fire_states:
					if fire.age < WarFireWave.BURN_TIME and _xz(fire.global_position).distance_to(_xz(plan.exit)) <= game.IMPACT_RADIUS + 0.7:
						burning = true
				if burning:
					continue
				var score := 0.0
				if game.FACTIONS.allied(building.faction, faction):
					var danger: float = threats.get(building.building_id, 0.0)
					if danger >= building.population * 0.75 and danger > 8.0:
						score = 25.0 + minf(plan.count, danger) * 1.5
				else:
					var arrival: float = plan.dig_duration + SKILL_RULES.BURROW_EXIT_DISTANCE / game.marches.base_speed(faction) + floorf(float(plan.count - 1) / WarMarches.COLUMNS) * SKILL_RULES.BURROW_BATCH_INTERVAL
					var garrison := INFORMATION.garrison_estimate(game, building, faction)
					var growth := minf(maxf(0.0, building.capacity - garrison), building.production_rate * maxf(0.0, arrival - building.disruption_remaining))
					var damage: float = plan.count * _combat_multiplier(game, combat, faction, building)
					if not incoming_by_target.has(building.building_id):
						incoming_by_target[building.building_id] = game.marches.team_incoming_for(building.building_id, faction)
					var committed := incoming_by_target[building.building_id]
					if committed == 0 and damage > garrison + growth + 2.0 and plan.length >= 9.0:
						score = 28.0 + minf(18.0, damage - garrison - growth)
				if score > best.score:
					best = {"index": 3, "score": score, "target": source, "destination": building, "percent": percent}
	if best.index in [0, 2]:
		game.cast_ground_skill(best.index, best.at, faction)
	elif best.index == 3:
		if game.cast_skill(3, best.target, faction):
			game.issue_order(best.target, best.destination, best.percent, faction)
	elif best.index == 1:
		game.cast_skill(1, best.target, faction)

func _rush_target(game: Node3D, visible: Array[WarMarches.MarchUnit]) -> Dictionary:
	# Aim at the present squad, not a future ground field. Small opening waves
	# are valuable when they can strike a neutral garrison during the rush.
	var cells: Dictionary[Vector2i, Dictionary] = {}
	var cell_size := SKILL_RULES.RABBIT_RUSH_RADIUS
	for unit: WarMarches.MarchUnit in visible:
		if not unit.is_exposed() or unit.order.faction != faction or unit.rush_remaining > 0.0:
			continue
		var cell := Vector2i(floori(unit.position.x / cell_size), floori(unit.position.z / cell_size))
		if not cells.has(cell):
			cells[cell] = {"sum": Vector3.ZERO, "count": 0}
		cells[cell].sum += unit.position
		cells[cell].count += 1
	var candidates := cells.values()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.count > b.count)
	var best := {}
	for candidate: Dictionary in candidates.slice(0, 24):
		var at: Vector3 = game.map.definition.surface_point(candidate.sum / candidate.count)
		var score := 0.0
		var count := 0
		for unit: WarMarches.MarchUnit in visible:
			if not unit.is_exposed() or unit.order.faction != faction or unit.rush_remaining > 0.0 or _xz(unit.position).distance_squared_to(_xz(at)) > cell_size * cell_size:
				continue
			var target: WarBuilding = game.by_id[unit.order.target_id]
			var remaining := unit.order.length - unit.distance
			if remaining < 0.5:
				continue
			count += 1
			var reaches: bool = remaining < game.marches.base_speed(faction) * SKILL_RULES.RABBIT_RUSH_MULTIPLIER * SKILL_RULES.RABBIT_DURATIONS[0]
			if not game.FACTIONS.allied(target.faction, faction) and reaches:
				score += 3.0
			else:
				score += minf(1.3, remaining / 10.0)
		if count >= 5 and (best.is_empty() or score > best.score):
			best = {"at": at, "score": score}
	return best

func _disable_score(game: Node3D, building: WarBuilding, visible: Array[WarMarches.MarchUnit], future_positions: Dictionary[WarMarches.MarchUnit, Vector3]) -> float:
	if building.kind == 3:
		var count: int = game.energy_tower_count(building.faction)
		var denied: float = SKILL_RULES.energy_tower_bonus(count) - SKILL_RULES.energy_tower_bonus(maxi(0, count - 1))
		return denied * SKILL_RULES.DISABLE_DURATION * 2.0
	if building.kind == 0:
		# Hidden occupancy and another commander's remaining recruitment clock
		# cannot tell us how much production a seal will actually prevent.
		var garrison := INFORMATION.garrison_estimate(game, building, faction)
		var prevented := minf(building.production_rate * SKILL_RULES.DISABLE_DURATION, maxf(0.0, building.capacity - garrison))
		return prevented * 1.6
	if building.kind == 2:
		var count: int = game.forge_count(building.faction)
		var attack_lost: float = game.COMBAT_RULES.forge_attack_bonus(count) - game.COMBAT_RULES.forge_attack_bonus(maxi(0, count - 1))
		var defense_lost: float = game.COMBAT_RULES.forge_defense_bonus(count) - game.COMBAT_RULES.forge_defense_bonus(maxi(0, count - 1))
		var engaged := 0.0
		for unit: WarMarches.MarchUnit in visible:
			if not unit.is_exposed() or not INFORMATION.is_unit_known(game, unit, faction) or unit.order.faction != building.faction:
				continue
			var target: WarBuilding = game.by_id[unit.order.target_id]
			if game.FACTIONS.allied(target.faction, faction) and game.marches.movement_distance(unit, 6.0) >= unit.order.length - unit.distance:
				engaged += unit.order.strength
		return engaged * (attack_lost + defense_lost) * 2.0
	var exposed := 0
	for unit: WarMarches.MarchUnit in visible:
		if not unit.is_exposed() or not INFORMATION.is_unit_known(game, unit, faction) or not game.FACTIONS.allied(unit.order.faction, faction):
			continue
		# Each tower observes the same four-second path before the eventual cast.
		# Lazily sample it once without changing this building's visibility/counts.
		if not future_positions.has(unit):
			future_positions[unit] = unit.order.sample(minf(unit.order.length, unit.distance + game.marches.movement_distance(unit, 4.0)))
		var future := future_positions[unit]
		if Geometry2D.get_closest_point_to_segment(_xz(building.global_position), _xz(unit.position), _xz(future)).distance_to(_xz(building.global_position)) <= game.tower_range(building):
			exposed += 1
	return minf(exposed, building.level * ceili(6.0 / game.tower_interval(building))) * 2.0 + (8.0 if exposed >= 12 else 0.0)
