extends "res://tests/block_war_multiplayer_core_test.gd"
## Expiring defense and paid construction must not change outcomes by frame size.

func clean() -> void:
	super.clean()
	game.elapsed = 0.0
	game.winner_team = -2
	game.shields.clear(); game.fire_states.clear()
	game.bear.links.clear(); game.bear.wards.clear(); game.bear.damage_remainders.clear()
	game.morale.configure(game.faction_count)
	for state: RefCounted in game.faction_skills:
		state.commander = &"squirrel"
		state.durations.fill(0.0); state.recruit_target_id = -1
	game.sync_match_control_presentation()

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false); game.camera_rig.set_process(false); game.ai_enabled = false; game.audio.muted = true
	game.configure_match(config(), 105)
	_shield_boundaries()
	_toolbox_stalemates()
	_toolbox_energy_boundaries()
	await game.prepare_shutdown()
	print("RULE_BOUNDARIES checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _shield_case(arrival: float, steps: int) -> Vector2:
	clean()
	var target: WarBuilding = game.by_id[1]
	target.kind = 3; target.population = 0.8
	game.shields[1] = 0.02
	game.marches.send(0, 1, 0, 1, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]))
	var unit: WarMarches.MarchUnit = game.marches._units[0]
	unit.distance = unit.order.length - game.marches.base_speed(0) * arrival
	game.marches._update_pose(unit)
	for i: int in steps: game.simulate(1.0 / (30.0 * steps))
	check(game.marches._units.is_empty() and not game.shields.has(1), "arrival and shield expiry both settle within one 30 Hz frame")
	return Vector2(target.faction, target.population)

func _shield_boundaries() -> void:
	for arrival: float in [0.01, 0.025]:
		var results: Array[Vector2] = []
		for steps: int in [1, 10, 100]: results.append(_shield_case(arrival, steps))
		var before_expiry := arrival < 0.02
		for result: Vector2 in results:
			check(int(result.x) == (1 if before_expiry else 0), "shield protects only an arrival before its expiration")
			check(absf(result.y - (0.0 if before_expiry else 0.2)) < 0.00001, "shield boundary preserves the exact defender or attacker survivors")
		check(results[0].is_equal_approx(results[1]) and results[0].is_equal_approx(results[2]), "30 Hz and finer simulation agree on ownership and garrison")
	clean()
	game.shields[0] = 0.02; game.shields[1] = 0.03
	game.simulate(0.025)
	check(not game.shields.has(0) and absf(game.shields[1] - 0.005) < 0.000001, "independent shields expire at their own boundaries")
	game.set_match_paused(true, 5)
	game.simulate(1.0)
	check(absf(game.shields[1] - 0.005) < 0.000001, "global pause freezes the last shield interval")
	game.set_match_paused(false, 5)
	game.simulate(0.01)
	check(game.shields.is_empty(), "resuming consumes only actual remaining shield time")

func _exhausted_bear(faction: int = 0) -> WarBuilding:
	clean()
	for building: WarBuilding in game.buildings:
		building.faction = -1; building.kind = 3; building.population = 0.0
	var home: WarBuilding = game.by_id[0]
	home.faction = faction; home.kind = 1; home.population = 30.0
	game.by_id[1].faction = 1 - faction % 2; game.by_id[1].population = 0.5
	game.faction_skills[faction].commander = &"bear"
	game.faction_skills[faction].energy = 25.0
	check(game.begin_building_construction(home, -1, faction), "bear pays its last thirty soldiers for a tower upgrade")
	return home

func _toolbox_stalemates() -> void:
	for faction: int in [0, 1, 5]:
		var home := _exhausted_bear(faction)
		game.simulate(1.0 / 30.0)
		check(not game.finished and home.population == 0.0 and home.is_constructing, "available toolbox prevents a premature draw for any faction seat")
		check(game.cast_skill(0, home, faction) and home.population == 15.0, "player can recover fifteen real soldiers after the simulation frame")
		game._check_victory()
		check(not game.finished, "refunded soldiers keep the battle playable")
	var home := _exhausted_bear()
	game.faction_skills[0].energy = 24.5
	game.faction_skills[0].cooldowns[0] = 0.6
	game._check_victory()
	check(not game.finished, "energy and cooldown becoming ready before construction ends preserve recovery")
	game.simulate(0.6)
	check(game.cast_skill(0, home, 0) and home.population == 15.0, "the predicted recovery path is an actually legal cast")
	for unavailable: String in ["wrong_commander", "no_energy_in_time", "cooldown_at_completion", "no_receipt", "no_construction"]:
		home = _exhausted_bear()
		match unavailable:
			"wrong_commander": game.faction_skills[0].commander = &"rabbit"
			"no_energy_in_time": game.faction_skills[0].energy = 0.0
			"cooldown_at_completion": game.faction_skills[0].cooldowns[0] = home.construction_remaining
			"no_receipt": home.construction_cost = 0
			"no_construction": home.cancel_construction()
		game._check_victory()
		check(game.finished and game.winner_team == -1, "no feasible population recovery still ends in a draw: " + unavailable)
	home = _exhausted_bear()
	game.by_id[1].faction = -1
	game._check_victory()
	check(game.finished and game.winner_team == 0, "elimination takes priority over a potential toolbox refund")
	home = _exhausted_bear()
	game.simulate(10.0 + 1.0 / 30.0)
	check(game.finished and game.winner_team == -1 and not home.is_constructing,
		"declining the toolbox only postpones the draw until natural completion consumes its receipt")

func _toolbox_energy_boundaries() -> void:
	for recovery: String in ["disruption_ends", "energy_conversion_finishes"]:
		var home := _exhausted_bear()
		var supply: WarBuilding = game.by_id[2]
		supply.faction = 0
		if recovery == "disruption_ends":
			supply.begin_disruption(1.0)
		else:
			supply.kind = 2; supply.population = 20.0
			check(game.begin_building_construction(supply, 3, 0), "spare forge pays for energy conversion")
			supply.construction_remaining = 1.0
		game.faction_skills[0].energy = 12.0
		game._check_victory()
		check(not game.finished, "scheduled energy recovery preserves a real toolbox window: " + recovery)
		# One second at +1, then +1.5: Q becomes affordable at nine seconds,
		# before the empty tower completes its ten-second upgrade.
		game.simulate(9.1)
		check(home.is_constructing and game.cast_skill(0, home, 0) and home.population == 15.0,
			"predicted energy recovery permits the actual paid cast: " + recovery)
	var home := _exhausted_bear()
	var supply: WarBuilding = game.by_id[2]
	supply.faction = 0; supply.population = 20.0
	check(game.begin_building_construction(supply, 2, 0), "energy tower pays for conversion away from energy production")
	supply.construction_remaining = 1.0
	game.faction_skills[0].energy = 14.0
	game._check_victory()
	check(game.finished and game.winner_team == -1, "temporary current energy bonus cannot promise an impossible refund")
	home = _exhausted_bear()
	supply = game.by_id[2]
	supply.faction = 2
	game.faction_skills[0].energy = 15.0
	game._check_victory()
	check(game.finished and game.winner_team == -1, "a teammate's energy tower does not fund this commander's refund")
