extends SceneTree
## Real garrisons remain present until their soldiers actually leave the doorway.

var game: Node3D
var source: WarBuilding
var target: WarBuilding
var other: WarBuilding
var checks := 0
var failures: Array[String] = []
var burned := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL ", description)

func near(actual: float, expected: float, description: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: actual=%s expected=%s" % [description, actual, expected])

func reset_match(population: float = 80.0) -> void:
	if game != null:
		await game.prepare_shutdown()
	root.get_node("Session").block_war_map_id = "rift"
	root.get_node("Session").block_war_commander = &"squirrel"
	root.get_node("Session").block_war_opponent_commander = &"squirrel"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for building: WarBuilding in game.buildings:
		building.faction = -1
		building.kind = 0
		building.level = 1
		building.population = 1000.0
		building.refresh_visual()
	source = game.by_id[0]
	target = game.by_id[1]
	other = game.by_id[2]
	source.faction = 0
	source.kind = 2
	source.population = population
	target.faction = 1
	source.refresh_visual()
	target.refresh_visual()
	for state: RefCounted in game.faction_skills:
		state.energy = 0.0
	burned = 0
	game.marches.unit_defeated.connect(func(_at: Vector3, _heading: Vector3, faction: int, _impulse: Vector3, burning: bool):
		if faction == 0 and burning:
			burned += 1
	)

func check_garrison(initial: int, expected_exposed: int) -> void:
	var visible: int = game.marches.get_units().size()
	check(visible == expected_exposed, "only ranks that crossed the doorway are exposed")
	near(source.population + visible, initial, "physical garrison and visible army conserve soldiers")
	check(source.get_node("PopulationLabel").text == str(floori(source.population)), "badge changes in the departure frame")
	check(source.queued_population + visible == initial, "remaining reservations match concealed soldiers")
	check(game.total_for(0) == initial and game.team_total_for(0) == initial, "faction and team totals count each reserved soldier once")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(_timeout)
	await reset_match()
	check(game.issue_order(source, target, 100) == 80, "full command reserves eighty soldiers")
	check_garrison(80, 0)
	check(source.available_population == 0.0, "queued soldiers cannot receive a second order")
	game.marches.tick(0.02)
	check_garrison(80, 2)
	game.marches.tick(0.08)
	check_garrison(80, 6)
	game.marches.tick(0.3)
	check_garrison(80, 12)
	game.set_paused(true)
	game.simulate(5.0)
	check_garrison(80, 12)
	game.set_paused(false)
	game.marches.tick(4.0)
	check_garrison(80, 80)

	await reset_match(5.0)
	check(game.issue_order(source, target, 100) == 5, "odd small formation is accepted")
	check_garrison(5, 1)
	game.marches.clear()
	check(source.population == 4.0 and source.available_population == 4.0 and source.queued_population == 0, "clear releases concealed reservations without refunding the departed soldier")

	await reset_match()
	check(game.issue_order(source, target, 50) == 40, "first half command reserves forty")
	check(game.issue_order(source, other, 50) == 20, "second half uses the remaining forty")
	check(game.issue_order(source, target, 25) == 5, "quarter command uses the remaining twenty")
	check(game.issue_order(source, other, 100) == 15, "final command reserves the remaining fifteen")
	check(game.issue_order(source, target, 100) == 0, "repeated commands cannot duplicate reserved units")
	check(game.marches.incoming_for(target.building_id, 0) == 45 and game.marches.incoming_for(other.building_id, 0) == 35, "different destinations preserve their committed forces")
	check_garrison(80, 0)
	game.marches.clear()
	check(source.population == 80.0 and source.available_population == 80.0 and game.total_for(0) == 80, "clearing an untouched queue restores availability without adding soldiers")

	# A real casualty swaps the last array entry forward; later damage must still
	# cancel the newest order, preserving the older soldiers' destination.
	await reset_match(40.0)
	game.issue_order(source, target, 50)
	game.issue_order(source, other, 100)
	game.marches.tick(0.1)
	var victim: WarMarches.MarchUnit = game.marches._units[0]
	check(victim.is_exposed() and game.marches.hit_target(victim, Vector3.RIGHT), "an exposed casualty compacts the live march array")
	game._on_unit_arrived(source.building_id, 1, 20.0)
	check(source.population == 14.0 and source.queued_population == 14, "garrison casualties trim commitments to the surviving physical soldiers")
	check(game.marches.incoming_for(other.building_id, 0) == 0 and game.marches.incoming_for(target.building_id, 0) == 19, "damage cancels the newest destination despite compacted array order")
	game._on_unit_arrived(source.building_id, 1, 15.0)
	check(source.faction == 1 and source.queued_population == 0, "capture cancels all remaining departures before changing ownership")
	near(source.population, 1.0, "capture preserves the surviving attacker's strength")
	check(game.marches.total_for(0) == 5 and game.marches.get_units().size() == 5, "already departed soldiers survive the loss of their source")
	game.marches.tick(0.1)
	check(game.total_for(0) == 5, "captured source cannot create more soldiers for its old owner")
	near(source.population, 1.0, "captured source cannot pay for the old owner's queue")

	await reset_match(30.0)
	game.issue_order(source, target, 100)
	check(game.marches.get_units().is_empty() and source.queued_population == 30, "last-source capture fixture has no departed survivors")
	game._on_unit_arrived(source.building_id, 1, 31.0)
	game._check_victory()
	check(game.finished and source.faction == 1 and game.total_for(0) == 0 and game.marches.total_for(0) == 0, "cancelled departures cannot keep an eliminated faction alive")

	await reset_match(30.0)
	source.kind = 0
	source.refresh_visual()
	game.issue_order(source, target, 100)
	game.select_building(source)
	check(game.hud.get_node("%Upgrade").disabled and game.hud.get_node("%ConvertTower").disabled, "building action buttons reflect unreserved troops, not the larger physical badge")
	game.upgrade_selected()
	game.convert_selected(1)
	check(not source.is_constructing and source.population == 30.0, "upgrade and conversion cannot consume reserved defenders")
	var strategy: RefCounted = game.AI_STRATEGY.new(0)
	strategy.take_turn(game)
	check(not source.is_constructing and source.population == 30.0 and game.marches.total_for(0) == 30, "AI also cannot develop or dispatch using a committed garrison")

	await reset_match(60.0)
	game.faction_skills[0].commander = game.SKILL_RULES.RABBIT
	game.energy = 100.0
	game.issue_order(source, target, 50)
	var tunnel: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, source, other, 100)
	check(tunnel.count == 30, "rabbit plan only uses troops not committed to the ordinary queue")
	check(game.cast_skill(3, source) and game.issue_order(source, other, 100) == 30, "the next order reserves the uncommitted remainder for digging")
	check(source.population == 60.0 and source.queued_population == 60 and source.available_population == 0.0, "ordinary and tunnel queues both remain inside until real departures")
	check(game.total_for(0) == 60, "mixed tunnel and ordinary reservations conserve the army")
	check(game.RABBIT_SKILLS.burrow_plan(game, source, other, 100).is_empty(), "rabbit cannot borrow either set of reservations")
	game.marches.tick(tunnel.dig_duration + 0.01)
	var departed: int = game.marches.get_units().size()
	check(departed > 0 and source.queued_population > 0, "both departure systems progress while later tunnel ranks remain inside")
	game._on_unit_arrived(source.building_id, 1, source.population + 1.0)
	check(source.faction == 1 and source.queued_population == 0 and game.marches.total_for(0) == departed, "source capture cancels both pending queues and preserves departed travelers")
	var captured_population: float = source.population
	game.marches.tick(0.2)
	check(game.marches.total_for(0) == departed and source.population == captured_population, "canceled delayed tunnel ranks never debit the captured building")

	await reset_match()
	var route: PackedVector3Array = game.map.get_building_route(source, target)
	source.population -= 12.0
	game.marches.send(source.building_id, target.building_id, 0, 12, route)
	game.marches.tick(0.4)
	check(source.population == 68.0 and source.queued_population == 0 and game.total_for(0) == 80, "already paid direct transport never debits its source again")

	var fire_outcomes: Array[Vector3i] = []
	for small_steps: bool in [false, true]:
		await reset_match()
		game.issue_order(source, target, 100)
		game.faction_skills[1].energy = 100.0
		check(game.cast_ground_skill(3, source.global_position, 1), "hostile fire can strike a dispatching garrison")
		check(source.population == 55.0 and source.queued_population == 55 and burned == 0, "ignition damages the building once and trims concealed orders without outdoor casualties")
		if small_steps:
			for frame: int in 100:
				game.simulate(0.01)
		else:
			game.simulate(1.0)
		check(burned > 0 and game.marches.get_units().is_empty(), "soldiers become vulnerable to fire only after departure")
		near(source.population + burned, 55.0, "burned departures each debit the surviving garrison once")
		check(source.queued_population == int(source.population) and game.total_for(0) == int(source.population), "fire leaves no hidden duplicate soldiers in totals or reservations")
		check(source.get_node("PopulationLabel").text == str(floori(source.population)), "fire and departing ranks refresh the badge immediately")
		fire_outcomes.append(Vector3i(int(source.population), source.queued_population, burned))
	check(fire_outcomes[0] == fire_outcomes[1], "one long frame and a hundred small frames agree on fire casualties and garrisons")

	var production_outcomes: Array[Vector2] = []
	for small_steps: bool in [false, true]:
		await reset_match(30.0)
		source.kind = 0
		source.refresh_visual()
		game.issue_order(source, target, 100)
		if small_steps:
			for frame: int in 100:
				game.simulate(0.01)
		else:
			game.simulate(0.005)
			check(source.population == 30.0 and game.total_for(0) == 30, "a physically full residence cannot produce before its first departure")
			game.simulate(0.995)
		var physical_total: float = source.population + game.marches.get_units().size()
		check(physical_total > 30.98 and physical_total < 31.0, "residence resumes production only for time after the first soldier leaves")
		production_outcomes.append(Vector2(source.population, source.available_population))
	near(production_outcomes[0].x, production_outcomes[1].x, "frame partitioning preserves physical production")
	near(production_outcomes[0].y, production_outcomes[1].y, "frame partitioning preserves spendable production")
	await game.prepare_shutdown()
	print("BLOCK_WAR_DEPARTURE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _timeout() -> void:
	printerr("FAIL departure regression timed out")
	if game != null and not game._closing:
		await game.prepare_shutdown()
	quit(3)
