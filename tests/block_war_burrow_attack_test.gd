extends "res://tests/block_war_rabbit_test.gd"
## Exercise actual departures and arrivals: a tunnel boosts damage, never population.

func stable(map_id: String = "rift") -> void:
	await reset(map_id)
	# No production, forge bonuses or tower projectiles obscure the skill's damage.
	for building: WarBuilding in game.buildings:
		building.kind = 3
		building.level = 1
		building.population = 100.0
	game.sync_environment_bonuses()

func launch(target: WarBuilding, count: int = 6) -> float:
	home().population = count
	var plan: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, home(), target, 100)
	check(not plan.is_empty(), "a real map route supports the tunnel")
	check(game.cast_skill(3, home()), "R arms the source through the paid skill path")
	check(game.issue_order(home(), target, 100) == count, "the next building command reserves the requested real soldiers")
	return plan.dig_duration

func squad_center() -> Vector3:
	var center := Vector3.ZERO
	var count := 0
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.is_exposed():
			center += unit.position
			count += 1
	assert(count > 0)
	return center / count

func finish_marches() -> void:
	# Long enough for a recalled full-map surface journey, without producing troops.
	game.marches.tick(120.0)

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	await _real_dispatch_and_followup()
	await _skill_groups()
	await _friendly_population()
	await _capture_survivors()
	await _recall()
	await _conversion()
	await _surrender()
	await _cancelled_departures()
	await _short_tunnels()
	await _frame_partitions()
	await game.prepare_shutdown()
	print("BLOCK_WAR_BURROW_ATTACK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _real_dispatch_and_followup() -> void:
	await stable()
	var target := enemy()
	var dig := launch(target, 12)
	check(home().population == 12.0 and home().queued_population == 12, "digging reserves soldiers without debiting or multiplying them")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(unit.order.rabbit_burrow and unit.order.strength == 1.0, "tunnel provenance carries attack independently of one-person strength")
	game.marches.tick(dig - 0.01)
	near(target.population, 100.0, "hidden reservations cause no damage before emergence")
	check(game.marches.get_units().is_empty(), "digging exposes no attacking soldiers")
	game.marches.tick(0.011)
	check(home().population == 6.0 and home().queued_population == 6, "the first six emerge and debit exactly six soldiers")
	finish_marches()
	near(target.population, 82.0, "twelve real tunnel arrivals deal eighteen damage")
	check(home().population == 0.0 and home().queued_population == 0 and game.marches.total_for(0) == 0, "completed assault leaves neither duplicated population nor hidden reservations")
	home().population = 6.0
	check(game.issue_order(home(), target, 100) == 6, "later ordinary command remains usable after the consumed enchantment")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(not unit.order.rabbit_burrow, "later departures cannot inherit a spent tunnel's attack")
	finish_marches()
	near(target.population, 76.0, "ordinary follow-up deals six damage rather than nine")
	await stable()
	target = enemy()
	home().population = 70.0
	check(game.cast_skill(3, home()) and game.issue_order(home(), target, 100) == 50, "attack boost keeps the fifty-person tunnel limit")
	finish_marches()
	near(home().population, 20.0, "seventy-person source retains the twenty unselected soldiers")
	near(target.population, 25.0, "the fifty-person limit still permits exactly seventy-five damage")

func _skill_groups() -> void:
	for rush: bool in [false, true]:
		for mist: bool in [false, true]:
			await stable()
			var target := enemy()
			var dig := launch(target)
			game.marches.tick(dig + 0.001)
			var center := squad_center()
			if rush:
				check(game.cast_ground_skill(0, center), "real Q selects the emerged tunnel squad")
			if mist:
				game.faction_skills[1].commander = RULES.FROG
				check(game.cast_ground_skill(0, center, 1), "enemy frog casts a real weakening cloud on the emerged squad")
			var bonus := 0.5 + (0.5 if rush else 0.0) - (0.3 if mist else 0.0)
			for unit: WarMarches.MarchUnit in game.marches._units:
				near(game.marches.projected_attack_bonus(unit), bonus, "tunnel, Q and mist sum within one skill group")
			near(game.skill_defense_bonus(target), 0.0, "the defender's own mist does not change its defense")
			game.marches.tick(4.0)
			near(target.population, 100.0 - 6.0 * (1.0 + bonus), "real arrivals use additive tunnel/Q/weakness damage")
			check(game.marches.total_for(0) == 0, "each stacked soldier resolves once")
	await stable()
	var target := enemy()
	var dig := launch(target)
	game.marches.tick(dig + 0.001)
	check(game.cast_ground_skill(0, squad_center()), "Q begins before an extended levitation hold")
	# A hold past Q's lifetime must retain R's march-long attack and lose Q's timer.
	for unit: WarMarches.MarchUnit in game.marches._units:
		unit.levitation_remaining = 9.0
	game.marches.tick(9.0)
	for unit: WarMarches.MarchUnit in game.marches._units:
		near(game.marches.projected_attack_bonus(unit), 0.5, "R remains after Q expires while the squad is held")
	finish_marches()
	near(target.population, 91.0, "expired Q does not remove R or leave its own attack behind")

func _friendly_population() -> void:
	for recipient_faction: int in [0, 2]:
		await stable("rivers")
		var target: WarBuilding = game.buildings[2]
		target.faction = recipient_faction
		target.population = 10.0
		launch(target)
		var before: int = game.team_total_for(0)
		finish_marches()
		near(target.population, 16.0, "own/allied reinforcement gains six actual soldiers rather than nine")
		check(target.faction == recipient_faction and game.team_total_for(0) == before, "reinforcement preserves recipient ownership and alliance population")
		check(game.issue_order(target, enemy(), 100, recipient_faction) == 16, "reinforced garrison may issue a fresh ordinary order")
		for unit: WarMarches.MarchUnit in game.marches._units:
			check(not unit.order.rabbit_burrow, "entering any friendly building ends the previous march's attack bonus")

func _capture_survivors() -> void:
	await stable()
	var target: WarBuilding = game.buildings[2]
	target.faction = -1
	target.population = 0.75
	launch(target, 1)
	finish_marches()
	check(target.faction == 0, "boosted tunnel soldier captures a fractional neutral garrison")
	near(target.population, 0.5, "capture survivor is half a real soldier rather than inflated attack strength")

func _recall() -> void:
	for captured: bool in [false, true]:
		await stable()
		var target := enemy()
		var dig := launch(target)
		game.marches.tick(dig + 0.001)
		var original: WarMarches.MarchUnit = game.marches._units[0]
		var at := original.position
		if captured:
			game._on_unit_arrived(home().building_id, 1, 30.0)
			check(home().faction == 1 and home().population == 30.0, "the original source is captured while all six passengers are exposed")
		check(game.cast_ground_skill(2, squad_center()), "E recalls actual tunnel passengers")
		check(game.marches._units[0] == original and original.position.is_equal_approx(at), "recall preserves soldier identity and position")
		for unit: WarMarches.MarchUnit in game.marches._units:
			check(unit.order.returning and unit.order.rabbit_burrow, "return orders retain tunnel provenance")
			near(game.marches.projected_attack_bonus(unit), 0.5, "long return retains R without a duration limit")
		finish_marches()
		near(home().population, 21.0 if captured else 6.0, "recall attacks a captured source for nine damage or reinforces home with six people")
		near(target.population, 100.0, "recalled passengers never also damage their former destination")

func _conversion() -> void:
	await stable()
	var target: WarBuilding = game.buildings[2]
	target.faction = -1
	var dig := launch(target)
	game.marches.tick(dig + 0.001)
	var before: Array = game.marches._units.duplicate()
	game.faction_skills[1].commander = RULES.FOX
	check(game.cast_ground_skill(2, squad_center(), 1), "fox converts the exposed tunnel squad through its real skill")
	for index: int in before.size():
		var unit: WarMarches.MarchUnit = game.marches._units[index]
		check(unit == before[index] and unit.order.faction == 1 and unit.order.rabbit_burrow, "conversion preserves actual soldiers and their tunnel attack")
	finish_marches()
	near(target.population, 91.0, "converted tunnel soldiers retain nine damage against their neutral destination")

func _surrender() -> void:
	await stable("rivers")
	var config := {"map_id": "rivers", "host_player_id": 100, "slots": []}
	for faction: int in game.faction_count:
		config.slots.append({"slot_id": faction, "faction_id": faction, "team_id": faction % 2,
			"kind": "human", "commander": "rabbit", "player_id": 100 + faction,
			"name": "Seat %d" % faction, "controller": "human", "control_epoch": 1})
	game.configure_match(config, 100)
	var target := enemy()
	var dig := launch(target, 12)
	game.marches.tick(dig + 0.001)
	var exposed: Array[WarMarches.MarchUnit] = game.marches._units.filter(func(unit: WarMarches.MarchUnit): return unit.is_exposed())
	check(exposed.size() == 6 and home().population == 6.0, "surrender fixture has six exposed and six reserved soldiers")
	var result: Dictionary = game.surrender_faction(0)
	check(result.accepted and not result.defeated and home().faction == 2, "surrender transfers to the remaining allied human")
	check(home().queued_population == 3 and game.marches.total_for(2) == 9, "forty-percent garrison loss cancels only the excess hidden reservations")
	for unit: WarMarches.MarchUnit in exposed:
		check(unit in game.marches._units and unit.order.faction == 2 and unit.order.rabbit_burrow, "surrender preserves exposed soldier identity and tunnel attack")
	finish_marches()
	near(home().population, 0.6, "transferred queue debits only the three remaining real soldiers")
	near(target.population, 86.5, "six exposed and three retained passengers deal thirteen-and-a-half damage after surrender")

func _cancelled_departures() -> void:
	for captured: bool in [false, true]:
		await stable()
		var target := enemy()
		launch(target)
		if captured:
			game._on_unit_arrived(home().building_id, 1, 20.0)
		else:
			game.marches.trim_departures(home().building_id, 0, 0)
		check(game.marches._units.is_empty() and home().queued_population == 0, "cancellation or source capture removes all underground reservations")
		finish_marches()
		near(target.population, 100.0, "cancelled passengers cannot appear later or deal boosted damage")
		if not captured:
			near(home().population, 6.0, "cancelling before departure returns six real available soldiers")
			check(game.issue_order(home(), target, 100) == 6, "cancelled paid enchantment permits an ordinary replacement order")
			finish_marches()
			near(target.population, 94.0, "replacement soldiers cannot inherit cancelled tunnel attack")
	await stable()
	home().population = 6.0
	check(game.cast_skill(3, home()), "unused tunnel arms normally")
	game.simulate(15.01)
	check(game.issue_order(home(), enemy(), 100) == 6, "expired tunnel permits ordinary dispatch")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(not unit.order.rabbit_burrow, "expiry cannot leak a bonus to the next ordinary order")

func _short_tunnels() -> void:
	for queued: bool in [false, true]:
		await stable()
		var route := PackedVector3Array([Vector3(-10, 0, 0), Vector3(-8, 0, 0)])
		home().population = 1.0 if queued else 0.0
		if queued:
			game.marches.queue_tunnel_departure(home().building_id, enemy().building_id, 0, 1, route, RULES.BURROW_BATCH_INTERVAL, 0.25)
		else:
			game.marches.send_tunnel(home().building_id, enemy().building_id, 0, 1, route, RULES.BURROW_BATCH_INTERVAL)
		var unit: WarMarches.MarchUnit = game.marches._units[0]
		near(unit.order.departure_distance, 0.0, "short tunnel starts at zero surface distance")
		near(game.marches.projected_attack_bonus(unit), 0.5, "both tunnel constructors preserve attack on a route shorter than the exit distance")
		finish_marches()
		near(enemy().population, 98.5, "zero departure distance still yields one boosted arrival")
		near(home().population, 0.0, "short queued tunnel debits exactly one soldier")

func _frame_partitions() -> void:
	var outcomes: Array[Vector3] = []
	for small_steps: bool in [false, true]:
		await stable()
		var target := enemy()
		launch(target, 12)
		if small_steps:
			for frame: int in 80:
				game.simulate(0.05)
		else:
			game.simulate(4.0)
		outcomes.append(Vector3(home().population, target.population, game.marches.total_for(0)))
		near(target.population, 82.0, "full simulation partitions settle twelve boosted arrivals")
	check(outcomes[0].is_equal_approx(outcomes[1]), "one long frame and eighty short frames agree on damage, garrison and soldiers")
