extends "res://tests/block_war_pig_test.gd"
## Generated soldiers share ordinary arrival combat and exact simulation timing.

func reset() -> void:
	super.reset()
	game._local_menu = false
	for building: WarBuilding in game.buildings:
		building.kind = 3
	game.sync_environment_bonuses()

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	session.block_war_map_id = "highland"
	session.block_war_commander = RULES.PIG
	session.block_war_opponent_commander = RULES.PIG
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false); game.camera_rig.set_process(false); game.ai_enabled = false
	for building: WarBuilding in game.buildings: positions[building.building_id] = building.position
	reset()
	var home: WarBuilding = game.by_id[0]
	var enemy: WarBuilding = game.by_id[1]
	var ally: WarBuilding = game.by_id[2]
	var neutral: WarBuilding = game.by_id[6]
	check(RULES.PIG_COSTS == [20.0, 35.0, 65.0, 80.0], "Deliberate opening charge and premium offensive airlift costs")
	game.energy = 64.0
	check(not game.cast_skill(2, home) and game.pig.airlifts.is_empty(), "Insufficient energy creates no free troops")
	refill()
	check(not game.cast_skill(2, null), "No building rejects cast")
	near(game.energy, 100, "Invalid cast does not spend energy")
	var total: int = game.total_for(0)
	check(game.cast_skill(2, home), "Airlift accepts own building")
	near(game.energy, 35, "E pays sixty-five energy once")
	check(not game.cast_skill(2, home), "Cooldown prevents repeated airdrops")
	check(game.pig.ready.is_empty() and game.marches._units.is_empty(), "E neither arms formation nor dispatches an army")
	check(game.total_for(0) == total + 40, "Generated airborne soldiers enter population exactly once")
	check(game.hud.get_node("%PlayerTotal").text == str(game.team_total_for(0)), "HUD alliance total includes airborne population at cast time")
	check(game.hud.get_node("%Balance").get_node("Totals/Faction0").text == str(total + 40), "HUD personal total includes pending soldiers")
	var debug: Dictionary = game.DEBUG_DATA.capture(game)
	check(debug.airlifting == 40 and debug.army_total == total + 40, "Debug panel counts pending airborne population separately")
	near(home.population, 70, "Cast does not prematurely put airborne troops inside")
	near(enemy.population, 70, "No other building supplies these troops")
	game.pig.advance(game, 0.399)
	near(home.population, 70, "No early landing before the first batch")
	game.pig.advance(game, 0.001)
	near(home.population, 78, "Eight troops land at exactly 0.4 seconds")
	check(game.pig.pending_for(0) == 32 and game.total_for(0) == total + 40, "First landing moves population rather than duplicating it")
	game.update_hud()
	check(game.hud.get_node("%Balance").get_node("Totals/Faction0").text == str(total + 40), "Landing transfers between airborne and garrison without a HUD population jump")
	for batch: int in range(2, 6):
		game.pig.advance(game, 0.4)
		near(home.population, 70 + batch * 8, "Wave %d enters in real batches" % batch)
		check(game.pig.pending_for(0) == 40 - batch * 8, "Wave %d retires airborne population" % batch)
	check(game.pig.airlifts.size() == 1 and game.pig.airlifts[0].landed == 40, "Final landing keeps its short visual tail")
	near(game.active_durations[2], 0, "Gameplay duration ends at two seconds")
	game.pig.advance(game, 0.181)
	check(game.pig.airlifts.is_empty() and home.population == 110, "Visual tail retires without more soldiers; reinforcement may exceed soft capacity")
	reset()
	game.cast_skill(2, ally)
	game.pig.advance(game, 2.3)
	check(ally.faction == 2 and ally.population == 110, "Ally receives forty soldiers without changing command")
	near(home.population, 70, "Allied airdrop has no source cost")
	reset()
	neutral.population = 5.0
	game.cast_skill(2, neutral)
	game.pig.advance(game, 0.4)
	check(neutral.faction == 0 and neutral.population > 0, "Neutral is captured by ordinary first-wave combat")
	var after_capture := neutral.population
	game.pig.advance(game, 1.6)
	near(neutral.population, after_capture + 32, "Remaining waves reinforce the captured building")
	reset()
	enemy.population = 5.0
	game.cast_skill(2, enemy)
	game.pig.advance(game, 0.4)
	check(enemy.faction == 0 and enemy.population > 0, "Enemy can be captured during a batch")
	after_capture = enemy.population
	game.pig.advance(game, 1.6)
	near(enemy.population, after_capture + 32, "Capture does not cancel the rest of an airdrop")
	reset()
	game.cast_skill(2, home)
	game.pig.advance(game, 0.4)
	home.faction = 1; home.population = 1.0
	game.sync_environment_bonuses()
	game.pig.advance(game, 0.4)
	check(home.faction == 0 and home.population > 0, "Troops follow current ownership after enemy takes target mid-flight")
	reset()
	game.shields[1] = 4.0
	var defended_damage: float = game.combat_multiplier(0, enemy)
	check(defended_damage < 1.0, "Shield fixture supplies real defense")
	game.cast_skill(2, enemy)
	game.pig.advance(game, 2.0)
	near(enemy.population, 70 - 40 * defended_damage, "Airlift respects ordinary building defense instead of removing forty garrison directly")
	reset()
	game.cast_skill(2, home)
	game.match_paused = true
	game.simulate(10.0)
	near(game.pig.airlifts[0].age, 0, "Pause freezes airdrop clock")
	near(home.population, 70, "Pause cannot land soldiers")
	game.match_paused = false
	game.simulate(2.2)
	near(home.population, 110, "A long frame lands exactly forty troops across internal boundaries")
	check(game.pig.airlifts.is_empty(), "Long frame also retires the effect")
	reset()
	game.cast_skill(2, home)
	for step: int in 220: game.simulate(0.01)
	near(home.population, 110, "Small frames agree with the long-frame outcome")
	reset()
	game.cast_skill(2, neutral)
	for building: WarBuilding in game.buildings:
		building.faction = 1
	neutral.population = 0.0
	game._check_victory()
	check(not game.finished, "Losing the last building does not eliminate forty airborne soldiers")
	game.simulate(0.4)
	check(not game.finished and neutral.faction == 0, "Pending airdrop can recover a building and keep the game alive")
	reset()
	game.cast_skill(2, enemy)
	for building: WarBuilding in game.buildings:
		building.faction = 1; building.population = 1000.0
	game.simulate(2.0)
	check(game.finished and game.winner_team == 1, "All failed landings resolve elimination despite the cosmetic tail")
	reset()
	game.cast_skill(2, neutral)
	refill(); game.cast_skill(2, neutral, 1)
	check(game.pig.pending_for(0) == 40 and game.pig.pending_for(1) == 40, "Opposing airdrops keep separate generated armies")
	game.pig.advance(game, 2.2)
	check(game.pig.airlifts.is_empty() and game.pig.pending_for(0) == 0 and game.pig.pending_for(1) == 0, "Concurrent opposing airdrops settle once without residual population")
	await game.prepare_shutdown()
	print("BLOCK_WAR_PIG_AIRLIFT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
