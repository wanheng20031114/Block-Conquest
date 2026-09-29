extends SceneTree
## Native-map integration: elevated ground, ramp topology, all routes and full formations.

const MAP_IDS: Array[String] = ["terraces", "switchback", "crown"]
const TOLERANCE := 0.002
const FOOTPRINT: Array[Vector3] = [Vector3(-0.842, 0, -0.55), Vector3(-0.842, 0, 0.383), Vector3(0.695, 0, -0.55), Vector3(0.695, 0, 0.383)]
var game: Node3D
var checks := 0
var failures: Array[String] = []
var scenario := "synthetic"

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		var message := scenario + ": " + label
		failures.append(message)
		printerr("FAIL ", message)

func _zone(rect: Rect2, low: float, high: float, axis: int = 0) -> WarHeightZone:
	var zone := WarHeightZone.new()
	zone.region = rect
	zone.start_height = low
	zone.end_height = high
	zone.axis = axis
	return zone

func _synthetic_ground() -> void:
	var flat := WarMapDefinition.new()
	check(flat.ray_ground(Vector3(2, 10, 3), Vector3.DOWN).is_equal_approx(Vector3(2, 0, 3)), "old flat maps retain ground picking")
	check(not flat.ray_ground(Vector3(2, 10, 3), Vector3.UP).is_finite(), "a ray pointing away returns the explicit miss sentinel")
	check(not flat.ray_ground(Vector3(2, 10, 3), Vector3.RIGHT).is_finite(), "parallel rays cannot invent a ground target")
	var cliff := WarMapDefinition.new()
	cliff.height_zones = [_zone(Rect2(-2, 2, 4, 1), 6, 6)]
	check(cliff.ray_ground(Vector3(0, 10, 2.5), Vector3.DOWN).is_equal_approx(Vector3(0, 6, 2.5)), "vertical rays choose the elevated top before the base")
	check(not cliff.ray_ground(Vector3(0, 10, 10), Vector3(0, -1, -1).normalized()).is_finite(), "a cliff face occludes the low ground behind it")
	check(not cliff.ray_ground(Vector3(-3, 10, 3), Vector3(2, -10, -2).normalized()).is_finite(), "a ray cannot pick low ground through the exact corner of a raised cliff")
	check(cliff.ray_ground(Vector3(3, 10, 10), Vector3(0, -1, -1).normalized()).is_equal_approx(Vector3(3, 0, 0)), "a ray beside the cliff still reaches open ground")
	check(not cliff.surface_segment_walkable(Vector2(0, 0), Vector2(0, 5)), "equal-height endpoints cannot cross an intervening plateau")
	check(not cliff.surface_segment_walkable(Vector2(-3, 3), Vector2(-1, 1)), "touching a raised corner does not permit a diagonal cliff crossing")
	var slope := WarMapDefinition.new()
	slope.height_zones = [_zone(Rect2(-4, -3, 8, 6), 0, 4), _zone(Rect2(4, -3, 4, 6), 4, 4)]
	check(slope.surface_segment_walkable(Vector2(-6, 0), Vector2(6, 0)), "a maximum-gradient ramp is traversable in one continuous crossing")
	check(slope.surface_segment_walkable(Vector2(6, 0), Vector2(-6, 0)), "descending uses the same ramp continuity")
	check(not slope.surface_segment_walkable(Vector2(0, 0), Vector2(0, 4)), "a ramp's lateral cliff cannot become an exit")
	check(slope.ray_ground(Vector3(0, 10, 0), Vector3.DOWN).is_equal_approx(Vector3(0, 2, 0)), "ray picking intersects the inclined surface")
	var steep := WarMapDefinition.new()
	steep.height_zones = [_zone(Rect2(0, 0, 4, 8), 0, 4)]
	check(not steep.is_walkable(Vector2(2, 4)), "steep faces are not walkable points")
	check(not steep.surface_segment_walkable(Vector2(1, 4), Vector2(3, 4)), "steep segments are rejected even within a single zone")
	var descending := WarMapDefinition.new()
	descending.height_zones = [_zone(Rect2(-3, -4, 6, 8), 4, 0, 1)]
	check(descending.ray_ground(Vector3(0, 10, 2), Vector3.DOWN).is_equal_approx(Vector3(0, 1, 2)), "negative Z gradients have the correct surface plane")
	var map := WarMap.new()
	map.definition = slope
	var route := map._surface_route(PackedVector3Array([Vector3(-6, 0, 0), Vector3(6, 4, 0)]))
	check(_route_error(route, slope).is_empty(), "resampling cannot put a straight chord below a ramp entrance or crest")
	check(Array(route).any(func(point: Vector3): return point.distance_to(Vector3(-4, 0, 0)) < TOLERANCE), "the ramp entrance is retained as an exact route vertex")
	check(Array(route).any(func(point: Vector3): return point.distance_to(Vector3(4, 4, 0)) < TOLERANCE), "the ramp crest is retained as an exact route vertex")
	map.definition = flat
	var original := PackedVector3Array([Vector3(-6, 0, 0), Vector3(6, 0, 0)])
	check(map._surface_route(original) == original, "flat maps retain their existing route samples verbatim")
	map.free()

func _route_error(route: PackedVector3Array, definition: WarMapDefinition) -> String:
	if route.size() < 2:
		return "missing route"
	if route.size() > 2048:
		return "route exceeds the multiplayer snapshot point limit"
	for index: int in route.size():
		var point := route[index]
		if not point.is_finite() or absf(point.y - definition.surface_height(Vector2(point.x, point.z))) > TOLERANCE:
			return "route vertex is off the terrain at %s" % point
		if index == 0:
			continue
		var before := route[index - 1]
		var span := point - before
		if span.length() > 0.251:
			return "surface samples are too far apart: %.4f" % span.length()
		if absf(span.y) > Vector2(span.x, span.z).length() * 0.501 + TOLERANCE:
			return "route climbs a cliff between %s and %s" % [before, point]
		var middle := (point + before) * 0.5
		if absf(middle.y - definition.surface_height(Vector2(middle.x, middle.z))) > TOLERANCE:
			return "route interpolation cuts below or above terrain at %s" % middle
	return ""

func _mesh_height(faces: PackedVector3Array, point: Vector2) -> float:
	var height := 0.0
	for index: int in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(point.x, 100, point.y), Vector3.DOWN, faces[index], faces[index + 1], faces[index + 2])
		if hit != null:
			height = maxf(height, hit.y)
	return height

func _authored_ground(definition: WarMapDefinition) -> void:
	var known: Array[Vector3] = []
	var across_cliff: Array[Vector2] = []
	match definition.map_id:
		"terraces":
			known = [Vector3(0, 4.5, 0), Vector3(-19, 2.25, 0), Vector3(19, 2.25, 0), Vector3(0, 2.25, -18), Vector3(0, 0, -28)]
			across_cliff = [Vector2(10, 10), Vector2(14, 10)]
		"switchback":
			known = [Vector3(0, 8, 0), Vector3(0, 6.25, -12), Vector3(0, 4.5, -27), Vector3(-26, 2.25, -27), Vector3(26, 2.25, 27), Vector3(20, 0, 0)]
			across_cliff = [Vector2(5, 0), Vector2(11, 0)]
		"crown":
			known = [Vector3(0, 0, 0), Vector3(0, 5, -28), Vector3(-28, 5, 0), Vector3(0, 2.5, -14), Vector3(-44, 2.5, 0), Vector3(44, 2.5, 26)]
			across_cliff = [Vector2(18, 0), Vector2(22, 0)]
	var upland: MeshInstance3D = game.map.get_node("Terrain/Upland")
	var cliffs: MeshInstance3D = game.map.get_node("Terrain/Cliffs")
	check(upland.mesh != null and cliffs.mesh != null and cliffs.mesh.get_faces().size() > 0, "native scene contains real raised tops and cliff geometry")
	var faces := upland.mesh.get_faces()
	for point: Vector3 in known:
		var xz := Vector2(point.x, point.z)
		check(absf(definition.surface_height(xz) - point.y) < TOLERANCE, "known ground elevation at %s" % point)
		check(absf(_mesh_height(faces, xz) - point.y) < TOLERANCE, "rendered terrain matches the authored height at %s" % point)
		check(definition.ray_ground(point + Vector3.UP * 20.0, Vector3.DOWN).distance_to(point) < TOLERANCE, "ground picking matches visible height at %s" % point)
	check(not definition.surface_segment_walkable(across_cliff[0], across_cliff[1]), "the map's exposed cliff blocks direct travel")
	for zone: WarHeightZone in definition.height_zones:
		check(absf(zone.gradient()) <= 0.5, "every authored slope stays within the walkable gradient")
		var center := zone.region.get_center()
		check(absf(_mesh_height(faces, center) - definition.surface_height(center)) < TOLERANCE, "every authored zone has matching rendered ground")
		if is_equal_approx(zone.start_height, zone.end_height):
			continue
		var start := center
		var finish := center
		if zone.axis == 0:
			start.x = zone.region.position.x - 0.05
			finish.x = zone.region.end.x + 0.05
		else:
			start.y = zone.region.position.y - 0.05
			finish.y = zone.region.end.y + 0.05
		check(definition.surface_segment_walkable(start, finish) and definition.surface_segment_walkable(finish, start), "the entire ramp connects both neighboring levels")
		check(absf(definition.surface_height(start) - zone.start_height) < TOLERANCE and absf(definition.surface_height(finish) - zone.end_height) < TOLERANCE, "ramp mouths have no invisible height step")

func _building_sites(definition: WarMapDefinition) -> void:
	check(game.buildings.size() == definition.building_positions.size(), "native scene and map preview have the same building count")
	var starters := PackedInt32Array()
	starters.resize(definition.team_size * 2)
	for building: WarBuilding in game.buildings:
		var point := building.global_position
		check(point.is_equal_approx(definition.building_positions[building.building_id]), "the native building uses the authored position")
		check(absf(point.y - definition.surface_height(Vector2(point.x, point.z))) < TOLERANCE, "the building's feet are on the ground")
		var level_seat := true
		# Leave room for the walkability probe inside the open six-metre safety disk.
		for radius: float in [2.5, 4.0, 5.95]:
			for step: int in 64:
				var sample := Vector2(point.x, point.z) + Vector2.from_angle(step * TAU / 64.0) * radius
				if absf(definition.surface_height(sample) - point.y) > TOLERANCE or not definition.is_walkable(sample):
					level_seat = false
		check(level_seat, "building %d has a flat six-metre safety footprint" % building.building_id)
		if building.faction >= 0:
			starters[building.faction] += 1
			check(building.kind == 0 and building.level == 1 and building.population == 60.0, "all commanders start with equal homes and garrisons")
	for count: int in starters:
		check(count == 1, "each participating commander has exactly one home")
	check(game.team_total_for(0) == game.team_total_for(1), "both sides have the same initial unit total")

func _mirrored_id(point: Vector3) -> int:
	var mirrored := Vector3(-point.x, point.y, point.z)
	for building: WarBuilding in game.buildings:
		if building.global_position.distance_to(mirrored) < TOLERANCE:
			return building.building_id
	return -1

func _fairness(definition: WarMapDefinition) -> void:
	var geometry_equal := true
	for x: int in range(0, int(definition.half_size.x), 2):
		for z: int in range(-int(definition.half_size.y), int(definition.half_size.y), 2):
			var left := Vector2(-x, z)
			var right := Vector2(x, z)
			if absf(definition.surface_height(left) - definition.surface_height(right)) > TOLERANCE or definition.is_walkable(left) != definition.is_walkable(right):
				geometry_equal = false
	check(geometry_equal, "both teams receive mirrored elevations and traversable terrain")
	for source: WarBuilding in game.buildings:
		var mirrored_source := _mirrored_id(source.global_position)
		check(mirrored_source >= 0, "every building has a geometrically mirrored counterpart")
		if mirrored_source < 0:
			continue
		var opposite: WarBuilding = game.buildings[mirrored_source]
		check(source.kind == opposite.kind and source.level == opposite.level and source.population == opposite.population, "mirrored buildings have matching economic and defensive value")
		if source.faction < 0 or source.faction % 2 != 0:
			continue
		for target: WarBuilding in game.buildings:
			if target == source:
				continue
			var mirrored_target := _mirrored_id(target.global_position)
			if mirrored_target < 0:
				continue
			var distance: float = game.map.get_building_distance(source, target)
			var opposing_distance: float = game.map.get_building_distance(opposite, game.buildings[mirrored_target])
			check(absf(distance - opposing_distance) <= maxf(2.0, distance * 0.08), "mirrored starts have comparable travel cost to building %d" % target.building_id)

func _formation_error(order: WarMarches.MarchOrder, definition: WarMapDefinition) -> String:
	for step: int in range(ceili(order.length * 2.0) + 1):
		for unit: WarMarches.MarchUnit in game.marches._units:
			unit.distance = minf(order.length, step * 0.5)
			game.marches._update_pose(unit)
			var point := unit.position
			if absf(point.y - definition.surface_height(Vector2(point.x, point.z))) > TOLERANCE:
				return "lane %.2f floats or sinks at %s" % [unit.lane, point]
			if not game.map.is_walkable(point):
				return "lane %.2f enters blocked ground at %s" % [unit.lane, point]
			var basis := Basis(Vector3.UP, atan2(-unit.heading.x, -unit.heading.z)).scaled(Vector3.ONE * WarMarches.MODEL_SCALE)
			for corner: Vector3 in FOOTPRINT:
				var edge := point + basis * corner
				if not game.map.is_walkable(edge):
					return "a soldier footprint leaves traversable land at %s" % edge
				# Independent height-rise bound catches a body straddling a cliff.
				var height: float = definition.surface_height(Vector2(edge.x, edge.z))
				if absf(height - point.y) > Vector2(edge.x - point.x, edge.z - point.z).length() * 0.501 + TOLERANCE:
					return "a soldier straddles a cliff at %s" % edge
	return ""

func _routes(definition: WarMapDefinition) -> void:
	var pairs := 0
	var elevated := 0
	for source: WarBuilding in game.buildings:
		for target: WarBuilding in game.buildings:
			if source.building_id >= target.building_id:
				continue
			pairs += 1
			var route: PackedVector3Array = game.map.get_building_route(source, target)
			var label := "%d -> %d" % [source.building_id, target.building_id]
			var route_error := _route_error(route, definition)
			check(route_error.is_empty(), label + " surface route: " + route_error)
			if route.size() < 2:
				continue
			var reverse: PackedVector3Array = game.map.get_building_route(target, source)
			reverse.reverse()
			check(route == reverse, label + " uses the same corridor in both directions")
			var length := 0.0
			var flat_length := 0.0
			for index: int in range(1, route.size()):
				length += route[index].distance_to(route[index - 1])
				flat_length += Vector2(route[index].x, route[index].z).distance_to(Vector2(route[index - 1].x, route[index - 1].z))
			if length > flat_length + 0.1:
				elevated += 1
			check(absf(game.map.get_building_distance(source, target) - length) < 0.02, label + " AI distance measures actual three-dimensional travel")
			game.marches.clear()
			game.marches.send(source.building_id, target.building_id, 0, 6, route)
			var order: WarMarches.MarchOrder = game.marches._units[0].order
			check(absf(order.length - length) < 0.04, label + " rendered marching curve agrees with the saved route length")
			var formation_error := _formation_error(order, definition)
			check(formation_error.is_empty(), label + " six-column formation: " + formation_error)
			# A returning outer file must rejoin the same surface guide safely.
			if source.faction >= 0 and target.global_position.y > 0:
				var unit: WarMarches.MarchUnit = game.marches._units[0]
				unit.distance = order.length * 0.6
				game.marches._update_pose(unit)
				var returning: PackedVector3Array = game.map.get_return_route(unit.position, source, target)
				var return_error := _route_error(returning, definition)
				check(return_error.is_empty(), label + " recall across levels: " + return_error)
				if returning.size() >= 2:
					check(returning[0].distance_to(unit.position) < TOLERANCE and returning[-1].distance_to(route[0]) < TOLERANCE, label + " recall begins at the soldier and ends at its original doorway")
	game.marches.clear()
	check(elevated > 0, "real routes use the ramps and include their added travel distance")
	print("WAR_HEIGHTS ", definition.map_id, " pairs=", pairs, " elevated=", elevated)

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func(): quit(3))
	_synthetic_ground()
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	for map_id: String in MAP_IDS:
		if not OS.get_cmdline_user_args().is_empty() and map_id not in OS.get_cmdline_user_args():
			continue
		scenario = map_id
		session.block_war_map_id = map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		game = current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.ai_enabled = false
		game.audio.muted = true
		var definition: WarMapDefinition = game.map.definition
		check(definition.map_id == map_id and not definition.height_zones.is_empty(), "the selected height map loads through the real match")
		check(game.marches.map_definition == definition, "all formation lanes use this match's terrain")
		_authored_ground(definition)
		_building_sites(definition)
		_fairness(definition)
		_routes(definition)
		await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("BLOCK_WAR_HEIGHTS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
