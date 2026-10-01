extends SceneTree
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var positions: Dictionary[int, Vector3] = {}

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func near(a: float, b: float, label: String) -> void:
	check(absf(a - b) < 0.00001, "%s (%s / %s)" % [label, a, b])

func reset() -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.bear.links.clear(); game.bear.wards.clear(); game.bear.shots.clear()
	game.bear.damage_remainders.clear(); game.bear.combat_damage_remainders.clear()
	game.pig.ready.clear(); game.pig.ready_owners.clear(); game.pig.drops.clear(); game.pig.airlifts.clear()
	game.shields.clear(); game.fire_states.clear()
	game.morale.configure(game.faction_count)
	game.elapsed = 0.0; game.finished = false; game.match_paused = false
	game.surrendered_factions.clear()
	game._cancel_skill_drag()
	for building: WarBuilding in game.buildings:
		building.faction = building.building_id if building.building_id < 6 else -1
		building.population = 70.0; building.kind = 2; building.level = 1
		building.position = positions[building.building_id]
		building.cancel_construction(); building.clear_disruption(); building.clear_burrow()
		building.refresh_visual()
	for state: RefCounted in game.faction_skills:
		state.commander = RULES.PIG
		state.energy = 100.0; state.cooldowns.fill(0.0); state.durations.fill(0.0)
	game.world_effects.pig_ready(game.buildings, game.pig.ready)
	game.world_effects.sync_pig_drops(game.pig.drops)
	game.world_effects.get_node("PigEffects").sync_airlifts(game.pig.airlifts, game.by_id)

func refill() -> void:
	game.energy = 100
	game.cooldowns.fill(0.0)

func soldier(faction: int, at: Vector3) -> WarMarches.MarchUnit:
	game.marches.send(1, 0, faction, 1, PackedVector3Array([at, at + Vector3(40, 0, 0)]))
	var unit: WarMarches.MarchUnit = game.marches._units[-1]
	unit.distance = 0.5
	unit.position = at
	return unit

func _run() -> void:
	create_timer(55.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	session.block_war_map_id = "highland"
	session.block_war_commander = RULES.PIG; session.block_war_opponent_commander = RULES.PIG
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false); game.camera_rig.set_process(false); game.ai_enabled = false
	for building: WarBuilding in game.buildings: positions[building.building_id] = building.position
	reset()
	var home: WarBuilding = game.by_id[0]
	var enemy: WarBuilding = game.by_id[1]
	game.energy = RULES.ENERGY_INITIAL
	check(game.can_cast_skill(0), "Opening Q affordable")
	for index: int in 4:
		check(game.skill_is_ground(index) == (index == 3), "Target mode %d" % index)
		check(not RULES.description(index, RULES.PIG).is_empty(), "Tooltip %d" % index)
	refill()
	check(not game.cast_skill(0, enemy), "Own buildings only, enemy rejected")
	check(not game.cast_skill(0, game.by_id[2]), "Ally building rejected")
	near(game.energy, 100, "Invalid target costs nothing")
	check(game.cast_skill(0, home), "Arm Q")
	refill(); check(not game.cast_skill(0, home), "Duplicate Q rejected")
	check(game.issue_order(home, home, 100) == 0, "Invalid order rejected")
	near(game.pig.flags_for(0).x, 15, "Invalid order retains preparation")
	home.population = 0
	check(game.issue_order(home, enemy, 100) == 0, "Empty order rejected")
	near(game.pig.flags_for(0).x, 15, "Empty order retains preparation")
	game.pig.advance(game, 14.9)
	check(game.pig.ready.has(0), "Preparation alive before 15")
	game.pig.advance(game, 0.101)
	check(not game.pig.ready.has(0), "Preparation expires after 15")
	near(game.active_durations[0], 0, "Expiry clears HUD duration")
	for skill_indices: Array in [[0], [1], [0, 1]]:
		reset()
		for index: int in skill_indices:
			refill(); check(game.cast_skill(index, home), "Stack preparation %s %d" % [skill_indices, index])
		var expected := 20 if 0 in skill_indices else 60
		check(game.dispatch_count(home, 100) == expected, "Preview enforces cap %s" % str(skill_indices))
		check(game.issue_order(home, enemy, 100) == expected, "Dispatch respects cap %s" % str(skill_indices))
		check(not game.pig.ready.has(0), "Successful dispatch consumes preparation")
		near(home.population, 70, "Dispatch does not instantly remove garrison")
		check(home.queued_population == expected, "Reservations match cap")
		var order: WarMarches.MarchOrder = game.marches._units[0].order
		check(order.pig_charge == (0 in skill_indices) and order.airborne == (1 in skill_indices) and not order.dense, "Only charge and flight modify the issued wave")
		game.marches.tick(0.1)
		check(home.population < 70 and home.population > 70 - expected, "Garrison decreases in batches")
		for step: int in 50: game.marches.tick(0.1)
		near(home.population, 70 - expected, "Only capped wave left home")
		check(home.queued_population == 0, "All capped reservations settled")
	reset()
	game.issue_order(home, enemy, 25)
	var old: WarMarches.MarchOrder = game.marches._units[0].order
	check(game.cast_skill(0, home), "New preparation after existing queue")
	game.issue_order(home, enemy, 25)
	check(not old.pig_charge and game.marches._units[-1].order.pig_charge, "No retroactive buff to earlier queue")
	reset(); game.cast_skill(1, home)
	home.population = 0
	game._on_unit_arrived(0, 1, 1.0)
	check(home.faction == 1 and not game.pig.ready.has(0), "Capture clears prepared building")
	reset(); game.cast_skill(0, home); game.cast_ground_skill(3, home.position)
	game.match_paused = true; game.simulate(1.0)
	near(game.pig.flags_for(0).x, 15, "Pause freezes preparation")
	near(game.pig.drops[0].age, 0, "Pause freezes falling pig")
	reset()
	var at := home.position
	var friendly := soldier(0, at + Vector3(2.9, 0, 0))
	var hostile := soldier(1, at + Vector3(0, 0, 2.9))
	var ally := soldier(2, at + Vector3(-2.9, 0, 0))
	var outside := soldier(1, at + Vector3(3.01, 0, 0))
	var airborne := soldier(1, at + Vector3(0, 9, 0)); airborne.order.airborne = true
	var cloaked := soldier(1, at); cloaked.cloaked = true
	game.issue_order(home, enemy, 100)
	check(game.cast_ground_skill(3, at), "R accepts own building location")
	game.pig.advance(game, 0.649)
	check(friendly.alive and hostile.alive and ally.alive, "Warning causes no premature damage")
	near(home.population, 70, "Building unchanged during warning")
	game.pig.advance(game, 0.001)
	check(not friendly.alive and not hostile.alive and not ally.alive and not airborne.alive and not cloaked.alive, "R affects all teams and airborne/cloaked units")
	check(outside.alive, "Small radius excludes unit just outside")
	near(home.population, 35, "R halves garrison exactly once")
	check(home.queued_population == 35, "R trims pending departures without double loss")
	game.pig.advance(game, 0.1)
	near(home.population, 35, "No repeated impact")
	game.pig.advance(game, 1.0)
	check(game.pig.drops.is_empty(), "Effect record retires")
	reset(); home.population = 31
	game.bear.wards[0] = {"faction": 0, "remaining": 5.0, "shot_clock": 0.5, "pulse": 0.0, "hostile": false}
	game.cast_ground_skill(3, home.position); game.pig.advance(game, 2.0)
	near(home.population, 15.5, "Direct population effect halves odd garrison, ignores protection")
	check(game.pig.drops.is_empty(), "Long step impacts then retires once")
	reset(); game.cast_skill(1, home)
	var recipients: Array[int] = [2, 4]
	var result: Dictionary = game.SURRENDER.transfer(game, 0, recipients)
	check(result.buildings > 0 and home.faction in [2, 4], "Surrender distributes assets to eligible ally")
	check(not game.pig.ready.has(0), "Surrender clears unspent building effects")
	near(home.population, 42, "Surrender loss remains forty percent")
	await game.prepare_shutdown()
	print("BLOCK_WAR_PIG checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
