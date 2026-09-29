extends SceneTree
## Audit the authored economy independently of layout-generation code and routes.
## The map's full seat count includes computers. Towers and forges never count as homes.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const HOMES_PER_SEAT := 4
const EARLY_EXPANSIONS_PER_SEAT := 2
const EARLY_EXPANSION_RADIUS := 34.0
const TEAM_OPENING_TOLERANCE := 1.2

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

func _eligible_expansions(definition: WarMapDefinition, home_id: int, homes: PackedInt32Array, neutrals: PackedInt32Array) -> Array[int]:
	var candidates: Array[int] = []
	var origin := _flat(definition.building_positions[home_id])
	var team := definition.building_factions[home_id] % 2
	for target_id: int in neutrals:
		var target := _flat(definition.building_positions[target_id])
		var distance := origin.distance_to(target)
		if distance > EARLY_EXPANSION_RADIUS:
			continue
		var enemy_distance := INF
		for other_id: int in homes:
			if definition.building_factions[other_id] % 2 != team:
				enemy_distance = minf(enemy_distance, _flat(definition.building_positions[other_id]).distance_to(target))
		# First expansion should be available on one's own side, not require
		# winning the enemy doorstep or an equidistant central objective.
		if distance + 0.1 < enemy_distance:
			candidates.append(target_id)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		return origin.distance_squared_to(_flat(definition.building_positions[a])) < origin.distance_squared_to(_flat(definition.building_positions[b])))
	return candidates

func _assign_expansion(request: int, candidates: Array, assigned: Dictionary, visited: Dictionary) -> bool:
	# Each commander requests two different houses. Augmenting paths allow
	# shared options without counting the same neutral house for two allies.
	for target_id: int in candidates[request / EARLY_EXPANSIONS_PER_SEAT]:
		if visited.has(target_id):
			continue
		visited[target_id] = true
		if not assigned.has(target_id) or _assign_expansion(assigned[target_id], candidates, assigned, visited):
			assigned[target_id] = request
			return true
	return false

func _audit(definition: WarMapDefinition) -> void:
	var prefix := definition.map_id + ": "
	var seats := definition.team_size * 2
	var homes := PackedInt32Array()
	var neutrals := PackedInt32Array()
	var starters := PackedInt32Array()
	starters.resize(seats)
	var metadata_complete := definition.building_positions.size() == definition.building_kinds.size() and definition.building_positions.size() == definition.building_factions.size()
	check(metadata_complete, prefix + "every building has matching position, role and ownership metadata")
	if not metadata_complete:
		return
	var residence_count := 0
	for id: int in definition.building_positions.size():
		var faction := definition.building_factions[id]
		var is_home := definition.building_kinds[id] == 0
		residence_count += int(is_home)
		check(faction >= -1 and faction < seats, prefix + "building %d has a valid full-match seat" % id)
		if faction >= 0 and faction < seats:
			starters[faction] += 1
			homes.append(id)
			check(is_home, prefix + "every starting property produces units as a residence")
		elif faction == -1 and is_home:
			neutrals.append(id)
	check(residence_count >= seats * HOMES_PER_SEAT, prefix + "%d residences support %d seats at a minimum of %d each" % [residence_count, seats, HOMES_PER_SEAT])
	for faction: int in seats:
		check(starters[faction] == 1, prefix + "seat %d starts with exactly one residence" % faction)
	var native_map := (load(definition.scene_path) as PackedScene).instantiate()
	var populations := {}
	var native_houses := 0
	var native_buildings := native_map.get_node("Buildings").get_children()
	check(native_buildings.size() == definition.building_positions.size(), prefix + "native scene contains every catalog building")
	for building: WarBuilding in native_buildings:
		native_houses += int(building.kind == 0)
		populations[building.building_id] = building.population
		check(building.building_id >= 0 and building.building_id < definition.building_positions.size(), prefix + "scene building ID belongs to catalog")
		if building.building_id < 0 or building.building_id >= definition.building_positions.size():
			continue
		check(building.kind == definition.building_kinds[building.building_id] and building.faction == definition.building_factions[building.building_id], prefix + "scene and catalog agree on residence ownership and role")
		if building.faction >= 0:
			check(is_equal_approx(building.population, 60.0), prefix + "every seat retains the same sixty-unit opening")
	check(native_houses == residence_count, prefix + "density reflects actual native residences, not only preview markers")
	var candidates: Array = []
	var team_distances := PackedFloat64Array([0.0, 0.0])
	var team_garrisons := PackedFloat64Array([0.0, 0.0])
	for home_id: int in homes:
		var nearby := _eligible_expansions(definition, home_id, homes, neutrals)
		candidates.append(nearby)
		var faction := definition.building_factions[home_id]
		check(nearby.size() >= EARLY_EXPANSIONS_PER_SEAT, prefix + "seat %d has two early neutral residences before the enemy frontier" % faction)
		var opening_cost := 0.0
		for index: int in mini(EARLY_EXPANSIONS_PER_SEAT, nearby.size()):
			var target_id := nearby[index]
			team_distances[faction % 2] += _flat(definition.building_positions[home_id]).distance_to(_flat(definition.building_positions[target_id]))
			team_garrisons[faction % 2] += float(populations[target_id])
			opening_cost += float(populations[target_id]) + 1.0
		check(opening_cost <= float(populations[home_id]), prefix + "seat %d can overcome its first two neutral garrisons with its initial army" % faction)
	var assigned := {}
	var matched := 0
	for request: int in homes.size() * EARLY_EXPANSIONS_PER_SEAT:
		matched += int(_assign_expansion(request, candidates, assigned, {}))
	check(matched == seats * EARLY_EXPANSIONS_PER_SEAT, prefix + "all seats can claim two distinct early houses without double-counting shared options")
	check(maxf(team_distances[0], team_distances[1]) <= minf(team_distances[0], team_distances[1]) * TEAM_OPENING_TOLERANCE, prefix + "both sides have comparable opening expansion distances")
	check(maxf(team_garrisons[0], team_garrisons[1]) <= minf(team_garrisons[0], team_garrisons[1]) * TEAM_OPENING_TOLERANCE, prefix + "both sides face comparable opening garrison costs")
	print("HOUSING_AUDIT ", definition.map_id, " seats=", seats, " residences=", residence_count, " neutral_residences=", neutrals.size(), " matched_early_expansions=", matched, " opening_distances=", team_distances, " opening_garrisons=", team_garrisons)
	native_map.free()

func _run() -> void:
	for definition: WarMapDefinition in CATALOG.MAPS:
		_audit(definition)
	print("BLOCK_WAR_HOUSING_DENSITY checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
