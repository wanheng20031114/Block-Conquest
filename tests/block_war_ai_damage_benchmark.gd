extends SceneTree
## Compare the frozen incoming-damage calculation with a decision-local cache.
## Run against the real battle, buildings, morale and march prediction methods.
const INFORMATION := preload("res://scripts/block_war/war_ai_information.gd")

var game: Node3D
var checks := 0
var failures: Array[String] = []
var soldiers := 1800
var rounds := 3
var iterations := 3
var verify_only := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL AI_DAMAGE ", label)

# Frozen from war_ai_information.gd at f5c0cc8. Do not replace with a production
# call: this is the independent reference after the candidate is installed.
# BEGIN_REFERENCE_DAMAGE
func reference_damage(battle: Node3D, building: WarBuilding, incoming: Dictionary[Vector2i, int], faction: int) -> float:
	var damage := 0.0
	for attacker: int in battle.faction_count:
		if battle.FACTIONS.hostile(building.faction, attacker):
			damage += incoming.get(Vector2i(building.building_id, attacker), 0) * battle.combat_multiplier(attacker, building)
	for unit: WarMarches.MarchUnit in battle.marches._units:
		if not INFORMATION.is_unit_known(battle, unit, faction) or unit.order.target_id != building.building_id or not battle.FACTIONS.hostile(building.faction, unit.order.faction):
			continue
		damage += (unit.order.strength - 1.0) * battle.combat_multiplier(unit.order.faction, building)
		damage += unit.order.strength * (battle.combat_multiplier(unit.order.faction, building, battle.marches.projected_attack_bonus(unit)) - battle.combat_multiplier(unit.order.faction, building))
	return damage
# END_REFERENCE_DAMAGE

# This candidate retains the faction accumulation order and both per-soldier
# additions. Nonzero bonuses still use the complete original multiply/divide
# expression through combat_multiplier; base * (1 + bonus) is not equivalent.
# BEGIN_CANDIDATE_DAMAGE
func candidate_damage(battle: Node3D, building: WarBuilding, incoming: Dictionary[Vector2i, int], faction: int) -> float:
	var damage := 0.0
	var bases := PackedFloat64Array()
	bases.resize(battle.faction_count)
	for attacker: int in battle.faction_count:
		if battle.FACTIONS.hostile(building.faction, attacker):
			bases[attacker] = battle.combat_multiplier(attacker, building)
			damage += incoming.get(Vector2i(building.building_id, attacker), 0) * bases[attacker]
	for unit: WarMarches.MarchUnit in battle.marches._units:
		if unit.order.target_id != building.building_id or not INFORMATION.is_unit_known(battle, unit, faction) or not battle.FACTIONS.hostile(building.faction, unit.order.faction):
			continue
		var base: float = bases[unit.order.faction]
		damage += (unit.order.strength - 1.0) * base
		var bonus: float = battle.marches.projected_attack_bonus(unit)
		var adjusted: float = base if bonus == 0.0 else battle.combat_multiplier(unit.order.faction, building, bonus)
		damage += unit.order.strength * (adjusted - base)
	return damage
# END_CANDIDATE_DAMAGE

func _fixture(label: String, count: int) -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.shields.clear()
	game.bear.links.clear()
	game.bear.wards.clear()
	game.bear.shots.clear()
	game.bear.damage_remainders.clear()
	game.bear.combat_damage_remainders.clear()
	game.finished = false
	game.elapsed = 130.0
	game.morale.configure(game.faction_count)
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
		building.faction = building.building_id % 6
		building.kind = 2 if building.building_id >= 12 else (1 if building.building_id % 3 == 0 else 0)
		building.level = 1 if building.kind == 2 else 1 + building.building_id % 4
		building.population = 500.0
		if building.kind == 2 and building.building_id % 5 == 0:
			building.disruption_remaining = 0.75
	game.by_id[6].faction = -1
	for faction: int in game.faction_count:
		game.morale.adjust(faction, game.MORALE.points_for_stars(float(faction) + 0.17 if faction < 5 else 5.0))
	game.sync_environment_bonuses()
	game.marches.begin_render_batch()
	# Every attacker has orders to all six owners and one neutral target. The
	# other buildings exercise the target-first miss path without fake objects.
	for group: int in 42:
		var amount := count / 42 + int(group < count % 42)
		if amount == 0: continue
		var attacker := group / 7
		var target_id := group % 7
		var target: WarBuilding = game.by_id[target_id]
		var finish: Vector3 = target.global_position
		var route := PackedVector3Array([finish + Vector3(-28.0, 0.0, -4.0), finish + Vector3(-14.0, 0.0, 3.0), finish])
		game.marches.send(attacker, target_id, attacker, amount, route)
	for index: int in game.marches._units.size():
		var unit: WarMarches.MarchUnit = game.marches._units[index]
		unit.distance = unit.order.length - (0.2 if index % 2 == 0 else 17.0)
		if label in ["strength", "mixed"]:
			unit.order.strength = [0.625, 1.0, 1.35, 7.125][unit.order.order_id % 4]
		if label in ["rush", "haste", "levitation", "mixed"]:
			unit.rush_remaining = 4.0 if index % 3 != 0 else 0.01
		if label in ["rush", "mixed"]:
			unit.order.pig_charge = unit.order.order_id % 3 == 0
		if label in ["weak", "mixed"]:
			unit.weakened = index % 3 == 0
		if label in ["cloak_queue_dead", "mixed"]:
			unit.cloaked = index % 5 == 0
			unit.alive = index % 17 != 0
			unit.spawn_delay = 0.5 if index % 11 == 0 else 0.0
		if label in ["levitation", "mixed"]:
			unit.levitation_remaining = 3.0 if index % 2 == 0 else 0.2
		game.marches._update_pose(unit)
	if label in ["cloak_queue_dead", "mixed"]:
		game.marches.queue_departure(0, 1, 0, 6, PackedVector3Array([game.by_id[0].global_position, game.by_id[1].global_position]))
	if label in ["haste", "mixed"]:
		game.marches.create_haste_zone(0, Vector3.ZERO, 100.0, 8.0, game.SKILL_RULES.HASTE_MULTIPLIER)
		game.marches.create_slow_zone(3, Vector3.ZERO, 80.0, 2.7)
	if label in ["mist", "mixed"]:
		game.marches.weak_zones[1] = {"at": Vector3(-42.0, 0.0, 0.0), "radius": 23.0, "remaining": 5.0}
	if label in ["shield", "mixed"]:
		for target: int in [0, 1, 4]: game.shields[target] = 2.0
	if label in ["ward", "mixed"]:
		for target: int in [0, 3, 5]:
			game.bear.wards[target] = {"faction": game.by_id[target].faction, "remaining": 2.0, "shot_clock": 1.0, "pulse": 0.0}
	game.marches.end_render_batch()

func _clear_prediction_caches() -> void:
	var seen := {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if seen.has(unit.order): continue
		seen[unit.order] = true
		unit.order.haste_intervals.clear()
		unit.order.slow_intervals.clear()
		unit.order.mist_intervals.clear()

func _verify_fixture(label: String) -> void:
	for observer: int in game.faction_count:
		var incoming: Dictionary[Vector2i, int] = INFORMATION.snapshot_incoming(game, observer)
		var observation := INFORMATION.snapshot_defense(game, observer)
		check(observation.counts == incoming, "%s batch counts observer %d" % [label, observer])
		for building: WarBuilding in game.buildings:
			_clear_prediction_caches()
			var expected := reference_damage(game, building, incoming, observer)
			_clear_prediction_caches()
			var actual := candidate_damage(game, building, incoming, observer)
			check(actual == expected, "%s observer %d building %d exact %.17f / %.17f" % [label, observer, building.building_id, actual, expected])
			check(INFORMATION.incoming_damage(game, building, incoming, observer) == expected, "%s current production observer %d building %d" % [label, observer, building.building_id])
			if game.FACTIONS.allied(building.faction, observer):
				check(observation.damage.get(building.building_id, 0.0) == expected, "%s batch exact observer %d building %d" % [label, observer, building.building_id])

func _queries() -> Array[Dictionary]:
	var queries: Array[Dictionary] = []
	for observer: int in range(1, game.faction_count):
		var incoming: Dictionary[Vector2i, int] = INFORMATION.snapshot_incoming(game, observer)
		for building: WarBuilding in game.buildings:
			if game.FACTIONS.allied(building.faction, observer):
				queries.append({"building": building, "observer": observer, "incoming": incoming})
	return queries

func _batch(queries: Array[Dictionary], candidate: bool) -> float:
	var checksum := 0.0
	for query: Dictionary in queries:
		checksum += candidate_damage(game, query.building, query.incoming, query.observer) if candidate else reference_damage(game, query.building, query.incoming, query.observer)
	return checksum

func _statistics(samples: Array[float]) -> Dictionary:
	var ordered := samples.duplicate()
	ordered.sort()
	var total := 0.0
	for value: float in samples: total += value
	return {"mean_ms": total / samples.size(), "median_ms": ordered[ordered.size() / 2],
		"p95_ms": ordered[ceili(ordered.size() * 0.95) - 1], "max_ms": ordered[-1]}

func _benchmark(label: String) -> void:
	_fixture(label, soldiers)
	var queries := _queries()
	# Both paths use identical warmed geometry; this measures damage evaluation,
	# not the independent first-field route-sampling cost.
	var expected := _batch(queries, false)
	check(_batch(queries, true) == expected, "%s benchmark batch exact checksum" % label)
	for round_index: int in rounds:
		for candidate: bool in ([false, true] if round_index % 2 == 0 else [true, false]):
			var samples: Array[float] = []
			for iteration: int in iterations:
				var start := Time.get_ticks_usec()
				var result := _batch(queries, candidate)
				samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
				check(result == expected, "%s round %d variant %s iteration %d stable exact result" % [label, round_index, candidate, iteration])
			print("AI_DAMAGE_SAMPLE ", JSON.stringify({"case": label, "variant": "candidate" if candidate else "reference",
				"round": round_index, "soldiers": game.marches._units.size(), "buildings": game.buildings.size(),
				"queries": queries.size(), "iterations": iterations, "checksum": expected,
				"statistics": _statistics(samples), "samples_ms": samples}))

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--soldiers="): soldiers = int(argument.get_slice("=", 1))
		elif argument.begins_with("--rounds="): rounds = int(argument.get_slice("=", 1))
		elif argument.begins_with("--iterations="): iterations = int(argument.get_slice("=", 1))
		elif argument == "--verify-only": verify_only = true
	assert(soldiers > 0 and rounds > 0 and iterations > 0)
	var session: Node = root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	session.block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for label: String in ["ordinary", "strength", "rush", "haste", "weak", "mist", "cloak_queue_dead", "levitation", "shield", "ward", "mixed"]:
		_fixture(label, 84)
		_verify_fixture(label)
	if not verify_only:
		_benchmark("ordinary")
		_benchmark("mixed")
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("AI_DAMAGE_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
