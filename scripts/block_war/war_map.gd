class_name WarMap
extends Node3D
## The riverbed is physically below the plateau. Only the four bridges connect
## the three banks; graph clearance reserves room for a five-column march.

const HALF_SIZE := Vector2(40.0, 28.0)
const FORMATION_CLEARANCE := 1.6
const GRID_STEP := 2.0
const BRIDGE_Z := 14.0
const BRIDGE_HALF_WIDTH := 3.2
const BUILDING_CLEARANCE := 3.35
var _navigation := AStar3D.new()
var _grid: Dictionary[Vector2i, int] = {}
var _building_positions := PackedVector3Array()
var _route_cache: Dictionary[Vector4, PackedVector3Array] = {}
var _tree_obstacle_grid: Dictionary[Vector2i, Array] = {}
var _flow_time := 0.0
var _visual_paused := false
@onready var _river_material: ShaderMaterial = $Terrain/River0.material_override
@onready var _wind_material: ShaderMaterial = preload("res://assets/block_war/environment/forest_wind.tres")


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
	_wind_material.set_shader_parameter("flow_time", _flow_time)


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


func get_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var key := Vector4(from.x, from.z, to.x, to.z)
	if not _route_cache.has(key):
		_route_cache[key] = _compute_route(from, to)
	return _route_cache[key]


func _compute_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var doorway_start := Vector3(from.x, 0.0, from.z)
	var doorway_finish := Vector3(to.x, 0.0, to.z)
	var start := _door_approach(doorway_start)
	var finish := _door_approach(doorway_finish)
	if not is_walkable(start) or not is_walkable(finish):
		return PackedVector3Array()
	if _segment_clear(start, finish):
		return _include_doorways(PackedVector3Array([start, finish]), doorway_start, doorway_finish)
	var start_id := _navigation.get_available_point_id()
	var finish_id := start_id + 1
	_navigation.add_point(start_id, start)
	_navigation.add_point(finish_id, finish)
	# Connect endpoints to visible bank vertices. A wide radius lets the approach
	# leave each doorway naturally without snapping to the grid.
	for point_id: int in _grid.values():
		var point := _navigation.get_point_position(point_id)
		if start.distance_squared_to(point) < 180.0 and _segment_clear(start, point):
			_navigation.connect_points(start_id, point_id)
		if finish.distance_squared_to(point) < 180.0 and _segment_clear(finish, point):
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
		while next > anchor + 1 and not _segment_clear(raw[anchor], raw[next]):
			next -= 1
		result.append(raw[next])
		anchor = next
	return _include_doorways(result, doorway_start, doorway_finish)


func _door_approach(point: Vector3) -> Vector3:
	for building: WarBuilding in $Buildings.get_children():
		if point.distance_squared_to(building.door_position()) < 0.01:
			return point + Vector3(0.0, 0.0, 1.8)
	return point


func _include_doorways(route: PackedVector3Array, start: Vector3, finish: Vector3) -> PackedVector3Array:
	if not route[0].is_equal_approx(start):
		route.insert(0, start)
	if not route[-1].is_equal_approx(finish):
		route.append(finish)
	return route


func _is_route_point_clear(point: Vector3) -> bool:
	if not _has_clearance(point):
		return false
	for building_position: Vector3 in _building_positions:
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


func _segment_clear(from: Vector3, to: Vector3) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / 0.5))
	for index in range(steps + 1):
		if not _is_route_point_clear(from.lerp(to, float(index) / float(steps))):
			return false
	return true


func _build_navigation() -> void:
	_navigation.clear()
	_grid.clear()
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
