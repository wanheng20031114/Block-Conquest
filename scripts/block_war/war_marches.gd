class_name WarMarches
extends Node3D
## Every entry is one population point. Marchers never collide or fight in transit.
## The controller calls tick from _process; stopping tick also stops the GPU gait.

signal unit_arrived(target_id: int, faction: int, strength: float)
signal unit_defeated(at: Vector3, heading: Vector3, faction: int, impulse: Vector3, burning: bool)

const COLUMNS := 6
const COLUMN_SPACING := 0.56
const ROW_SPACING := 0.90
const SPEED := 3.1
const MODEL_SCALE := 0.62
const GATE_LENGTH := 2.4
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
const FACTION_COLORS: Array[Color] = FACTIONS.COLORS

class MarchOrder extends RefCounted:
	var source_id: int
	var target_id: int
	var faction: int
	var strength: float
	var curve: Curve3D
	var length: float
	var haste_intervals: Dictionary[float, PackedVector2Array] = {}

class MarchUnit extends RefCounted:
	var alive := true
	var reserved := false
	var order: MarchOrder
	var distance: float
	var lane: float
	var position: Vector3
	var heading: Vector3 = Vector3.FORWARD
	var gait: float
	var spawn_delay := 0.0

	func is_exposed() -> bool:
		return alive and distance >= 0.0 and spawn_delay <= 0.0

@onready var _multimesh: MultiMesh = $Militia.multimesh
var _units: Array[MarchUnit] = []
var haste_zones: Dictionary[int, Dictionary] = {}

func _ready() -> void:
	_multimesh.instance_count = 4096
	_multimesh.visible_instance_count = 0

func _make_order(source_id: int, target_id: int, faction: int, route: PackedVector3Array, strength: float = 1.0) -> MarchOrder:
	assert(route.size() >= 2, "A march needs a source and destination in its route.")
	assert(faction >= 0 and faction < FACTION_COLORS.size(), "Unknown marching faction.")
	var order := MarchOrder.new()
	order.source_id = source_id
	order.target_id = target_id
	order.faction = faction
	order.strength = strength
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

func send(source_id: int, target_id: int, faction: int, count: int, route: PackedVector3Array, strength: float = 1.0) -> void:
	if count <= 0:
		return
	var order := _make_order(source_id, target_id, faction, route, strength)
	# All exits of a building share one queue, including orders heading to different sides.
	var first_distance := 0.0
	for existing: MarchUnit in _units:
		if existing.order.source_id == source_id and existing.distance < first_distance:
			first_distance = existing.distance
	if first_distance < 0.0:
		first_distance -= ROW_SPACING
	var columns := mini(COLUMNS, count)
	for index: int in count:
		var unit := MarchUnit.new()
		unit.order = order
		var row: int = index / columns
		var row_count := mini(columns, count - row * columns)
		unit.lane = (float(index % columns) - float(row_count - 1) * 0.5) * COLUMN_SPACING
		unit.distance = first_distance - float(row) * ROW_SPACING - absf(unit.lane) * 0.11
		unit.position = route[0]
		# Adjacent ranks share a cadence, with a restrained phase offset per file.
		unit.gait = float(row % 2) * 0.35 + float(index % columns) * 0.08
		if unit.distance >= 0.0:
			_update_pose(unit)
		_units.append(unit)
	_ensure_capacity(_units.size())
	_render()

func send_tunnel(source_id: int, target_id: int, faction: int, count: int, route: PackedVector3Array, interval: float) -> void:
	var order := _make_order(source_id, target_id, faction, route)
	for index: int in count:
		var unit := MarchUnit.new()
		unit.order = order
		unit.distance = 0.0
		unit.lane = (float(index % COLUMNS) - 2.5) * COLUMN_SPACING
		unit.gait = float(index % COLUMNS) * 0.08
		unit.spawn_delay = floorf(float(index) / COLUMNS) * interval
		_update_pose(unit)
		_units.append(unit)
	_ensure_capacity(_units.size())
	_render()

func redirect(unit: MarchUnit, target_id: int, route: PackedVector3Array) -> void:
	assert(unit.is_exposed())
	# Keep the same soldier object: in-flight cannonballs retain their real target.
	unit.order = _make_order(unit.order.source_id, target_id, unit.order.faction, route, unit.order.strength)
	unit.distance = 0.0
	unit.lane = 0.0
	_update_pose(unit)

func tick(delta: float, fire_segments: Array[Dictionary] = []) -> void:
	if delta <= 0.0:
		return
	var arrivals: Array[MarchOrder] = []
	var index := 0
	while index < _units.size():
		var unit := _units[index]
		var concealed_time := minf(delta, unit.spawn_delay)
		var step := movement_distance(unit, delta)
		unit.spawn_delay = maxf(0.0, unit.spawn_delay - delta)
		if concealed_time >= delta:
			index += 1
			continue
		var before := unit.position
		var previous_distance := unit.distance
		unit.distance += step
		unit.gait += step * 7.0
		if unit.distance >= 0.0:
			_update_pose(unit)
			# Check the visible part of the movement before arrival is settled.
			# Queued soldiers are protected until they actually emerge from a doorway.
			var concealed_fraction := concealed_time / delta
			var emerged := concealed_fraction + (1.0 - concealed_fraction) * clampf(-previous_distance / step, 0.0, 1.0)
			var arrived := concealed_fraction + (1.0 - concealed_fraction) * clampf((unit.order.length - previous_distance) / step, 0.0, 1.0)
			var burned := false
			for fire: Dictionary in fire_segments:
				var contact := fire_contact(before, unit.position, fire, emerged, arrived)
				if contact >= 0.0:
					unit.position = before.lerp(unit.position, inverse_lerp(emerged, arrived, contact))
					_defeat(index, (unit.position - fire.center).normalized(), true)
					burned = true
					break
			if burned:
				continue
		if unit.distance >= unit.order.length:
			arrivals.append(unit.order)
			_remove_unit(index)
			continue
		index += 1
	for faction: int in haste_zones.keys():
		haste_zones[faction].remaining -= delta
		if haste_zones[faction].remaining <= 0.000001:
			haste_zones.erase(faction)
	_render()
	# Emitting after iteration lets capture/victory handlers safely clear the march.
	for order: MarchOrder in arrivals:
		unit_arrived.emit(order.target_id, order.faction, order.strength)

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

func estimate_arrival_time(source_id: int, route_length: float, count: int) -> float:
	# AI marches use ordinary speed. Include the shared doorway queue and last rank,
	# so an apparently weak residence has time to recruit before the whole wave lands.
	var first_distance := 0.0
	for unit: MarchUnit in _units:
		if unit.order.source_id == source_id:
			first_distance = minf(first_distance, unit.distance)
	if first_distance < 0.0:
		first_distance -= ROW_SPACING
	var last_rank := floorf(float(count - 1) / COLUMNS) * ROW_SPACING
	return (route_length - first_distance + last_rank + COLUMN_SPACING * (COLUMNS - 1) * 0.5 * 0.11) / SPEED

func get_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: MarchUnit in _units:
		if unit.is_exposed():
			result.append({"position": unit.position, "faction": unit.order.faction,
				"source_id": unit.order.source_id, "target_id": unit.order.target_id,
				"strength": unit.order.strength, "distance": unit.distance, "lane": unit.lane})
	return result

func acquire_targets(center: Vector3, attacking_faction: int, radius: float, count: int) -> Array[MarchUnit]:
	var targets: Array[MarchUnit] = []
	var radius_squared := radius * radius
	for target_index: int in count:
		var nearest := -1
		var nearest_distance := radius_squared
		for index: int in _units.size():
			var unit := _units[index]
			if FACTIONS.allied(unit.order.faction, attacking_faction) or not unit.is_exposed() or unit.reserved:
				continue
			var distance_squared := unit.position.distance_squared_to(center)
			if distance_squared <= nearest_distance:
				nearest_distance = distance_squared
				nearest = index
		if nearest < 0:
			break
		_units[nearest].reserved = true
		targets.append(_units[nearest])
	return targets

func has_marchers() -> bool:
	return not _units.is_empty()

func hit_target(unit: MarchUnit, impulse: Vector3) -> bool:
	if not unit.alive:
		return false
	_defeat(_units.find(unit), impulse, false)
	_render()
	return true

func ignite_at(center: Vector3, radius: float) -> void:
	# Resolve the ignition core on release, using the same contact rule as expansion.
	var core := {"center": center, "from_radius": radius, "to_radius": radius, "active_fraction": 1.0}
	for index: int in range(_units.size() - 1, -1, -1):
		var unit := _units[index]
		if unit.is_exposed() and fire_contact(unit.position, unit.position, core) >= 0.0:
			_defeat(index, (unit.position - center).normalized(), true)
	_render()

func _defeat(index: int, impulse: Vector3, burning: bool) -> void:
	var unit := _units[index]
	unit_defeated.emit(unit.position, unit.heading, unit.order.faction, impulse, burning)
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

func speed_multiplier(unit: MarchUnit) -> float:
	if not unit.is_exposed() or not haste_zones.has(unit.order.faction):
		return 1.0
	var zone := haste_zones[unit.order.faction]
	var offset := Vector2(unit.position.x - zone.at.x, unit.position.z - zone.at.z)
	return zone.multiplier if offset.length_squared() <= zone.radius * zone.radius else 1.0

func movement_distance(unit: MarchUnit, delta: float) -> float:
	var concealed_time := minf(delta, unit.spawn_delay)
	delta -= concealed_time
	if not haste_zones.has(unit.order.faction):
		return SPEED * delta
	var zone := haste_zones[unit.order.faction]
	var active: float = minf(delta, maxf(0.0, zone.remaining - concealed_time))
	var remaining := active
	var distance := unit.distance
	if not unit.order.haste_intervals.has(unit.lane):
		unit.order.haste_intervals[unit.lane] = _zone_intervals(unit.order, unit.lane, zone)
	# Integrate the time spent inside each route interval, including entering,
	# leaving, re-entering, doorway queues and expiry within a single long tick.
	for interval: Vector2 in unit.order.haste_intervals[unit.lane]:
		if interval.y <= distance:
			continue
		var before_time := maxf(0.0, interval.x - distance) / SPEED
		var before_step := minf(remaining, before_time)
		distance += before_step * SPEED
		remaining -= before_step
		if remaining <= 0.0:
			break
		var inside_time: float = (interval.y - distance) / (SPEED * zone.multiplier)
		var inside_step := minf(remaining, inside_time)
		distance += inside_step * SPEED * float(zone.multiplier)
		remaining -= inside_step
		if remaining <= 0.0:
			break
	return distance - unit.distance + SPEED * (remaining + delta - active)

func _zone_intervals(order: MarchOrder, lane: float, zone: Dictionary) -> PackedVector2Array:
	var intervals := PackedVector2Array()
	var center := Vector2(zone.at.x, zone.at.z)
	var count := ceili(order.length / 0.24)
	var from := order.curve.sample_baked(0.0)
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
	for unit: MarchUnit in _units:
		unit.alive = false
	_units.clear()
	haste_zones.clear()
	_multimesh.visible_instance_count = 0

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
	# Grow rather than cap: dispatch has already deducted every soldier at its source.
	var capacity := maxi(4096, _multimesh.instance_count)
	while capacity < required:
		capacity *= 2
	_multimesh.instance_count = capacity

func _update_pose(unit: MarchUnit) -> void:
	var order := unit.order
	var distance := unit.distance
	unit.heading = _route_heading(order, distance)
	unit.position = _formation_position(order, distance, unit.lane, unit.heading)

func _route_heading(order: MarchOrder, distance: float) -> Vector3:
	var before := order.curve.sample_baked(maxf(0.0, distance - 0.3))
	var after := order.curve.sample_baked(minf(order.length, distance + 0.3))
	var heading := after - before
	heading.y = 0.0
	return heading.normalized()

func _formation_position(order: MarchOrder, distance: float, lane: float, heading: Vector3) -> Vector3:
	var center := order.curve.sample_baked(distance)
	var sideways := Vector3(-heading.z, 0.0, heading.x)
	var gate_width := smoothstep(0.0, GATE_LENGTH, minf(distance, order.length - distance))
	# Measure the upcoming bend over a fixed distance, independent of the number
	# of sampled guide points. Broad curves stay wide; tight turns gather the files.
	var approach := center - order.curve.sample_baked(maxf(0.0, distance - 1.2))
	var departure := order.curve.sample_baked(minf(order.length, distance + 1.2)) - center
	var turn := approach.angle_to(departure) if approach.length_squared() > 0.0001 and departure.length_squared() > 0.0001 else 0.0
	var corner_width := lerpf(1.0, 0.63, smoothstep(0.12, 0.85, turn))
	return center + sideways * lane * gate_width * corner_width

func _render() -> void:
	var slot := 0
	for unit: MarchUnit in _units:
		if not unit.is_exposed():
			continue
		var yaw := atan2(-unit.heading.x, -unit.heading.z)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * MODEL_SCALE)
		_multimesh.set_instance_transform(slot, Transform3D(basis, unit.position + Vector3(0, 0.035, 0)))
		var color := FACTION_COLORS[unit.order.faction].srgb_to_linear()
		color.a = unit.gait
		_multimesh.set_instance_custom_data(slot, color)
		slot += 1
	_multimesh.visible_instance_count = slot
