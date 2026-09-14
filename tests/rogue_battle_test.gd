extends SceneTree
## Real encounter scenes cover navigation, immutable modifiers and separate victory rules.
var game: Node3D
var checks: int = 0
var failures: Array[String] = []
var session: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures.append(label)

func frames(amount: int) -> void:
	for i: int in amount:
		await physics_frame
		await process_frame

func load_battle(kind: String, emergency: bool = false) -> void:
	if is_instance_valid(game):
		await game.prepare_shutdown()
	session.rogue.state = RogueRunState.new()
	check(session.rogue.state.start_new("melee", "steady", 24681) == OK, "fixture run starts")
	session.rogue.state.data.phase = "battle"
	session.rogue.state.data.battle_kind = kind
	session.rogue.state.data.emergency = emergency
	change_scene_to_file("res://scenes/rogue/battle.tscn")
	await scene_changed
	game = current_scene
	game.camera_rig.edge_scroll = false
	while not game._match_ready:
		await process_frame
	await frames(5)

func _run() -> void:
	create_timer(75.0, true, false, true).timeout.connect(func(): quit(3))
	session = root.get_node("Session")
	await load_battle("outpost")
	check(game.remaining_buildings() == 8 and game.living_enemies() == 16, "outpost authors five towers, three barracks and sixteen defenders")
	check(game.player_count() == 15 and game.players[0].military_supply == 18, "stable roster deploys the entire eighteen-population army")
	check(game.get_node("IncomeTimer").is_stopped() and game.gold == 0, "encounter has no passive income")
	check(game.elapsed == 0.0 and game.get_node("Units").process_mode == Node.PROCESS_MODE_DISABLED, "intro freezes real simulation")
	var roster: Array = session.rogue.state.data.roster.duplicate(true)
	game.skip_intro()
	await frames(20)
	check(game.elapsed > 0.0 and not game.finished, "no player headquarters does not cause outpost defeat")
	game.handle_pause_action()
	var paused_time: float = game.elapsed
	await create_timer(0.1, true).timeout
	check(paused and game.elapsed == paused_time, "pause freezes the combat clock")
	game.handle_pause_action()
	var swordsman: BattleUnit = game.get_node("Units").get_children().filter(func(u: BattleUnit): return u.owner_id == 0 and u.unit_type == "swordsman")[0]
	check(is_equal_approx(swordsman._stats.damage, 9.9) and swordsman._stats.melee_armor == 3, "strategy affects effective damage and armor")
	check(BalanceCatalog.unit("swordsman").damage == 9 and BalanceCatalog.unit("swordsman").melee_armor == 2, "shared competitive definitions are immutable")
	var nav: RID = game.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, Vector3(-43,0,0), Vector3(29,0,4), true)
	check(path.size() > 1 and path[-1].distance_to(Vector3(29,0,4)) < 1.5, "native navigation connects western deployment to eastern defenses")
	var from: Vector3 = swordsman.position
	swordsman.issue_move(from + Vector3(5,0,0))
	await frames(50)
	check(swordsman.position.distance_to(from) > 0.8, "deployed soldier actually follows native path")
	var guarded: BattleUnit = game.get_node("Units").get_children().filter(func(u: BattleUnit): return u.owner_id == 1 and u.unit_type == "swordsman")[0]
	check(guarded.order == BattleUnit.Order.HOLD, "authored guards hold their post")
	game._command_searchers()
	check(game._searchers.any(func(u: BattleUnit): return u.order == BattleUnit.Order.ATTACK_MOVE), "search teams receive active pursuit route")
	for building: BattleBuilding in game.get_node("Buildings").get_children():
		building.receive_damage(building.hp)
	game.check_victory()
	check(not game.finished, "remaining enemies prevent premature building-only victory")
	for unit: BattleUnit in game.get_node("Units").get_children():
		if unit.alive and unit.owner_id == 1:
			unit.receive_damage(unit.hp)
	game.check_victory()
	check(game.finished and game.battle_won, "all buildings and defenders cleared wins outpost")
	check(session.rogue.state.data.roster == roster, "battle movement and casualties never mutate persistent formation")
	await load_battle("outpost", true)
	check(game.living_enemies() == 20, "emergency adds four defenders on the same map")
	var tower: BattleBuilding = game.get_node("Buildings").get_child(0)
	check(tower.max_hp == 450 and is_equal_approx(tower._stats.damage, 10.35), "emergency modifiers apply to encounter fortifications")
	game.skip_intro()
	for unit: BattleUnit in game.get_node("Units").get_children():
		if unit.owner_id == 0:
			unit.receive_damage(unit.hp)
	game.check_victory()
	check(game.finished and not game.battle_won, "outpost army elimination loses")
	await load_battle("siege")
	game.skip_intro()
	await frames(12)
	check(game.headquarters.max_hp == 1800 and game.headquarters._stats.damage == 24, "siege uses isolated central base balance")
	check(BalanceCatalog.building("headquarters").hp == 3000, "competitive headquarters is unchanged")
	session.rogue.state.data.level = 30
	for i: int in 50:
		game.spawn_unit("swordsman", 0, Vector3(18 + i % 5 * 2.0, 0, -15 + i / 5 * 2.5))
	game.select_army()
	var ids: Array = game.selected_ids()
	var commanded: Dictionary = game.command_bus.execute({"kind": "move", "units": ids, "at": [18,0,0]}, 0)
	check(ids.size() == 65 and game.command_unit_limit(0) >= 65 and commanded.ok, "upgraded population admits a real sixty-five-unit formation command")
	game.elapsed = 9.99
	await frames(2)
	check(game.wave_index == 1 and game.living_enemies() == 4, "first native fixed tick schedules four-sided wave")
	for i: int in 19:
		game.spawn_unit("spearman", 1, Vector3(-28 + i % 7 * 2.0, 0, 20 + i / 7 * 2.0))
	game._spawn_siege_wave(game.encounter.waves[6])
	check(game.living_enemies() == 24, "wave caps living enemies and discards overflow")
	for unit: BattleUnit in game.get_node("Units").get_children():
		if unit.owner_id == 0:
			unit.receive_damage(unit.hp)
	game.check_victory()
	check(not game.finished and game.headquarters.alive, "siege continues without surviving field troops")
	game.headquarters.receive_damage(game.headquarters.hp)
	check(game.finished and not game.battle_won, "headquarters death alone defeats siege")
	game._resolve_deadline()
	check(not game.battle_won, "deadline never overrides same-step base defeat")
	await load_battle("siege")
	await create_timer(6.1).timeout
	check(not game.intro_active and game.game_started, "native AnimationPlayer completion starts combat without skipping")
	game.wave_index = 7
	game.elapsed = 149.99
	await frames(3)
	check(game.finished and game.battle_won, "deadline with surviving base wins even if enemies need not be cleared")
	await game.prepare_shutdown()
	print("ROGUE_BATTLE_RESULT ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
