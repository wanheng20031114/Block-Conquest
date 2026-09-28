extends RefCounted
## A primitive, lossless rule mirror. Rendering never calls combat or production.
const SCHEMA := 1
const GROUPS: Array[String] = ["buildings", "factions", "orders", "units", "fields", "shots", "links", "wards", "remainders", "fires"]
const UNIT_SIZE := 14
const MAX_ID := 2147483647
const MAX_RECORDS := 65536
const MAX_TIME := 1000000000.0
const MAX_EXTRAPOLATION := 1.0
const STRUCTURE_FIELDS := {"buildings": [0, 1, 2, 4, 5, 6, 7, 8, 9], "factions": [0, 3, 4, 5]}
const FIRE := preload("res://scripts/block_war/war_fire_state.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var _order_cache: Dictionary = {}
var _shot_serial := 1
var _objects: Dictionary = {}
var _orders: Dictionary = {}
var _installed_unit_rows: Dictionary = {}
var _installed_order_rows: Dictionary = {}
var _presentation_rows: Array[Array] = []
var _field_geometry: Dictionary = {}
var _last_state: Dictionary = {}

static func v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func deadline(now: float, remaining: float) -> float:
	return now + remaining if remaining > 0.0 else 0.0

static func remaining(end: float, now: float) -> float:
	return maxf(0.0, end - now)

func capture(game: Node, tick: int) -> Dictionary:
	var now: float = game.elapsed
	var state := {"schema": SCHEMA, "tick": tick, "time": now, "finished": game.finished, "winner": game.winner_team}
	for group: String in GROUPS:
		state[group] = {}
	for b: WarBuilding in game.buildings:
		state.buildings[str(b.building_id)] = [b.faction, b.kind, b.level, b.population, b.queued_population,
			deadline(now, b.construction_remaining), b.construction_cost, b.conversion_target,
			deadline(now, b.disruption_remaining), deadline(now, b.burrow_remaining),
			deadline(now, float(game.tower_clocks[b.building_id])), now]
	for f: int in game.faction_count:
		var skill: RefCounted = game.faction_skills[f]
		var cooldown: Array = []
		var duration: Array = []
		for index: int in 4:
			cooldown.append(deadline(now, skill.cooldowns[index]))
			duration.append(deadline(now, skill.durations[index]))
		state.factions[str(f)] = [str(skill.commander), skill.energy, cooldown, duration, skill.recruit_target_id,
			game.morale._points[f], game.morale._idle_seconds[f], game.morale._next_decay_at[f], now]
	for unit: WarMarches.MarchUnit in game.marches._units:
		var order := unit.order
		var oid := str(order.order_id)
		if not _order_cache.has(oid):
			var points: Array = []
			for index: int in order.curve.point_count:
				points.append(v3(order.curve.get_point_position(index)))
			_order_cache[oid] = [order.source_id, order.target_id, order.faction, order.strength,
				order.returning, order.departure_distance, points]
		state.orders[oid] = _order_cache[oid]
		state.units[str(unit.unit_id)] = [order.order_id, unit.distance, unit.lane, unit.pending_departure,
			unit.departure_sequence, now + unit.spawn_delay if unit.spawn_delay > 0.0 else 0.0,
			now + unit.rush_remaining if unit.rush_remaining > 0.0 else 0.0,
			now + unit.levitation_remaining if unit.levitation_remaining > 0.0 else 0.0, unit.cloaked, unit.weakened, unit.reserved,
			unit.intercepted_by, now, unit.gait]
	for key: String in _order_cache.keys():
		if not state.orders.has(key):
			_order_cache.erase(key)
	for kind: String in ["haste", "slow", "weak"]:
		var zones: Dictionary = game.marches.get(kind + "_zones")
		for f: int in zones:
			var zone: Dictionary = zones[f]
			state.fields[kind + ":" + str(f)] = [kind, f, v3(zone.at), zone.radius,
				deadline(now, zone.remaining), zone.get("duration", game.SKILL_RULES.FROG_DURATIONS[0]),
				zone.get("multiplier", 1.0), str(zone.get("style", "squirrel"))]
	for id: int in game.shields:
		state.fields["shield:" + str(id)] = ["shield", id, deadline(now, game.shields[id])]
	for id: int in game.bear.links:
		var link: Dictionary = game.bear.links[id]
		state.links[str(id)] = [link.target, link.support, link.faction, deadline(now, link.remaining), link.settled, link.pulse]
	for id: int in game.bear.wards:
		var ward: Dictionary = game.bear.wards[id]
		state.wards[str(id)] = [ward.faction, deadline(now, ward.remaining), deadline(now, ward.shot_clock), ward.pulse]
	for id: int in game.bear.damage_remainders:
		state.remainders[str(id)] = game.bear.damage_remainders[id]
	for shots: Array in [game.projectiles, game.bear.shots]:
		for shot: Dictionary in shots:
			_shot_serial = maxi(_shot_serial, int(shot.get("network_id", 0)) + 1)
	_capture_shots(state.shots, game.projectiles, "tower", now)
	_capture_shots(state.shots, game.bear.shots, "orb", now)
	for fire: RefCounted in game.fire_states:
		if fire.age >= WarFireWave.LIFETIME:
			continue
		var hits: Array = []
		for id: int in fire.hit_buildings:
			hits.append(id)
		hits.sort()
		state.fires[str(fire.effect_id)] = [v3(fire.global_position), fire.radius, fire.faction, now - fire.age, hits]
	state["counters"] = [game.marches._next_order_id, game.marches._next_unit_id, game.marches._departure_sequence, game._next_fire_id]
	return state

func _capture_shots(output: Dictionary, shots: Array, kind: String, now: float) -> void:
	for shot: Dictionary in shots:
		if not shot.has("network_id"):
			shot["network_id"] = _shot_serial
			_shot_serial += 1
		var origin: Vector3 = shot.at if kind == "tower" else shot.origin
		output[str(shot.network_id)] = [kind, shot.target.unit_id, v3(origin), v3(shot.to),
			now - float(shot.age), float(shot.duration), shot.get("tracking", true)]

static func for_player(state: Dictionary, faction: int) -> Dictionary:
	var result := state.duplicate(false)
	result.factions = state.factions.duplicate(false)
	for key: String in result.factions:
		if int(key) == faction:
			continue
		var row: Array = result.factions[key].duplicate(true)
		row[1] = 0.0
		row[2] = [0.0, 0.0, 0.0, 0.0]
		result.factions[key] = row
	return result

static func digest(state: Dictionary) -> String:
	# Godot's JSON parser turns integers into doubles and can round a decimal by
	# one ULP. Hash-only normalization is finer than the rule epsilon (1e-6);
	# full-precision fractions in the actual snapshot/mirror stay untouched.
	return JSON.stringify(_canonical(state), "", true, true).sha256_text()

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_canonical(item))
		return result
	if _number(value):
		return "number:" + ("0" if float(value) == 0.0 else String.num(float(value), 8))
	return value

static func diff(previous: Dictionary, current: Dictionary, force: bool = false) -> Dictionary:
	var changes: Dictionary = {}
	var removed: Dictionary = {}
	for group: String in GROUPS:
		var before: Dictionary = previous.get(group, {})
		var after: Dictionary = current[group]
		var writes: Dictionary = {}
		var deletes: Array = []
		for key: String in after:
			if force or not before.has(key) or _discrete_changed(group, before[key], after[key]) or (group == "buildings" and absf(_population_at(before[key], previous.factions, int(key), float(after[key][11])) - float(after[key][3])) > 0.00001):
				writes[key] = after[key]
		for key: String in before:
			if not after.has(key):
				deletes.append(key)
		if not writes.is_empty():
			changes[group] = writes
		if not deletes.is_empty():
			removed[group] = deletes
	# Speed/field changes re-anchor every moving soldier at the same boundary.
	# This avoids integrating an old movement anchor through a newly known field.
	var speed_changed: bool = changes.has("fields") or removed.has("fields")
	for key: String in changes.get("factions", {}):
		if previous.get("factions", {}).has(key) and previous.factions[key][5] != current.factions[key][5]:
			speed_changed = true
	if speed_changed:
		changes["units"] = current.units.duplicate(false)
	return {"tick": current.tick, "time": current.time, "finished": current.finished, "winner": current.winner,
		"set": changes, "remove": removed, "counters": current.counters}

static func _discrete_changed(group: String, old: Variant, next: Variant) -> bool:
	if group == "units":
		# This runs once per soldier per Host tick. Avoid allocating index arrays
		# and iterating Variants for the fixed wire layout.
		return old[0] != next[0] or old[2] != next[2] or old[3] != next[3] or old[4] != next[4] \
			or old[8] != next[8] or old[9] != next[9] or old[10] != next[10] or old[11] != next[11] \
			or absf(float(old[5]) - float(next[5])) > 0.00001 \
			or absf(float(old[6]) - float(next[6])) > 0.00001 \
			or absf(float(old[7]) - float(next[7])) > 0.00001
	if group == "buildings":
		for i: int in [0, 1, 2, 4, 6, 7]:
			if old[i] != next[i]: return true
		for i: int in [5, 8, 9]:
			if absf(float(old[i]) - float(next[i])) > 0.00001: return true
		# Natural growth is extrapolated; damage and paid construction are facts.
		return float(next[3]) < float(old[3]) - 0.000001
	if group == "factions":
		if old[0] != next[0] or old[4] != next[4] or old[5] != next[5]: return true
		for array_index: int in [2, 3]:
			for i: int in 4:
				if absf(float(old[array_index][i]) - float(next[array_index][i])) > 0.00001: return true
		return float(next[1]) < float(old[1]) - 0.000001
	if group == "links":
		for i: int in [0, 1, 2, 4]:
			if old[i] != next[i]: return true
		return absf(float(old[3]) - float(next[3])) > 0.00001
	if group == "wards":
		for i: int in 3:
			if absf(float(old[i]) - float(next[i])) > 0.00001: return true
		return false
	if group == "shots":
		return old[6] != next[6]
	if group == "fires":
		return old[0] != next[0] or old[1] != next[1] or old[2] != next[2] or absf(float(old[3]) - float(next[3])) > 0.00001 or old[4] != next[4]
	if group == "fields":
		if old.size() != next.size(): return true
		for i: int in old.size():
			if old[i] is float or old[i] is int:
				if absf(float(old[i]) - float(next[i])) > 0.00001: return true
			elif old[i] != next[i]: return true
		return false
	return old != next

static func apply_delta(state: Dictionary, delta: Dictionary) -> void:
	for group: String in delta.remove:
		for key: String in delta.remove[group]:
			state[group].erase(key)
	for group: String in delta.set:
		for key: String in delta.set[group]:
			state[group][key] = delta.set[group][key]
	state.tick = delta.tick
	state.time = delta.time
	state.finished = delta.finished
	state.winner = delta.winner
	state.counters = delta.counters

static func valid(state: Dictionary, game: Node) -> bool:
	if state.get("schema") != SCHEMA or not _integer(state.get("tick"), 0, MAX_ID) or not _nonnegative(state.get("time")) or not state.get("finished") is bool or not _integer(state.get("winner"), -2, 1):
		return false
	if bool(state.finished) != (int(state.winner) != -2): return false
	for group: String in GROUPS:
		if not state.get(group) is Dictionary or state[group].size() > MAX_RECORDS: return false
	if state.buildings.size() != game.buildings.size() or state.factions.size() != game.faction_count:
		return false
	for group: String in GROUPS:
		for key: Variant in state[group]:
			var row: Variant = state[group][key]
			if not valid_record(group, row, game): return false
			if group == "fields":
				if not key is String or key != str(row[0]) + ":" + str(int(row[1])): return false
			elif not _id(key): return false
			elif group in ["buildings", "wards", "remainders", "links"]:
				if not game.by_id.has(int(key)): return false
			elif group == "factions":
				if int(key) >= game.faction_count: return false
			elif int(key) < 1: return false
			if group == "units" and not state.orders.has(str(int(row[0]))): return false
			if group == "links" and int(key) != int(row[0]): return false
	if not _row(state.get("counters"), 4): return false
	for i: int in 4:
		if not _integer(state.counters[i], 0 if i == 2 else 1, MAX_ID): return false
	for pair: Array in [["orders", 0], ["units", 1], ["fires", 3]]:
		for key: String in state[pair[0]]:
			if int(key) >= int(state.counters[pair[1]]): return false
	# The hidden doorway soldiers and their garrison reservations form one fact.
	var reservations := {}
	for row: Array in state.units.values():
		var order: Array = state.orders[str(int(row[0]))]
		if row[3]:
			var source := str(int(order[0]))
			if int(state.buildings[source][0]) != int(order[2]): return false
			reservations[source] = int(reservations.get(source, 0)) + 1
	for key: String in state.buildings:
		if int(state.buildings[key][4]) != int(reservations.get(key, 0)): return false
	return true

static func valid_record(group: String, row: Variant, game: Node) -> bool:
	# Check the type before ANY indexing, integer conversion or nested cast.
	match group:
		"buildings":
			if not _row(row, 12) or not _integer(row[0], -1, game.faction_count - 1) or not _integer(row[1], 0, 2): return false
			if not _integer(row[2], 1, [4, 3, 1][int(row[1])]) or not _nonnegative(row[3]) or not _integer(row[4], 0, floori(float(row[3]) + 0.000001)): return false
			if not _integer(row[6], 0, MAX_ID) or not _integer(row[7], -1, 2): return false
			for i: int in [5, 8, 9, 10, 11]:
				if not _nonnegative(row[i]): return false
			return true
		"factions": return valid_account(row, game)
		"orders":
			if not _row(row, 7) or not _building_id(row[0], game) or not _building_id(row[1], game) or not _integer(row[2], 0, game.faction_count - 1): return false
			if not _nonnegative(row[3]) or float(row[3]) <= 0.0 or not row[4] is bool or not _nonnegative(row[5]): return false
			if not row[6] is Array or row[6].size() < 2 or row[6].size() > 2048: return false
			var length := 0.0
			var previous := Vector3.ZERO
			for i: int in row[6].size():
				if not _vector(row[6][i]): return false
				var point := vector(row[6][i])
				if i > 0: length += previous.distance_to(point)
				previous = point
			return length > 0.01 and float(row[5]) <= length + 0.05
		"units":
			if not _row(row, UNIT_SIZE) or not _integer(row[0], 1, MAX_ID) or not _number(row[1]) or absf(float(row[1])) > MAX_TIME or not _number(row[2]) or absf(float(row[2])) > 32.0: return false
			if not _integer(row[4], 0, MAX_ID) or not _integer(row[11], -1, game.faction_count - 1): return false
			for i: int in [5, 6, 7, 12, 13]:
				if not _nonnegative(row[i]): return false
			for i: int in [3, 8, 9, 10]:
				if not row[i] is bool: return false
			return true
		"fields":
			if not row is Array or row.is_empty() or not row[0] is String: return false
			if row[0] == "shield": return _row(row, 3) and _building_id(row[1], game) and _nonnegative(row[2])
			if not _row(row, 8) or row[0] not in ["haste", "slow", "weak"] or not _integer(row[1], 0, game.faction_count - 1) or not _vector(row[2]): return false
			for i: int in [3, 4, 5, 6]:
				if not _nonnegative(row[i]): return false
			return float(row[3]) > 0 and float(row[3]) < 1000 and float(row[5]) > 0 and float(row[6]) > 0 and float(row[6]) <= 100 and row[7] in ["squirrel", "rabbit", "bear", "frog"]
		"links":
			if not _row(row, 6) or not _building_id(row[0], game) or not _building_id(row[1], game) or int(row[0]) == int(row[1]) or not _integer(row[2], 0, game.faction_count - 1): return false
			return _nonnegative(row[3]) and _integer(row[4], 0, MAX_ID) and _nonnegative(row[5]) and float(row[5]) <= 1.0
		"wards":
			return _row(row, 4) and _integer(row[0], 0, game.faction_count - 1) and _nonnegative(row[1]) and _nonnegative(row[2]) and _nonnegative(row[3]) and float(row[3]) <= 1.0
		"remainders": return _nonnegative(row) and float(row) < 1.000001
		"shots":
			return _row(row, 7) and row[0] in ["tower", "orb"] and _integer(row[1], 1, MAX_ID) and _vector(row[2]) and _vector(row[3]) and _number(row[4]) and absf(float(row[4])) <= MAX_TIME and _number(row[5]) and float(row[5]) > 0 and float(row[5]) <= 10 and row[6] is bool
		"fires":
			if not _row(row, 5) or not _vector(row[0]) or not _number(row[1]) or float(row[1]) <= 0 or float(row[1]) >= 1000 or not _integer(row[2], 0, game.faction_count - 1) or not _number(row[3]) or absf(float(row[3])) > MAX_TIME or not row[4] is Array or row[4].size() > game.buildings.size(): return false
			for id: Variant in row[4]:
				if not _building_id(id, game): return false
			return true
	return false

static func valid_account(row: Variant, game: Node) -> bool:
	if not _row(row, 9) or row[0] not in ["squirrel", "rabbit", "bear", "frog"] or not _nonnegative(row[1]) or float(row[1]) > 100: return false
	for index: int in [2, 3]:
		if not _row(row[index], 4): return false
		for value: Variant in row[index]:
			if not _nonnegative(value): return false
	if not _integer(row[4], -1, MAX_ID) or (int(row[4]) >= 0 and not game.by_id.has(int(row[4]))): return false
	for i: int in [5, 6, 7, 8]:
		if not _nonnegative(row[i]): return false
	return float(row[5]) <= game.MORALE.MAX_POINTS

static func _building_id(value: Variant, game: Node) -> bool:
	return _integer(value, 0, MAX_ID) and game.by_id.has(int(value))

static func _id(value: Variant) -> bool:
	return value is String and value.is_valid_int() and value == str(value.to_int()) and value.to_int() >= 0 and value.to_int() <= MAX_ID

static func _row(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) <= MAX_TIME

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high

static func _vector(value: Variant) -> bool:
	return _row(value, 3) and _number(value[0]) and _number(value[1]) and _number(value[2]) and absf(float(value[0])) < 10000 and absf(float(value[1])) < 10000 and absf(float(value[2])) < 10000

static func _population_at(row: Array, factions: Dictionary, building: int, until: float) -> float:
	var population := float(row[3])
	if int(row[0]) < 0 or int(row[1]) != 0: return population
	var begin: float = row[11]
	var end: float = until
	# Stop at a pending upgrade/conversion: its next production rate is a fact.
	if float(row[5]) > 0: end = minf(end, float(row[5]))
	begin = maxf(begin, float(row[8]))
	var duration := maxf(0.0, end - begin)
	if duration <= 0: return population
	var rate: float = WarBuilding.HOUSE_PRODUCTION_RATES[int(row[2]) - 1]
	var cap: float = WarBuilding.HOUSE_PRODUCTION_LIMITS[int(row[2]) - 1]
	var recruitment := 0.0
	for skill: Array in factions.values():
		if int(skill[4]) == building:
			recruitment = minf(duration, maxf(0.0, float(skill[3][0]) - begin))
			break
	var ordinary := minf(recruitment, maxf(0.0, cap - population) / (RULES.RECRUIT_RATE + rate))
	population += RULES.RECRUIT_RATE * recruitment + rate * ordinary
	if population < cap: population = minf(cap, population + rate * (duration - recruitment))
	return population

static func same_structure(group: String, first: Array, second: Array) -> bool:
	if group == "units":
		# Optional anchors already passed record validation. Comparing their fixed
		# structure needs no temporary dictionary/arrays or repeat type probing.
		return first[0] == second[0] and first[3] == second[3] and first[4] == second[4] \
			and first[8] == second[8] and first[9] == second[9] and first[10] == second[10] and first[11] == second[11] \
			and absf(float(first[2]) - float(second[2])) <= 0.00001 \
			and absf(float(first[5]) - float(second[5])) <= 0.00001 \
			and absf(float(first[6]) - float(second[6])) <= 0.00001 \
			and absf(float(first[7]) - float(second[7])) <= 0.00001
	var indexes: Array = STRUCTURE_FIELDS.get(group, [])
	if indexes.is_empty(): return first == second
	for index: int in indexes:
		if _number(first[index]) and _number(second[index]):
			if absf(float(first[index]) - float(second[index])) > 0.00001: return false
		elif first[index] is Array and second[index] is Array:
			if first[index].size() != second[index].size(): return false
			for i: int in first[index].size():
				if absf(float(first[index][i]) - float(second[index][i])) > 0.00001: return false
		elif first[index] != second[index]: return false
	return true

func install(game: Node, state: Dictionary, at_time: float = -1.0) -> void:
	# Caller validates once before an atomic install. No gameplay signal is emitted.
	var now: float = float(state.time) if at_time < 0.0 else at_time
	game.elapsed = now
	_last_state = state
	_present_buildings(game, state, now)
	for key: String in state.factions:
		var f := int(key)
		var row: Array = state.factions[key]
		var skill: RefCounted = game.faction_skills[f]
		skill.commander = StringName(row[0])
		skill.energy = minf(100.0, float(row[1]) + game.ENERGY_REGEN * maxf(0.0, now - float(row[8]))) if f == game.local_faction else float(row[1])
		for i: int in 4:
			skill.cooldowns[i] = remaining(row[2][i], now)
			skill.durations[i] = remaining(row[3][i], now)
		skill.recruit_target_id = int(row[4])
		game.morale._points[f] = float(row[5])
		game.morale._idle_seconds[f] = float(row[6])
		game.morale._next_decay_at[f] = float(row[7])
		game.marches.morale_speed[f] = game.morale.speed(f)
	var orders_changed := false
	for key: String in state.orders:
		if _installed_order_rows.get(key) == state.orders[key]: continue
		orders_changed = true
		var row: Array = state.orders[key]
		var order := WarMarches.MarchOrder.new()
		order.order_id = int(key)
		order.source_id = int(row[0]); order.target_id = int(row[1]); order.faction = int(row[2])
		order.strength = float(row[3]); order.returning = row[4]; order.departure_distance = float(row[5])
		order.curve = Curve3D.new(); order.curve.bake_interval = 0.12
		for point: Array in row[6]: order.curve.add_point(vector(point))
		order.length = order.curve.get_baked_length()
		_orders[key] = order
		_installed_order_rows[key] = row
	for key: String in _orders.keys():
		if not state.orders.has(key):
			_orders.erase(key); _installed_order_rows.erase(key)
	_install_fields(game, state, now)
	game.marches.blocked_destinations.clear()
	for key: String in state.wards:
		if remaining(state.wards[key][1], now) > 0:
			game.marches.blocked_destinations[int(key)] = int(state.wards[key][0])
	# Preserve expired fields until all older motion anchors have integrated their
	# remaining active interval. Their historical deadlines stay in this view.
	var units: Array[WarMarches.MarchUnit] = []
	var rows: Array[Array] = []
	var units_changed := false
	for key: String in state.units:
		var row: Array = state.units[key]
		rows.append(row)
		var unit: WarMarches.MarchUnit = _objects.get(key)
		var existing := unit != null
		if not existing:
			unit = WarMarches.MarchUnit.new(); unit.unit_id = int(key)
			_objects[key] = unit
		var installed: Variant = _installed_unit_rows.get(key)
		if (is_same(installed, row) or installed == row) and (not orders_changed or unit.order == _orders[str(int(row[0]))]):
			units.append(unit)
			continue
		units_changed = true
		var previous := unit.position + unit.presentation_offset
		var was_exposed := existing and unit.is_exposed()
		unit.alive = true; unit.order = _orders[str(int(row[0]))]
		unit.distance = float(row[1]); unit.lane = float(row[2]); unit.pending_departure = row[3]
		unit.departure_sequence = int(row[4]); unit.cloaked = row[8]; unit.weakened = row[9]
		unit.reserved = row[10]; unit.intercepted_by = int(row[11]); unit.gait = float(row[13])
		var base: float = row[12]
		unit.spawn_delay = remaining(row[5], base); unit.rush_remaining = remaining(row[6], base)
		unit.levitation_remaining = remaining(row[7], base)
		_set_field_clock(game, state, base, false)
		_move_visual_unit(game, unit, minf(MAX_EXTRAPOLATION, maxf(0.0, now - base)))
		unit.spawn_delay = remaining(row[5], now); unit.rush_remaining = remaining(row[6], now)
		unit.levitation_remaining = remaining(row[7], now)
		game.marches._update_pose(unit)
		var offset := previous - unit.position
		unit.presentation_offset = offset if was_exposed and unit.is_exposed() and offset.length_squared() <= 16.0 else Vector3.ZERO
		_installed_unit_rows[key] = row
		units.append(unit)
	_set_field_clock(game, state, now, true)
	for key: String in _objects.keys():
		if not state.units.has(key):
			units_changed = true
			_objects[key].alive = false
			_objects.erase(key); _installed_unit_rows.erase(key)
	game.marches._units = units
	_presentation_rows = rows
	game.marches._next_order_id = int(state.counters[0]); game.marches._next_unit_id = int(state.counters[1]); game.marches._departure_sequence = int(state.counters[2])
	game.marches._ensure_capacity(units.size())
	if units_changed: game.marches._render()
	game.bear.links.clear(); game.bear.wards.clear(); game.bear.damage_remainders.clear(); game.marches.blocked_destinations.clear()
	for key: String in state.links:
		var row: Array = state.links[key]
		game.bear.links[int(key)] = {"target": int(row[0]), "support": int(row[1]), "faction": int(row[2]), "remaining": remaining(row[3], now), "settled": int(row[4]), "pulse": float(row[5])}
	for key: String in state.wards:
		var row: Array = state.wards[key]
		game.bear.wards[int(key)] = {"faction": int(row[0]), "remaining": remaining(row[1], now), "shot_clock": remaining(row[2], now), "pulse": float(row[3])}
		if remaining(row[1], now) > 0: game.marches.blocked_destinations[int(key)] = int(row[0])
	for key: String in state.remainders: game.bear.damage_remainders[int(key)] = float(state.remainders[key])
	_install_shots(game, state, now)
	_install_fire(game, state, now)
	game.world_effects.update_skills(0.0, game.faction_skills, game.shields, game.by_id, game.marches)
	game.world_effects.get_node("Bear").sync(game.bear, game.marches, game.by_id, 0.0)
	game.world_effects.get_node("Frog").sync(game.marches, 0.0)
	game.update_hud()

func _present_buildings(game: Node, state: Dictionary, now: float) -> void:
	for key: String in state.buildings:
		var b: WarBuilding = game.by_id[int(key)]
		var row: Array = state.buildings[key]
		var was_constructing := b.is_constructing
		var was_disrupted := b.disruption_remaining > 0.0
		b.faction = int(row[0]); b.kind = int(row[1]); b.level = int(row[2])
		b.population = _population_at(row, state.factions, b.building_id, minf(now, float(row[11]) + MAX_EXTRAPOLATION))
		b.queued_population = int(row[4])
		# Reaching a clock endpoint is presentation, not a completion/capture fact.
		b.construction_remaining = maxf(0.000001, remaining(row[5], now)) if float(row[5]) > 0.0 else 0.0
		b.construction_cost = int(row[6]); b.conversion_target = int(row[7])
		b.disruption_remaining = remaining(row[8], now); b.burrow_remaining = remaining(row[9], now)
		game.tower_clocks[b.building_id] = remaining(row[10], now)
		if not was_constructing and b.is_constructing:
			b.get_node("Construction").show(); b.get_node("Construction/Complete").hide()
			b.get_node("Construction/Dust").restart(); b.get_node("Construction/Chips").restart()
		elif was_constructing and not b.is_constructing:
			b.get_node("Construction").hide()
			b.get_node("Construction/Dust").emitting = false; b.get_node("Construction/Chips").emitting = false
		if not was_disrupted and b.disruption_remaining > 0:
			b.get_node("Disruption").start(b.disruption_remaining)
		elif was_disrupted and b.disruption_remaining <= 0:
			b.get_node("Disruption").finish()
		b._sync_disruption_visual()
		b.get_node("BurrowReady").set_remaining(b.burrow_remaining)
		b.refresh_visual()

func _install_fields(game: Node, state: Dictionary, now: float) -> void:
	game.shields.clear()
	game.marches.haste_zones.clear(); game.marches.slow_zones.clear(); game.marches.weak_zones.clear()
	var geometry := {}
	for key: String in state.fields:
		var row: Array = state.fields[key]
		if row[0] == "shield":
			if remaining(row[2], now) > 0: game.shields[int(row[1])] = remaining(row[2], now)
			continue
		geometry[key] = [row[2], row[3]]
		var zone := {"at": vector(row[2]), "radius": float(row[3]), "remaining": remaining(row[4], now), "duration": float(row[5]), "multiplier": float(row[6]), "style": StringName(row[7])}
		var zones: Dictionary = game.marches.get(str(row[0]) + "_zones")
		zones[int(row[1])] = zone
	if geometry != _field_geometry:
		for order: WarMarches.MarchOrder in _orders.values():
			order.haste_intervals.clear(); order.slow_intervals.clear(); order.mist_intervals.clear()
		_field_geometry = geometry

func _set_field_clock(game: Node, state: Dictionary, now: float, discard_expired: bool) -> void:
	for row: Array in state.fields.values():
		if row[0] == "shield": continue
		var zones: Dictionary = game.marches.get(str(row[0]) + "_zones")
		var id := int(row[1])
		if not zones.has(id): continue
		zones[id].remaining = remaining(row[4], now)
		if discard_expired and zones[id].remaining <= 0.0: zones.erase(id)

func _move_visual_unit(game: Node, unit: WarMarches.MarchUnit, seconds: float) -> void:
	if not unit.pending_departure and seconds > 0.0:
		var step: float = game.marches.movement_distance(unit, seconds)
		unit.distance = minf(unit.order.length - 0.001, unit.distance + step)
		if game.marches.blocked_destinations.has(unit.order.target_id) and game.FACTIONS.hostile(unit.order.faction, game.marches.blocked_destinations[unit.order.target_id]):
			unit.distance = minf(unit.distance, unit.order.length - 0.12)
		unit.gait += step * 7.0

func _install_shots(game: Node, state: Dictionary, now: float) -> void:
	game.projectiles.clear(); game.bear.shots.clear()
	for key: String in state.shots:
		var row: Array = state.shots[key]
		var target: WarMarches.MarchUnit = _objects.get(str(int(row[1])))
		if target == null:
			target = WarMarches.MarchUnit.new(); target.unit_id = int(row[1]); target.alive = false
		var origin := vector(row[2])
		var to := vector(row[3])
		var age := maxf(0.0, now - float(row[4]))
		var shot := {"network_id": int(key), "target": target, "position": origin, "previous": origin, "to": to, "age": age, "duration": float(row[5]), "tracking": row[6]}
		shot["at" if row[0] == "tower" else "origin"] = origin
		var shots: Array = game.projectiles if row[0] == "tower" else game.bear.shots
		shots.append(shot)
		_shot_serial = maxi(_shot_serial, int(key) + 1)
	_draw_shots(game, 0.0)

func _install_fire(game: Node, state: Dictionary, now: float) -> void:
	game.fire_states.clear()
	for key: String in state.fires:
		var row: Array = state.fires[key]
		var fire := FIRE.new()
		fire.effect_id = int(key)
		fire.global_position = vector(row[0]); fire.radius = float(row[1]); fire.faction = int(row[2])
		fire.age = maxf(0.0, now - float(row[3]))
		for id: Variant in row[4]: fire.hit_buildings[int(id)] = true
		game.fire_states.append(fire)
	game._next_fire_id = int(state.counters[3])
	game.world_effects.sync_fire_states(game.fire_states)

func present(game: Node, _state: Dictionary, delta: float) -> void:
	# No departure, hit, capture, production event, AI, or morale settlement.
	if delta <= 0.0 or _last_state.is_empty(): return
	var before: float = game.elapsed
	game.elapsed += delta
	var marches: WarMarches = game.marches
	var smoothing := exp(-delta / 0.08)
	for index: int in marches._units.size():
		var unit: WarMarches.MarchUnit = marches._units[index]
		var row: Array = _presentation_rows[index]
		var prediction := minf(delta, maxf(0.0, float(row[12]) + MAX_EXTRAPOLATION - before))
		_move_visual_unit(game, unit, prediction)
		unit.spawn_delay = remaining(row[5], game.elapsed)
		unit.rush_remaining = remaining(row[6], game.elapsed)
		unit.levitation_remaining = remaining(row[7], game.elapsed)
		unit.presentation_offset *= smoothing
		marches._update_pose(unit)
	marches._render()
	for f: int in game.faction_count:
		var skill: RefCounted = game.faction_skills[f]
		if f == game.local_faction: skill.energy = minf(game.ENERGY_MAX, skill.energy + game.ENERGY_REGEN * delta)
		for i: int in 4:
			skill.cooldowns[i] = maxf(0.0, skill.cooldowns[i] - delta)
			skill.durations[i] = maxf(0.0, skill.durations[i] - delta)
	_present_buildings(game, _last_state, game.elapsed)
	_set_field_clock(game, _last_state, game.elapsed, true)
	for key: int in game.shields.keys():
		game.shields[key] = maxf(0.0, game.shields[key] - delta)
		if game.shields[key] <= 0: game.shields.erase(key)
	for link: Dictionary in game.bear.links.values():
		link.remaining = maxf(0.0, link.remaining - delta); link.pulse = maxf(0.0, link.pulse - delta * 3)
	for id: int in game.bear.wards:
		var ward: Dictionary = game.bear.wards[id]
		ward.remaining = maxf(0.0, ward.remaining - delta); ward.pulse = maxf(0.0, ward.pulse - delta * 5)
		if ward.remaining <= 0: game.marches.blocked_destinations.erase(id)
	for fire: RefCounted in game.fire_states: fire.age += delta
	for index: int in range(game.effects.size() - 1, -1, -1):
		game.effects[index].life -= delta
		if game.effects[index].life <= 0.0: game.effects.remove_at(index)
	_draw_shots(game, delta)
	game.audio.tick_marches(delta, game.marches)
	game.world_effects.tick(delta)
	game.world_effects.update_skills(delta, game.faction_skills, game.shields, game.by_id, game.marches)
	game.world_effects.get_node("Bear").sync(game.bear, game.marches, game.by_id, delta)
	game.world_effects.get_node("Frog").sync(game.marches, delta)

func _draw_shots(game: Node, delta: float) -> void:
	for kind: String in ["tower", "orb"]:
		var shots: Array = game.projectiles if kind == "tower" else game.bear.shots
		for index: int in range(shots.size() - 1, -1, -1):
			var shot: Dictionary = shots[index]
			shot.age += delta
			if shot.age >= shot.duration:
				# Expiring a display projectile never applies its damage. The Host's
				# casualty fact remains the only authority over the target soldier.
				shots.remove_at(index)
				continue
			var previous: Vector3 = shot.position
			var origin: Vector3 = shot.at if kind == "tower" else shot.origin
			if shot.tracking and shot.target.alive: shot.to = shot.target.position + Vector3.UP * 0.65
			var fraction: float = clampf(shot.age / shot.duration, 0, 1)
			shot.position = origin.lerp(shot.to, fraction)
			if kind == "tower": shot.position += Vector3.UP * sin(fraction * PI) * 0.65
			# Installing an older snapshot must not draw a trail from its muzzle to
			# the corrected position. Normal frames trail the last displayed point.
			shot.previous = previous if delta > 0.0 else shot.position
	game.world_effects.render_projectiles(game.projectiles)
