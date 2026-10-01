extends SceneTree
## Real capture, construction, projectiles, movement, pause and new-match state.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < .00001, "%s: %s / %s" % [label, actual, expected])

func reset() -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.morale.configure(game.faction_count)
	game.shields.clear()
	game.finished = false
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.kind = 0
		building.level = 1
		building.population = 30.0
		building.faction = building.building_id if building.building_id < 6 else -1
		game.tower_clocks[building.building_id] = 100.0
		building.refresh_visual()

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	check(game.faction_count == 6, "authored six-player battlefield")
	_captures()
	_combat()
	_interceptions()
	_movement()
	_idle_decay_in_battle()
	_combat_activity_and_decay()
	_ai_upgrades_without_combat()
	_construction_and_time()
	game.update_hud()
	await game.prepare_shutdown()
	root.get_node("Session").block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	check(game.faction_count == 2, "new match uses its own faction count")
	near(game.morale.points(0) + game.morale.points(1), 0.0, "new match never inherits morale")
	near(game.marches.base_speed(0), WarMarches.SPEED, "new match resets marching speed")
	await game.prepare_shutdown()
	print("BLOCK_WAR_MORALE ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _captures() -> void:
	for neutral: bool in [true, false]:
		for kind: int in 3:
			for tier: int in range(1, [4, 3, 1][kind] + 1):
				reset()
				var target: WarBuilding = game.by_id[6]
				target.faction = -1 if neutral else 1
				target.kind = kind
				target.level = tier
				target.population = 0.0
				game.morale.adjust(1, 1500.0)
				game._on_unit_arrived(6, 0, 1.0)
				check(target.faction == 0 and target.level == maxi(1, tier - 1), "capture retains native ownership and downgrade")
				near(game.morale.points(0), WarMorale.capture_reward(kind, tier, neutral), "capture reward uses the level before downgrade")
				near(game.morale.points(1), 1500.0 if neutral else 1500.0 - WarMorale.loss_penalty(kind, tier), "former owner alone pays loss penalty")
				near(game.morale.points(2), 0.0, "teammates have independent morale")

func _combat() -> void:
	reset()
	var target: WarBuilding = game.by_id[1]
	target.population = 100.0
	game.morale.adjust(0, 500.0)
	game.morale.adjust(1, 4000.0)
	near(game.combat_multiplier(0, target), 1.05 / 1.8, "attack and defense use each owner's whole-star multiplier")
	game._on_unit_arrived(1, 0, 10.0)
	near(target.population, 100.0 - 10.0 * 1.05 / 1.8, "real attack resolves the morale coefficient")
	near(game.morale.points(0), 400.0, "ten consumed attackers lose one hundred morale")
	near(game.morale.points(1), 4100.0, "defender gains ten points per incoming attacker killed")
	near(game.combat_multiplier(0, target), 1.0 / 1.8, "dropping below one star removes its bonus immediately")
	game._on_unit_arrived(2, 0, 4.0)
	near(game.morale.points(0), 400.0, "allied reinforcement is not a combat loss")
	near(game.morale.points(2), 0.0, "receiving allied troops awards no morale")
	reset()
	target.population = 2.0
	game.morale.adjust(0, 100.0)
	game.morale.adjust(1, 100.0)
	game._on_unit_arrived(1, 0, 5.0)
	near(target.population, 3.0, "surviving attackers enter captured building")
	near(game.morale.points(0), 180.0, "capture survivors are not charged as dead attackers")
	near(game.morale.points(1), 70.0, "defensive kills and lost building each settle once")
	reset()
	game.morale.adjust(0, 10.0)
	game.morale.adjust(1, 20.0)
	game.marches.send(0, 1, 0, 1, PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 1)]))
	game._simulate_step(.6)
	near(game.morale.points(0), 0.0, "real march arrival settles its attacking loss")
	near(game.morale.points(1), 30.0, "real march arrival settles defensive kill credit")
	near(game.morale.idle_seconds(0), 0.0, "new zero-capped combat event is not backdated")
	near(game.morale.idle_seconds(1), 0.0, "new defensive event is not backdated")
	near(game.morale.idle_seconds(2), .6, "unrelated faction still accumulates idle time")

func _interceptions() -> void:
	reset()
	var tower: WarBuilding = game.by_id[6]
	tower.kind = 1
	tower.faction = 0
	var at := tower.global_position + Vector3(4, 0, 0)
	game.morale.adjust(1, 200.0)
	game.marches.send(1, 0, 1, 1, PackedVector3Array([at, at + Vector3(0, 0, 10)]))
	game._fire_tower(tower)
	tower.faction = 1
	game._tick_projectiles(1.0)
	near(game.morale.points(0), 10.0, "shot remembers its firing faction after tower capture")
	near(game.morale.points(1), 190.0, "intercepted attacking soldier pays its loss")
	game._tick_projectiles(1.0)
	near(game.morale.points(0), 10.0, "dead projectile target cannot award a second kill")
	game.marches.send(1, 0, 1, 1, PackedVector3Array([at, at + Vector3(0, 0, 10)]))
	game.marches.ignite_at(at, .45, 0)
	near(game.morale.points(0), 20.0, "defensive fire attributes a hostile attacking casualty")
	near(game.morale.points(1), 180.0, "fire and tower use the same attacking-loss rule")
	game.morale.adjust(0, 100.0)
	game.marches.send(0, 1, 0, 1, PackedVector3Array([at, at + Vector3(0, 0, 10)]))
	game.marches.ignite_at(at, .45, 0)
	near(game.morale.points(0), 110.0, "own fire can cost an attacking soldier")
	near(game.morale.points(1), 180.0, "friendly fire does not gift defensive-kill credit")
	game.marches.send(1, 1, 1, 1, PackedVector3Array([at, at + Vector3(0, 0, 10)]))
	game.marches.ignite_at(at, .45, 0)
	near(game.morale.points(0), 110.0, "intercepting a transfer is not killing an attacker")
	near(game.morale.points(1), 180.0, "a reinforcement was not on an attack order")

func _movement() -> void:
	near(WarMarches.SPEED, 2.2, "default movement is 2.2 metres per second")
	var thresholds := [0.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]
	var speeds := [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]
	for level: int in thresholds.size():
		reset()
		game.by_id[0].kind = 2
		game.morale.adjust(0, thresholds[level])
		game.sync_environment_bonuses()
		game.marches.send(0, 1, 0, 1, PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 50)]))
		var unit: WarMarches.MarchUnit = game.marches._units[0]
		game.marches.tick(1.0)
		near(unit.distance, WarMarches.SPEED * speeds[level], "actual morale movement at level %d excludes forge speed" % level)
		near(game.marches.speed_multiplier(unit), speeds[level], "movement feedback at level %d excludes forge speed" % level)
		if level > 0:
			game.morale.adjust(0, -0.001)
			near(game.marches.base_speed(0), WarMarches.SPEED * speeds[level - 1], "falling below morale threshold %d immediately refreshes movement" % level)
	reset()
	var route := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 50)])
	game.morale.adjust(1, 4000.0)
	game.marches.send(0, 1, 0, 1, route)
	game.marches.send(1, 0, 1, 1, route)
	var ordinary: WarMarches.MarchUnit = game.marches._units[0]
	var charged: WarMarches.MarchUnit = game.marches._units[1]
	game.marches.tick(1.0)
	near(ordinary.distance, 2.2, "zero stars move exactly 2.2 metres in one actual simulation second")
	near(charged.distance, WarMarches.SPEED * 1.4, "four stars change actual route travel")
	game.morale.adjust(1, 4000.0)
	charged.rush_remaining = 2.0
	near(game.marches.movement_distance(charged, 1.0), WarMarches.SPEED * 1.5 * 2.0, "morale multiplies the existing rush skill")
	near(game.marches.speed_multiplier(charged), 3.0, "movement feedback matches real morale speed")
	near(game.marches.estimate_arrival_time(1, 50, 1, 1) * 1.5, game.marches.estimate_arrival_time(0, 50, 1, 0), "AI arrival estimator uses the selected owner's morale")
	game.marches.clear()
	game.marches.queue_departure(1, 0, 1, 12, route)
	var limit: float = game.marches.departure_step_limit()
	game.morale.adjust(1, -8000.0)
	near(game.marches.departure_step_limit(), limit * 1.5, "doorway timing changes with live morale")
	game.marches.clear()

func _check_fifth_star(faction: int, charge: float, label: String) -> void:
	var row: HBoxContainer = game.hud.get_node("%Balance").get_node("Stars/Faction%d" % faction)
	var fifth: TextureProgressBar = row.get_child(4)
	near(fifth.value, charge, label + ": actual HUD fifth-star charge")
	check(fifth.get_node("Glow").visible == (charge == 1.0), label + ": only a complete fifth star glows")

func _idle_decay_in_battle() -> void:
	for small_steps: bool in [false, true]:
		reset()
		for faction: int in game.faction_count:
			game.morale.adjust(faction, 8000.0)
		game.update_hud()
		for faction: int in game.faction_count:
			_check_fifth_star(faction, 1.0, "all six factions start at five stars")
		var previous := 0.0
		for sample: Vector3 in [Vector3(10.0, 7300.0, 0.825), Vector3(30.0, 5300.0, 0.325), Vector3(60.0, 3100.0, 0.0)]:
			var delta := sample.x - previous
			if small_steps:
				for step: int in roundi(delta * 10.0):
					game.simulate(0.1)
			else:
				game.simulate(delta)
			game.update_hud()
			for faction: int in game.faction_count:
				var label := "faction %d, idle %ds, short frames %s" % [faction, sample.x, small_steps]
				near(game.morale.points(faction), sample.y, label + ": real simulation settles idle decay")
				check(game.morale.level(faction) == (3 if sample.x == 60.0 else 4), label + ": bonuses use complete stars")
				_check_fifth_star(faction, sample.z, label)
			previous = sample.x

func _combat_activity_and_decay() -> void:
	for defender: int in [0, 1]:
		reset()
		game.morale.adjust(defender, 8000.0)
		for event: int in 3:
			game.marches.send(1 - defender, defender, 1 - defender, 1, PackedVector3Array([Vector3.ZERO, Vector3(0.1, 0, 0)]))
			game.simulate(4.0)
			near(game.morale.points(defender), 8000.0, "actual defensive casualties refresh capped morale for either team")
		check(game.marches._units.is_empty(), "every attacker has actually arrived before the quiet interval")
		game.update_hud()
		_check_fifth_star(defender, 1.0, "recent defensive casualty keeps the complete fifth star")
		game.simulate(5.0 - game.morale.idle_seconds(defender))
		near(game.morale.points(defender), 7800.0, "stopping real defensive kills restores decay at the exact idle deadline")
		check(game.morale.level(defender) == 4, "post-combat decay removes the fifth full bonus")
		game.update_hud()
		_check_fifth_star(defender, 0.95, "post-combat fifth star is partial and cannot glow")

func _ai_upgrades_without_combat() -> void:
	reset()
	game.elapsed = 0.0
	game.ai_clock = 3.0
	game.ai_enabled = true
	# A developed opponent can keep building during a ceasefire. The passive
	# human's garrison makes invasion unaffordable, isolating paid AI upgrades.
	game.by_id[0].population = 100000.0
	for building: WarBuilding in game.buildings:
		if building.building_id > 0:
			building.faction = 1
			building.population = 100.0
	for state: RefCounted in game.faction_skills:
		state.energy = 0.0
	game._ai_turn()
	game.simulate(9.0)
	game.morale.adjust(1, 8000.0)
	for sample: int in 3:
		game.simulate(10.0)
		check(game.marches._units.is_empty(), "AI economy-only scenario has no marching or fighting soldiers")
		near(game.morale.points(1), 8000.0, "staggered actual AI upgrades sustain full morale without combat")
		check(game.morale.idle_seconds(1) < 3.01, "completed AI construction refreshes the activity clock")
		game.update_hud()
		_check_fifth_star(1, 1.0, "actual construction activity can keep a full glowing fifth star")
	game.ai_enabled = false
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
	for state: RefCounted in game.faction_skills:
		state.recruit_target_id = -1
		state.durations.fill(0.0)
	game.simulate(5.0 - game.morale.idle_seconds(1))
	near(game.morale.points(1), 7800.0, "stopping construction as well as combat restores idle decay")
	game.update_hud()
	_check_fifth_star(1, 0.95, "the AI's fifth star becomes partial after all morale activity ends")

func _construction_and_time() -> void:
	reset()
	var house: WarBuilding = game.by_id[0]
	house.begin_construction()
	game.simulate(5.0)
	near(game.morale.points(0), 50.0, "actual completion gives first-upgrade reward")
	near(game.morale.idle_seconds(0), 0.0, "the five-second completion starts the new reward's idle clock")
	game.simulate(9.99)
	near(game.morale.points(0), 50.0, "fresh reward keeps its full idle grace")
	game.simulate(.01)
	near(game.morale.points(0), 40.0, "idle decay is wired into real simulation")
	house.begin_construction()
	house.advance_construction(10.0)
	near(game.morale.points(0), 140.0, "immediate native completion also rewards once")
	house.advance_construction(10.0)
	near(game.morale.points(0), 140.0, "completed construction cannot reward again")
	house.begin_construction(1)
	house.advance_construction(10.0)
	near(game.morale.points(0), 140.0, "conversion cannot farm upgrade rewards")
	house.begin_construction()
	house.cancel_construction()
	house.advance_construction(10.0)
	near(game.morale.points(0), 140.0, "cancelled upgrade awards nothing")
	game.morale.adjust(0, 7860.0)
	game.set_paused(true)
	game.simulate(20.0)
	near(game.morale.points(0), 8000.0, "pause freezes the morale clock")
	game.set_paused(false)
	game.simulate(5.0)
	near(game.morale.points(0), 7800.0, "five-star idle decay uses two hundred points")
	game.finished = true
	game.simulate(20.0)
	near(game.morale.points(0), 7800.0, "game over freezes morale")
