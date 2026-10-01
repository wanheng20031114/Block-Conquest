extends SceneTree
## Exercise paid pig decisions through the real battle scene and dispatch path.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const TACTICS := preload("res://scripts/block_war/war_ai_skills.gd")
const INFORMATION := preload("res://scripts/block_war/war_ai_information.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var actions: Array[Dictionary] = []
var positions: Dictionary[int, Vector3] = {}
var flight_ids := Vector2i(-1, -1)

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL PIG_AI ", label)

func near(value: float, expected: float, label: String) -> void:
	check(absf(value - expected) < 0.00001, "%s: %s expected %s" % [label, value, expected])

func reset(index: int) -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.shields.clear()
	game.fire_states.clear()
	game.bear.links.clear()
	game.bear.locks.clear()
	game.bear.wards.clear()
	game.bear.shots.clear()
	game.bear.damage_remainders.clear()
	game.bear.combat_damage_remainders.clear()
	game.pig.ready.clear()
	game.pig.ready_owners.clear()
	game.pig.drops.clear()
	game.pig.airlifts.clear()
	game.pig.next_drop_id = 1
	game.pig.next_airlift_id = 1
	game.morale.configure(game.faction_count)
	game.finished = false
	game.match_paused = false
	game.elapsed = 30.0
	game.surrendered_factions.clear()
	game._cancel_skill_drag()
	game._cancel_drag()
	for state: RefCounted in game.faction_skills:
		state.commander = RULES.COMMANDER_ID
		state.energy = 100.0
		state.cooldowns.fill(999.0)
		state.durations.fill(0.0)
		state.recruit_target_id = -1
	game.faction_skills[1].commander = RULES.PIG
	game.faction_skills[1].cooldowns[index] = 0.0
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
		building.position = positions[building.building_id]
		building.faction = -1
		building.kind = 2
		building.level = 1
		building.population = 1000.0
		building.refresh_visual()
	game.world_effects.pig_ready(game.buildings, game.pig.ready)
	game.world_effects.sync_pig_drops(game.pig.drops)
	game.world_effects.get_node("PigEffects").sync_airlifts(game.pig.airlifts, game.by_id)
	actions.clear()

func building(id: int, owner: int, population: float) -> WarBuilding:
	var result: WarBuilding = game.by_id[id]
	result.faction = owner
	result.population = population
	result.refresh_visual()
	return result

func flight_pair() -> Vector2i:
	# Use authored topology, not a mocked flight shortcut: find an actual
	# long ground detour on the six-seat lake map.
	var best := Vector2i(-1, -1)
	var saving := 4.0
	for source: WarBuilding in game.buildings:
		for target: WarBuilding in game.buildings:
			if target.building_id <= source.building_id:
				continue
			var route: PackedVector3Array = game.flight_route(source, target)
			var length := 0.0
			for point: int in range(1, route.size()):
				length += route[point - 1].distance_to(route[point])
			var gain: float = game.map.get_building_distance(source, target) - length
			if gain > saving:
				saving = gain
				best = Vector2i(source.building_id, target.building_id)
	return best

func scenery_clearance() -> void:
	# This old map uses authored rock meshes, without a terrain height field.
	# Its left ridge previously pierced a flight fixed at 2.5 metres.
	check(not game.map.definition.has_elevation(), "Clearance regression uses the original flat highland map")
	check(game.map.flight_obstacle_top > 3.75, "Static flight clearance includes the highland rock summits")
	var route: PackedVector3Array = game.flight_route(game.by_id[14], game.by_id[23])
	var cruise := 0.0
	for point: Vector3 in route:
		cruise = maxf(cruise, point.y)
	check(cruise >= game.map.flight_obstacle_top + WarMarches.FLIGHT_CLEARANCE - 0.0001, "Cross-ridge flight rises above the whole visible canopy")
	var checked := 0
	for geometry: GeometryInstance3D in game.map.get_node("Nature").find_children("*", "GeometryInstance3D", true, false):
		if geometry.is_visible_in_tree():
			var bounds: AABB = geometry.global_transform * geometry.get_aabb()
			check(cruise >= bounds.end.y + WarMarches.FLIGHT_CLEARANCE - 0.0001, "Cruise clears authored nature: %s" % geometry.get_path())
			checked += 1
	check(checked > 100, "Regression checks actual visible rocks and tree parts")
	var flat: PackedVector3Array = game.marches.make_flight_route(Vector3.ZERO, Vector3(12, 0, 0))
	var flat_top := 0.0
	for point: Vector3 in flat:
		flat_top = maxf(flat_top, point.y)
	near(flat_top, WarMarches.FLIGHT_CLEARANCE, "Standalone flight keeps an explicit zero-obstacle default")

func skill_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action: Dictionary in actions:
		if action.kind == "skill":
			result.append(action)
	return result

func dispatch_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action: Dictionary in actions:
		if action.kind == "dispatch":
			result.append(action)
	return result

func dispatch_decisions(pair: Vector2i) -> void:
	for index: int in 2:
		reset(index)
		var source_id := pair.x if index == 1 else 1
		var target_id := pair.y if index == 1 else 7
		var stock := 300.0 if index == 1 else 120.0
		var source := building(source_id, 1, stock)
		building(target_id, -1, 10.0)
		var tactics := TACTICS.new(1)
		tactics.take_turn(game)
		var skills := skill_actions()
		var orders := dispatch_actions()
		check(skills.size() == 1 and orders.size() == 1, "QWE %d pays for one skill and immediately issues one order" % index)
		if skills.size() != 1 or orders.size() != 1:
			continue
		check(skills[0].payload.skill == index and skills[0].payload.target == source_id, "QWE %d enchants the chosen source building" % index)
		check(orders[0].payload.source == source_id and orders[0].payload.target == target_id, "QWE %d dispatches to the planned target" % index)
		var count: int = orders[0].payload.count
		if index == 1:
			check(count == RULES.PIG_FLIGHT_LIMIT, "W stops at its sixty-person cap")
		else:
			check(count == RULES.PIG_CHARGE_LIMIT, "Q sends at most twenty strengthened soldiers")
		near(game.faction_skills[1].energy, 100.0 - RULES.PIG_COSTS[index], "QWE %d has the real energy cost" % index)
		check(not game.pig.ready.has(source_id), "QWE %d consumes preparation without idle expiry" % index)
		near(game.faction_skills[1].durations[index], 0.0, "QWE %d clears ready-duration HUD state" % index)
		check(source.available_population >= 8.0, "QWE %d preserves a defensive garrison" % index)
		check(game.marches._units.size() == count, "QWE %d creates exactly the planned soldiers" % index)
		var order: WarMarches.MarchOrder = game.marches._units[0].order
		check(order.pig_charge == (index == 0) and order.airborne == (index == 1) and not order.dense, "QW %d applies the correct issued-order effect" % index)
		near(source.population, stock, "QWE %d keeps reserved soldiers inside the source" % index)
		game.marches.tick(0.5)
		check(source.population < stock and source.population >= stock - count, "QWE %d actually departs while respecting the cap" % index)
		var before := actions.size()
		tactics.take_turn(game)
		check(actions.size() == before, "QWE %d cannot recast in the same decision" % index)
	reset(0)
	building(1, 1, 12.0)
	building(7, -1, 10.0)
	TACTICS.new(1).take_turn(game)
	check(actions.is_empty() and game.pig.ready.is_empty(), "No affordable safe departure means no wasted enchantment")
	near(game.faction_skills[1].energy, 100.0, "No viable mission leaves energy untouched")

func airlift_decisions() -> void:
	for owner: int in [-1, 0, 1, 3]:
		reset(2)
		var survivor := building(0, 0, 1000.0)
		survivor.kind = 1
		survivor.level = 4
		survivor.refresh_visual()
		var source := building(1, 1, 80.0)
		source.kind = 0
		source.refresh_visual()
		var target := building(7, owner, 10.0)
		if owner == 1:
			target.kind = 0
			target.refresh_visual()
		elif owner == 3:
			var route := PackedVector3Array([target.position + Vector3(8, 0, 0), target.position])
			game.marches.send(0, 7, 0, 18, route)
			for unit: WarMarches.MarchUnit in game.marches._units:
				unit.distance = 0.0
				game.marches._update_pose(unit)
		var troops_before: int = game.marches._units.size()
		var population_before := target.population
		TACTICS.new(1).take_turn(game)
		check(game.pig.airlifts.size() == 1 and skill_actions().size() == 1, "E selects a useful target with owner %d" % owner)
		if game.pig.airlifts.is_empty():
			continue
		check(game.pig.airlifts[0].target == 7 and game.pig.airlifts[0].faction == 1, "E targets the destination directly for owner %d" % owner)
		check(dispatch_actions().is_empty() and game.marches._units.size() == troops_before, "E creates no source dispatch or marching army")
		near(source.population, 80.0, "E does not withdraw population from an owned source")
		near(target.population, population_before, "E does not land soldiers before its first batch")
		near(game.faction_skills[1].energy, 100.0 - RULES.PIG_COSTS[2], "E pays its independent airlift price")
		var airlift_key := Vector2i(7, 1)
		check(INFORMATION.snapshot_incoming(game, 0).get(airlift_key, 0) == RULES.PIG_AIRLIFT_COUNT, "public airlift starts with forty incoming soldiers")
		if owner == 0:
			var defense := INFORMATION.snapshot_defense(game, 0)
			near(defense.damage[7], RULES.PIG_AIRLIFT_COUNT * game.combat_multiplier(1, target), "defender observes the real airlift attack without a march object")
		game.simulate(RULES.PIG_AIRLIFT_BATCH_INTERVAL)
		check(INFORMATION.snapshot_incoming(game, 0).get(airlift_key, 0) == RULES.PIG_AIRLIFT_COUNT - RULES.PIG_AIRLIFT_BATCH_SIZE, "landed batch leaves the incoming count exactly once")
		game.simulate(RULES.PIG_AIRLIFT_DURATION - RULES.PIG_AIRLIFT_BATCH_INTERVAL)
		check(game.pig.airlifts[0].landed == RULES.PIG_AIRLIFT_COUNT, "E completes all forty generated landings")
		check(INFORMATION.snapshot_incoming(game, 0).get(airlift_key, 0) == 0, "completed airlift is not counted again as incoming")
		check(target.faction == (owner if owner in [1, 3] else 1), "E completes actual reinforcement or capture")
		near(source.population, 80.0, "completed E still leaves the source garrison unchanged")
	reset(2)
	building(1, 1, 80.0)
	var target := building(7, -1, 10.0)
	game.pig.airlifts.append({"id": 100, "faction": 3, "target": 7, "age": 0.0, "landed": 0})
	TACTICS.new(1).take_turn(game)
	check(skill_actions().is_empty(), "AI avoids duplicating an ally's already committed airlift")
	reset(2)
	building(1, 1, 80.0)
	target = building(7, -1, 100.0)
	TACTICS.new(1).take_turn(game)
	check(game.pig.airlifts.is_empty(), "E does not waste forty soldiers on a known overwhelming neutral garrison")
	reset(2)
	building(1, 1, 80.0)
	building(7, -1, 10.0)
	game.faction_skills[1].energy = RULES.PIG_COSTS[2] - 1.0
	TACTICS.new(1).take_turn(game)
	check(game.pig.airlifts.is_empty(), "E respects its full revised energy cost")

func airlift_defense_decisions() -> void:
	for commander: StringName in [&"squirrel", &"bear"]:
		reset(2)
		game.faction_skills[1].commander = commander
		game.faction_skills[1].cooldowns.fill(999.0)
		game.faction_skills[1].cooldowns[2 if commander == &"squirrel" else 3] = 0.0
		var target := building(1, 1, 15.0)
		game.faction_skills[0].commander = RULES.PIG
		game.faction_skills[0].cooldowns[2] = 0.0
		check(game.cast_skill(2, target, 0), "hostile airlift launches against the defending " + commander)
		near(INFORMATION.airlift_threats(game, 1)[1], RULES.PIG_AIRLIFT_COUNT * game.combat_multiplier(0, target), "skill threat counts publicly falling soldiers once")
		TACTICS.new(1).take_turn(game)
		check(game.shields.has(1) if commander == &"squirrel" else game.bear.wards.has(1), commander + " uses its defensive skill against visible airlift")
		check(game.marches._units.is_empty(), "airlift defense decision does not need fake marching soldiers")
	reset(2)
	var target := building(1, 1, 15.0)
	game.pig.airlifts.append({"id": 100, "faction": 3, "target": 1, "age": 0.0, "landed": 0})
	check(INFORMATION.airlift_threats(game, 1).is_empty() and INFORMATION.snapshot_defense(game, 1).damage.is_empty(), "allied airlift is reinforcement, never hostile pressure")
	game.pig.airlifts[0].faction = 0
	target.faction = 0
	check(INFORMATION.airlift_threats(game, 1).is_empty(), "lost building no longer asks its former owner for protection")

func exposed_group(owner: int, count: int, at: Vector3, cloak: bool = false) -> void:
	for index: int in count:
		var offset := Vector3(0.0, 0.0, (float(index % 3) - 1.0) * 0.2)
		game.marches.send(1 if owner % 2 == 1 else 0, 7, owner, 1, PackedVector3Array([at - Vector3(5, 0, 0), at + Vector3(20, 0, 0)]))
		var unit: WarMarches.MarchUnit = game.marches._units[-1]
		unit.distance = 5.0
		unit.position = at + offset
		unit.cloaked = cloak

func impact_decisions() -> void:
	var at := Vector3(-46, 0, -28)
	reset(3)
	building(1, 1, 40.0)
	exposed_group(0, 32, at)
	var expected: Vector3 = game.map.definition.surface_point(at + Vector3(game.marches.base_speed(0) * RULES.PIG_DROP_FALL_TIME, 0, 0))
	var plan: Dictionary = TACTICS.new(1)._pig_drop_target(game)
	check(not plan.is_empty(), "R finds a valuable known enemy cluster")
	if not plan.is_empty():
		check(Vector2(plan.at.x - expected.x, plan.at.z - expected.z).length() < 0.25, "R leads moving armies by the full falling delay")
	TACTICS.new(1).take_turn(game)
	check(game.pig.drops.size() == 1 and skill_actions().size() == 1, "R creates a real delayed impact")
	near(game.faction_skills[1].energy, 20.0, "R pays eighty energy")
	check(game.marches._units.size() == 32, "R warning does not kill units early")
	game.marches.tick(RULES.PIG_DROP_FALL_TIME)
	game.pig.advance(game, RULES.PIG_DROP_FALL_TIME)
	check(game.marches._units.is_empty(), "R impact actually catches its predicted moving army")
	for owner: int in [1, 3]:
		reset(3)
		building(1, 1, 40.0)
		exposed_group(0, 32, at)
		exposed_group(owner, 40, at)
		TACTICS.new(1).take_turn(game)
		check(game.pig.drops.is_empty() and actions.is_empty(), "R refuses greater friendly army losses, allied seat %d" % owner)
		near(game.faction_skills[1].energy, 100.0, "Refused friendly-fire strike preserves energy")
	reset(3)
	building(1, 1, 40.0)
	var allied := building(3, 3, 200.0)
	allied.position = expected
	exposed_group(0, 32, at)
	TACTICS.new(1).take_turn(game)
	check(game.pig.drops.is_empty(), "R counts allied building population-halving as collateral")
	reset(3)
	building(1, 1, 40.0)
	exposed_group(0, 40, at, true)
	check(TACTICS.new(1)._pig_drop_target(game).is_empty(), "A cloaked enemy cluster cannot create an R target")
	TACTICS.new(1).take_turn(game)
	check(actions.is_empty(), "AI does not spend on unobservable cloaked armies")

func signature(index: int, population: float, hidden: String = "") -> Array[Dictionary]:
	reset(index)
	var source_id := flight_ids.x if index == 1 else 1
	var target_id := flight_ids.y if index == 1 else 7
	building(source_id, 1, 200.0)
	building(target_id, 0, population)
	game.faction_skills[0].energy = population
	game.faction_skills[0].cooldowns.fill(population)
	if index == 3:
		exposed_group(0, 32, Vector3(-46, 0, -28))
	if hidden == "cloak":
		exposed_group(0, 50, game.by_id[source_id].position + Vector3(4, 0, 0), true)
	elif hidden == "queue":
		var route := PackedVector3Array([game.by_id[target_id].position, game.by_id[source_id].position])
		game.marches.queue_tunnel_departure(target_id, source_id, 0, 8, route, 0.16, 3.0)
	TACTICS.new(1).take_turn(game)
	return actions.duplicate(true)

func information_pairs() -> void:
	for index: int in 4:
		if index == 1 and flight_ids.x < 0:
			continue
		var baseline := signature(index, 40.0)
		check(not baseline.is_empty(), "Information fixture %d performs a real action" % index)
		for population: float in [1.0, 9999.0]:
			check(signature(index, population) == baseline, "Skill %d ignores hidden enemy population and energy %s" % [index, population])
		for hidden: String in ["cloak", "queue"]:
			check(signature(index, 40.0, hidden) == baseline, "Skill %d ignores enemy %s troops" % [index, hidden])

func target_types() -> void:
	reset(0)
	var source := building(1, 1, 60.0)
	var ally := building(3, 3, 60.0)
	var enemy := building(0, 0, 60.0)
	for index: int in 4:
		game.faction_skills[1].cooldowns.fill(0.0)
		game.faction_skills[1].energy = 100.0
		check(game.skill_is_ground(index, 1) == (index == 3), "Pig target type %d is correct for non-local faction" % index)
		check(game._valid_skill_target(index, source, 1) == (index < 3), "Only QWE accepts an owned building, index %d" % index)
		check(game._valid_skill_target(index, ally, 1) == (index == 2), "Only E accepts another allied commander's building, index %d" % index)
		check(game._valid_skill_target(index, enemy, 1) == (index == 2), "Only E accepts enemy buildings, index %d" % index)
		check(game._valid_skill_target(index, game.by_id[6], 1) == (index == 2), "Only E accepts neutral buildings, index %d" % index)
		if index < 3:
			check(not game.cast_ground_skill(index, source.position, 1), "QWE cannot be cast as a ground spell, index %d" % index)
		else:
			check(not game.cast_skill(index, source, 1), "R cannot be submitted as a building spell")
		near(game.faction_skills[1].energy, 100.0, "Wrong target type %d has no cost" % index)

func _run() -> void:
	create_timer(75.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	var previous_commander: StringName = session.block_war_commander
	var previous_opponent: StringName = session.block_war_opponent_commander
	session.block_war_map_id = "highland"
	session.block_war_commander = RULES.PIG
	session.block_war_opponent_commander = RULES.PIG
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for site: WarBuilding in game.buildings:
		positions[site.building_id] = site.position
	game.presentation_event.connect(func(kind: String, payload: Dictionary):
		if kind in ["dispatch", "skill"] and int(payload.faction) == 1:
			actions.append({"kind": kind, "payload": payload.duplicate(true)}))
	scenery_clearance()
	flight_ids = flight_pair()
	check(flight_ids.x >= 0 and flight_ids.y >= 0, "Authored highland map offers a genuine flight shortcut")
	if flight_ids.x >= 0:
		dispatch_decisions(flight_ids)
	airlift_decisions()
	airlift_defense_decisions()
	impact_decisions()
	information_pairs()
	target_types()
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	session.block_war_commander = previous_commander
	session.block_war_opponent_commander = previous_opponent
	print("PIG_AI ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
