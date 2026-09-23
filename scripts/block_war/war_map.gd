class_name WarMap
extends Node3D
## The riverbed is physically below the plateau. Only the four bridges connect
## the three banks; graph clearance includes all six files and rotated militia.

const HALF_SIZE := Vector2(40.0, 28.0)
const FORMATION_CLEARANCE := 2.1
const GRID_STEP := 2.0
const BRIDGE_Z := 14.0
const BRIDGE_HALF_WIDTH := 3.2
# Includes the outer file, rotated militia and the widest ground-level walls.
const BUILDING_CLEARANCE := 4.0
const ROUTE_SAMPLE_STEP := 0.25
const TURN_TRIM := 3.8
const ENDPOINT_RUN := 2.6
const MAX_ARC_OFFSET := 1.5
var _navigation := AStar3D.new()
var _grid: Dictionary[Vector2i, int] = {}
var _building_positions := PackedVector3Array()
var _route_cache: Dictionary[Vector4, PackedVector3Array] = {}
var _building_links: Dictionary[Vector3, PackedInt64Array] = {}
var _tree_obstacle_grid: Dictionary[Vector2i, Array] = {}
var _flow_time := 0.0
var _visual_paused := false
@onready var _river_material: ShaderMaterial = $Terrain/River0.material_override
const NATURE_MATERIALS: Array[ShaderMaterial] = [
	preload("res://assets/models/block_war/nature/leaves.tres"),
	preload("res://assets/models/block_war/nature/grass.tres"),
	preload("res://assets/models/block_war/nature/bark.tres"),
]


func _ready() -> void:
	for building: Node3D in $Buildings.get_children():
		_building_positions.append(building.global_position)
	for decoration: Node3D in $Nature.get_children():
		if decoration.has_meta("route_radius"):
			_register_tree_obstacle(Vector3(decoration.position.x, decoration.position.z, float(decoration.get_meta("route_radius")) * decoration.scale.x))
	_build_navigation()


func _process(delta: float) -> void:
	if _visual_paused:
		return
	_flow_time += delta
	_river_material.set_shader_parameter("flow_time", _flow_time)
	for material: ShaderMaterial in NATURE_MATERIALS:
		material.set_shader_parameter("flow_time", _flow_time)


func set_visual_paused(value: bool) -> void:
	_visual_paused = value


func is_walkable(point: Vector3) -> bool:
	if not _is_terrain_walkable(point):
		return false
	for obstacle: Vector3 in _tree_obstacle_grid.get(_obstacle_cell(point), []):
		if Vector2(point.x, point.z).distance_squared_to(Vector2(obstacle.x, obstacle.y)) < obstacle.z * obstacle.z:
			return false
	return true


func _is_terrain_walkable(point: Vector3) -> bool:
	if absf(point.x) > HALF_SIZE.x or absf(point.z) > HALF_SIZE.y:
		return false
	var river := (point.x > -15.0 and point.x < -9.0) or (point.x > 9.0 and point.x < 15.0)
	return not river or absf(absf(point.z) - BRIDGE_Z) <= BRIDGE_HALF_WIDTH


func _obstacle_cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / 6.0), floori(point.z / 6.0))


func _register_tree_obstacle(obstacle: Vector3) -> void:
	var radius := obstacle.z + FORMATION_CLEARANCE
	for x in range(floori((obstacle.x - radius) / 6.0), floori((obstacle.x + radius) / 6.0) + 1):
		for z in range(floori((obstacle.y - radius) / 6.0), floori((obstacle.y + radius) / 6.0) + 1):
			var cell := Vector2i(x, z)
			if not _tree_obstacle_grid.has(cell):
				_tree_obstacle_grid[cell] = []
			_tree_obstacle_grid[cell].append(obstacle)


func get_building_route(source: WarBuilding, target: WarBuilding) -> PackedVector3Array:
	if source == target:
		return PackedVector3Array()
	# Both directions share the same guide, regardless of which side orders first.
	var reverse := source.building_id > target.building_id
	var first := target if reverse else source
	var last := source if reverse else target
	var from := first.global_position
	var to := last.global_position
	var key := Vector4(from.x, from.z, to.x, to.z)
	if not _route_cache.has(key):
		var corridor := _compute_building_route(first, last)
		_route_cache[key] = _shape_route(corridor) if corridor.size() >= 2 else corridor
	# Drag previews and march callers own their copy; cancelling one must not
	# empty the shared route used by later orders or AI evaluations.
	var route := _route_cache[key].duplicate()
	if reverse:
		route.reverse()
	return route


func _shape_route(corridor: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array([corridor[0]])
	for index: int in range(1, corridor.size() - 1):
		var corner := corridor[index]
		var incoming := corner - corridor[index - 1]
		var outgoing := corridor[index + 1] - corner
		var trim := minf(TURN_TRIM, minf(incoming.length(), outgoing.length()) * 0.4)
		# Keep a radial entrance/exit while the six files fan out or fold together.
		if index == 1:
			trim = minf(trim, maxf(0.0, incoming.length() - ENDPOINT_RUN))
		if index == corridor.size() - 2:
			trim = minf(trim, maxf(0.0, outgoing.length() - ENDPOINT_RUN))
		var arc := PackedVector3Array([corner])
		# A bounded clearance search chooses the widest safe turn. A tight corner
		# keeps its corridor vertex if no rounded span fits the complete formation.
		for attempt: int in 6:
			if trim < 0.08:
				break
			var entry := corner - incoming.normalized() * trim
			var exit := corner + outgoing.normalized() * trim
			var curve := Curve3D.new()
			curve.add_point(entry, Vector3.ZERO, (corner - entry) * (2.0 / 3.0))
			curve.add_point(exit, (corner - exit) * (2.0 / 3.0))
			var points := curve.tessellate_even_length(8, ROUTE_SAMPLE_STEP)
			if _curve_clear(points):
				arc = points
				break
			trim *= 0.5
		_append_flow_span(result, arc[0], index == 1, false)
		for point: int in range(1, arc.size()):
			result.append(arc[point])
	_append_flow_span(result, corridor[-1], corridor.size() == 2, true)
	return result


func _append_flow_span(route: PackedVector3Array, end: Vector3, leaving: bool, arriving: bool) -> void:
	var start := route[-1]
	var direction := (end - start).normalized()
	var arc_start := start + direction * ENDPOINT_RUN if leaving else start
	var arc_end := end - direction * ENDPOINT_RUN if arriving else end
	var length := (arc_end - arc_start).dot(direction)
	# Short connectors and narrow passages need no decorative detour.
	if length >= 8.0:
		var middle := (arc_start + arc_end) * 0.5
		var side := Vector3(-direction.z, 0, direction.x)
		# Prefer the open interior of the map; check both sides against real terrain.
		if side.dot(-middle) < 0.0:
			side = -side
		var offset := minf(MAX_ARC_OFFSET, length * 0.07)
		for attempt: int in 4:
			for sign_value: float in [1.0, -1.0]:
				var curve := Curve3D.new()
				var handle := direction * length / 6.0
				curve.add_point(arc_start, Vector3.ZERO, handle)
				curve.add_point(middle + side * offset * sign_value, -handle, handle)
				curve.add_point(arc_end, -handle)
				var points := curve.tessellate_even_length(8, ROUTE_SAMPLE_STEP)
				if _curve_clear(points):
					if leaving:
						route.append(arc_start)
					for point: int in range(1, points.size()):
						route.append(points[point])
					if arriving:
						route.append(end)
					return
			offset *= 0.5
	route.append(end)


func _curve_clear(points: PackedVector3Array) -> bool:
	# Validate the sampled polyline used by BOTH the preview and the march. No
	# unchecked interpolation is allowed to cut across a bank, trunk or wall.
	for index: int in points.size():
		if not _is_route_point_clear(points[index]):
			return false
		if index > 0 and not _is_route_point_clear((points[index - 1] + points[index]) * 0.5):
			return false
	return true


func _compute_building_route(source: WarBuilding, target: WarBuilding) -> PackedVector3Array:
	var start := source.global_position
	var finish := target.global_position
	if _building_segment_clear(start, finish, source, target):
		return PackedVector3Array([source.march_perimeter_towards(finish), target.march_perimeter_towards(start)])
	# Centers only choose which side has the shortest safe route. They are never
	# rendered or marched through: the final route starts and ends at the perimeter.
	var start_id := _navigation.get_available_point_id()
	var finish_id := start_id + 1
	_navigation.add_point(start_id, start)
	_navigation.add_point(finish_id, finish)
	for point_id: int in _get_building_links(source):
		_navigation.connect_points(start_id, point_id)
	for point_id: int in _get_building_links(target):
		_navigation.connect_points(finish_id, point_id)
	var raw := _navigation.get_point_path(start_id, finish_id)
	_navigation.remove_point(start_id)
	_navigation.remove_point(finish_id)
	if raw.is_empty():
		return raw
	var result := PackedVector3Array([raw[0]])
	var anchor := 0
	while anchor < raw.size() - 1:
		var next := raw.size() - 1
		while next > anchor + 1 and not _building_segment_clear(raw[anchor], raw[next], source, target):
			next -= 1
		result.append(raw[next])
		anchor = next
	result[0] = source.march_perimeter_towards(result[1])
	result[-1] = target.march_perimeter_towards(result[-2])
	return result


func _get_building_links(building: WarBuilding) -> PackedInt64Array:
	var center := building.global_position
	if not _building_links.has(center):
		var links := PackedInt64Array()
		for point_id: int in _grid.values():
			var point := _navigation.get_point_position(point_id)
			if center.distance_squared_to(point) < 180.0:
				var perimeter := building.march_perimeter_towards(point)
				if _segment_clear(perimeter, point, center):
					links.append(point_id)
		_building_links[center] = links
	return _building_links[center]


func _building_segment_clear(from: Vector3, to: Vector3, source: WarBuilding, target: WarBuilding) -> bool:
	var leaving := source.global_position if from == source.global_position else Vector3.INF
	var arriving := target.global_position if to == target.global_position else Vector3.INF
	var start := source.march_perimeter_towards(to) if leaving != Vector3.INF else from
	var finish := target.march_perimeter_towards(from) if arriving != Vector3.INF else to
	return _segment_clear(start, finish, leaving, arriving)


func _is_route_point_clear(point: Vector3, leaving: Vector3 = Vector3.INF, arriving: Vector3 = Vector3.INF) -> bool:
	if not _has_clearance(point):
		return false
	for building_position: Vector3 in _building_positions:
		if building_position == leaving or building_position == arriving:
			continue
		if point.distance_squared_to(building_position) < BUILDING_CLEARANCE * BUILDING_CLEARANCE:
			return false
	for obstacle: Vector3 in _tree_obstacle_grid.get(_obstacle_cell(point), []):
		var clearance := obstacle.z + FORMATION_CLEARANCE
		if Vector2(point.x, point.z).distance_squared_to(Vector2(obstacle.x, obstacle.y)) < clearance * clearance:
			return false
	return true


func _has_clearance(point: Vector3) -> bool:
	if not _is_terrain_walkable(point):
		return false
	for offset: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		if not _is_terrain_walkable(point + offset * FORMATION_CLEARANCE):
			return false
	return true


func _segment_clear(from: Vector3, to: Vector3, leaving: Vector3 = Vector3.INF, arriving: Vector3 = Vector3.INF) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / 0.5))
	for index in range(steps + 1):
		if not _is_route_point_clear(from.lerp(to, float(index) / float(steps)), leaving, arriving):
			return false
	return true


func _build_navigation() -> void:
	_navigation.clear()
	_grid.clear()
	_route_cache.clear()
	_building_links.clear()
	for x in range(-19, 20):
		for z in range(-13, 14):
			var point := Vector3(x * GRID_STEP, 0, z * GRID_STEP)
			if not _is_route_point_clear(point):
				continue
			var point_id := _navigation.get_available_point_id()
			_grid[Vector2i(x, z)] = point_id
			_navigation.add_point(point_id, point)
	for cell: Vector2i in _grid:
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var neighbor := cell + direction
			if _grid.has(neighbor):
				var from := _navigation.get_point_position(_grid[cell])
				var to := _navigation.get_point_position(_grid[neighbor])
				if _segment_clear(from, to):
					_navigation.connect_points(_grid[cell], _grid[neighbor])
