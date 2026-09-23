extends SceneTree
## Ally arrivals transfer command; combat, support and victory honor both teams.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	var player: WarBuilding = game.by_id[0]
	var ally: WarBuilding = game.by_id[2]
	var second_ally: WarBuilding = game.by_id[4]
	for building: WarBuilding in game.buildings:
		building.kind = 2
		building.refresh_visual()
	ally.level = 2
	ally.begin_construction()
	var team_total: int = game.team_total_for(0)
	check(game.issue_order(player, ally, 50) == 30, "the player can send a legal reinforcement to a teammate")
	check(game.total_for(0) == 60 and game.total_for(2) == 60, "soldiers in transit remain with their sender until arrival")
	# Advance only the actual marching system so construction and production cannot
	# obscure ownership or conservation in this transfer test.
	for step: int in 1200:
		game.marches.tick(0.05)
		if game.marches.total_for(0) == 0:
			break
	check(ally.faction == 2 and ally.population == 90.0 and ally.level == 2, "arrivals add to the recipient without capturing or downgrading its building")
	check(ally.is_constructing and ally.construction_remaining == 10.0, "receiving allied troops never interrupts the recipient's construction")
	check(game.total_for(0) == 30 and game.total_for(2) == 90 and game.team_total_for(0) == team_total, "arrival transfers personal strength while conserving the alliance's total")
	check(game.issue_order(ally, player, 100) == 0, "the player cannot command troops after they join an ally")
	game.select_building(ally)
	var before: float = ally.population
	game.upgrade_selected()
	game.convert_selected(0)
	check(ally.population == before and ally.kind == 2 and ally.construction_remaining == 10.0, "selecting a teammate never grants construction controls")
	check(game.hud.get_node("%Upgrade").disabled, "the native upgrade control is disabled for allied buildings")
	check(game.issue_order(ally, player, 50, 2) == 45, "the recipient AI can dispatch its combined army")
	for step: int in 1200:
		game.marches.tick(0.05)
		if game.marches.total_for(2) == 0:
			break
	check(player.population == 75.0 and player.faction == 0 and game.total_for(2) == 45, "reverse reinforcement transfers command back on arrival")
	check(game.issue_order(player, second_ally, 25) > 0, "returned troops can be commanded by the player again")
	game.marches.clear()
	ally.cancel_construction()
	for faction: int in 6:
		game.marches.send(faction, (faction + 1) % 6, faction, 6, PackedVector3Array([Vector3.ZERO, Vector3(8, 0, 0)]))
	game.marches.tick(0.5)
	for faction: int in 6:
		var targets: Array[WarMarches.MarchUnit] = game.marches.acquire_targets(Vector3(3, 0, 0), faction, 15.0, 1)
		check(targets.size() == 1 and game.FACTIONS.hostile(targets[0].order.faction, faction), "every faction's tower targets opponents and protects all allies")
	game.marches.clear()
	# Different opponents retain their own forge upgrades; incoming damage sums
	# those attack multipliers rather than treating every opponent as faction 1.
	game.by_id[1].level = 1
	game.by_id[3].level = 3
	game.marches.send(1, 0, 1, 10, PackedVector3Array([Vector3.ZERO, Vector3(8, 0, 0)]))
	game.marches.send(3, 0, 3, 10, PackedVector3Array([Vector3.ZERO, Vector3(8, 0, 0)]))
	var expected: float = (10 * game.attack_multiplier(1) + 10 * game.attack_multiplier(3)) / game.defense_multiplier(player)
	check(is_equal_approx(game.incoming_damage_for(player, game.marches.snapshot_incoming()), expected), "defense planning accounts for all hostile factions and their real bonuses")
	game.marches.clear()
	for building: WarBuilding in game.buildings:
		building.faction = -1
		building.kind = 0
		building.level = 1
		building.population = 1000.0
	player.faction = 0
	player.population = 10.0
	ally.faction = 2
	ally.level = 4
	ally.population = 80.0
	game.by_id[1].faction = 1
	game.by_id[1].population = 60.0
	check(game.issue_order(game.by_id[1], player, 50, 1) == 30, "a real hostile march threatens the human player's residence")
	var ally_strategy: RefCounted = game.AI_STRATEGY.new(2)
	ally_strategy.take_turn(game)
	check(game.marches.incoming_for(0, 2) > 0 and ally.population >= 14.0, "AI teammates relieve the human player's threatened home while keeping their own guard")
	check(game.marches.incoming_for(1, 2) == 0, "relief takes priority over a teammate opening another attack")
	game.marches.clear()
	game.energy = 100.0
	game.cooldowns.fill(0.0)
	check(game.cast_skill(0, ally), "the player can recruit directly into a teammate's residence")
	game.simulate(1.0)
	check(ally.population > 20.0 and game._recruit_target_id == ally.building_id, "recruitment stays with the allied recipient")
	game._cancel_recruitment()
	check(game.cast_skill(2, ally), "a teammate's building can receive the player's defensive shield")
	var ally_population: float = ally.population
	game._on_unit_arrived(ally.building_id, 4, 1.0)
	check(ally.population == ally_population + 1 and ally.faction == 2, "a second ally reinforces without taking over the first ally's building")
	player.faction = -1
	player.population = 0.0
	game._check_victory()
	check(not game.finished, "losing the human commander's own buildings does not eliminate living teammates")
	game.by_id[1].faction = -1
	game.marches.send(1, 3, 5, 1, PackedVector3Array([Vector3.ZERO, Vector3(8, 0, 0)]))
	game._check_victory()
	check(not game.finished, "the last opponent's marching survivor keeps the enemy alliance alive")
	game.marches.clear()
	game._check_victory()
	check(game.finished and game.hud.get_node("%ResultTitle").text == "胜利", "an allied survivor can win for an eliminated human commander")
	await game.prepare_shutdown()
	root.get_node("Session").block_war_map_id = "rift"
	print("BLOCK_WAR_TEAMS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
