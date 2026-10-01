extends "res://tests/block_war_bear_test.gd"
## Real commands prove that lock cancels reservations and the hostile orb serves its caster.

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	await _lock_orders()
	await _lock_operations()
	await _hostile_ward()
	await game.prepare_shutdown()
	print("BEAR_REWORK checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _lock_orders() -> void:
	for mode: String in ["ordinary", "tunnel", "flight", "dense"]:
		await reset("highland")
		var source: WarBuilding = game.by_id[1]
		var target: WarBuilding = game.by_id[0]
		source.kind = 3
		source.population = 100.0
		var route: PackedVector3Array = game.dispatch_route(source, target)
		if mode == "tunnel":
			game.marches.queue_tunnel_departure(1, 0, 1, 45, route, 0.16, 1.0)
		else:
			if mode == "flight": route = game.flight_route(source, target)
			game.marches.queue_departure(1, 0, 1, 30 if mode == "flight" else 60, route, false, false, mode == "flight", mode == "dense")
		var queued := source.queued_population
		var population := source.population
		var outside: Array[WarMarches.MarchUnit] = []
		for unit: WarMarches.MarchUnit in game.marches._units:
			if not unit.pending_departure: outside.append(unit)
		check(queued > 0, mode + " fixture contains a real unexposed departure queue")
		check(game.cast_skill(1, source), mode + " W targets an enemy building")
		check(game.bear.is_locked(1) and source.queued_population == 0, mode + " W cancels every pending reservation")
		near(source.population, population, mode + " cancelled reservations remain in the real garrison")
		check(game.marches._units.size() == outside.size(), mode + " W only removes unexposed soldiers")
		for unit: WarMarches.MarchUnit in outside:
			check(unit.alive and unit in game.marches._units, mode + " already departed soldiers keep their identities")
		check(game.issue_order(source, target, 100, 1) == 0, mode + " locked building rejects a new command")
		refill()
		check(not game.cast_skill(1, source), mode + " overlapping lock is rejected without refreshing")
		near(game.energy, 100.0, mode + " rejected overlapping lock costs no energy")
		game.set_paused(true)
		game.simulate(3.0)
		near(game.bear.locks[1].remaining, RULES.BEAR_DURATIONS[1], mode + " pause freezes the lock")
		game.set_paused(false)
		game.simulate(RULES.BEAR_DURATIONS[1])
		check(not game.bear.is_locked(1) and source.queued_population == 0, mode + " expiration never restarts a cancelled order")
		near(source.population, population, mode + " old pending troops never leave automatically")
		check(game.issue_order(source, target, 25, 1) > 0, mode + " new commands work after expiration")

func _lock_operations() -> void:
	await reset("highland")
	var source: WarBuilding = game.by_id[1]
	source.kind = 0
	source.level = 2
	source.population = 10.0
	check(game.cast_skill(1, source), "W locks a producing residence")
	game.simulate(2.0)
	near(source.population, 10.0 + source.production_rate * 2.0, "locked residence keeps producing troops")
	var before := source.population
	game._on_unit_arrived(1, 3, 7.0)
	near(source.population, before + 7.0, "locked building still accepts allied reinforcement")
	check(game.begin_building_construction(source, -1, 1), "locked building can start a paid upgrade")
	var construction := source.construction_remaining
	game.simulate(1.0)
	near(source.construction_remaining, construction - 1.0, "lock does not stop construction")
	refill()
	check(not game.cast_skill(1, game.by_id[0]), "W rejects own buildings")
	check(not game.cast_skill(1, game.by_id[2]), "W rejects allied buildings")
	check(not game.cast_skill(1, game.by_id[6]), "W rejects neutral buildings")
	game._on_unit_arrived(1, 0, 300.0)
	check(source.faction == 0 and not game.bear.is_locked(1), "capture clears the old owner's lock")
	await reset("highland")
	source = game.by_id[1]
	source.kind = 1
	source.level = 1
	source.population = 100.0
	_orb_soldier(source, 6.0, 0)
	check(game.cast_skill(1, source), "W locks an enemy cannon tower")
	game.simulate(0.01)
	check(not game.projectiles.is_empty(), "locked tower continues shooting")

func _hostile_ward() -> void:
	await reset("highland")
	var target: WarBuilding = game.by_id[1]
	target.kind = 3
	target.population = 100.0
	var own := _orb_soldier(target, 17.0, 0)
	var ally := _orb_soldier(target, 16.0, 2)
	var enemies: Array[WarMarches.MarchUnit] = []
	for distance: float in [15.0, 14.0, 13.0, 12.0, 11.0, 10.0]:
		enemies.append(_orb_soldier(target, distance, 1))
	check(game.cast_skill(3, target), "R accepts an enemy building")
	check(game.bear.wards[1].hostile, "enemy R records a fixed hostile mode")
	near(game.skill_defense_bonus(target), -0.3, "enemy R applies minus thirty percent skill defense")
	near(game.combat_multiplier(0, target), 1.0 / 0.7, "enemy R increases real incoming combat damage")
	check(not game.shields.has(1), "enemy R never creates a protection shield")
	check(game.bear.shots.size() == 3, "enemy R immediately launches three fireballs")
	for shot: Dictionary in game.bear.shots:
		check(shot.target.order.faction == 1 and shot.target.intercepted_by == 0, "enemy-mounted fireball targets its caster's enemies")
	game.bear.advance(game, RULES.BEAR_HOSTILE_ORB_INTERVAL - 0.001)
	check(game.bear.shots.size() == 3, "enemy orb waits its precise shorter interval")
	game.bear.advance(game, 0.001)
	check(game.bear.shots.size() == 6, "enemy orb fires its second volley before the friendly interval")
	game.bear.tick_projectiles(game, 0.5)
	for soldier: WarMarches.MarchUnit in enemies: check(not soldier.alive, "enemy-mounted fireballs kill real enemy soldiers")
	check(own.alive and ally.alive, "enemy-mounted fireballs spare the caster and allies")
	game.shields[1] = 10.0
	near(game.skill_defense_bonus(target), -0.05, "enemy curse combines with an existing enemy protective skill")
	game._on_unit_arrived(1, 0, 19.0)
	near(target.population, 80.0, "stacked positive and negative defense use the same skill multiplier")
	game._on_unit_arrived(1, 0, 300.0)
	check(target.faction == 0 and not game.bear.wards.has(1), "capture clears the curse instead of converting it into a shield")
	near(game.active_durations[3], 0.0, "capture clears the caster's ultimate timer")
