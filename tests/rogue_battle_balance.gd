extends SceneTree
## Seeded, real-damage baseline. A simple assault order is not an expert player.
var game: Node3D
var results: Array[Dictionary] = []
var session: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(300.0, true, false, true).timeout.connect(func(): quit(3))
	session = root.get_node("Session")
	# Four times the native scheduling frequency keeps the simulation delta at 1/30.
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 4.0
	var kinds: Array = ["siege"] if "--siege-only" in OS.get_cmdline_user_args() else ["outpost", "siege"]
	var packs: Array = ["steady"] if "--steady-pair" in OS.get_cmdline_user_args() else ["steady", "ranged", "mobile"]
	for kind: String in kinds:
		for pack: String in packs:
			await _case(kind, pack)
	if "--growth" in OS.get_cmdline_user_args():
		await _case("siege", "steady", true)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 30
	print("ROGUE_BALANCE_RESULTS ", JSON.stringify(results))
	var result_file := FileAccess.open("res://artifacts/rogue_battle_balance_results.json", FileAccess.WRITE)
	result_file.store_string(JSON.stringify({"seed": 24681, "combat_seed": 24681, "strategy": "ranged", "active_defense": "--active-defense" in OS.get_cmdline_user_args(), "results": results}, "  "))
	result_file.close()
	quit()

func _case(kind: String, pack: String, growth: bool = false) -> void:
	if is_instance_valid(game):
		await game.prepare_shutdown()
	seed(24681)
	session.rogue.state = RogueRunState.new()
	session.rogue.state.start_new("ranged", pack, 24681)
	if growth:
		session.rogue.state.data.level = 2
		for i: int in 3:
			session.rogue.state._add_unit("archer", true)
	session.rogue.state.data.phase = "battle"
	session.rogue.state.data.battle_kind = kind
	change_scene_to_file("res://scenes/rogue/battle.tscn")
	await scene_changed
	game = current_scene
	game.camera_rig.edge_scroll = false
	while not game._match_ready:
		await process_frame
	game.skip_intro()
	var next_order: float = 0.0
	while not game.finished and game.elapsed < 420.0:
		if game.elapsed >= next_order:
			next_order += 3.0
			if kind == "outpost":
				_assault()
			elif "--active-defense" in OS.get_cmdline_user_args():
				_defend()
		await process_frame
	var record := {"battle": kind, "pack": pack, "growth": growth, "level": session.rogue.state.data.level,
		"population": session.rogue.state.population(), "population_cap": session.rogue.state.population_cap(), "won": game.finished and game.battle_won,
		"seconds": snappedf(game.elapsed, 0.1), "survivors": game.player_count(),
		"enemy_left": game.living_enemies(), "buildings_left": game.remaining_buildings(),
		"base_hp": snappedf(game.headquarters.hp, 0.1) if is_instance_valid(game.headquarters) else 0.0}
	results.append(record)
	print("ROGUE_BALANCE_CASE ", JSON.stringify(record))
	await game.prepare_shutdown()

func _defend() -> void:
	var visible: Array[BattleUnit] = []
	for enemy: BattleUnit in game.get_node("Units").get_children():
		if enemy.alive and enemy.owner_id == 1 and game.can_see_entity(0, enemy) and enemy.position.length() < 22.0:
			visible.append(enemy)
	for unit: BattleUnit in game.get_node("Units").get_children():
		if not unit.alive or unit.owner_id != 0:
			continue
		if unit.support.enabled():
			if is_instance_valid(unit.support.recipient):
				continue
			var recipient: BattleUnit
			for candidate: BattleUnit in game.get_node("Units").get_children():
				if unit.support.valid_target(candidate) and (recipient == null or candidate.hp / candidate.max_hp < recipient.hp / recipient.max_hp):
					recipient = candidate
			if recipient != null:
				unit.issue_support(recipient)
			continue
		if is_instance_valid(unit.target) and unit.target.alive:
			continue
		var nearest: BattleUnit
		for enemy: BattleUnit in visible:
			if nearest == null or unit.position.distance_squared_to(enemy.position) < unit.position.distance_squared_to(nearest.position):
				nearest = enemy
		if nearest != null:
			unit.issue_attack(nearest)

func _assault() -> void:
	var targets: Array[Node3D] = []
	for entity: Node3D in get_nodes_in_group("entities"):
		if entity.alive and entity.owner_id == 1:
			targets.append(entity)
	for unit: BattleUnit in game.get_node("Units").get_children():
		if not unit.alive or unit.owner_id != 0 or targets.is_empty():
			continue
		if unit.support.enabled():
			if is_instance_valid(unit.support.recipient):
				continue
			var ally: BattleUnit
			for candidate: BattleUnit in game.get_node("Units").get_children():
				if candidate.alive and candidate.owner_id == 0 and not candidate.support.enabled():
					if ally == null or candidate.position.x > ally.position.x:
						ally = candidate
			if ally != null and unit.position.distance_to(ally.position) > 4.0:
				unit.issue_move(ally.position - Vector3(3,0,0), true)
			continue
		if is_instance_valid(unit.target) and unit.target.alive:
			continue
		var target: Node3D = targets[0]
		for candidate: Node3D in targets:
			if candidate.position.distance_squared_to(unit.position) < target.position.distance_squared_to(unit.position):
				target = candidate
		unit.issue_move(target.position, true)
