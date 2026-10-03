extends SceneTree
## Audit the saved first two battlefields, including actual six-file march poses.

const MAP_IDS := ["flower_pool", "forest_fork"]
const EXPECTED_ROUTE_PAIRS := {"flower_pool": 66, "forest_fork": 91}
const MARCHES := preload("res://scenes/block_war/marches.tscn")
const PREVIEW := preload("res://scripts/block_war/war_map_preview.gd")
## Mean horizontal edge length in the minimum spanning tree of building sites,
## measured from bc48965 (the first published version of these two maps).
## A connected adjacency graph includes river crossings and both woodland lanes;
## nearest-neighbor samples alone would omit the long gaps between their clusters.
const PREVIOUS_ADJACENT_SPACING := {"flower_pool": 20.3831618702, "forest_fork": 17.8748881915}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	_check_curved_water()
	if not OS.get_cmdline_user_args().has("--geometry-only"):
		for map_id: String in MAP_IDS:
			var definition := load("res://data/block_war/maps/%s.tres" % map_id) as WarMapDefinition
			check(definition != null, "%s has a saved native map definition" % map_id)
			if definition == null:
				continue
			var map := load(definition.scene_path).instantiate() as WarMap
			root.add_child(map)
			map.set_visual_paused(true)
			var buildings := map.get_node("Buildings").get_children()
			_check_layout(map, buildings)
			_check_compact_spacing(map, buildings)
			_check_saved_routes(map, buildings)
			if map_id == "flower_pool":
				_check_flower_pool(map, buildings)
			else:
				_check_forest_fork(map, buildings)
			map.free()
			await process_frame
	print("CAMPAIGN_BATTLE_MAPS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_curved_water() -> void:
	var definition := WarMapDefinition.new()
	definition.half_size = Vector2(8, 8)
	# A bent channel with an open notch cannot be replaced by its bounding box.
	definition.water_polygons = [PackedVector2Array([Vector2(-10, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-1, 3), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-10, -1)])]
	check(not definition.is_walkable(Vector2(-4, -2)), "the long arm of a concave river blocks movement")
	check(not definition.is_walkable(Vector2(2, 2)), "the curved river's return arm blocks movement")
	check(definition.is_walkable(Vector2.ZERO), "dry land inside a river's bounding box stays walkable")
	check(not definition.is_walkable(Vector2(3, 0)), "the native polygon boundary is part of the impassable bank")
	definition.bridges = [Rect2(-3, -4, 4, 4)]
	check(definition.is_walkable(Vector2(-2, -2)), "a saved bridge overrides curved water underneath")
	check(not definition.is_walkable(Vector2(-4, -2)), "land beside the bridge cannot cross the same water")
	definition.water_regions = [Rect2(-7, 4, 4, 2)]
	check(not definition.is_walkable(Vector2(-5, 5)), "legacy rectangular rivers remain blocked")
	check(not definition.is_walkable(Vector2(9, 0)), "bridges and polygons never bypass playable bounds")
	var preview := PREVIEW.new()
	preview.definition = definition
	var bounds := Rect2(20, 30, 320, 320)
	var visible: Array[PackedVector2Array] = preview._water_screen_polygons(bounds)
	check(visible.size() == 1, "preview retains the continuous curved river outline")
	var all_inside := true
	var wet_arm := false
	var dry_notch := true
	for polygon: PackedVector2Array in visible:
		for point: Vector2 in polygon:
			all_inside = all_inside and bounds.grow(0.001).has_point(point)
		wet_arm = wet_arm or Geometry2D.is_point_in_polygon(bounds.position + Vector2(4, 6) * 20, polygon)
		dry_notch = dry_notch and not Geometry2D.is_point_in_polygon(bounds.position + Vector2(8, 8) * 20, polygon)
	check(all_inside and wet_arm and dry_notch, "preview clips outside the map without filling the river's dry concavity")
	preview.free()
	var diamond := WarMapDefinition.new()
	diamond.water_polygons = [PackedVector2Array([Vector2(-3, 0), Vector2(0, 3), Vector2(3, 0), Vector2(0, -3)])]
	for point: Vector2 in [Vector2(0, 3), Vector2(0, -3), Vector2(1, 2), Vector2(-1, -2)]:
		check(diamond.is_water(point), "curved-water boundaries include pointed extrema and sloped edges")
	# This fixed regression fixture is independent of the flower map's live layout.
	# A ray through consecutive bank vertices must count each shared edge only once.
	var winding := WarMapDefinition.new()
	winding.water_polygons = [PackedVector2Array([Vector2(-3, -4), Vector2(-2, -2), Vector2(-3, 0), Vector2(-2, 2), Vector2(-3, 4), Vector2(1, 4), Vector2(2, 2), Vector2(1, 0), Vector2(2, -2), Vector2(1, -4)])]
	for point: Vector2 in [Vector2(-5, 0), Vector2(5, 0), Vector2(-5, 2), Vector2(5, 2)]:
		check(not winding.is_water(point) and winding.is_walkable(point), "a shared ray vertex cannot turn dry land into an isolated water obstacle")

func _check_layout(map: WarMap, buildings: Array[Node]) -> void:
	var definition: WarMapDefinition = map.definition
	check(definition.team_size == 1 and definition.asymmetric_start, "%s is an explicit asymmetric 1v1 encounter" % definition.map_id)
	check(buildings.size() >= 8 and buildings.size() <= 15, "%s keeps 8–15 authored buildings" % definition.map_id)
	check(buildings.size() == definition.building_positions.size(), "preview and scene have identical building counts")
	var player_count := 0
	var enemy_count := 0
	var neutral_count := 0
	for i: int in buildings.size():
		var building: WarBuilding = buildings[i]
		check(building.building_id == i and building.position.is_equal_approx(definition.building_positions[i]), "scene ID and position match the native map resource")
		check(building.kind == definition.building_kinds[i] and building.faction == definition.building_factions[i], "preview role and ownership match each building")
		check(map.is_walkable(building.position), "every building sits on usable land")
		check(absf(building.position.y - definition.surface_height(Vector2(building.position.x, building.position.z))) < 0.01, "each building stands on its actual terrain surface")
		if building.faction == 0:
			player_count += 1
			check(building.level == 1 and building.position.x < -definition.half_size.x * 0.7, "the player begins at level one on the far left")
		elif building.faction == 1:
			enemy_count += 1
			check(building.position.x > definition.half_size.x * 0.7, "enemy starting buildings occupy the far right")
		else:
			neutral_count += 1
	check(player_count == 1 and enemy_count > player_count, "enemy starts with more buildings than the single player residence")
	check(neutral_count >= 7, "the middle offers many neutral capture decisions")

func _check_compact_spacing(map: WarMap, buildings: Array[Node]) -> void:
	var connected: Array[int] = [0]
	var adjacent_total := 0.0
	var closest_pair := INF
	var models_unchanged := true
	for building: WarBuilding in buildings:
		models_unchanged = models_unchanged and building.scene_file_path == "res://scenes/block_war/building.tscn" and building.scale.is_equal_approx(Vector3.ONE)
	while connected.size() < buildings.size():
		var nearest := INF
		var next := -1
		for source: int in connected:
			for target: int in buildings.size():
				if target in connected:
					continue
				var a: Vector3 = buildings[source].position
				var b: Vector3 = buildings[target].position
				var distance := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
				if distance < nearest:
					nearest = distance
					next = target
		connected.append(next)
		adjacent_total += nearest
		closest_pair = minf(closest_pair, nearest)
	var average := adjacent_total / float(buildings.size() - 1)
	var ratio: float = average / PREVIOUS_ADJACENT_SPACING[map.definition.map_id]
	# Half a percentage point tolerance permits deliberate fractional lane offsets.
	check(ratio >= 0.645 and ratio <= 0.755, "%s adjacent objectives are about 25–35 percent closer than the original map (%.2f percent reduction)" % [map.definition.map_id, (1.0 - ratio) * 100.0])
	check(closest_pair >= 8.0, "nearby buildings retain distinct entrances, approach room and selectable silhouettes")
	check(models_unchanged, "compact spacing preserves the original full-size building scene")
	print("CAMPAIGN_SPACING ", map.definition.map_id, " original=", PREVIOUS_ADJACENT_SPACING[map.definition.map_id], " current=", average, " reduction=", (1.0 - ratio) * 100.0, " percent closest=", closest_pair)

func _check_saved_routes(map: WarMap, buildings: Array[Node]) -> void:
	var definition: WarMapDefinition = map.definition
	var marches: WarMarches = MARCHES.instantiate()
	marches.map_definition = definition
	root.add_child(marches)
	var pairs := 0
	var missing := 0
	var illegal := 0
	var floating := 0
	var bad_distance := 0
	var bad_reverse := 0
	var water_crossings := 0
	var off_bridge := 0
	var first_failure := ""
	var mesh: Mesh = marches.get_node("Militia").multimesh.mesh
	var bounds := mesh.get_aabb()
	var footprint: Array[Vector3] = [Vector3.ZERO]
	for x: float in [bounds.position.x, bounds.end.x]:
		for z: float in [bounds.position.z, bounds.end.z]:
			footprint.append(Vector3(x, 0, z))
	for i: int in buildings.size():
		for j: int in range(i + 1, buildings.size()):
			pairs += 1
			var route := map.get_building_route(buildings[i], buildings[j])
			if route.size() < 2:
				missing += 1
				continue
			var reverse := map.get_building_route(buildings[j], buildings[i])
			reverse.reverse()
			bad_reverse += int(reverse != route)
			marches.clear()
			marches.send(i, j, 0, 6, route)
			var length: float = marches._units[0].order.length
			bad_distance += int(absf(map.get_building_distance(buildings[i], buildings[j]) - length) > 0.02)
			for step: int in range(ceili(length / 0.5) + 1):
				for unit: WarMarches.MarchUnit in marches._units:
					unit.distance = minf(length - 0.001, step * 0.5)
					marches._update_pose(unit)
					floating += int(absf(unit.position.y - definition.surface_height(Vector2(unit.position.x, unit.position.z))) > 0.01)
					var basis := Basis(Vector3.UP, atan2(-unit.heading.x, -unit.heading.z)).scaled(Vector3.ONE * WarMarches.MODEL_SCALE)
					for corner: Vector3 in footprint:
						var world := unit.position + basis * corner
						var point := Vector2(world.x, world.z)
						if not map.is_walkable(world):
							illegal += 1
							if illegal <= 5:
								print("ROUTE_FOOTPRINT_FAILURE ", definition.map_id, " ", i, " -> ", j, " point=", world, " pose=", unit.position)
							if first_failure.is_empty():
								first_failure = "%d -> %d at %s" % [i, j, world]
						if definition.is_water(point):
							water_crossings += 1
							var on_bridge := false
							for bridge: Rect2 in definition.bridges:
								on_bridge = on_bridge or WarMapDefinition._inside(bridge, point)
							off_bridge += int(not on_bridge)
							if not on_bridge and off_bridge <= 5:
								print("ROUTE_BRIDGE_FAILURE ", definition.map_id, " ", i, " -> ", j, " point=", world, " pose=", unit.position)
	check(pairs == EXPECTED_ROUTE_PAIRS[definition.map_id] and pairs == buildings.size() * (buildings.size() - 1) / 2 and missing == 0, "%s retains the complete expected set of saved building-pair routes" % definition.map_id)
	check(bad_reverse == 0 and bad_distance == 0, "reverse routes and AI distances match the real march guide")
	check(illegal == 0, "%s six-file soldier footprints never enter water, cliffs or tree trunks: %s" % [definition.map_id, first_failure])
	check(floating == 0, "%s actual soldier poses follow the rendered height surface" % definition.map_id)
	check(off_bridge == 0, "all actual river-crossing footprints stay inside the bridge decks")
	if definition.map_id == "flower_pool":
		check(water_crossings > 0, "routes really cross the rivers on bridges rather than bypassing the map")
	print("CAMPAIGN_ROUTES ", definition.map_id, " pairs=", pairs, " missing=", missing, " illegal=", illegal, " floating=", floating, " water_samples=", water_crossings, " first=", first_failure)
	marches.free()

func _check_flower_pool(map: WarMap, buildings: Array[Node]) -> void:
	var definition: WarMapDefinition = map.definition
	check(definition.title == "水间花池", "the first dedicated battlefield retains its requested name")
	check(definition.water_polygons.size() >= 2 and definition.bridges.size() >= 4, "several curved streams offer separate carefully placed crossings")
	var enemy_count := 0
	var all_houses := true
	for building: WarBuilding in buildings:
		if building.faction == 1:
			enemy_count += 1
			all_houses = all_houses and building.kind == 0 and building.level == 2
	check(enemy_count == 2 and all_houses, "rabbit begins with exactly two second-level houses")

func _check_forest_fork(map: WarMap, buildings: Array[Node]) -> void:
	var definition: WarMapDefinition = map.definition
	check(definition.title == "双径森林", "the second dedicated battlefield uses the requested forest name")
	check(definition.has_elevation(), "woodland elevation is shared by visible ground and movement")
	check(not definition.is_walkable(Vector2.ZERO), "the forested central ridge blocks a direct third lane")
	check(definition.surface_height(Vector2.ZERO) >= 8.0, "the woodland ridge remains visibly higher than both playable lanes")
	for z: float in [-16.5, 16.5]:
		check(definition.surface_height(Vector2(0, z)) >= 2.6, "both compact lanes ascend to the central high ground")
		check(definition.surface_height(Vector2(0, z)) - definition.surface_height(Vector2(-28, z)) >= 2.6, "the raised center differs materially from its entrance")
		var left: WarBuilding = null
		var right: WarBuilding = null
		for building: WarBuilding in buildings:
			if absf(building.position.z - z) < 1.0:
				if left == null or building.position.x < left.position.x:
					left = building
				if right == null or building.position.x > right.position.x:
					right = building
		check(left != null and right != null and left != right, "each forest lane has distinct entrance and exit objectives")
		if left == null or right == null or left == right:
			continue
		var route := map.get_building_route(left, right)
		var stays_in_lane := not route.is_empty()
		var reaches_high_ground := false
		for point: Vector3 in route:
			stays_in_lane = stays_in_lane and point.z * signf(z) > 10.0
			reaches_high_ground = reaches_high_ground or point.y >= 2.6
		check(stays_in_lane and reaches_high_ground, "a cross-map forest route climbs its own lane without jumping to the other path")
	var illegal_middle_crossing := false
	for i: int in buildings.size():
		for j: int in range(i + 1, buildings.size()):
			var route := map.get_building_route(buildings[i], buildings[j])
			for point: Vector3 in route:
				if absf(point.x) < 1.0 and absf(point.z) <= 10.0:
					illegal_middle_crossing = true
	check(not illegal_middle_crossing, "every cached route respects the forest ridge separating both lanes")
