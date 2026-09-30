class_name WarMarches
extends Node3D
## Every entry is one population point. Marchers never collide or fight in transit.
## The controller calls tick from _process; stopping tick also stops the GPU gait.

signal unit_arrived(target_id: int, faction: int, strength: float, attack_bonus: float, energy_origin: bool)
signal unit_defeated(at: Vector3, heading: Vector3, faction: int, impulse: Vector3, burning: bool)
signal combat_death(faction: int, target_id: int, killer_faction: int)
signal departure_queue_changed(source_id: int, faction: int, change: int)
signal unit_departed(source_id: int, faction: int)

const COLUMNS := 6
const COLUMN_SPACING := 0.56
const ROW_SPACING := 0.90
const DENSE_COLUMN_SPACING := 0.44
const DENSE_ROW_SPACING := 0.50
const FLIGHT_CLEARANCE := 2.5
const GROUND_FIRE_HEIGHT := 0.40
const SPEED := 3.1
const MODEL_SCALE := 0.62
const GATE_LENGTH := 2.4
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FACTION_COLORS: Array[Color] = FACTIONS.COLORS

class MarchOrder extends RefCounted:
	var order_id := 0
	var source_id: int
	var target_id: int
	var faction: int
	var strength: float
	# Issued-order provenance survives conversion, capture, tunnels and recall.
	var energy_origin := false
	var pig_charge := false
	var airborne := false
	var dense := false
	# Fox panic remains visible for the entire march, including recall/conversion.
	var panicked := false
	var curve: Curve3D
	var length: float
	var returning := false
	var departure_distance := 0.0
	var haste_intervals: Dictionary[float, PackedVector2Array] = {}
	var slow_intervals: Dictionary[Vector2, PackedVector2Array] = {}
	var mist_intervals: Dictionary[Vector2, PackedVector2Array] = {}
	var ground_fire_intervals: Dictionary[float, PackedVector2Array] = {}

	func sample(distance: float) -> Vector3:
		return curve.sample_baked(length - distance if returning else distance)

class MarchUnit extends RefCounted:
	var unit_id := 0
	var alive := true
	var reserved := false
	var intercepted_by := -1
	var order: MarchOrder
	var distance: float
	var lane: float
	var position: Vector3
	# Client-only interpolation; never enters simulation snapshots or targeting.
	var presentation_offset := Vector3.ZERO
	var presentation_gait_offset := 0.0
	var heading: Vector3 = Vector3.FORWARD
	var gait: float
	var spawn_delay := 0.0
	var pending_departure := false
	var departure_sequence := 0
	var rush_remaining := 0.0
	var levitation_remaining := 0.0
	# These effects belong to this march, ending when the soldier enters a building.
	var cloaked := false
	var weakened := false

	func is_exposed() -> bool:
		return alive and not pending_departure and distance >= 0.0 and spawn_delay <= 0.0

@onready var _multimesh: MultiMesh = $Militia.multimesh
@onready var _cloaked_mesh: MultiMesh = $CloakedMilitia.multimesh
@onready var _panic_mesh: MultiMesh = $PanicMarks.multimesh
var _units: Array[MarchUnit] = []
var _render_batch_depth := 0
var _render_pending := false
# Standalone simulation fixtures have a flat surface until a battle configures it.
var map_definition := WarMapDefinition.new()
var haste_zones: Dictionary[int, Dictionary] = {}
var slow_zones: Dictionary[int, Dictionary] = {}
var weak_zones: Dictionary[int, Dictionary] = {}
var _departure_sequence := 0
var _next_order_id := 1
var _next_unit_id := 1
var environment_speed := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

func base_speed(faction: int) -> float:
	return SPEED * environment_speed[faction]

func _ready() -> void:
	_multimesh.instance_count = 4096
	_multimesh.visible_instance_count = 0
	_cloaked_mesh.instance_count = 4096
	_cloaked_mesh.visible_instance_count = 0
	_panic_mesh.instance_count = 4096
	_panic_mesh.visible_instance_count = 0

func _make_order(source_id: int, target_id: int, faction: int, route: PackedVector3Array, strength: float = 1.0, energy_origin: bool = false) -> MarchOrder:
	assert(route.size() >= 2, "A march needs a source and destination in its route.")
	assert(faction >= 0 and faction < FACTION_COLORS.size(), "Unknown marching faction.")
	var order := MarchOrder.new()
	order.order_id = _next_order_id
	_next_order_id += 1
	order.source_id = source_id
	order.target_id = target_id
	order.faction = faction
	order.strength = strength
	order.energy_origin = energy_origin
	order.curve = Curve3D.new()
	order.curve.bake_interval = 0.12
	# The map has already shaped and clearance-checked this guide. Resample only
	# along its segments, keeping the preview and every soldier on the same path.
	var last := route[0]
	order.curve.add_point(last)
	for index: int in range(1, route.size()):
		var point := route[index]
		var segment_length := point.distance_to(last)
		if segment_length < 0.001:
			continue
		order.curve.add_point(point)
		last = point
	order.length = order.curve.get_baked_length()
	assert(order.length > 0.01, "Cannot send soldiers along a zero-length route.")
	return order

func send(source_id: int, target_id: int, faction: int, count: int, route: PackedVector3Array, strength: float = 1.0, energy_origin: bool = false, panicked: bool = false) -> void:
	# Transport soldiers whose source has already paid for them (including fixtures).
	_send(source_id, target_id, faction, count, route, strength, false, energy_origin, false, false, false, panicked)

func queue_departure(source_id: int, target_id: int, faction: int, count: int, route: PackedVector3Array, energy_origin: bool = false, charge: bool = false, airborne: bool = false, dense: bool = false) -> void:
	# Normal building orders reserve a garrison, then pay one soldier per departure.
	_send(source_id, target_id, faction, count, route, 1.0, true, energy_origin, charge, airborne, dense)

func _send(source_id: int, target_id: int, faction: int, count: int, route: PackedVector3Array, strength: float, from_garrison: bool, energy_origin: bool, charge: bool = false, airborne: bool = false, dense: bool = false, panicked: bool = false) -> void:
	if count <= 0:
		return
	var order := _make_order(source_id, target_id, faction, route, strength, energy_origin)
	order.pig_charge = charge
	order.airborne = airborne
	order.dense = dense
	order.panicked = panicked
	var column_spacing := DENSE_COLUMN_SPACING if dense else COLUMN_SPACING
	var row_spacing := DENSE_ROW_SPACING if dense else ROW_SPACING
	if from_garrison:
		departure_queue_changed.emit(source_id, faction, count)
	# All exits of a building share one queue, including orders heading to different sides.
	var first_distance := 0.0
	var preceding_spacing := row_spacing
	for existing: MarchUnit in _units:
		if existing.order.source_id == source_id and existing.distance < first_distance:
			first_distance = existing.distance
			preceding_spacing = DENSE_ROW_SPACING if existing.order.dense else ROW_SPACING
	if first_distance < 0.0:
		first_distance -= maxf(row_spacing, preceding_spacing)
	var columns := mini(COLUMNS, count)
	for index: int in count:
		var unit := MarchUnit.new()
		unit.unit_id = _next_unit_id
		_next_unit_id += 1
		unit.order = order
		unit.pending_departure = from_garrison
		unit.departure_sequence = _departure_sequence
		_departure_sequence += 1
		var row: int = index / columns
		var row_count := mini(columns, count - row * columns)
		unit.lane = (float(index % columns) - float(row_count - 1) * 0.5) * column_spacing
		unit.distance = first_distance - float(row) * row_spacing - absf(unit.lane) * 0.11
		unit.position = route[0]
		# Adjacent ranks share a cadence, with a restrained phase offset per file.
		unit.gait = float(row % 2) * 0.35 + float(index % columns) * 0.08
		if unit.distance >= 0.0:
			_depart(unit)
			_update_pose(unit)
		_units.append(unit)
	_ensure_capacity(_units.size())
	_render()

func make_flight_route(from: Vector3, to: Vector3, obstacle_top: float = 0.0) -> PackedVector3Array:
	# Lift above the entire terrain before crossing it. Compact rounded corners
	# keep takeoff/landing smooth even for neighboring buildings or cliff edges.
	# Every horizontal point stays on the direct source-to-target line.
	var horizontal := Vector3(to.x - from.x, 0.0, to.z - from.z)
	assert(horizontal.length_squared() > 0.0001, "Flight needs distinct building exits.")
	var direction := horizontal.normalized()
	var terrain_top := map_definition.terrain.max_height if map_definition.has_elevation() else 0.0
	var cruise := maxf(maxf(terrain_top, obstacle_top), maxf(from.y, to.y)) + FLIGHT_CLEARANCE
	var bend := minf(0.8, horizontal.length() * 0.25)
	var route := PackedVector3Array([from, Vector3(from.x, cruise - bend, from.z)])
	for index: int in range(1, 7):
		var angle := float(index) / 6.0 * PI * 0.5
		var point := from + direction * bend * (1.0 - cos(angle))
		point.y = cruise - bend + sin(angle) * bend
		route.append(point)
	var descent := to - direction * bend
	descent.y = cruise
	route.append(descent)
	for index: int in range(1, 7):
		var angle := float(index) / 6.0 * PI * 0.5
		var point := to - direction * bend * (1.0 - sin(angle))
		point.y = cruise - bend + cos(angle) * bend
		route.append(point)
	route.append(to)
	return route

func _depart(unit: MarchUnit) -> void:
	if not unit.pending_departure:
		return
	unit.pending_departure = false
	departure_queue_changed.emit(unit.order.source_id, unit.order.faction, -1)
	unit_departed.emit(unit.order.source_id, unit.order.faction)

func trim_departures(source_id: int, faction: int, remaining: int) -> void:
	var pending: Array[MarchUnit] = []
	for unit: MarchUnit in _units:
		if unit.pending_departure and unit.order.source_id == source_id and unit.order.faction == faction:
			pending.append(unit)
	var cancelled := pending.size() - maxi(0, remaining)
	if cancelled <= 0:
		return
	# Combat removal swaps array slots. An explicit sequence preserves older orders.
	pending.sort_custom(func(a: MarchUnit, b: MarchUnit): return a.departure_sequence > b.departure_sequence)
	for index: int in cancelled:
		pending[index].alive = false
		pending[index].pending_departure = false
	_units = _units.filter(func(unit: MarchUnit): return unit.alive)
	departure_queue_changed.emit(source_id, faction, -cancelled)

func departure_step_limit() -> float:
	# Production changes only after a real departure creates room in the garrison.
	var limit := INF
	for unit: MarchUnit in _units:
		if unit.pending_departure:
			limit = minf(limit, maxf(0.000001, unit.spawn_delay + maxf(0.0, -unit.distance / base_speed(unit.order.faction))))
	return limit

func queue_tunnel_departure(source_id: int, target_id: int, faction: int, count: int, route: PackedVector3Array, interval: float, dig_duration: float, energy_origin: bool = false) -> void:
	# The digging team prepares the passage while soldiers still defend their home.
	# Each rank enters the completed tunnel as it emerges at the other end.
	if count <= 0:
		return
	var order := _make_order(source_id, target_id, faction, route, 1.0, energy_origin)
	# Retain the complete surface guide even when only its final metres are walked.
	# A recalled tunnel squad can then retrace the safe bridges all the way home.
	order.departure_distance = maxf(0.0, order.length - RULES.BURROW_EXIT_DISTANCE)
	departure_queue_changed.emit(source_id, faction, count)
	for index: int in count:
		var unit := MarchUnit.new()
		unit.unit_id = _next_unit_id
		_next_unit_id += 1
		unit.order = order
		unit.pending_departure = true
		unit.departure_sequence = _departure_sequence
		_departure_sequence += 1
		unit.distance = order.departure_distance
		unit.lane = (float(index % COLUMNS) - 2.5) * COLUMN_SPACING
		unit.gait = float(index % COLUMNS) * 0.08
		unit.spawn_delay = dig_duration + floorf(float(index) / COLUMNS) * interval
		_update_pose(unit)
		_units.append(unit)
	_ensure_capacity(_units.size())
	_render()

func send_tunnel(source_id: int, target_id: int, faction: int, count: int, route: PackedVector3Array, interval: float, energy_origin: bool = false) -> void:
	var order := _make_order(source_id, target_id, faction, route, 1.0, energy_origin)
	order.departure_distance = maxf(0.0, order.length - RULES.BURROW_EXIT_DISTANCE)
	for index: int in count:
		var unit := MarchUnit.new()
		unit.unit_id = _next_unit_id
		_next_unit_id += 1
		unit.order = order
		unit.distance = order.departure_distance
		unit.lane = (float(index % COLUMNS) - 2.5) * COLUMN_SPACING
		unit.gait = float(index % COLUMNS) * 0.08
		unit.spawn_delay = floorf(float(index) / COLUMNS) * interval
		_update_pose(unit)
		_units.append(unit)
	_ensure_capacity(_units.size())
	_render()

func return_order(outbound: MarchOrder) -> MarchOrder:
	assert(not outbound.returning)
	var order := MarchOrder.new()
	order.source_id = outbound.source_id
	order.target_id = outbound.source_id
	order.faction = outbound.faction
	order.strength = outbound.strength
	order.energy_origin = outbound.energy_origin
	order.pig_charge = outbound.pig_charge
	order.airborne = outbound.airborne
	order.dense = outbound.dense
	order.panicked = outbound.panicked
	order.curve = outbound.curve
	order.length = outbound.length
	order.departure_distance = outbound.departure_distance
	order.returning = true
	return order

func transfer_order(original: MarchOrder, faction: int) -> MarchOrder:
	# Changed ownership gets a new snapshot identity; the shared curve and
	# soldiers remain intact. Field interval caches rebuild for the new faction.
	var order := MarchOrder.new()
	order.order_id = _next_order_id
	_next_order_id += 1
	order.source_id = original.source_id
	order.target_id = original.target_id
	order.faction = faction
	order.strength = original.strength
	order.energy_origin = original.energy_origin
	order.pig_charge = original.pig_charge
	order.airborne = original.airborne
	order.dense = original.dense
	order.panicked = original.panicked
	order.curve = original.curve
	order.length = original.length
	order.returning = original.returning
	order.departure_distance = original.departure_distance
	return order

func redirect(unit: MarchUnit, order: MarchOrder) -> void:
	assert(unit.is_exposed())
	assert(order.returning and order.curve == unit.order.curve)
	# Aiming must not consume identities. Register a return order on first use.
	if order.order_id == 0:
		order.order_id = _next_order_id
		_next_order_id += 1
	# Mirror travel, not the squad's world positions. Rank spacing, files and the
	# actual soldier objects (including projectile locks/statuses) stay intact.
	unit.distance = order.length - unit.distance
	unit.lane = -unit.lane
	unit.order = order
	_update_pose(unit)

func return_preview(unit: MarchUnit, order: MarchOrder) -> PackedVector3Array:
	var route := PackedVector3Array([unit.position])
	var start := order.length - unit.distance
	var samples := maxi(1, ceili(unit.distance / 1.0))
	for index: int in range(1, samples + 1):
		var distance := lerpf(start, order.length, float(index) / samples)
		route.append(_formation_position(order, distance, -unit.lane, _route_heading(order, distance)))
	return route

func tick(delta: float, fire_segments: Array[Dictionary] = []) -> void:
	if delta <= 0.0:
		return
	var arrivals: Array[Dictionary] = []
	var index := 0
	while index < _units.size():
		var unit := _units[index]
		var concealed_time := minf(delta, unit.spawn_delay)
		var step := movement_distance(unit, delta)
		if not unit.weakened and _touches_mist(unit, delta, step):
			unit.weakened = true
		# Sample the buff at contact, including an arrival before its expiry within
		# one long frame. Population strength remains independent of combat bonuses.
		var arrival_bonus := projected_attack_bonus(unit) if unit.distance + step >= unit.order.length else 0.0
		unit.levitation_remaining = maxf(0.0, unit.levitation_remaining - delta)
		if unit.levitation_remaining < 0.000001:
			unit.levitation_remaining = 0.0
		unit.rush_remaining = maxf(0.0, unit.rush_remaining - delta)
		if unit.rush_remaining < 0.000001:
			unit.rush_remaining = 0.0
		unit.spawn_delay = maxf(0.0, unit.spawn_delay - delta)
		if unit.spawn_delay < 0.000001:
			unit.spawn_delay = 0.0
		if concealed_time >= delta and unit.spawn_delay > 0.0:
			index += 1
			continue
		var before := unit.position
		var previous_distance := unit.distance
		unit.distance += step
		unit.gait += step * 7.0
		if unit.distance >= 0.0:
			# Debit before exposure, fire contact or arrival, even within a long tick.
			_depart(unit)
			_update_pose(unit)
			# Check the visible part of the movement before arrival is settled.
			# Queued soldiers are protected until they actually emerge from a doorway.
			var concealed_fraction := concealed_time / delta
			var emerged := concealed_fraction + (1.0 - concealed_fraction) * clampf(-previous_distance / maxf(step, 0.000001), 0.0, 1.0)
			var arrived := concealed_fraction + (1.0 - concealed_fraction) * clampf((unit.order.length - previous_distance) / maxf(step, 0.000001), 0.0, 1.0)
			var burned := false
			for fire: Dictionary in fire_segments:
				var contact := _march_fire_contact(unit, before, previous_distance, fire, emerged, arrived)
				if contact >= 0.0:
					var progress := inverse_lerp(emerged, arrived, contact)
					if unit.order.airborne:
						var fire_distance := lerpf(maxf(0.0, previous_distance), minf(unit.order.length, unit.distance), progress)
						unit.position = _formation_position(unit.order, fire_distance, unit.lane, _route_heading(unit.order, fire_distance))
					else:
						unit.position = before.lerp(unit.position, progress)
					if map_definition.has_elevation() and not unit.order.airborne:
						unit.position = map_definition.surface_point(unit.position)
					_defeat(index, (unit.position - fire.center).normalized(), true, int(fire.get("faction", -1)))
					burned = true
					break
			if burned:
				continue
		if unit.distance >= unit.order.length:
			arrivals.append({"order": unit.order, "attack_bonus": arrival_bonus})
			_remove_unit(index)
			continue
		index += 1
	for faction: int in haste_zones.keys():
		haste_zones[faction].remaining -= delta
		if haste_zones[faction].remaining <= 0.000001:
			haste_zones.erase(faction)
	for faction: int in slow_zones.keys():
		slow_zones[faction].remaining -= delta
		if slow_zones[faction].remaining <= 0.000001:
			slow_zones.erase(faction)
	for faction: int in weak_zones.keys():
		weak_zones[faction].remaining -= delta
		if weak_zones[faction].remaining <= 0.000001:
			weak_zones.erase(faction)
	_render()
	# Emitting after iteration lets capture/victory handlers safely clear the march.
	for arrival: Dictionary in arrivals:
		var order: MarchOrder = arrival.order
		unit_arrived.emit(order.target_id, order.faction, order.strength, arrival.attack_bonus, order.energy_origin)

func total_for(faction: int) -> int:
	var total := 0
	for unit: MarchUnit in _units:
		if unit.order.faction == faction:
			total += 1
	return total

func incoming_for(target_id: int, faction: int) -> int:
	var total := 0
	for unit: MarchUnit in _units:
		if unit.order.target_id == target_id and unit.order.faction == faction:
			total += 1
	return total

func team_total_for(faction: int) -> int:
	var total := 0
	for unit: MarchUnit in _units:
		if FACTIONS.allied(unit.order.faction, faction):
			total += 1
	return total

func team_incoming_for(target_id: int, faction: int) -> int:
	var total := 0
	for unit: MarchUnit in _units:
		if unit.order.target_id == target_id and FACTIONS.allied(unit.order.faction, faction):
			total += 1
	return total

func hostile_incoming_for(target_id: int, faction: int) -> int:
	var total := 0
	for unit: MarchUnit in _units:
		if unit.order.target_id == target_id and FACTIONS.hostile(unit.order.faction, faction):
			total += 1
	return total

func estimate_arrival_time(source_id: int, route_length: float, count: int, faction: int = 0) -> float:
	# AI marches use ordinary speed. Include the shared doorway queue and last rank,
	# so an apparently weak residence has time to recruit before the whole wave lands.
	var first_distance := 0.0
	for unit: MarchUnit in _units:
		if unit.order.source_id == source_id:
			first_distance = minf(first_distance, unit.distance)
	if first_distance < 0.0:
		first_distance -= ROW_SPACING
	var last_rank := floorf(float(count - 1) / COLUMNS) * ROW_SPACING
	return (route_length - first_distance + last_rank + COLUMN_SPACING * (COLUMNS - 1) * 0.5 * 0.11) / base_speed(faction)

func get_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: MarchUnit in _units:
		if unit.is_exposed():
			result.append({"position": unit.position, "faction": unit.order.faction,
				"source_id": unit.order.source_id, "target_id": unit.order.target_id,
				"strength": unit.order.strength, "distance": unit.distance, "lane": unit.lane, "rush_remaining": unit.rush_remaining})
	return result

func tower_can_target(unit: MarchUnit) -> bool:
	if not unit.is_exposed() or unit.cloaked or unit.levitation_remaining > 0.0:
		return false
	# Fog hides every faction from cannon sight; weakness only affects its enemies.
	for zone: Dictionary in weak_zones.values():
		if _inside_mist(unit.position, zone):
			return false
	return true

func acquire_targets(center: Vector3, attacking_faction: int, radius: float, count: int, farthest: bool = false, tower_shot: bool = false) -> Array[MarchUnit]:
	var targets: Array[MarchUnit] = []
	var radius_squared := radius * radius
	for target_index: int in count:
		var nearest := -1
		var nearest_distance := -1.0 if farthest else radius_squared
		for index: int in _units.size():
			var unit := _units[index]
			if FACTIONS.allied(unit.order.faction, attacking_faction) or not unit.is_exposed() or unit.reserved:
				continue
			if tower_shot and not tower_can_target(unit):
				continue
			var distance_squared := Vector2(unit.position.x - center.x, unit.position.z - center.z).length_squared()
			if distance_squared <= radius_squared and ((farthest and distance_squared > nearest_distance) or (not farthest and distance_squared <= nearest_distance)):
				nearest_distance = distance_squared
				nearest = index
		if nearest < 0:
			break
		_units[nearest].reserved = true
		_units[nearest].intercepted_by = attacking_faction
		targets.append(_units[nearest])
	return targets

func has_marchers() -> bool:
	return not _units.is_empty()

func hit_target(unit: MarchUnit, impulse: Vector3, tower_shot: bool = false) -> bool:
	if not unit.alive:
		return false
	if FACTIONS.allied(unit.order.faction, unit.intercepted_by):
		# Recruitment can change allegiance while an already fired shot is flying.
		unit.reserved = false
		unit.intercepted_by = -1
		return false
	if tower_shot and not tower_can_target(unit):
		unit.reserved = false
		unit.intercepted_by = -1
		return false
	_defeat(_units.find(unit), impulse, false, unit.intercepted_by)
	_render()
	return true

func ignite_at(center: Vector3, radius: float, faction: int = -1) -> void:
	# Resolve the ignition core on release, using the same contact rule as expansion.
	var core := {"center": center, "from_radius": radius, "to_radius": radius, "active_fraction": 1.0}
	for index: int in range(_units.size() - 1, -1, -1):
		var unit := _units[index]
		if unit.is_exposed() and (not unit.order.airborne or _near_ground(unit.position)) and fire_contact(unit.position, unit.position, core) >= 0.0:
			_defeat(index, (unit.position - center).normalized(), true, faction)
	_render()

func _near_ground(at: Vector3) -> bool:
	return at.y - map_definition.surface_height(Vector2(at.x, at.z)) <= GROUND_FIRE_HEIGHT

func _march_fire_contact(unit: MarchUnit, before: Vector3, previous_distance: float, fire: Dictionary, emerged: float, arrived: float) -> float:
	if not unit.order.airborne:
		return fire_contact(before, unit.position, fire, emerged, arrived)
	# Clip the moving fire test to the actual takeoff/landing segments touching
	# the ground. A long tick can cross an entire flight without burning its cruise.
	var start := maxf(0.0, previous_distance)
	var end := minf(unit.order.length, unit.distance)
	if end <= start:
		return fire_contact(before, unit.position, fire, emerged, arrived) if _near_ground(unit.position) else -1.0
	if not unit.order.ground_fire_intervals.has(unit.lane):
		unit.order.ground_fire_intervals[unit.lane] = _ground_fire_spans(unit.order, unit.lane)
	for span: Vector2 in unit.order.ground_fire_intervals[unit.lane]:
		var low := maxf(start, span.x)
		var high := minf(end, span.y)
		if high <= low:
			continue
		var from := _formation_position(unit.order, low, unit.lane, _route_heading(unit.order, low))
		var to := _formation_position(unit.order, high, unit.lane, _route_heading(unit.order, high))
		var first := lerpf(emerged, arrived, inverse_lerp(start, end, low))
		var last := lerpf(emerged, arrived, inverse_lerp(start, end, high))
		var contact := fire_contact(from, to, fire, first, last)
		if contact >= 0.0:
			return contact
	return -1.0

func _ground_fire_spans(order: MarchOrder, lane: float) -> PackedVector2Array:
	var spans := PackedVector2Array()
	var count := maxi(1, ceili(order.length / 0.12))
	var from := _formation_position(order, 0.0, lane, _route_heading(order, 0.0))
	var previous_clearance := from.y - map_definition.surface_height(Vector2(from.x, from.z)) - GROUND_FIRE_HEIGHT
	var opened := 0.0 if previous_clearance <= 0.0 else -1.0
	for index: int in range(1, count + 1):
		var low := order.length * float(index - 1) / count
		var high := order.length * float(index) / count
		var at := _formation_position(order, high, lane, _route_heading(order, high))
		var clearance := at.y - map_definition.surface_height(Vector2(at.x, at.z)) - GROUND_FIRE_HEIGHT
		if (clearance <= 0.0) != (previous_clearance <= 0.0):
			var crossing := lerpf(low, high, previous_clearance / (previous_clearance - clearance))
			if clearance <= 0.0:
				opened = crossing
			else:
				spans.append(Vector2(opened, crossing))
				opened = -1.0
		previous_clearance = clearance
	if opened >= 0.0:
		spans.append(Vector2(opened, order.length))
	return spans

func _defeat(index: int, impulse: Vector3, burning: bool, killer_faction: int = -1) -> void:
	var unit := _units[index]
	unit_defeated.emit(unit.position, unit.heading, unit.order.faction, impulse, burning)
	combat_death.emit(unit.order.faction, unit.order.target_id, killer_faction)
	_remove_unit(index)

static func fire_contact(from: Vector3, to: Vector3, fire: Dictionary, emerged: float = 0.0, arrived: float = 1.0) -> float:
	# Solve moving point versus expanding circle continuously within this step.
	# This catches fast crossings and never burns a unit that outruns the front.
	var end_time := minf(fire.active_fraction, arrived)
	if emerged >= end_time:
		return -1.0
	var v := Vector2(to.x - from.x, to.z - from.z) / (arrived - emerged)
	var p := Vector2(from.x - fire.center.x, from.z - fire.center.z) - v * emerged
	var radius: float = fire.from_radius + 0.18
	var growth: float = fire.to_radius - fire.from_radius
	var a := v.dot(v) - growth * growth
	var b := 2.0 * (p.dot(v) - radius * growth)
	var c := p.dot(p) - radius * radius
	if (a * emerged + b) * emerged + c <= 0.0:
		return emerged
	if absf(a) < 0.000001:
		if b >= 0.0:
			return -1.0
		var crossing := -c / b
		return crossing if crossing >= emerged and crossing <= end_time else -1.0
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var first := (-b - sqrt(discriminant)) / (2.0 * a)
	var second := (-b + sqrt(discriminant)) / (2.0 * a)
	var contact := minf(first, second)
	if contact < emerged:
		contact = maxf(first, second)
	return contact if contact >= emerged and contact <= end_time else -1.0

func create_haste_zone(faction: int, at: Vector3, radius: float, duration: float, multiplier: float, style: StringName = &"squirrel") -> void:
	haste_zones[faction] = {"at": at, "radius": radius, "remaining": duration, "duration": duration, "multiplier": multiplier, "style": style}
	for unit: MarchUnit in _units:
		if unit.order.faction == faction:
			unit.order.haste_intervals.clear()

func rush_targets(faction: int, at: Vector3, radius: float) -> Array[MarchUnit]:
	var targets: Array[MarchUnit] = []
	if not at.is_finite():
		return targets
	for unit: MarchUnit in _units:
		var offset := Vector2(unit.position.x - at.x, unit.position.z - at.z)
		if unit.order.faction == faction and unit.is_exposed() and offset.length_squared() <= radius * radius:
			targets.append(unit)
	return targets

func apply_rush(faction: int, at: Vector3, radius: float, duration: float) -> int:
	var targets := rush_targets(faction, at, radius)
	for unit: MarchUnit in targets:
		unit.rush_remaining = maxf(unit.rush_remaining, duration)
	_render()
	return targets.size()

func create_slow_zone(faction: int, at: Vector3, radius: float, duration: float) -> void:
	slow_zones[faction] = {"at": at, "radius": radius, "remaining": duration, "duration": duration}
	for unit: MarchUnit in _units:
		unit.order.slow_intervals.clear()
	_render()

func projected_attack_bonus(unit: MarchUnit) -> float:
	var bonus := RULES.PIG_CHARGE_ATTACK_BONUS if unit.order.pig_charge else 0.0
	if unit.rush_remaining > 0.0 and unit.distance + movement_distance(unit, unit.rush_remaining) > unit.order.length + 0.000001:
		bonus += RULES.RABBIT_RUSH_ATTACK_BONUS
	if unit.weakened or _touches_mist(unit, INF):
		bonus -= RULES.FROG_WEAKNESS
	return bonus

func _inside_mist(at: Vector3, zone: Dictionary) -> bool:
	return zone.remaining > 0.0 and Vector2(at.x - zone.at.x, at.z - zone.at.z).length_squared() <= zone.radius * zone.radius

func _touches_mist(unit: MarchUnit, seconds: float, max_step: float = INF) -> bool:
	# Sample the travelled files, including crossing a whole cloud within one tick.
	# Cache per shared route/lane, and clip travel to each cloud's actual expiry.
	for faction: int in weak_zones:
		var zone := weak_zones[faction]
		if not FACTIONS.hostile(faction, unit.order.faction):
			continue
		if unit.is_exposed() and _inside_mist(unit.position, zone):
			return true
		var active := minf(seconds, zone.remaining)
		if active <= unit.spawn_delay:
			continue
		var end := minf(unit.order.length, unit.distance + minf(max_step, movement_distance(unit, active)))
		var start := maxf(0.0, unit.distance)
		if end <= start:
			continue
		var key := Vector2(faction, unit.lane)
		if not unit.order.mist_intervals.has(key):
			unit.order.mist_intervals[key] = _zone_intervals(unit.order, unit.lane, zone)
		for span: Vector2 in unit.order.mist_intervals[key]:
			if end > span.x + 0.000001 and start < span.y:
				return true
	return false

func frog_targets(index: int, faction: int, at: Vector3) -> Array[MarchUnit]:
	var targets: Array[MarchUnit] = []
	for unit: MarchUnit in _units:
		if not unit.is_exposed() or Vector2(unit.position.x - at.x, unit.position.z - at.z).length_squared() > pow(RULES.FROG_RADII[index], 2):
			continue
		if index == 0 and FACTIONS.hostile(faction, unit.order.faction):
			targets.append(unit)
		elif index == 1 and unit.levitation_remaining <= 0.0:
			targets.append(unit)
		elif index == 2 and unit.order.faction == faction and not unit.cloaked:
			targets.append(unit)
	return targets

func apply_frog_field(index: int, faction: int, at: Vector3) -> int:
	if index == 0:
		weak_zones[faction] = {"at": at, "radius": RULES.FROG_RADII[0], "remaining": RULES.FROG_DURATIONS[0]}
		for unit: MarchUnit in _units:
			unit.order.mist_intervals.clear()
		for unit: MarchUnit in frog_targets(0, faction, at):
			unit.weakened = true
		return 1
	var targets := frog_targets(index, faction, at)
	for unit: MarchUnit in targets:
		if index == 1:
			unit.levitation_remaining = RULES.FROG_DURATIONS[1]
		else:
			unit.cloaked = true
	_render()
	return targets.size()

func speed_multiplier(unit: MarchUnit) -> float:
	if unit.levitation_remaining > 0.0:
		return 0.0
	if not unit.is_exposed():
		return environment_speed[unit.order.faction]
	var multiplier := RULES.RABBIT_RUSH_MULTIPLIER if unit.rush_remaining > 0.0 else 1.0
	if unit.order.pig_charge:
		multiplier += RULES.PIG_CHARGE_SPEED_BONUS
	if haste_zones.has(unit.order.faction):
		var zone := haste_zones[unit.order.faction]
		var offset := Vector2(unit.position.x - zone.at.x, unit.position.z - zone.at.z)
		if zone.remaining > 0.0 and offset.length_squared() <= zone.radius * zone.radius:
			multiplier += zone.multiplier - 1.0
	for faction: int in slow_zones:
		var zone := slow_zones[faction]
		if zone.remaining > 0.0 and FACTIONS.hostile(faction, unit.order.faction) and Vector2(unit.position.x - zone.at.x, unit.position.z - zone.at.z).length_squared() <= zone.radius * zone.radius:
			return environment_speed[unit.order.faction] * (multiplier + RULES.BEAR_SLOW_MULTIPLIER - 1.0)
	return environment_speed[unit.order.faction] * multiplier

func movement_distance(unit: MarchUnit, delta: float) -> float:
	# Timed boosts and fields continue aging while a soldier is held in the air.
	var concealed_time := minf(delta, maxf(unit.spawn_delay, unit.levitation_remaining))
	delta -= concealed_time
	# A newer enchanted order must not overtake a previous queue while its
	# population still belongs to the building. Split the exact exit time first.
	var queued_time := minf(delta, maxf(0.0, -unit.distance / base_speed(unit.order.faction)))
	var queued_step := queued_time * base_speed(unit.order.faction)
	delta -= queued_time
	concealed_time += queued_time
	if delta <= 0.0:
		return queued_step
	var charge := RULES.PIG_CHARGE_SPEED_BONUS if unit.order.pig_charge else 0.0
	var rushing := minf(delta, maxf(0.0, unit.rush_remaining - concealed_time))
	# The ordinary case has no spatial crossings. Integrate the boost's expiry
	# directly, avoiding two field-segment walks for every soldier each tick.
	if slow_zones.is_empty() and not haste_zones.has(unit.order.faction):
		return queued_step + base_speed(unit.order.faction) * (delta * (1.0 + charge) + rushing * (RULES.RABBIT_RUSH_MULTIPLIER - 1.0))
	var zone_time := 0.0
	if haste_zones.has(unit.order.faction):
		zone_time = maxf(0.0, haste_zones[unit.order.faction].remaining - concealed_time)
	var start := unit.distance + queued_step
	var step := _movement_segment(unit, start, rushing, RULES.RABBIT_RUSH_MULTIPLIER + charge, zone_time, concealed_time)
	return queued_step + step + _movement_segment(unit, start + step, delta - rushing, 1.0 + charge, maxf(0.0, zone_time - rushing), concealed_time + rushing)

func _movement_segment(unit: MarchUnit, from_distance: float, delta: float, multiplier: float, zone_time: float, time_offset: float = 0.0) -> float:
	if delta == 0.0:
		return 0.0
	if not slow_zones.is_empty():
		return _movement_with_fields(unit, from_distance, delta, multiplier, zone_time, time_offset)
	# Different skill sources add their percentages within the skill group.
	# Split both independent expiry times, then integrate route entry/exit exactly.
	var speed := base_speed(unit.order.faction) * multiplier
	if delta <= 0.0 or zone_time <= 0.0:
		return speed * delta
	var zone := haste_zones[unit.order.faction]
	var active := minf(delta, zone_time)
	var remaining := active
	var distance := from_distance
	if not unit.order.haste_intervals.has(unit.lane):
		unit.order.haste_intervals[unit.lane] = _zone_intervals(unit.order, unit.lane, zone)
	for interval: Vector2 in unit.order.haste_intervals[unit.lane]:
		if interval.y <= distance:
			continue
		var before_time := maxf(0.0, interval.x - distance) / speed
		var before_step := minf(remaining, before_time)
		distance += before_step * speed
		remaining -= before_step
		if remaining <= 0.0:
			break
		var inside_speed: float = base_speed(unit.order.faction) * (multiplier + zone.multiplier - 1.0)
		var inside_time: float = (interval.y - distance) / inside_speed
		var inside_step := minf(remaining, inside_time)
		distance += inside_step * inside_speed
		remaining -= inside_step
		if remaining <= 0.0:
			break
	return distance - from_distance + speed * (remaining + delta - active)

func _movement_with_fields(unit: MarchUnit, from_distance: float, delta: float, multiplier: float, zone_time: float, time_offset: float) -> float:
	# Integrate actual route crossings and expiries. Stacking slows use the same
	# 60% reduction once; haste and rush each contribute their additive bonus.
	var fields: Array[Dictionary] = []
	if zone_time > 0.0:
		var haste := haste_zones[unit.order.faction]
		if not unit.order.haste_intervals.has(unit.lane):
			unit.order.haste_intervals[unit.lane] = _zone_intervals(unit.order, unit.lane, haste)
		fields.append({"spans": unit.order.haste_intervals[unit.lane], "until": zone_time, "speed": haste.multiplier})
	for faction: int in slow_zones:
		var slow := slow_zones[faction]
		if not FACTIONS.hostile(faction, unit.order.faction) or slow.remaining <= time_offset:
			continue
		var key := Vector2(faction, unit.lane)
		if not unit.order.slow_intervals.has(key):
			unit.order.slow_intervals[key] = _zone_intervals(unit.order, unit.lane, slow)
		fields.append({"spans": unit.order.slow_intervals[key], "until": slow.remaining - time_offset, "speed": RULES.BEAR_SLOW_MULTIPLIER})
	var distance := from_distance
	var elapsed := 0.0
	while delta - elapsed > 0.0000001:
		var next_distance := INF
		var next_time := delta - elapsed
		var boost := 1.0
		var slowest := 1.0
		for field: Dictionary in fields:
			if field.until - elapsed <= 0.0000001:
				continue
			next_time = minf(next_time, field.until - elapsed)
			for span: Vector2 in field.spans:
				if span.y <= distance + 0.0000001:
					continue
				if span.x > distance + 0.0000001:
					next_distance = minf(next_distance, span.x)
				else:
					next_distance = minf(next_distance, span.y)
					boost = maxf(boost, field.speed)
					slowest = minf(slowest, field.speed)
				break
		var speed := base_speed(unit.order.faction) * (multiplier + boost + slowest - 2.0)
		var step := minf(next_time, (next_distance - distance) / speed)
		distance += step * speed
		elapsed += step
	return distance - from_distance

func _zone_intervals(order: MarchOrder, lane: float, zone: Dictionary) -> PackedVector2Array:
	var intervals := PackedVector2Array()
	var center := Vector2(zone.at.x, zone.at.z)
	var count := ceili(order.length / 0.24)
	var from := order.sample(0.0)
	for index: int in count:
		var low := order.length * float(index) / count
		var high := order.length * float(index + 1) / count
		var to := _formation_position(order, high, lane, _route_heading(order, high))
		var a := Vector2(from.x, from.z)
		var b := Vector2(to.x, to.z)
		var start := 0.0 if a.distance_to(center) <= zone.radius else Geometry2D.segment_intersects_circle(a, b, center, zone.radius)
		if start >= 0.0:
			var end := 1.0 if b.distance_to(center) <= zone.radius else 1.0 - Geometry2D.segment_intersects_circle(b, a, center, zone.radius)
			var span := Vector2(lerpf(low, high, start), lerpf(low, high, end))
			if span.y > span.x:
				if not intervals.is_empty() and absf(intervals[-1].y - span.x) < 0.00001:
					intervals[-1] = Vector2(intervals[-1].x, span.y)
				else:
					intervals.append(span)
		from = to
	return intervals

func clear() -> void:
	var cancelled: Dictionary[Vector2i, int] = {}
	for unit: MarchUnit in _units:
		if unit.pending_departure:
			var source := Vector2i(unit.order.source_id, unit.order.faction)
			cancelled[source] = cancelled.get(source, 0) + 1
			unit.pending_departure = false
		unit.alive = false
	_units.clear()
	for source: Vector2i in cancelled:
		departure_queue_changed.emit(source.x, source.y, -cancelled[source])
	_departure_sequence = 0
	haste_zones.clear()
	slow_zones.clear()
	weak_zones.clear()
	_multimesh.visible_instance_count = 0
	_cloaked_mesh.visible_instance_count = 0
	_panic_mesh.visible_instance_count = 0

func snapshot_incoming() -> Dictionary[Vector2i, int]:
	var incoming: Dictionary[Vector2i, int] = {}
	for unit: MarchUnit in _units:
		var key := Vector2i(unit.order.target_id, unit.order.faction)
		incoming[key] = incoming.get(key, 0) + 1
	return incoming

func _remove_unit(index: int) -> void:
	_units[index].alive = false
	var last := _units.size() - 1
	if index != last:
		_units[index] = _units[last]
	_units.pop_back()

func _ensure_capacity(required: int) -> void:
	if required <= _multimesh.instance_count:
		return
	# Allocation is exceptional; the initial 4096-slot resource covers normal play.
	# Grow rather than cap: every entry represents a paid soldier or a reservation.
	var capacity := maxi(4096, _multimesh.instance_count)
	while capacity < required:
		capacity *= 2
	_multimesh.instance_count = capacity
	_cloaked_mesh.instance_count = capacity
	_panic_mesh.instance_count = capacity

func _update_pose(unit: MarchUnit) -> void:
	var order := unit.order
	var distance := unit.distance
	unit.heading = _route_heading(order, distance)
	unit.position = _formation_position(order, distance, unit.lane, unit.heading)
	if unit.levitation_remaining > 0.0:
		var age := RULES.FROG_DURATIONS[1] - unit.levitation_remaining
		var lift := smoothstep(0.0, 0.12, age) * smoothstep(0.0, 0.16, unit.levitation_remaining)
		unit.position.y += (1.65 + sin(age * 3.0) * 0.035) * lift

func _route_heading(order: MarchOrder, distance: float) -> Vector3:
	var before := order.sample(maxf(0.0, distance - 0.3))
	var after := order.sample(minf(order.length, distance + 0.3))
	var heading := after - before
	heading.y = 0.0
	if order.airborne and heading.length_squared() < 0.000001:
		# Vertical takeoff/landing still faces the intended horizontal destination.
		heading = order.sample(order.length) - order.sample(0.0)
		heading.y = 0.0
	return heading.normalized()

func _formation_position(order: MarchOrder, distance: float, lane: float, heading: Vector3) -> Vector3:
	var center := order.sample(distance)
	var sideways := Vector3(-heading.z, 0.0, heading.x)
	var forward_distance := order.length - distance if order.returning else distance
	var gate_distance := minf(forward_distance, order.length - forward_distance)
	gate_distance = minf(gate_distance, absf(forward_distance - order.departure_distance))
	var gate_width := smoothstep(0.0, GATE_LENGTH, gate_distance)
	# Measure the upcoming bend over a fixed distance, independent of the number
	# of sampled guide points. Broad curves stay wide; tight turns gather the files.
	var approach := center - order.sample(maxf(0.0, distance - 1.2))
	var departure := order.sample(minf(order.length, distance + 1.2)) - center
	approach.y = 0.0
	departure.y = 0.0
	var turn := approach.angle_to(departure) if approach.length_squared() > 0.0001 and departure.length_squared() > 0.0001 else 0.0
	var corner_width := lerpf(1.0, 0.63, smoothstep(0.12, 0.85, turn))
	var point := center + sideways * lane * gate_width * corner_width
	return point if order.airborne or not map_definition.has_elevation() else map_definition.surface_point(point)

func _presentation_position(unit: MarchUnit) -> Vector3:
	var at := unit.position + unit.presentation_offset
	if map_definition.has_elevation() and not unit.order.airborne and unit.presentation_offset != Vector3.ZERO:
		# Network correction may slide a body across a ramp or terrace edge.
		# Preserve spell levitation, but never interpolate terrain height in air.
		# Without a correction, the existing pose already has the surface/lift.
		var lift := unit.position.y - map_definition.surface_height(Vector2(unit.position.x, unit.position.z))
		at = map_definition.surface_point(at) + Vector3.UP * lift
	return at + Vector3(0, 0.035, 0)

func begin_render_batch() -> void:
	# Synchronous scopes only: always pair the outermost end before returning
	# or awaiting. Rules/signals still run immediately; only mesh writes wait.
	_render_batch_depth += 1

func end_render_batch() -> void:
	assert(_render_batch_depth > 0, "Unpaired march render batch.")
	_render_batch_depth -= 1
	if _render_batch_depth == 0 and _render_pending:
		_render()

func _render() -> void:
	if _render_batch_depth > 0:
		_render_pending = true
		return
	_render_pending = false
	var slot := 0
	var cloaked_slot := 0
	var panic_slot := 0
	for unit: MarchUnit in _units:
		if not unit.is_exposed():
			continue
		var yaw := atan2(-unit.heading.x, -unit.heading.z)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * MODEL_SCALE)
		var mesh := _cloaked_mesh if unit.cloaked else _multimesh
		var index := cloaked_slot if unit.cloaked else slot
		mesh.set_instance_transform(index, Transform3D(basis, _presentation_position(unit)))
		var color := FACTION_COLORS[unit.order.faction].srgb_to_linear()
		var gait := unit.gait + unit.presentation_gait_offset
		color.a = -(gait + 1.0) if unit.rush_remaining > 0.0 else gait
		mesh.set_instance_custom_data(index, color)
		if unit.order.panicked and not unit.cloaked:
			# Share the body's interpolated position and simulation-driven gait:
			# marks follow network corrections and freeze with the fleeing soldier.
			_panic_mesh.set_instance_transform(panic_slot, Transform3D(Basis.IDENTITY, _presentation_position(unit) + Vector3.UP * 1.85))
			_panic_mesh.set_instance_custom_data(panic_slot, Color(0, 0, 0, gait))
			panic_slot += 1
		if unit.cloaked:
			cloaked_slot += 1
		else:
			slot += 1
	_multimesh.visible_instance_count = slot
	_cloaked_mesh.visible_instance_count = cloaked_slot
	_panic_mesh.visible_instance_count = panic_slot
