class_name WarMarches
extends Node3D
## Every entry is one population point. Marchers never collide or fight in transit.
## The controller calls tick from _process; stopping tick also stops the GPU gait.

signal unit_arrived(target_id: int, faction: int, strength: float)

const COLUMNS := 6
const COLUMN_SPACING := 0.45
const ROW_SPACING := 0.72
const SPEED := 3.45
const MODEL_SCALE := 0.44
const GATE_LENGTH := 2.4
const FACTION_COLORS: Array[Color] = [Color(1.0, 0.65, 0.18), Color(0.2, 0.83, 0.67), Color("94c964"), Color("e9bf5b")]

class MarchOrder extends RefCounted:
	var source_id: int
	var target_id: int
	var faction: int
	var strength: float
	var curve: Curve3D
	var length: float
	var corners: PackedFloat32Array

class MarchUnit extends RefCounted:
	var order: MarchOrder
	var distance: float
	var lane: float
	var position: Vector3
	var heading: Vector3 = Vector3.FORWARD
	var gait: float

@onready var _multimesh: MultiMesh = $Militia.multimesh
var _units: Array[MarchUnit] = []
var _boosts: Dictionary = {}

func _ready() -> void:
	_multimesh.instance_count = 4096
	_multimesh.visible_instance_count = 0

func send(source_id: int, target_id: int, faction: int, count: int, route: PackedVector3Array, strength: float = 1.0) -> void:
	assert(route.size() >= 2, "A march needs a source and destination in its route.")
	assert(faction >= 0 and faction < FACTION_COLORS.size(), "Unknown marching faction.")
	if count <= 0:
		return
	var order := MarchOrder.new()
	order.source_id = source_id
	order.target_id = target_id
	order.faction = faction
	order.strength = strength
	order.curve = Curve3D.new()
	order.curve.bake_interval = 0.12
	# Keep the route's clearance guarantee: no Bezier handles cutting ravine corners.
	# Only headings and formation width are smoothed around the original waypoints.
	var last := route[0]
	var running_length := 0.0
	order.curve.add_point(last)
	for index: int in range(1, route.size()):
		var point := route[index]
		var segment_length := point.distance_to(last)
		if segment_length < 0.001:
			continue
		running_length += segment_length
		order.curve.add_point(point)
		if index < route.size() - 1:
			order.corners.append(running_length)
		last = point
	order.length = order.curve.get_baked_length()
	assert(order.length > 0.01, "Cannot send soldiers along a zero-length route.")
	# Consecutive orders from the same door join its queue instead of spawning stacks.
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
		_units.append(unit)
	_ensure_capacity(_units.size())
	_render()

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	var step_boosts: Dictionary = {}
	for faction: int in _boosts:
		var boost: Vector2 = _boosts[faction]
		# Integrate only the portion of this tick still covered by the skill.
		var boosted_time := minf(delta, boost.x)
		step_boosts[faction] = (boosted_time * boost.y + delta - boosted_time) / delta
		boost.x -= delta
		_boosts[faction] = boost
	for faction: int in _boosts.keys():
		if _boosts[faction].x <= 0.0:
			_boosts.erase(faction)
	var arrivals: Array[MarchOrder] = []
	var index := 0
	while index < _units.size():
		var unit := _units[index]
		var step := SPEED * delta * float(step_boosts.get(unit.order.faction, 1.0))
		unit.distance += step
		unit.gait += step * 7.0
		if unit.distance >= unit.order.length:
			arrivals.append(unit.order)
			_remove_unit(index)
			continue
		if unit.distance >= 0.0:
			_update_pose(unit)
		index += 1
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

func get_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: MarchUnit in _units:
		if unit.distance >= 0.0:
			result.append({"position": unit.position, "faction": unit.order.faction,
				"source_id": unit.order.source_id, "target_id": unit.order.target_id,
				"strength": unit.order.strength, "distance": unit.distance, "lane": unit.lane})
	return result

func damage_near(center: Vector3, attacking_faction: int, radius: float, damage: int) -> Vector3:
	var hit := Vector3.INF
	var radius_squared := radius * radius
	for casualty: int in maxi(damage, 0):
		var nearest := -1
		var nearest_distance := radius_squared
		for index: int in _units.size():
			var unit := _units[index]
			if unit.order.faction == attacking_faction or unit.distance < 0.0:
				continue
			var distance_squared := unit.position.distance_squared_to(center)
			if distance_squared <= nearest_distance:
				nearest_distance = distance_squared
				nearest = index
		if nearest < 0:
			break
		if hit == Vector3.INF:
			hit = _units[nearest].position
		_remove_unit(nearest)
	if hit != Vector3.INF:
		_render()
	return hit

func boost_faction(faction: int, duration: float, speed_multiplier: float) -> void:
	assert(duration > 0.0 and speed_multiplier >= 1.0)
	_boosts[faction] = Vector2(duration, speed_multiplier)

func clear() -> void:
	_units.clear()
	_boosts.clear()
	_multimesh.visible_instance_count = 0

func _remove_unit(index: int) -> void:
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
	var center := order.curve.sample_baked(distance)
	var before := order.curve.sample_baked(maxf(0.0, distance - 0.3))
	var after := order.curve.sample_baked(minf(order.length, distance + 0.3))
	var heading := after - before
	heading.y = 0.0
	unit.heading = heading.normalized()
	var sideways := Vector3(-unit.heading.z, 0.0, unit.heading.x)
	var gate_width := smoothstep(0.0, GATE_LENGTH, minf(distance, order.length - distance))
	var corner_width := 1.0
	for corner: float in order.corners:
		corner_width = minf(corner_width, lerpf(0.63, 1.0, smoothstep(0.0, 1.2, absf(distance - corner))))
	unit.position = center + sideways * unit.lane * gate_width * corner_width

func _render() -> void:
	var slot := 0
	for unit: MarchUnit in _units:
		if unit.distance < 0.0:
			continue
		var yaw := atan2(-unit.heading.x, -unit.heading.z)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * MODEL_SCALE)
		_multimesh.set_instance_transform(slot, Transform3D(basis, unit.position + Vector3(0, 0.035, 0)))
		var color := FACTION_COLORS[unit.order.faction].srgb_to_linear()
		color.a = unit.gait
		_multimesh.set_instance_custom_data(slot, color)
		slot += 1
	_multimesh.visible_instance_count = slot
