extends SceneTree
## Own spell history and real building contracts drive a conservative investment.

const ECONOMY := preload("res://scripts/block_war/war_ai_economy.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")

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
		printerr("FAIL AI_ENERGY_POLICY ", message)

func fixture(commander: StringName = &"squirrel", initial_energy: float = 100.0) -> RefCounted:
	game.marches.clear()
	game.projectiles.clear()
	game.shields.clear()
	game.elapsed = 0.0
	game.finished = false
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.queued_population = 0
		building.faction = -1
		building.kind = 0
		building.level = 1
		building.population = 1000.0
		building.refresh_visual()
	set_building(0, 0, 0)
	for id: int in [1, 3]:
		set_building(id, 1, 0)
	for id: int in [2, 4]:
		set_building(id, 1, 2)
	var state: RefCounted = game.faction_skills[1]
	state.commander = commander
	state.energy = initial_energy
	state.cooldowns.fill(0.0)
	state.durations.fill(0.0)
	return ECONOMY.new(1)

func set_building(id: int, owner: int, kind: int) -> WarBuilding:
	var building: WarBuilding = game.by_id[id]
	building.faction = owner
	building.kind = kind
	building.population = 100.0
	building.refresh_visual()
	return building

func observe_trace(policy: RefCounted, casts: Dictionary, seconds: int = 30) -> void:
	# Legal costs and cooldowns, sampled at the AI's normal three-second cadence.
	policy.observe(game)
	var state: RefCounted = game.faction_skills[1]
	var costs: Array[float] = RULES.costs_for(state.commander)
	var cooldowns: Array[float] = RULES.cooldowns_for(state.commander)
	var started_at: float = game.elapsed
	for time: int in range(3, seconds + 1, 3):
		state.energy = minf(RULES.ENERGY_MAX, state.energy + RULES.natural_energy_between(game.elapsed, 3.0))
		game.elapsed = started_at + float(time)
		for index: int in state.cooldowns.size():
			state.cooldowns[index] = maxf(0.0, state.cooldowns[index] - 3.0)
		policy.observe(game)
		if casts.has(time):
			var skill: int = casts[time]
			check(state.energy >= costs[skill] and state.cooldowns[skill] <= 0.0, "sampled cast at %d seconds is affordable and ready" % time)
			state.energy -= costs[skill]
			state.cooldowns[skill] = cooldowns[skill]
			policy.record_spending(game.elapsed, costs[skill])

func prepare_demand() -> RefCounted:
	var policy := fixture()
	observe_trace(policy, {3: 1, 6: 0, 9: 2})
	return policy

func score(policy: RefCounted, building_id: int = 2, distance: float = 60.0) -> float:
	return policy.tower_score(game, game.by_id[building_id], 2, 8.0, distance, false)

func demand_history() -> void:
	var policy := fixture(&"squirrel", 10.0)
	check(score(policy) == 0.0, "low starting energy alone never buys a tower")
	observe_trace(policy, {})
	check(score(policy) == 0.0, "idle regeneration is not spell demand")
	policy = fixture(&"frog")
	observe_trace(policy, {15: 3})
	check(game.faction_skills[1].energy < ECONOMY.LOW_ENERGY, "one expensive ultimate leaves the test below the low-energy threshold")
	check(score(policy) == 0.0, "one expensive ultimate does not prove sustained demand")
	policy = fixture(&"frog", 20.0)
	game.elapsed = 100.0
	observe_trace(policy, {3: 0, 24: 0})
	check(score(policy) == 0.0, "cheap repeated casts covered by late base regeneration do not buy a tower")
	policy = fixture()
	observe_trace(policy, {3: 1, 6: 0, 9: 2}, 27)
	check(score(policy) == 0.0, "investment waits for a complete observation window")
	for repeat: int in 20:
		policy.observe(game)
	check(score(policy) == 0.0, "repeated decisions at the same time cannot invent observation history")
	policy = prepare_demand()
	check(score(policy) > 0.0, "repeated paid spells with lasting low reserves justify the first tower")
	game.elapsed += 3.0
	game.faction_skills[1].energy = 80.0
	policy.observe(game)
	check(score(policy) == 0.0, "a recovered energy reserve clears demand")
	policy = prepare_demand()
	for time: int in range(33, 67, 3):
		game.elapsed = float(time)
		game.faction_skills[1].energy = 10.0
		for index: int in 4:
			game.faction_skills[1].cooldowns[index] = maxf(0.0, game.faction_skills[1].cooldowns[index] - 3.0)
		policy.observe(game)
	check(score(policy) == 0.0, "expired spending history cannot support an indefinitely low energy sample")
	policy = prepare_demand()
	game.elapsed = 100.0
	policy.observe(game)
	check(score(policy) == 0.0, "a gap in observations cannot prove continuous demand")
	policy = prepare_demand()
	game.elapsed = 0.0
	policy.observe(game)
	check(score(policy) == 0.0, "rewinding to a new match clears past pressure")

func ownership_and_contracts() -> void:
	var policy := prepare_demand()
	var tower := set_building(6, 1, 3)
	check(score(policy) == 0.0, "one existing own tower satisfies the investment target")
	tower.begin_disruption(6.0)
	check(game.energy_tower_count(1) == 0, "sealed tower currently grants no regeneration")
	check(score(policy) == 0.0, "a temporary seal does not trigger a replacement tower")
	tower.clear_disruption()
	tower.faction = 3
	check(score(policy) > 0.0, "an ally's tower does not satisfy this player's energy needs")
	tower.faction = 0
	check(score(policy) > 0.0, "an enemy tower does not count as owned")
	policy = prepare_demand()
	var pending := set_building(6, 1, 2)
	check(game.begin_building_construction(pending, 3, 1), "first tower enters a normal paid construction contract")
	check(score(policy) == 0.0, "a pending tower prevents a parallel second purchase even with spare forges")
	pending.faction = 3
	check(score(policy) > 0.0, "an ally's pending tower does not block this player's investment")
	policy = prepare_demand()
	var leaving: WarBuilding = game.by_id[4]
	check(game.begin_building_construction(leaving, 0, 1), "the second forge is already paid to become a residence")
	check(game.forge_count(1) == 2, "both original forges still grant attack during construction")
	check(score(policy) == 0.0, "a forge already converting away cannot be the one retained for attack")
	policy = prepare_demand()
	game.by_id[4].faction = 3
	check(score(policy) == 0.0, "an ally's forge cannot replace the player's last own forge")
	var incoming := set_building(6, 1, 0)
	check(game.begin_building_construction(incoming, 2, 1), "a new forge has not finished its conversion")
	check(score(policy) == 0.0, "the last completed forge remains until its replacement really finishes")

func candidate_safety() -> void:
	var policy := prepare_demand()
	var candidate: WarBuilding = game.by_id[2]
	check(score(policy, 2, 60.0) > score(policy, 4, 10.0), "a rear forge outranks an otherwise equal front forge")
	check(policy.tower_score(game, candidate, 2, 8.0, 60.0, true) == 0.0, "incoming attackers rule out investment at this forge")
	check(policy.tower_score(game, candidate, 1, 8.0, 60.0, false) == 0.0, "one residence is too small an economy for the investment")
	candidate.population = 27.0
	check(score(policy) == 0.0, "conversion must leave the defensive garrison intact")
	candidate.population = 28.0
	check(score(policy) > 0.0, "exact conversion cost plus reserve is affordable")
	candidate.population = 100.0
	candidate.queued_population = 73
	check(score(policy) == 0.0, "queued departing troops cannot also pay for the tower")
	candidate.queued_population = 0
	candidate.faction = -1
	check(score(policy) == 0.0, "a neutral forge is not an investment candidate")
	candidate.faction = 1
	candidate.kind = 0
	check(score(policy) == 0.0, "a residence cannot skip the required forge stage")

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
	demand_history()
	ownership_and_contracts()
	candidate_safety()
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("AI_ENERGY_POLICY ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
