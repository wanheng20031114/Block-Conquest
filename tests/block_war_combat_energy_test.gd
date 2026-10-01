extends SceneTree
## Real battle events distinguish casualties from transfers, spell damage and spending.

var game: Node3D
var checks := 0
var failures: Array[String] = []
var initial_positions: Dictionary[int, Vector3] = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL COMBAT_ENERGY ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.00001, "%s: %s expected %s" % [label, actual, expected])

func energy_for(faction: int) -> float:
	return game.faction_skills[faction].energy

func set_stars(faction: int, stars: float) -> void:
	game.morale.adjust(faction, game.MORALE.points_for_stars(stars) - game.morale.points(faction))

func fixture() -> void:
	game.set_paused(false)
	game.set_process(false)
	game.marches.clear()
	game.projectiles.clear()
	game.shields.clear()
	game.fire_states.clear()
	game.world_effects.sync_fire_states(game.fire_states)
	game.bear = game.BEAR_SKILLS.new()
	game.elapsed = 0.0
	game.finished = false
	game.morale.configure(game.faction_count)
	for state: RefCounted in game.faction_skills:
		state.commander = &"squirrel"
		state.energy = 10.0
		state.cooldowns.fill(0.0)
		state.durations.fill(0.0)
		state.recruit_target_id = -1
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
		building.faction = building.building_id if building.building_id < 6 else -1
		building.kind = 0
		building.level = 1
		building.population = 100.0
		building.global_position = initial_positions[building.building_id]
		building.refresh_visual()
	game.select_building(null)

func regeneration() -> void:
	for faction: int in game.faction_count:
		near(energy_for(faction), 20.0, "every new faction starts with twenty energy")
	fixture()
	near(game.energy_regen_for(0), 1.0, "opening natural regeneration is one per second")
	game.simulate(0.25)
	near(energy_for(0), 10.25, "opening regeneration keeps fractional time")
	fixture()
	game.elapsed = 99.75
	game.simulate(0.5)
	near(energy_for(0), 10.75, "a frame crossing one hundred seconds integrates both rates")
	near(game.elapsed, 100.25, "crossing the rate boundary preserves all simulation time")
	near(game.energy_regen_for(0), 2.0, "natural regeneration is two after one hundred seconds")
	fixture()
	game.elapsed = 99.0
	game.simulate(1.0)
	near(energy_for(0), 11.0, "time ending exactly at one hundred still earned the opening rate")
	near(game.energy_regen_for(0), 2.0, "the displayed rate changes exactly at one hundred")
	game.simulate(0.5)
	near(energy_for(0), 12.0, "time beginning at one hundred uses the later rate")
	fixture()
	game.elapsed = 90.0
	game.energy = 0.0
	game.simulate(20.0)
	var whole: float = game.energy
	near(whole, 30.0, "one long interval gets ten opening plus twenty later energy")
	fixture()
	game.elapsed = 90.0
	game.energy = 0.0
	for step: int in 40:
		game.simulate(0.5)
	near(game.energy, whole, "partitioning time does not change regeneration")
	fixture()
	game.by_id[6].faction = 0
	game.by_id[6].kind = 3
	game.elapsed = 99.75
	game.simulate(0.5)
	near(energy_for(0), 11.0, "energy tower bonus remains additive across the boundary")
	near(energy_for(2), 10.75, "allies do not share the owner's tower bonus")
	fixture()
	game.elapsed = 99.0
	game.set_paused(true)
	game.simulate(5.0)
	near(game.elapsed, 99.0, "pause cannot advance the one-hundred-second threshold")
	near(game.energy, 10.0, "pause cannot regenerate energy")
	game.set_paused(false)
	game.set_process(false)
	game.simulate(2.0)
	near(game.energy, 13.0, "resume integrates only actual active time")
	game.energy = 99.9
	game.simulate(1.0)
	near(game.energy, 100.0, "natural regeneration retains the hundred-energy cap")
	game.energy = 10.0
	game.finished = true
	game.simulate(5.0)
	near(game.energy, 10.0, "finished battles do not regenerate")

func morale_brackets() -> void:
	var stars: Array[float] = [2.999, 3.0, 4.999, 5.0]
	var rates: Array[float] = [0.2, 0.15, 0.15, 0.1]
	for index: int in stars.size():
		fixture()
		set_stars(0, stars[index])
		var attacker_points: float = game.morale.points(0)
		var target: WarBuilding = game.by_id[1]
		game._on_unit_arrived(target.building_id, 0, 1.0)
		near(energy_for(0), 10.0 + rates[index], "attacker uses pre-fight %s-star bracket" % stars[index])
		near(energy_for(1), 10.0 + (100.0 - target.population) * 0.2, "defender uses its own morale bracket")
		near(game.morale.points(0), attacker_points - 10.0, "energy brackets do not change attacker morale penalty")
		near(game.morale.points(1), 10.0, "energy brackets do not change defender kill reward")
		fixture()
		set_stars(1, stars[index])
		target = game.by_id[1]
		var defender_points: float = game.morale.points(1)
		game._on_unit_arrived(target.building_id, 0, 1.0)
		near(energy_for(1), 10.0 + (100.0 - target.population) * rates[index], "defender uses pre-fight %s-star bracket" % stars[index])
		near(energy_for(0), 10.2, "attacker does not borrow the defender's lower rate")
		near(game.morale.points(1), minf(8000.0, defender_points + 10.0), "defender still receives its original morale reward")
	fixture()
	set_stars(0, 3.0)
	game._on_unit_arrived(1, 0, 1.0)
	check(game.morale.stars(0) < 3.0, "first attacker casualty really crosses below three stars")
	game._on_unit_arrived(1, 0, 1.0)
	near(energy_for(0), 10.35, "the following fight uses the newly lowered morale bracket")
	fixture()
	set_stars(1, 2.999)
	game._on_unit_arrived(1, 0, 1.0)
	check(game.morale.stars(1) >= 3.0, "first defensive kill really crosses above three stars")
	var before_energy := energy_for(1)
	var before_population: float = game.by_id[1].population
	game._on_unit_arrived(1, 0, 1.0)
	near(energy_for(1) - before_energy, (before_population - game.by_id[1].population) * 0.15, "following defense uses its newly raised bracket")

func ownership_and_fractional_losses() -> void:
	fixture()
	var target: WarBuilding = game.by_id[1]
	target.population = 0.3
	game._on_unit_arrived(1, 0, 1.0)
	check(target.faction == 0, "fractional garrison is captured")
	near(target.population, 0.7, "the surviving part of the attacker remains alive")
	near(energy_for(0), 10.06, "attacker receives energy for only its lost fraction")
	near(energy_for(1), 10.06, "old owner receives its fractional garrison loss")
	near(energy_for(2), 10.0, "teammate has no share in another player's casualties")
	fixture()
	target = game.by_id[1]
	target.population = 0.25
	game._on_unit_arrived(1, 0, 1.0, 1.0)
	near(target.population, 0.875, "attack buff changes survival without creating population")
	near(energy_for(0), 10.025, "overkill and attack bonuses are not counted as attacker deaths")
	near(energy_for(1), 10.05, "overkill cannot award more than the actual garrison")
	fixture()
	set_stars(1, 3.0)
	target = game.by_id[1]
	target.population = 0.4
	game._on_unit_arrived(1, 0, 1.0)
	check(target.faction == 0 and game.morale.stars(1) < 3.0, "capture changes ownership and drops the previous owner's morale bracket")
	near(energy_for(1), 10.06, "captured defender retains its pre-fight three-star rate")
	near(energy_for(0), 10.128, "captor receives only its own actual losses")
	fixture()
	target = game.by_id[6]
	target.population = 0.3
	game._on_unit_arrived(6, 0, 1.0)
	near(energy_for(0), 10.06, "attacking a neutral garrison compensates real own casualties")
	near(energy_for(1), 10.0, "neutral losses are not credited to another faction")
	fixture()
	game._on_unit_arrived(2, 0, 5.0)
	near(game.by_id[2].population, 105.0, "allied arrival transfers all soldiers to the recipient")
	near(energy_for(0), 10.0, "sending allied reinforcements grants no casualty energy")
	near(energy_for(2), 10.0, "receiving allied reinforcements grants no casualty energy")
	game._on_unit_arrived(2, 1, 1.0)
	near(energy_for(2), 10.2, "later garrison casualties belong to the receiving ally")
	near(energy_for(0), 10.0, "original sender cannot claim transferred garrison casualties")
	fixture()
	game.by_id[1].population = 0.3
	game._on_unit_arrived(1, 0, 1.0, 0.0, true)
	near(energy_for(0), 20.06, "energy-tower capture reward and real casualties each apply once")
	fixture()
	game.faction_skills[0].energy = 99.99
	game.faction_skills[1].energy = 99.99
	game._on_unit_arrived(1, 0, 1.0)
	near(energy_for(0), 100.0, "attacker casualty energy respects the cap")
	near(energy_for(1), 100.0, "defender casualty energy respects the cap")

func linked_pair() -> Array[WarBuilding]:
	fixture()
	var target: WarBuilding = game.by_id[1]
	var support: WarBuilding = game.by_id[6]
	support.faction = 1
	support.global_position = target.global_position + Vector3(10, 0, 0)
	game.faction_skills[1].commander = &"bear"
	game.faction_skills[1].energy = 100.0
	check(game.cast_skill(2, target, 1), "real bear skill establishes the casualty-sharing link")
	game.faction_skills[1].energy = 10.0
	return [target, support]

func linked_losses() -> void:
	var pair := linked_pair()
	game._on_unit_arrived(1, 0, 25.2)
	near(pair[0].population, 90.0, "linked target loses ten of twenty-one damage")
	near(pair[1].population, 89.0, "linked support really loses the odd extra soldier")
	near(energy_for(1), 14.2, "target and support losses award one combined real casualty total")
	near(energy_for(0), 15.04, "sharing does not duplicate attacking losses")
	pair = linked_pair()
	pair[1].population = 3.0
	game._on_unit_arrived(1, 0, 25.2)
	near(pair[0].population, 82.0, "exhausted support returns its unfunded damage share")
	near(pair[1].population, 0.0, "support loses only the three soldiers it actually held")
	near(energy_for(1), 14.2, "exhausting support cannot duplicate or omit casualties")
	pair = linked_pair()
	game.faction_skills[1].energy = 100.0
	check(game.cast_skill(3, pair[1], 1), "support can receive the defensive ward")
	game.faction_skills[1].energy = 10.0
	game._on_unit_arrived(1, 0, 25.2)
	near(pair[1].population, 89.0, "warded support still loses its assigned eleven soldiers")
	near(energy_for(1), 14.2, "all twenty-one real linked casualties grant energy exactly once")
	pair = linked_pair()
	game.bear.apply_damage(game, pair[0], 0.5)
	near(energy_for(1), 10.0, "fractional spell damage has no settled casualty")
	game._on_unit_arrived(1, 0, 0.6)
	near(pair[1].population, 99.0, "mixed spell and melee fractions settle one real support casualty")
	near(energy_for(1), 10.1, "spell remainder is excluded when melee settles mixed damage")
	near(energy_for(0), 10.12, "fractional attacker loss is still paid independently")
	pair = linked_pair()
	game._on_unit_arrived(1, 0, 0.6)
	near(energy_for(1), 10.0, "unsettled melee fraction does not pay for a nonexistent defender casualty")
	game.bear.apply_damage(game, pair[0], 0.5)
	near(energy_for(1), 10.1, "spell-triggered settlement preserves only the earlier melee share")
	pair = linked_pair()
	game.bear.apply_damage(game, pair[0], 0.75)
	game._on_unit_arrived(1, 0, 0.6)
	near(energy_for(1), 10.08, "first mixed casualty receives its proportional melee fraction")
	game.bear.apply_damage(game, pair[0], 0.75)
	near(energy_for(1), 10.1, "remaining melee fraction survives into a later settlement exactly once")

func excluded_damage_and_spending() -> void:
	var pair := linked_pair()
	game.start_fire(pair[0].global_position, 4.5, 0)
	game._tick_fire_buildings()
	near(pair[0].population, 90.0, "link defense reduces fire before target casualties")
	near(pair[1].population, 90.0, "reduced fire is shared without double defense")
	near(energy_for(1), 10.0, "direct fire and its shared damage grant no energy")
	near(energy_for(0), 10.0, "dealing spell damage grants no kill energy")
	pair = linked_pair()
	game.faction_skills[0].commander = &"fox"
	game.energy = 100.0
	check(game.cast_skill(0, pair[0]), "fox bomb uses the real paid skill path")
	near(pair[0].population + pair[1].population, 170.0, "fox bomb inflicts thirty actual shared casualties")
	near(energy_for(1), 10.0, "shared fox bomb casualties grant no energy")
	near(energy_for(0), 75.0, "fox pays its full cost without a damage refund")
	pair = linked_pair()
	game.faction_skills[0].commander = &"frog"
	game.energy = 100.0
	check(game.cast_skill(3, pair[0]), "frog strike uses the real paid skill path")
	near(pair[0].population, 20.0, "frog strike removes eighty percent of the target garrison")
	near(pair[1].population, 100.0, "frog strike bypasses linked support")
	near(energy_for(1), 10.0, "frog's direct casualties grant no energy")
	fixture()
	var route := PackedVector3Array([Vector3.ZERO, Vector3(20, 0, 0)])
	for tower_shot: bool in [true, false]:
		game.marches.send(0, 1, 0, 1, route)
		var targets: Array[WarMarches.MarchUnit] = game.marches.acquire_targets(Vector3.ZERO, 1, 10.0, 1)
		check(targets.size() == 1, "road casualty fixture has an exposed enemy")
		if targets.size() == 1:
			check(game.marches.hit_target(targets[0], Vector3.RIGHT, tower_shot), "tower or orb really kills the road soldier")
		near(energy_for(0), 10.0, "road projectile deaths grant no casualty energy")
		near(energy_for(1), 10.0, "road projectile kills grant no energy to their attacker")
	game.marches.send(0, 1, 0, 1, route)
	game.marches.ignite_at(Vector3.ZERO, 2.0, 0)
	check(game.marches.total_for(0) == 0, "friendly fire actually kills the fixture soldier")
	near(energy_for(0), 10.0, "friendly fire cannot be used to farm casualty energy")
	fixture()
	check(game.begin_building_construction(game.by_id[0], -1, 0), "upgrade really spends population")
	near(game.by_id[0].population, 95.0, "first residence upgrade debits five soldiers")
	near(energy_for(0), 10.0, "construction population cost grants no energy")
	fixture()
	check(game.issue_order(game.by_id[0], game.by_id[2], 25) == 25, "reinforcement really queues twenty-five soldiers at a supported dispatch percentage")
	game.marches.tick(0.1)
	check(game.by_id[0].population < 100.0, "at least one queued soldier really leaves the building")
	near(energy_for(0), 10.0, "departure population debit grants no energy")
	fixture()
	game.faction_skills[0].commander = &"fox"
	game.energy = 100.0
	game.by_id[6].faction = 1
	check(game.cast_skill(3, game.by_id[1]), "panic really moves the enemy garrison to its other buildings")
	near(game.by_id[1].population, 20.0, "panic removes eighty soldiers from the source without killing them")
	near(energy_for(1), 10.0, "panic population transfer grants no casualty energy")
	fixture()
	game.energy = 40.0
	check(game.cast_skill(0, game.by_id[0]), "recruitment uses the real paid skill path")
	game._tick_recruitment(6.0)
	near(game.by_id[0].population, 124.0, "recruitment creates twenty-four additional soldiers")
	near(energy_for(0), 10.0, "recruitment creates no immediate casualty refund")
	game._on_unit_arrived(1, 0, 24.0)
	near(energy_for(0), 14.8, "even losing all recruited soldiers returns only four-point-eight energy")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	var previous_commander: StringName = session.block_war_commander
	session.block_war_map_id = "islands"
	session.block_war_commander = &"squirrel"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.camera_rig.set_process(false)
	for building: WarBuilding in game.buildings:
		initial_positions[building.building_id] = building.global_position
	regeneration()
	morale_brackets()
	ownership_and_fractional_losses()
	linked_losses()
	excluded_damage_and_spending()
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	session.block_war_commander = previous_commander
	print("COMBAT_ENERGY ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
