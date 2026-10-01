extends "res://tests/block_war_ai_information_test.gd"
## Actual paid casts, public-information choices and the two ultimate roles.

func bear_fixture(skill: int, energy: float = 100.0) -> void:
	reset()
	game.bear.locks.clear()
	game.bear.combat_damage_remainders.clear()
	game.faction_skills[1].commander = &"bear"
	game.faction_skills[1].cooldowns[skill] = 0.0
	game.faction_skills[1].energy = energy
	game.by_id[0].position = Vector3(-9, 0, 0)
	game.by_id[1].position = Vector3(9, 0, 0)
	game.by_id[1].population = 80.0
	game.sync_environment_bonuses()

func exposed(source: int, target: int, owner: int, count: int, offset: Vector3 = Vector3.ZERO) -> void:
	var from: Vector3 = game.by_id[source].global_position + offset
	var to: Vector3 = game.by_id[target].global_position
	var first: int = game.marches._units.size()
	game.marches.send(source, target, owner, count, PackedVector3Array([from, to]))
	for unit: WarMarches.MarchUnit in game.marches._units.slice(first):
		unit.distance = 0.0
		game.marches._update_pose(unit)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	session.block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	_upgrade_choices()
	_lock_choices()
	_ward_choices()
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("BEAR_AI_REWORK ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _upgrade_choices() -> void:
	bear_fixture(0, game.SKILL_RULES.BEAR_COSTS[0])
	game.by_id[1].population = 0.0
	TACTICS.new(1).take_turn(game)
	check(game.by_id[1].level == 2, "funded bear upgrades an empty idle residence")
	near(game.by_id[1].population, 0.0, "AI instant upgrade does not invent or spend soldiers")
	near(game.faction_skills[1].energy, 0.0, "funded upgrade pays exactly its affordable cost")
	near(game.faction_skills[1].cooldowns[0], game.SKILL_RULES.BEAR_COOLDOWNS[0], "AI uses ordinary Q cooldown")
	bear_fixture(0)
	check(game.begin_building_construction(game.by_id[1], -1, 1), "paid upgrade fixture begins")
	var paid: float = game.by_id[1].population
	TACTICS.new(1).take_turn(game)
	check(game.by_id[1].level == 2 and not game.by_id[1].is_constructing, "AI completes a paid upgrade exactly once")
	near(game.by_id[1].population, paid, "AI does not budget a removed construction refund")
	bear_fixture(0)
	game.by_id[1].level = 4
	var ally := set_building(3, 3, 1, 2, 50.0)
	TACTICS.new(1).take_turn(game)
	check(ally.level == 3 and ally.population == 50.0, "AI upgrades a teammate's idle tower")
	bear_fixture(0)
	check(game.begin_building_construction(game.by_id[1], 1, 1), "conversion fixture begins")
	TACTICS.new(1).take_turn(game)
	check(game.faction_skills[1].cooldowns[0] == 0.0, "AI refuses conversion targets")

func _lock_choices() -> void:
	bear_fixture(1)
	var route := PackedVector3Array([game.by_id[0].global_position, game.by_id[1].global_position])
	game.marches.queue_departure(0, 1, 0, 50, route)
	game.simulate(0.6)
	var departed := 0
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.is_exposed(): departed += 1
	check(departed >= 4 and game.by_id[0].queued_population > 0, "source has a visible column and an unfinished queue")
	var population: float = game.by_id[0].population
	TACTICS.new(1).take_turn(game)
	check(game.bear.is_locked(0), "visible doorway column makes its enemy source a W target")
	check(game.by_id[0].queued_population == 0 and game.marches.total_for(0) == departed, "AI W cancels only soldiers still inside")
	near(game.by_id[0].population, population, "cancelled queue preserves garrison population")
	near(game.faction_skills[1].cooldowns[1], game.SKILL_RULES.BEAR_COOLDOWNS[1], "AI W routes through a paid building cast")
	for hidden: String in ["cloak", "queue", "dig"]:
		bear_fixture(1)
		hidden_army(hidden, 30)
		TACTICS.new(1).take_turn(game)
		check(game.bear.locks.is_empty() and game.faction_skills[1].energy == 100.0, "W ignores hidden " + hidden + " information")
	for population_value: float in [1.0, 9999.0]:
		bear_fixture(1)
		game.by_id[0].population = population_value
		exposed(0, 1, 0, 8)
		TACTICS.new(1).take_turn(game)
		check(game.bear.is_locked(0), "same public column produces same W decision despite hidden garrison")
	bear_fixture(1)
	exposed(0, 1, 0, 10)
	for unit: WarMarches.MarchUnit in game.marches._units:
		unit.distance = 8.0
		game.marches._update_pose(unit)
	TACTICS.new(1).take_turn(game)
	check(game.bear.locks.is_empty(), "distant departed troops do not justify locking an old source")

func _ward_choices() -> void:
	bear_fixture(3)
	game.by_id[1].population = 10.0
	exposed(0, 1, 0, 24, Vector3(12, 0, 0))
	TACTICS.new(1).take_turn(game)
	check(game.bear.wards.has(1) and not game.bear.wards[1].hostile, "R prioritizes a threatened friendly building")
	near(game.skill_defense_bonus(game.by_id[1]), game.SKILL_RULES.BEAR_WARD_DEFENSE, "defensive AI ultimate grants the real defense bonus")
	near(game.faction_skills[1].energy, 100.0 - game.SKILL_RULES.BEAR_COSTS[3], "defensive ultimate pays the global cost")
	bear_fixture(3)
	exposed(1, 0, 1, 24, Vector3(-12, 0, 0))
	TACTICS.new(1).take_turn(game)
	check(game.bear.wards.has(0) and game.bear.wards[0].hostile, "R weakens the enemy destination ahead of a real assault")
	near(game.skill_defense_bonus(game.by_id[0]), game.SKILL_RULES.BEAR_CURSE_DEFENSE, "offensive AI ultimate applies actual negative defense")
	check(game.bear.wards[0].faction == 1, "enemy-building fireball retains the caster's side")
	for hidden: String in ["cloak", "queue", "dig"]:
		bear_fixture(3)
		hidden_army(hidden, 30)
		TACTICS.new(1).take_turn(game)
		check(game.bear.wards.is_empty(), "R cannot select an offensive location using " + hidden + " enemies")
	bear_fixture(3, game.SKILL_RULES.BEAR_COSTS[3] - 1.0)
	exposed(1, 0, 1, 24, Vector3(-12, 0, 0))
	TACTICS.new(1).take_turn(game)
	check(game.bear.wards.is_empty(), "new ultimate cost is respected by offensive AI")
	bear_fixture(3)
	game.by_id[1].population = 10.0
	exposed(0, 1, 0, 24, Vector3(12, 0, 0))
	game.set_paused(true)
	TACTICS.new(1).take_turn(game)
	check(game.bear.wards.is_empty(), "paused AI cannot cast the reworked ultimate")
	game.set_paused(false)
