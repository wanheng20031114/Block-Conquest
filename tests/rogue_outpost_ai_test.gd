extends SceneTree
## Native battle fixtures: no model substitutes and no persistent run/save writes.
const OutpostAI = preload("res://scripts/rogue/rogue_outpost_ai.gd")
var game: Node3D
var session: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	root.visible = false
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func frames(amount: int) -> void:
	for index: int in amount:
		await physics_frame
		await process_frame

func load_battle(emergency: bool = false, kind: String = "outpost") -> void:
	if is_instance_valid(game): await game.prepare_shutdown()
	session.rogue.state = RogueRunState.new()
	session.rogue.state.start_new("ranged", "steady", 72943)
	session.rogue.state.data.phase = "battle"
	session.rogue.state.data.battle_kind = kind
	session.rogue.state.data.emergency = emergency
	change_scene_to_file("res://scenes/rogue/battle.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_physics_process(false)
	game.camera_rig.edge_scroll = false
	await frames(3)

func ai_step(seconds: float) -> void:
	game.get_node("FogOfWar").tick(seconds)
	game.outpost_ai.tick(seconds)
	game.command_bus.tick()

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	session = root.get_node("Session")
	await load_battle()
	var ai: OutpostAI = game.outpost_ai
	ai.tick(100.0)
	check(ai._clock == 0.0 and game.enemy_total == 16, "intro prevents recruitment and AI decisions")
	check(ai is SkirmishBot and ai.producers.size() == 3, "outpost adapts the native PvE commander and three real barracks")
	game.skip_intro()
	game.get_node("Units").process_mode = Node.PROCESS_MODE_DISABLED
	game.get_node("Buildings").process_mode = Node.PROCESS_MODE_DISABLED
	var guard: BattleUnit = game.owned_entities(1, "units").filter(func(unit: BattleUnit): return unit.unit_type == "swordsman")[0]
	var shooter: BattleUnit = game.owned_entities(0, "units").filter(func(unit: BattleUnit): return unit.unit_type == "archer")[0]
	shooter.position = guard.position + Vector3(-10, 0, 0)
	shooter.reset_physics_interpolation()
	await frames(2)
	game.get_node("FogOfWar").tick(1.0)
	check(game.can_see_entity(1, shooter), "ranged attacker is legitimately visible to defending alliance")
	guard.receive_damage(1.0, shooter)
	check(guard.target == shooter and guard.order != BattleUnit.Order.HOLD, "native damage response acquires a shooter beyond melee reach")
	ai_step(1.0)
	check(ai.squads.filter(func(squad: Dictionary): return squad.state == "assist").size() >= 2, "nearby separate posts support a soldier under ranged attack")
	check(guard.order == BattleUnit.Order.ATTACK and guard.target == shooter, "PvE command validator accepts an actual counterattack")
	var before: Vector3 = guard.position
	guard.process_mode = Node.PROCESS_MODE_ALWAYS
	await frames(40)
	check(guard.position.distance_to(before) > 0.5, "counterattacking guard actually navigates toward shooter")
	guard.process_mode = Node.PROCESS_MODE_INHERIT
	# A hidden player cannot change the remembered search destination.
	shooter.position = Vector3(-48, 0, 25)
	await frames(2)
	ai_step(1.0)
	check(not ai._visible_enemies.has(shooter), "hidden shooter is removed from active target list")
	var memory: Vector3 = ai._memory[shooter.entity_id].position
	check(memory.distance_to(shooter.position) > 10.0, "enemy memory keeps the seen location instead of tracking hidden movement")
	ai_step(SkirmishBot.UNIT_MEMORY_SECONDS + 1.0)
	check(not ai._memory.has(shooter.entity_id), "stale unit observation expires using the PvE memory policy")
	check(ai.squads.any(func(squad: Dictionary): return squad.role == "scout" and squad.state == "search"), "scouts search authored lanes without seeing player positions")
	guard.receive_damage(1.0)
	ai_step(1.0)
	check(ai.squads.any(func(squad: Dictionary): return squad.role == "guard" and squad.state == "investigate") and not ai._memory.has(shooter.entity_id), "unseen artillery damage prompts bounded scouting without revealing the hidden shooter")
	ai_step(game.encounter.barracks_first_recruit_seconds - ai._clock + 0.1)
	ai_step(game.encounter.barracks_recruit_stagger_seconds)
	ai_step(game.encounter.barracks_recruit_stagger_seconds)
	ai_step(1.0)
	check(ai._reserve.units.size() == 3 and ai._reserve.role == "reserve", "three soldiers spread across barracks must still physically muster")
	var rank: int = 0
	for unit: BattleUnit in ai._reserve.units:
		unit.position = game.encounter.raid_muster_point + Vector3(rank * 2, 0, 0)
		rank += 1
	ai_step(1.0)
	check(ai._reserve.role == "raider" and ai._reserve.state == "search", "a gathered three-unit squad launches a real coordinated search")
	# Fresh scene isolates production from combat casualties and consumed clock.
	await load_battle(true)
	ai = game.outpost_ai
	game.skip_intro()
	game.get_node("Units").process_mode = Node.PROCESS_MODE_DISABLED
	game.get_node("Buildings").process_mode = Node.PROCESS_MODE_DISABLED
	var total: int = game.enemy_total
	ai_step(game.encounter.barracks_first_recruit_seconds - 0.1)
	check(game.enemy_total == total, "no reinforcements before configured opening grace period")
	paused = true
	var clock_before: float = ai._clock
	ai.tick(99.0)
	await create_timer(0.1, true).timeout
	check(ai._clock == clock_before and game.enemy_total == total, "pause freezes both tactical clock and barracks production")
	paused = false
	ai_step(0.11)
	check(game.enemy_total == total + 1 and game.enemy_reinforcements == 1, "first living barracks produces one dynamically counted soldier")
	var newborn: BattleUnit = game.owned_entities(1, "units").filter(func(unit: BattleUnit): return unit.has_meta("rogue_producer"))[0]
	check(is_equal_approx(newborn.max_hp, BalanceCatalog.unit(newborn.unit_type).hp * game.encounter.emergency_hp_multiplier), "produced units receive emergency HP growth")
	check(is_equal_approx(newborn._stats.damage, BalanceCatalog.unit(newborn.unit_type).damage * game.encounter.emergency_damage_multiplier), "produced units receive emergency attack growth")
	var origin: BattleBuilding = game.entities_by_id[int(newborn.get_meta("rogue_producer"))]
	check(newborn.position.distance_to(origin.position) > origin.radius and game.get_node("ConstructionNavigation").contains_walkable_point(newborn.position), "recruits use the real navigable barracks perimeter")
	check(ai._reserve.role == "reserve" and newborn.order == BattleUnit.Order.ATTACK_MOVE, "new soldier heads to muster point before a raid")
	check(not game.submit_local({"kind": "recruit", "target": origin.entity_id, "unit_type": "swordsman"}).ok and game.gold == 0, "enemy scenario production never enables player recruitment or income")
	var second: BattleBuilding = ai.producers[1].building
	second.receive_damage(second.hp)
	check(game.living_enemy_barracks() == 2, "destroyed barracks leaves active producer count")
	second.queue_free()
	await frames(2)
	ai_step(game.encounter.barracks_recruit_stagger_seconds + 0.1)
	check(game.enemy_total == total + 1, "destroyed and freed barracks cannot finish its scheduled recruit")
	ai_step(game.encounter.barracks_recruit_stagger_seconds + 0.1)
	check(game.enemy_total == total + 2, "another surviving barracks keeps producing independently")
	# Fill only to the configured living cap, then prove missed slots do not backlog.
	while game.living_enemies() < game.encounter.enemy_cap:
		game.spawn_unit("swordsman", 1, Vector3(45, 0, 25))
	var at_cap: int = game.enemy_total
	ai_step(game.encounter.barracks_recruit_interval * 3.0)
	check(game.enemy_total == at_cap, "full living cap skips elapsed recruitment slots without overflow")
	check(ai.squads.any(func(squad: Dictionary): return squad.role == "raider" and squad.state == "search"), "depleted reinforcements eventually search after bounded muster wait")
	newborn.receive_damage(newborn.hp)
	ai_step(1.0)
	check(game.enemy_total == at_cap, "opening one slot does not replay a backlog")
	ai_step(game.encounter.barracks_recruit_interval)
	check(game.living_enemies() == game.encounter.enemy_cap and game.enemy_total == at_cap + 1, "one available slot admits at most one recruit across all barracks")
	for building: BattleBuilding in game.get_node("Buildings").get_children():
		if building.alive: building.receive_damage(building.hp)
	game.check_victory()
	check(not game.finished and game.remaining_buildings() == 0, "all eight buildings destroyed is insufficient while current enemies live")
	var no_producers_total: int = game.enemy_total
	ai_step(100.0)
	check(game.enemy_total == no_producers_total, "destroying every barracks permanently stops reinforcements")
	for unit: BattleUnit in game.owned_entities(1, "units"): unit.receive_damage(unit.hp)
	game.check_victory()
	check(game.finished and game.battle_won, "clearing every currently living initial or produced enemy wins")
	ai.tick(100.0)
	check(game.enemy_total == no_producers_total, "finished battle cannot create reinforcements")
	await load_battle(false, "siege")
	check(game.outpost_ai == null and game.encounter.enemy_cap == 24, "siege retains its independent wave controller and original cap")
	await game.prepare_shutdown()
	print("ROGUE_OUTPOST_AI_TEST ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
