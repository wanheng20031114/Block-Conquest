extends SceneTree
## All building pairs, actual soldier footprints and arbitrary perimeter exits.

const MAP := preload("res://scenes/block_war/map.tscn")
const MARCHES := preload("res://scenes/block_war/marches.tscn")
var _checks := 0
var _failures: Array[String] = []
var _arrivals: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL ", description)


func _route_length(route: PackedVector3Array) -> float:
	var length := 0.0
	for index: int in range(1, route.size()):
		length += route[index - 1].distance_to(route[index])
	return length


func _wall_outline(building: WarBuilding) -> PackedVector2Array:
	var points := PackedVector2Array()
	var original_kind := building.kind
	var original_level := building.level
	# Cached routes must stay safe after upgrades and conversions at any point.
	for kind: int in 3:
		building.kind = kind
		for level: int in range(1, building.max_level + 1):
			building.level = level
			building.refresh_visual()
			var model := building.get_node("Visual/" + ["House", "Tower", "Smithy"][kind])
			for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for surface: int in part.mesh.get_surface_count():
					var vertices: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					for vertex: Vector3 in vertices:
						var world := part.global_transform * vertex
						# Overhead roofs and walkable foundation steps do not obstruct soldiers.
						if world.y >= 0.5 and world.y <= 1.6:
							points.append(Vector2(world.x, world.z))
	building.kind = original_kind
	building.level = original_level
	building.refresh_visual()
	return Geometry2D.convex_hull(points)


func _run() -> void:
	var map: WarMap = MAP.instantiate()
	# This audit also compares the curves to freshly computed AStar corridors.
	map.bake_routes = true
	root.add_child(map)
	map.set_visual_paused(true)
	var marches: WarMarches = MARCHES.instantiate()
	root.add_child(marches)
	marches.unit_arrived.connect(func(target_id: int, _faction: int, _strength: float): _arrivals.append(target_id))
	var buildings: Array[Node] = map.get_node("Buildings").get_children()
	var outlines: Array[PackedVector2Array] = []
	for building: WarBuilding in buildings:
		building.set_visual_paused(true)
		outlines.append(_wall_outline(building))
	_check(outlines.all(func(outline: PackedVector2Array): return outline.size() >= 3), "Wall audit loads all kinds and levels, including the fourth house, at every building position")
	var mesh: Mesh = marches.get_node("Militia").multimesh.mesh
	var bounds := mesh.get_aabb()
	var footprint: Array[Vector3] = [Vector3.ZERO]
	for x: float in [bounds.position.x, bounds.end.x]:
		for z: float in [bounds.position.z, bounds.end.z]:
			footprint.append(Vector3(x, 0, z))
	var graph_points := map._navigation.get_point_count()
	var routes := 0
	var missing := 0
	var invalid_endpoints := 0
	var off_ground := 0
	var wall_collisions := 0
	var samples := 0
	var first_failure := ""
	var largest_turn := 0.0
	var longest_detour := 1.0
	var symmetric := true
	var valid_points := true
	for source: WarBuilding in buildings:
		for target: WarBuilding in buildings:
			if source == target:
				continue
			routes += 1
			var route := map.get_building_route(source, target)
			if route.size() < 2:
				missing += 1
				continue
			var reverse := map.get_building_route(target, source)
			reverse.reverse()
			symmetric = symmetric and route == reverse
			for index: int in range(1, route.size()):
				var incoming := route[index] - route[index - 1]
				valid_points = valid_points and route[index].is_finite() and incoming.length() > 0.001
				if index < route.size() - 1:
					largest_turn = maxf(largest_turn, incoming.angle_to(route[index + 1] - route[index]))
			if source.building_id < target.building_id:
				var corridor := map._compute_building_route(source, target)
				longest_detour = maxf(longest_detour, _route_length(route) / _route_length(corridor))
			if not is_equal_approx(route[0].distance_to(source.global_position), source.MARCH_PERIMETER_RADIUS) or not is_equal_approx(route[-1].distance_to(target.global_position), target.MARCH_PERIMETER_RADIUS):
				invalid_endpoints += 1
			marches.clear()
			marches.send(source.building_id, target.building_id, 0, 6, route)
			var length := marches._units[0].order.length
			var steps := ceili(length / 0.35)
			for step: int in range(steps + 1):
				for unit: WarMarches.MarchUnit in marches._units:
					unit.distance = minf(length - 0.001, float(step) / float(steps) * length)
					marches._update_pose(unit)
					var basis := Basis(Vector3.UP, atan2(-unit.heading.x, -unit.heading.z)).scaled(Vector3.ONE * marches.MODEL_SCALE)
					for corner: Vector3 in footprint:
						var world := unit.position + basis * corner
						samples += 1
						if not map.is_walkable(world):
							off_ground += 1
						for index: int in buildings.size():
							if world.distance_squared_to(buildings[index].global_position) > 9.0:
								continue
							if Geometry2D.is_point_in_polygon(Vector2(world.x, world.z), outlines[index]):
								wall_collisions += 1
								if first_failure.is_empty():
									first_failure = "%d -> %d enters wall %d at %s" % [source.building_id, target.building_id, index, world]
	_check(routes == 156 and missing == 0, "All 156 ordered building pairs retain valid routes")
	_check(invalid_endpoints == 0, "Every route starts and stops at the building's outer perimeter")
	_check(off_ground == 0, "All six files and full soldier footprints avoid rivers and tree trunks")
	_check(wall_collisions == 0, "No soldier enters source, destination or intermediate building walls")
	_check(valid_points and rad_to_deg(largest_turn) < 10.0, "All guides have finite, distinct samples and no abrupt angular corners")
	_check(longest_detour < 1.03, "Gentle arcs never add more than three percent to a safe corridor")
	_check(symmetric and map._route_cache.size() == 78, "Opposite directions share one stable path for every building pair")
	_check(map._navigation.get_point_count() == graph_points, "Temporary endpoint vertices never remain in the shared navigation graph")
	var east := map.get_building_route(buildings[0], buildings[6])
	var north := map.get_building_route(buildings[0], buildings[2])
	var south := map.get_building_route(buildings[0], buildings[3])
	var west := map.get_building_route(buildings[1], buildings[7])
	var direct := north[-1] - north[0]
	var bow := 0.0
	for point: Vector3 in north:
		bow = maxf(bow, (point - north[0]).cross(direct).length() / direct.length())
	_check(bow > 0.4 and bow < 1.5, "Open ground uses a visible but restrained arc instead of a ruler-straight line")
	_check(east.size() == 2, "The short neighboring-building link stays direct where there is no room for an arc")
	_check(east[0].x > -30.0 and north[0].z < 0.0 and south[0].z > 0.0 and west[0].x < 30.0, "Buildings can dispatch from east, north, south and west sides")
	var cached := east.duplicate()
	east.clear()
	_check(map.get_building_route(buildings[0], buildings[6]) == cached, "Clearing a preview cannot corrupt the cached route")
	_check(map.get_building_route(buildings[0], buildings[0]).is_empty(), "A building cannot send a route into itself")
	marches.clear()
	marches.send(0, 6, 0, 1, cached)
	_check(marches._units[0].heading.dot((cached[1] - cached[0]).normalized()) > 0.999, "A newly visible soldier immediately faces its chosen perimeter exit")
	marches.clear()
	marches.send(0, 6, 0, 42, cached)
	marches.send(0, 2, 0, 24, north)
	var first_tail := INF
	var second_head := -INF
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.order.target_id == 6:
			first_tail = minf(first_tail, unit.distance)
		else:
			second_head = maxf(second_head, unit.distance)
	_check(second_head <= first_tail - marches.ROW_SPACING, "Opposite exits of one source preserve its shared dispatch queue")
	marches.tick(40.0)
	_check(_arrivals.count(6) == 42 and _arrivals.count(2) == 24 and marches.total_for(0) == 0, "Every queued soldier arrives exactly once at its own destination")
	print("BLOCK_WAR_ROUTES checks=", _checks, " failures=", _failures.size(), " routes=", routes, " samples=", samples, " off_ground=", off_ground, " wall_collisions=", wall_collisions, " max_turn_degrees=", rad_to_deg(largest_turn), " detour_ratio=", longest_detour, " first=", first_failure)
	marches.free()
	map.free()
	quit(0 if _failures.is_empty() else 1)
