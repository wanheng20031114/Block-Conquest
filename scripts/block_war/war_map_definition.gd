class_name WarMapDefinition
extends Resource
## Authored map metadata shared by navigation, camera limits and the map picker.

@export var map_id := "rift"
@export var title := "裂谷交汇"
@export_enum("小", "中", "大") var size_class := 0
@export_range(1, 3) var team_size := 1
# Dedicated campaign encounters retain their authored starting advantage in skirmish.
@export var asymmetric_start := false
@export_file("*.tscn") var scene_path := "res://scenes/block_war/map.tscn"
@export_file("*.res") var routes_path := "res://data/block_war/routes/rift.res"
@export_multiline var description := "两道溪谷与四座石桥，围绕中央据点展开争夺。"
@export var half_size := Vector2(40, 28)
# Full rendered X/Z bounds include the surrounding woodland, beyond playable half_size.
@export var camera_bounds := Rect2(-60, -54, 120, 108)
@export var ground_color := Color("799077")
@export var water_regions: Array[Rect2] = []
# Authored curved banks share their sampled outline with the rendered river mesh.
var _water_polygon_bounds: Array[Rect2] = []
@export var water_polygons: Array[PackedVector2Array] = []:
	set(value):
		water_polygons = value
		_water_polygon_bounds.clear()
		for polygon: PackedVector2Array in value:
			assert(polygon.size() >= 3, "An authored river needs a closed polygon outline.")
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for point: Vector2 in polygon:
				bounds = bounds.expand(point)
			_water_polygon_bounds.append(bounds)
@export var mountain_regions: Array[Rect2] = []
@export var bridges: Array[Rect2] = []
@export var terrain: WarTerrainSurface = null
@export var building_positions := PackedVector3Array()
@export var building_kinds := PackedInt32Array()
@export var building_factions := PackedInt32Array()

const MAX_WALKABLE_GRADIENT := 0.5

func has_elevation() -> bool:
	return terrain != null

func surface_height(point: Vector2) -> float:
	return terrain.sample(point) if has_elevation() else 0.0

func surface_point(point: Vector3) -> Vector3:
	return Vector3(point.x, surface_height(Vector2(point.x, point.z)), point.z)

func ray_ground(origin: Vector3, direction: Vector3) -> Vector3:
	if has_elevation():
		return terrain.ray_ground(origin, direction)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	return hit if hit != null else Vector3.INF

func surface_breakpoints(from: Vector2, to: Vector2) -> PackedFloat32Array:
	return terrain.breakpoints(from, to) if has_elevation() else PackedFloat32Array([0.0, 1.0])

func surface_segment_walkable(from: Vector2, to: Vector2) -> bool:
	return terrain.segment_walkable(from, to, MAX_WALKABLE_GRADIENT) if has_elevation() else true

func _height_point_walkable(point: Vector2) -> bool:
	return terrain.gradient_at(point).length() <= MAX_WALKABLE_GRADIENT + WarTerrainSurface.HEIGHT_EPSILON if has_elevation() else true

func is_walkable(point: Vector2) -> bool:
	if absf(point.x) > half_size.x or absf(point.y) > half_size.y:
		return false
	for bridge: Rect2 in bridges:
		if _inside(bridge, point):
			return _height_point_walkable(point)
	if is_water(point):
		return false
	for region: Rect2 in mountain_regions:
		if _inside(region, point):
			return false
	return _height_point_walkable(point)

func is_water(point: Vector2) -> bool:
	for region: Rect2 in water_regions:
		if _inside(region, point):
			return true
	for index: int in water_polygons.size():
		var bounds := _water_polygon_bounds[index]
		if point.x < bounds.position.x or point.x > bounds.end.x or point.y < bounds.position.y or point.y > bounds.end.y:
			continue
		if _inside_water_polygon(point, water_polygons[index]):
			return true
	return false

static func _inside_water_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	# Godot's Geometry2D::is_point_in_polygon (core/math/geometry_2d.h) counts
	# segment intersections with a slanted ray. A ray through a shared vertex
	# can count both adjoining edges; dense curved banks exposed isolated false
	# positives three metres inland. Half-open Y intervals count that vertex once.
	const EDGE_EPSILON := 0.000001
	var inside := false
	var previous := polygon[-1]
	for current: Vector2 in polygon:
		if absf(point.x - current.x) <= EDGE_EPSILON and absf(point.y - current.y) <= EDGE_EPSILON:
			return true
		if absf(current.y - previous.y) <= EDGE_EPSILON:
			if absf(point.y - current.y) <= EDGE_EPSILON and point.x >= minf(current.x, previous.x) and point.x <= maxf(current.x, previous.x):
				return true
		elif (current.y > point.y) != (previous.y > point.y):
			var crossing := previous.x + (point.y - previous.y) * (current.x - previous.x) / (current.y - previous.y)
			if absf(crossing - point.x) <= EDGE_EPSILON:
				return true
			if crossing > point.x:
				inside = not inside
		previous = current
	return inside

func mode_label() -> String:
	return "%dv%d" % [team_size, team_size]

static func _inside(region: Rect2, point: Vector2) -> bool:
	return point.x > region.position.x and point.x < region.end.x and point.y > region.position.y and point.y < region.end.y
