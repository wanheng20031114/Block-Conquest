extends "res://tests/block_war_ai_information_test.gd"
## The short-lived building debuff must support observed imminent attacks.

func fixture() -> void:
	reset()
	game.bear.locks.clear()
	game.bear.combat_damage_remainders.clear()
	game.faction_skills[1].commander = &"frog"
	game.faction_skills[1].cooldowns[0] = 0.0
	game.by_id[0].position = Vector3(-9, 0, 0)
	game.by_id[1].position = Vector3(9, 0, 0)
	game.sync_environment_bonuses()

func attackers(owner: int = 1, distance: float = 5.0, count: int = 20) -> void:
	var destination: Vector3 = game.by_id[0].global_position
	var first: int = game.marches._units.size()
	game.marches.send(1, 0, owner, count, PackedVector3Array([destination + Vector3(distance, 0, 0), destination]))
	for unit: WarMarches.MarchUnit in game.marches._units.slice(first):
		unit.distance = 0.0
		game.marches._update_pose(unit)

func decide() -> void:
	TACTICS.new(1).take_turn(game)

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
	for population_value: float in [1.0, 9999.0]:
		fixture()
		game.by_id[0].population = population_value
		attackers()
		decide()
		check(game.marches.weak_zones.has(1), "approaching attack earns building mist regardless of hidden garrison")
		check(game.marches.weak_zones[1].at.distance_to(game.by_id[0].global_position) < 0.001, "building center is a genuine siege candidate")
		near(game.skill_defense_bonus(game.by_id[0]), game.SKILL_RULES.FROG_BUILDING_DEFENSE, "chosen mist applies actual building defense reduction")
		near(game.faction_skills[1].energy, 100.0 - game.SKILL_RULES.FROG_COSTS[0], "siege mist pays ordinary cost")
		near(game.faction_skills[1].cooldowns[0], game.SKILL_RULES.FROG_COOLDOWNS[0], "siege mist uses ordinary cooldown")
	fixture()
	attackers(3)
	decide()
	check(game.marches.weak_zones.has(1), "AI mist also supports an ally's imminent attack")
	fixture()
	attackers(1, 16.0)
	decide()
	check(game.marches.weak_zones.is_empty(), "distant armies cannot spend a cloud that expires before arrival")
	fixture()
	game.by_id[0].population = 9999.0
	decide()
	check(game.marches.weak_zones.is_empty(), "a large hidden garrison alone does not trigger siege mist")
	fixture()
	attackers(1, 5.0, 3)
	decide()
	check(game.marches.weak_zones.is_empty(), "small patrols do not spend an entire siege cloud")
	fixture()
	game.by_id[0].faction = -1
	attackers()
	decide()
	check(game.marches.weak_zones.is_empty(), "neutral targets cannot justify enemy-only building reduction")
	fixture()
	attackers()
	game.marches.weak_zones[3] = {"at": game.by_id[0].global_position, "radius": game.SKILL_RULES.FROG_RADII[0], "remaining": 2.0}
	decide()
	check(not game.marches.weak_zones.has(1), "an allied cloud already weakening the target prevents redundant mist")
	fixture()
	attackers()
	game.marches.weak_zones[0] = {"at": game.by_id[0].global_position, "radius": game.SKILL_RULES.FROG_RADII[0], "remaining": 2.0}
	decide()
	check(game.marches.weak_zones.has(1), "the defender's own cloud does not block an effective attacking mist")
	fixture()
	attackers(1, 5.0, 24)
	game.faction_skills[0].commander = &"bear"
	game.faction_skills[0].cooldowns[3] = 0.0
	check(game.cast_skill(3, game.by_id[0], 0), "defended target fixture casts a real ward")
	decide()
	check(game.marches.weak_zones.has(1), "siege decision accounts for actual positive skill defense")
	near(game.skill_defense_bonus(game.by_id[0]), game.SKILL_RULES.BEAR_WARD_DEFENSE + game.SKILL_RULES.FROG_BUILDING_DEFENSE, "AI cloud reduces the ward's independent skill-defense group")
	for hidden: String in ["cloak", "queue", "dig"]:
		fixture()
		hidden_army(hidden, 30)
		decide()
		check(game.marches.weak_zones.is_empty(), "building-target expansion does not expose hidden " + hidden + " armies")
	fixture()
	attackers()
	game.faction_skills[1].energy = game.SKILL_RULES.FROG_COSTS[0] - 1.0
	decide()
	check(game.marches.weak_zones.is_empty(), "new tactical use still requires the full skill price")
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("FROG_SIEGE_AI ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
