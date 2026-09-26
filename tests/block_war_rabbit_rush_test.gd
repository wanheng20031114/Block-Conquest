extends "res://tests/block_war_rabbit_test.gd"
## Snapshot ownership, moving buffs, exact expiry and real-soldier arrival damage.

const CENTER := Vector3(-22, 0, 10)

func soldier(faction: int, from: Vector3, to: Vector3, target_id: int) -> WarMarches.MarchUnit:
	var source: WarBuilding = home() if faction == 0 else (enemy() if faction == 1 else game.buildings[2])
	game.marches.send(source.building_id, target_id, faction, 1, PackedVector3Array([from, to]))
	return game.marches._units[-1]

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	await _snapshot_and_expiry()
	await _partition_and_haste()
	await _recall_keeps_rush()
	await _arrival_timing()
	await _projected_defense()
	await _real_population()
	await game.prepare_shutdown()
	print("BLOCK_WAR_RABBIT_RUSH checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _snapshot_and_expiry() -> void:
	await reset()
	check(not game.cast_ground_skill(0, CENTER), "empty rush is rejected")
	check(game.energy == 100.0 and game.cooldowns[0] == 0.0, "empty rush spends neither energy nor cooldown")
	var finish := CENTER + Vector3(80, 0, 0)
	var own := soldier(0, CENTER, finish, enemy().building_id)
	var boundary := soldier(0, CENTER + Vector3(0, 0, 2.4), finish, enemy().building_id)
	var outside := soldier(0, CENTER + Vector3(0, 0, 2.41), finish, enemy().building_id)
	var hostile := soldier(1, CENTER, finish, home().building_id)
	game.buildings[2].faction = 2
	var ally := soldier(2, CENTER, finish, enemy().building_id)
	var queued := soldier(0, CENTER, finish, enemy().building_id)
	queued.distance = -1.0
	var underground := soldier(0, CENTER, finish, enemy().building_id)
	underground.spawn_delay = 0.5
	var later := soldier(0, CENTER - Vector3(4, 0, 0), finish, enemy().building_id)
	# Give the later marcher its own already-exposed position, independently of the doorway queue.
	later.distance = 0.0
	game.marches._update_pose(later)
	var total: int = game.total_for(0)
	check(game.marches.rush_targets(0, CENTER, RULES.RABBIT_RUSH_RADIUS).size() == 2, "snapshot selects only exposed own units within the 2.4-metre boundary")
	check(game.cast_ground_skill(0, CENTER), "nonempty own squad receives rush")
	check(own.rush_remaining == 6.0 and boundary.rush_remaining == 6.0, "the center and exact boundary receive six seconds")
	for excluded: WarMarches.MarchUnit in [outside, hostile, ally, queued, underground, later]:
		check(excluded.rush_remaining == 0.0, "outside, other factions, concealed and later units are excluded from the snapshot")
	check(game.energy == 75.0 and game.cooldowns[0] == 24.0 and game.marches.haste_zones.is_empty(), "rush retains its cost and cooldown without creating a haste field")
	game.marches.tick(1.0)
	near(own.distance, 6.2, "a selected soldier continues at double speed after leaving the original circle")
	near(game.marches.speed_multiplier(own), 2.0, "rush travels with its soldier")
	near(game.marches.speed_multiplier(later), 1.0, "a later arrival into the old circle gains no rush")
	check(queued.rush_remaining == 0.0 and underground.rush_remaining == 0.0, "subsequent emergence cannot acquire the old snapshot")
	check(game.total_for(0) == total, "selecting and moving a rushed squad preserves real troop count")
	game.set_paused(true)
	game.simulate(20.0)
	near(own.rush_remaining, 5.0, "pause freezes the per-soldier duration")
	near(own.distance, 6.2, "pause freezes rushed movement")
	game.set_paused(false)
	game.marches.tick(5.0)
	near(own.rush_remaining, 0.0, "rush expires at exactly six simulation seconds")
	near(own.distance, 37.2, "all six seconds receive double speed")
	game.marches.tick(1.0)
	near(own.distance, 40.3, "movement returns to ordinary speed after expiry")

func _partition_and_haste() -> void:
	var distances: Array[float] = []
	for small_steps: bool in [false, true]:
		await reset()
		var unit := soldier(0, CENTER, CENTER + Vector3(80, 0, 0), enemy().building_id)
		check(game.marches.apply_rush(0, CENTER, 2.4, 6.0) == 1, "rush application reports the actual selected count")
		if small_steps:
			for frame: int in 80:
				game.marches.tick(0.1)
		else:
			game.marches.tick(8.0)
		distances.append(unit.distance)
		near(unit.rush_remaining, 0.0, "both frame partitions finish the buff")
	near(distances[0], 43.4, "a long tick integrates six boosted seconds and two ordinary seconds")
	near(distances[1], distances[0], "small and large ticks travel the same distance across expiry")
	await reset()
	var unit := soldier(0, CENTER, CENTER + Vector3(80, 0, 0), enemy().building_id)
	game.marches.create_haste_zone(0, CENTER, 100.0, 2.0, 1.6)
	game.marches.apply_rush(0, CENTER, 2.4, 0.25)
	game.marches.tick(1.0)
	near(unit.distance, 5.27, "overlapping rush and haste use the strongest speed, then retain haste after rush expires")

func _recall_keeps_rush() -> void:
	await reset()
	var route: PackedVector3Array = game.map.get_building_route(home(), enemy())
	game.marches.send(home().building_id, enemy().building_id, 0, 1, route)
	var unit: WarMarches.MarchUnit = game.marches._units[0]
	unit.distance = unit.order.length * 0.5
	game.marches._update_pose(unit)
	check(game.cast_ground_skill(0, unit.position), "a marching soldier can receive rush away from its source")
	game.marches.tick(0.5)
	var before: Vector3 = unit.position
	var total: int = game.total_for(0)
	unit.reserved = true
	check(game.cast_ground_skill(2, unit.position), "the rushed soldier can be recalled")
	check(game.marches._units[0] == unit and unit.reserved and unit.position.is_equal_approx(before), "recall retains identity, projectile lock and current position")
	near(unit.rush_remaining, 5.5, "recall preserves remaining rush without restarting it")
	near(game.marches.speed_multiplier(unit), 2.0, "return movement keeps rush speed")
	check(unit.order.target_id == home().building_id and game.total_for(0) == total, "recall keeps the original source and real troop count")

func _arrival_timing() -> void:
	for arrival_time: float in [5.9, 6.0, 6.1]:
		await reset()
		home().kind = 2
		var target := enemy()
		target.kind = 1
		target.level = 3
		target.population = 100.0
		game.shields[target.building_id] = 8.0
		var length := WarMarches.SPEED * (2.0 * minf(arrival_time, 6.0) + maxf(0.0, arrival_time - 6.0))
		soldier(0, CENTER, CENTER + Vector3(length, 0, 0), target.building_id)
		check(game.cast_ground_skill(0, CENTER), "arrival boundary receives a real six-second cast")
		game.marches.tick(7.0)
		var damage := 1.2 if arrival_time < 6.0 else 0.7
		near(target.population, 100.0 - damage, "arrival %.1fs adds rush and smithy bonuses before subtracting tower and shield defense" % arrival_time)
		check(game.marches.total_for(0) == 0, "arrival is processed once even when the tick spans buff expiry")

func _projected_defense() -> void:
	await reset()
	enemy().kind = 2
	home().kind = 1
	home().level = 3
	game.shields[home().building_id] = 8.0
	soldier(1, CENTER, CENTER + Vector3(30, 0, 0), home().building_id)
	game.marches.apply_rush(1, CENTER, 2.4, 6.0)
	near(game.incoming_damage_for(home(), game.marches.snapshot_incoming()), 1.2, "AI defense includes rush when a hostile soldier can arrive before expiry")
	game.marches.clear()
	soldier(1, CENTER, CENTER + Vector3(40, 0, 0), home().building_id)
	game.marches.apply_rush(1, CENTER, 2.4, 6.0)
	near(game.incoming_damage_for(home(), game.marches.snapshot_incoming()), 0.7, "AI defense excludes a rush bonus that expires before the hostile arrival")

func _real_population() -> void:
	await reset()
	var target := enemy()
	target.kind = 2
	target.population = 100.0
	game.marches.send(home().building_id, target.building_id, 0, 2, PackedVector3Array([CENTER, CENTER + Vector3(3, 0, 0)]))
	var first: WarMarches.MarchUnit = game.marches._units[0]
	var second: WarMarches.MarchUnit = game.marches._units[1]
	first.distance = 0.0
	game.marches._update_pose(first)
	second.distance = -3.0
	check(first.order == second.order and game.marches.apply_rush(0, first.position, 2.4, 6.0) == 1, "only the exposed soldier in a shared order receives rush")
	check(first.rush_remaining == 6.0 and second.rush_remaining == 0.0, "a queued soldier sharing the exact same order retains ordinary attack and speed")
	game.marches.tick(3.0)
	near(target.population, 97.5, "per-soldier arrivals apply 1.5 damage for the selected unit and 1 for the unselected rank")
	await reset()
	var ally: WarBuilding = game.buildings[2]
	ally.faction = 2
	ally.kind = 2
	ally.population = 10.0
	soldier(0, CENTER, CENTER + Vector3(3, 0, 0), ally.building_id)
	var team_total: int = game.team_total_for(0)
	check(game.cast_ground_skill(0, CENTER), "friendly reinforcement receives rush")
	game.marches.tick(1.0)
	near(ally.population, 11.0, "rushed friendly arrival reinforces exactly one real soldier")
	check(game.team_total_for(0) == team_total and game.marches.total_for(0) == 0, "friendly command transfer conserves alliance population")
	await reset()
	var neutral: WarBuilding = game.buildings[2]
	neutral.kind = 2
	neutral.population = 0.75
	soldier(0, CENTER, CENTER + Vector3(3, 0, 0), neutral.building_id)
	check(game.cast_ground_skill(0, CENTER), "fractional capture receives rush")
	game.marches.tick(1.0)
	check(neutral.faction == 0, "boosted damage can capture a neutral garrison")
	near(neutral.population, 0.5, "capturing survivor uses the original strength of one rather than boosted damage as population")
