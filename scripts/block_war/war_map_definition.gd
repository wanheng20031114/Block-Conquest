class_name WarMapDefinition
extends Resource
## Authored map metadata shared by navigation, camera limits and the map picker.

@export var map_id := "rift"
@export var title := "裂谷交汇"
@export_enum("小", "中", "大") var size_class := 0
@export_range(1, 3) var team_size := 1
@export_file("*.tscn") var scene_path := "res://scenes/block_war/map.tscn"
@export_file("*.res") var routes_path := "res://data/block_war/routes/rift.res"
@export_multiline var description := "两道溪谷与四座石桥，围绕中央据点展开争夺。"
@export var half_size := Vector2(40, 28)
# Full rendered X/Z bounds include the surrounding woodland, beyond playable half_size.
@export var camera_bounds := Rect2(-60, -54, 120, 108)
@export var ground_color := Color("799077")
@export var water_regions: Array[Rect2] = []
@export var mountain_regions: Array[Rect2] = []
@export var bridges: Array[Rect2] = []
@export var height_zones: Array[WarHeightZone] = []
@export var building_positions := PackedVector3Array()
@export var building_kinds := PackedInt32Array()
@export var building_factions := PackedInt32Array()

const MAX_WALKABLE_GRADIENT := 0.5
const HEIGHT_EPSILON := 0.001
const CLIFF_PROBE := 0.02

func surface_height(point: Vector2) -> float:
	var zone := _height_zone_at(point)
	return zone.height_at(point) if zone != null else 0.0

func surface_point(point: Vector3) -> Vector3:
	return Vector3(point.x, surface_height(Vector2(point.x, point.z)), point.z)

func _height_zone_at(point: Vector2) -> WarHeightZone:
	var highest: WarHeightZone = null
	var height := -INF
	for zone: WarHeightZone in height_zones:
		if zone.contains(point) and zone.height_at(point) > height:
			highest = zone
			height = zone.height_at(point)
	return highest

func ray_ground(origin: Vector3, direction: Vector3) -> Vector3:
	var nearest := Vector3.INF
	var distance := INF
	var base: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if base != null and absf(surface_height(Vector2(base.x, base.z))) <= HEIGHT_EPSILON:
		nearest = base
		distance = origin.distance_squared_to(base)
	for zone: WarHeightZone in height_zones:
		var hit: Variant = zone.surface_plane().intersects_ray(origin, direction)
		if hit == null:
			continue
		var point := Vector2(hit.x, hit.z)
		if not zone.contains(point) or absf(hit.y - surface_height(point)) > HEIGHT_EPSILON:
			continue
		var candidate := origin.distance_squared_to(hit)
		if candidate < distance:
			nearest = hit
			distance = candidate
	# A lower plane beyond a raised zone may lie behind its vertical cliff wall.
	# Top-plane intersections alone would let a player aim straight through it.
	return nearest if nearest.is_finite() and _ray_reaches_surface(origin, nearest) else Vector3.INF

func _ray_reaches_surface(origin: Vector3, hit: Vector3) -> bool:
	var from := Vector2(origin.x, origin.z)
	var to := Vector2(hit.x, hit.z)
	var cuts := surface_breakpoints(from, to)
	for index: int in range(1, cuts.size()):
		var start := origin.lerp(hit, cuts[index - 1])
		var finish := origin.lerp(hit, cuts[index])
		var middle := start.lerp(finish, 0.5)
		var zone := _height_zone_at(Vector2(middle.x, middle.z))
		var start_height := zone.height_at(Vector2(start.x, start.z)) if zone != null else 0.0
		var finish_height := zone.height_at(Vector2(finish.x, finish.z)) if zone != null else 0.0
		if start.y < start_height - HEIGHT_EPSILON or finish.y < finish_height - HEIGHT_EPSILON:
			return false
		if finish.y < surface_height(Vector2(finish.x, finish.z)) - HEIGHT_EPSILON:
			return false
	return true

func surface_breakpoints(from: Vector2, to: Vector2) -> PackedFloat32Array:
	# Splitting at every zone edge makes cliff detection independent of sample spacing.
	var cuts := PackedFloat32Array([0.0, 1.0])
	var span := to - from
	for zone: WarHeightZone in height_zones:
		if absf(span.x) > 0.000001:
			for edge: float in [zone.region.position.x, zone.region.end.x]:
				var ratio := (edge - from.x) / span.x
				if ratio > 0.0 and ratio < 1.0: cuts.append(ratio)
		if absf(span.y) > 0.000001:
			for edge: float in [zone.region.position.y, zone.region.end.y]:
				var ratio := (edge - from.y) / span.y
				if ratio > 0.0 and ratio < 1.0: cuts.append(ratio)
	cuts.sort()
	var unique := PackedFloat32Array([cuts[0]])
	for index: int in range(1, cuts.size()):
		if cuts[index] - unique[-1] > 0.000001:
			unique.append(cuts[index])
	if unique[-1] < 1.0:
		unique.append(1.0)
	return unique

func surface_segment_walkable(from: Vector2, to: Vector2) -> bool:
	if height_zones.is_empty():
		return true
	var first_zone := _height_zone_at(from)
	# Authored zones do not overlap. A rectangle is convex, so a segment with
	# both endpoints on the same plane cannot leave it and cross a cliff.
	if first_zone != null and first_zone == _height_zone_at(to):
		return absf(first_zone.gradient()) <= MAX_WALKABLE_GRADIENT + HEIGHT_EPSILON
	var cuts := surface_breakpoints(from, to)
	var previous_height := surface_height(from)
	for index: int in range(1, cuts.size()):
		var start := from.lerp(to, cuts[index - 1])
		var finish := from.lerp(to, cuts[index])
		var zone := _height_zone_at(start.lerp(finish, 0.5))
		if zone != null and absf(zone.gradient()) > MAX_WALKABLE_GRADIENT + HEIGHT_EPSILON:
			return false
		var start_height := zone.height_at(start) if zone != null else 0.0
		var finish_height := zone.height_at(finish) if zone != null else 0.0
		if absf(start_height - previous_height) > HEIGHT_EPSILON:
			return false
		# A tangent touching only a raised corner is still not a ground crossing.
		if absf(finish_height - surface_height(finish)) > HEIGHT_EPSILON:
			return false
		previous_height = finish_height
	return absf(previous_height - surface_height(to)) <= HEIGHT_EPSILON

func _height_point_walkable(point: Vector2) -> bool:
	if height_zones.is_empty():
		return true
	var zone := _height_zone_at(point)
	if zone != null and absf(zone.gradient()) > MAX_WALKABLE_GRADIENT + HEIGHT_EPSILON:
		return false
	var height := surface_height(point)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if absf(surface_height(point + direction * CLIFF_PROBE) - height) > CLIFF_PROBE * MAX_WALKABLE_GRADIENT + HEIGHT_EPSILON:
			return false
	return true

func is_walkable(point: Vector2) -> bool:
	if absf(point.x) > half_size.x or absf(point.y) > half_size.y:
		return false
	for bridge: Rect2 in bridges:
		if _inside(bridge, point):
			return _height_point_walkable(point)
	for region: Rect2 in water_regions:
		if _inside(region, point):
			return false
	for region: Rect2 in mountain_regions:
		if _inside(region, point):
			return false
	return _height_point_walkable(point)

func mode_label() -> String:
	return "%dv%d" % [team_size, team_size]

static func _inside(region: Rect2, point: Vector2) -> bool:
	return point.x > region.position.x and point.x < region.end.x and point.y > region.position.y and point.y < region.end.y
