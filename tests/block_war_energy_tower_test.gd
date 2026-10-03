extends SceneTree
## Paid conversions, per-player regeneration and real march capture rewards.

var game: Node3D
var checks := 0
var failures: Array[String] = []
var previous_map: String

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ENERGY_TOWER ", message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %s expected %s" % [message, actual, expected])

func fixture() -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.shields.clear()
	game.elapsed = 0.0
	game.finished = false
	game.set_process(false)
	game.morale.configure(game.faction_count)
	for state: RefCounted in game.faction_skills:
		state.energy = 10.0
		state.cooldowns.fill(0.0)
		state.durations.fill(0.0)
		state.recruit_target_id = -1
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
		building.faction = -1
		building.kind = 0
		building.level = 1
		building.population = 100.0
		building.refresh_visual()
	set_building(0, 0, 0, 80.0)
	set_building(1, 1, 0, 80.0)
	game.select_building(null)

func set_building(id: int, owner: int, kind: int, population: float = 80.0) -> WarBuilding:
	var building: WarBuilding = game.by_id[id]
	building.faction = owner
	building.kind = kind
	building.population = population
	building.refresh_visual()
	return building

func regeneration() -> void:
	var rates: Array[float] = [1.0, 1.5, 1.75, 1.9, 2.0, 2.1, 2.2]
	for count: int in rates.size():
		fixture()
		for index: int in count:
			set_building(index + 2, 0, 3)
		near(game.energy_regen_for(0), rates[count], "marginal tower bonuses at count %d" % count)
		game.simulate(0.5)
		near(game.energy, 10.0 + rates[count] * 0.5, "fractional time accrues exact energy at count %d" % count)
		near(game.faction_skills[1].energy, 10.5, "enemy does not share this player's towers")
		near(game.faction_skills[2].energy, 10.5, "ally does not share this player's towers")
	fixture()
	var tower := set_building(2, 0, 3)
	set_building(3, 2, 3)
	set_building(4, 2, 3)
	set_building(5, 1, 3)
	near(game.energy_regen_for(0), 1.5, "local player has one own tower")
	near(game.energy_regen_for(2), 1.75, "ally separately has two towers")
	near(game.energy_regen_for(1), 1.5, "enemy separately has one tower")
	near(game.attack_bonus(0), 0.0, "energy tower grants no forge attack bonus")
	near(tower.production_rate, 0.0, "energy tower produces no soldiers")
	game.energy = 99.8
	game.simulate(1.0)
	near(game.energy, 100.0, "energy regeneration respects the cap")
	game.energy = 10.0
	game.set_paused(true)
	game.simulate(3.0)
	near(game.energy, 10.0, "pause stops all regeneration")
	game.set_paused(false)
	game.set_process(false)
	tower.faction = 1
	tower.refresh_visual()
	near(game.energy_regen_for(0), 1.0, "losing a tower immediately removes its bonus")
	near(game.energy_regen_for(1), 1.75, "capturing a tower recomputes its new owner's marginal bonus")
	fixture()
	tower = set_building(2, 0, 3)
	tower.begin_disruption(0.75)
	game.simulate(1.0)
	near(game.energy, 11.125, "one long tick integrates the exact seal expiry")
	near(game.energy_regen_for(0), 1.5, "seal expiry restores the tower bonus")
	set_building(3, 0, 3)
	tower.begin_disruption(2.0)
	near(game.energy_regen_for(0), 1.5, "one active tower still receives the first marginal bonus")

func conversions() -> void:
	for kind: int in [0, 1, 3]:
		fixture()
		var source := set_building(0, 0, kind)
		check(not game.execute_network_command(0, {"type": "convert", "building": 0, "kind": 3}).accepted, "kind %d cannot directly convert to energy tower" % kind)
		near(source.population, 80.0, "rejected energy conversion spends no garrison")
	fixture()
	var forge := set_building(0, 0, 2)
	check(not game.begin_building_construction(forge, 3, 1), "another player cannot pay for this tower")
	check(game.begin_building_construction(forge, 3, 0), "only a forge accepts the paid energy conversion")
	near(forge.population, 75.0, "forge-to-energy conversion costs five soldiers")
	check(forge.construction_cost == 5 and forge.construction_remaining == 10.0, "five-soldier receipt retains the ten-second construction time")
	near(game.energy_regen_for(0), 1.0, "unfinished tower grants no bonus")
	near(game.attack_bonus(0), 0.3, "forge keeps its attack bonus during construction")
	game.simulate(10.0)
	check(forge.kind == 3 and forge.level == 1 and not forge.is_constructing, "conversion completes into a level-one energy tower")
	near(game.energy, 20.0, "completion grants no retroactive regeneration")
	near(game.attack_bonus(0), 0.0, "completed tower replaces the forge bonus")
	game.simulate(1.0)
	near(game.energy, 21.5, "completed tower increases subsequent regeneration")
	check(not game.begin_building_construction(forge, -1, 0), "energy tower cannot upgrade")
	check(forge.max_level == 1 and forge.upgrade_cost == 0, "energy tower has no upgrade tier or cost")
	for target_kind: int in [0, 1, 2]:
		fixture()
		var tower := set_building(0, 0, 3)
		var cost := 5 if target_kind == 2 else 20
		if target_kind != 2:
			tower.population = 19.0
			check(not game.begin_building_construction(tower, target_kind, 0), "energy-to-kind-%d still requires twenty soldiers" % target_kind)
			tower.population = 80.0
		check(game.begin_building_construction(tower, target_kind, 0), "energy tower can convert back to kind %d" % target_kind)
		near(tower.population, 80.0 - cost, "reverse conversion charges the correct cost for kind %d" % target_kind)
		check(tower.construction_cost == cost and tower.construction_remaining == 10.0, "reverse conversion records the cost and retains ten seconds")
		game.simulate(10.0)
		near(game.energy, 25.0, "outgoing conversion retains the energy bonus until completion")
		check(tower.kind == target_kind and tower.level == 1, "reverse conversion installs the requested base building")
		near(game.energy_regen_for(0), 1.0, "outgoing conversion removes the completed tower's bonus")
	for source_kind: int in [2, 3]:
		fixture()
		var source := set_building(0, 0, source_kind, 4.0)
		var target_kind := 3 if source_kind == 2 else 2
		check(not game.execute_network_command(0, {"type": "convert", "building": 0, "kind": target_kind}).accepted, "four soldiers cannot fund conversion from kind %d" % source_kind)
		near(source.population, 4.0, "insufficient conversion leaves the garrison unchanged")
		source.population = 5.0
		source.queued_population = 1
		check(not game.begin_building_construction(source, target_kind, 0), "queued soldiers cannot fund conversion from kind %d" % source_kind)
		source.queued_population = 0
		check(game.execute_network_command(0, {"type": "convert", "building": 0, "kind": target_kind}).accepted, "exactly five available soldiers fund conversion from kind %d" % source_kind)
		near(source.population, 0.0, "five-soldier conversion charges exactly the available garrison")
		check(source.construction_cost == 5 and source.construction_remaining == 10.0, "network command retains the discounted receipt and full duration")
	fixture()
	forge = set_building(0, 0, 2, 50.0)
	check(game.begin_building_construction(forge, 3, 0), "forge begins the energy conversion before capture")
	game._on_unit_arrived(0, 1, 100.0)
	check(forge.faction == 1 and forge.kind == 2 and not forge.is_constructing, "capture cancels unfinished energy conversion and retains forge type")
	near(game.energy_regen_for(1), 1.0, "unfinished captured tower adds no regeneration")

func capture_rewards() -> void:
	for count: int in [0, 1, 4]:
		fixture()
		for index: int in count:
			set_building(index + 3, 0, 3)
		var target := set_building(2, 1, 0, 0.0)
		game._on_unit_arrived(2, 0, 1.0, 0.0, true)
		check(target.faction == 0, "charged soldier captures enemy outpost")
		near(game.energy, 20.0, "capture reward stays ten regardless of current tower count %d" % count)
		game._on_unit_arrived(2, 0, 1.0, 0.0, true)
		near(game.energy, 20.0, "later soldiers reinforce without duplicate capture rewards")
	for defender: int in [-1, 0, 2]:
		fixture()
		set_building(2, defender, 0, 0.0)
		game._on_unit_arrived(2, 0, 1.0, 0.0, true)
		near(game.energy, 10.0, "neutral/own/allied entry earns no capture energy: %d" % defender)
	fixture()
	set_building(2, 1, 0, 10.0)
	game._on_unit_arrived(2, 0, 1.0, 0.0, true)
	near(game.energy, 10.2, "a fallen attacker earns combat energy but no tower capture reward")
	near(game.faction_skills[1].energy, 10.2, "the defender independently recovers energy for its lost garrison")
	set_building(2, 1, 0, 0.0)
	game._on_unit_arrived(2, 0, 1.0)
	near(game.energy, 10.2, "an ordinary survivor capturing an empty building adds no capture reward")
	game.energy = 96.0
	set_building(2, 1, 0, 0.0)
	game._on_unit_arrived(2, 0, 1.0, 0.0, true)
	near(game.energy, 100.0, "capture reward respects the hundred-point cap")
	fixture()
	set_building(2, 0, 3, 0.0)
	game._on_unit_arrived(2, 1, 1.0, 0.0, true)
	near(game.faction_skills[1].energy, 20.0, "enemy commander receives its own capture reward")
	near(game.energy, 10.0, "enemy capture never rewards the local player")
	near(game.energy_regen_for(1), 1.5, "captured energy tower supplies its new owner")

func march_provenance() -> void:
	for tunnel: bool in [false, true]:
		fixture()
		var source := set_building(0, 0, 3, 12.0)
		var target := set_building(2, 1, 0, 0.0)
		if tunnel:
			source.begin_burrow(15.0)
		check(game.issue_order(source, target, 100, 0) == 12, "real %s command departs from energy tower" % ("tunnel" if tunnel else "surface"))
		var order: WarMarches.MarchOrder = game.marches._units[0].order
		check(order.energy_origin, "departure records the energy origin")
		check(game.marches.return_order(order).energy_origin, "recall preserves the original energy source")
		source.kind = 2
		source.refresh_visual()
		game.marches.tick(200.0)
		check(target.faction == 0, "real incoming soldiers capture the enemy building")
		near(game.energy, 20.0, "source changing type after dispatch cannot erase the reward")
		check(game.issue_order(target, game.by_id[1], 100, 0) > 0, "captured outpost can issue another order")
		check(not game.marches._units[0].order.energy_origin, "garrison does not inherit energy provenance on a new non-tower order")
	fixture()
	var source := set_building(0, 0, 3, 1.0)
	var target := set_building(2, 1, 0, 0.0)
	game.issue_order(source, target, 100, 0)
	game.marches.tick(0.5)
	check(source.queued_population == 0, "capture-loss fixture has actually left the source")
	game._on_unit_arrived(0, 1, 100.0)
	game.marches.tick(200.0)
	check(target.faction == 0, "departed army survives loss of its original tower")
	near(game.energy, 20.0, "loss of the source tower does not cancel already-departed capture energy")

func ai_development() -> void:
	fixture()
	for building: WarBuilding in game.buildings:
		building.population = 1000.0
	for id: int in [1, 3]:
		var home := set_building(id, 1, 0, 20.0)
		home.level = 4
		home.refresh_visual()
	set_building(2, 1, 2, 100.0)
	set_building(4, 1, 2, 100.0)
	var strategy: RefCounted = game.AI_STRATEGY.new(1)
	strategy.take_turn(game)
	for building: WarBuilding in game.buildings:
		check(building.conversion_target != 3, "low energy at one decision does not trigger an investment")
	# Observe legal repeated spending over a full window before asking the real
	# development policy to choose and pay for its first tower.
	game.marches.clear()
	for id: int in [2, 4]:
		game.by_id[id].population = 100.0
	var state: RefCounted = game.faction_skills[1]
	state.commander = &"squirrel"
	state.energy = 100.0
	state.cooldowns.fill(0.0)
	strategy = game.AI_STRATEGY.new(1)
	strategy._economy.observe(game)
	# Include a complete observation window at the normal decision cadence.
	for time: int in range(3, 34, 3):
		game.simulate(3.0)
		strategy._economy.observe(game)
		var energy_before: float = state.energy
		if time == 3:
			check(game.cast_ground_skill(1, game.by_id[1].global_position, 1), "AI economy history starts with a paid support spell")
		elif time == 6:
			check(game.cast_skill(0, game.by_id[1], 1), "AI economy history includes paid recruitment")
		elif time == 9:
			check(game.cast_skill(2, game.by_id[1], 1), "AI economy history includes a paid shield")
		strategy._economy.record_spending(game.elapsed, maxf(0.0, energy_before - state.energy))
	strategy.take_turn(game)
	var conversions := 0
	for building: WarBuilding in game.buildings:
		if building.conversion_target == 3:
			conversions += 1
			check(building.kind == 2 and building.faction == 1, "AI uses its own forge as the only legal energy source")
			near(building.population, 95.0, "AI pays the same five-soldier conversion price")
	check(conversions == 1, "an established AI can invest a spare forge into one tower")
	game.simulate(10.0)
	check(game.forge_count(1) == 1 and game.energy_tower_count(1) == 1, "AI retains an attack forge while gaining energy regeneration")
	game.faction_skills[1].energy = 10.0
	strategy.take_turn(game)
	for building: WarBuilding in game.buildings:
		check(building.conversion_target != 3, "AI does not convert away its last attack forge")

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	previous_map = session.block_war_map_id
	session.block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.camera_rig.set_process(false)
	regeneration()
	conversions()
	capture_rewards()
	march_provenance()
	ai_development()
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("ENERGY_TOWER ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
