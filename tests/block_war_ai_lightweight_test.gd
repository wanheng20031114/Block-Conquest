extends "res://tests/block_war_ai_information_test.gd"
## Exercise decision-local caches against a changing real battle. Arithmetic
## equivalence for large mixed armies is covered by the damage benchmark.

class LiveModifiersAI extends "res://scripts/block_war/war_ai.gd":
	var evaluations := 0
	var modifier_mismatches := 0

	func _assault_losses_with_environment(battle: Node3D, target: WarBuilding, defenders: float, environment_attack: float, environment_defense: float, skill_defense: float) -> float:
		# Re-read modifiers for every candidate, as the pre-hoisting search did.
		# Exact comparisons also detect accidental float32 storage even when the
		# affected candidate does not become the winning plan.
		var live_attack: float = 1.0 + battle.attack_bonus(faction)
		var live_defense: float = 1.0 + battle.defense_bonus(target)
		var live_skill: float = 1.0 + battle.skill_defense_bonus(target)
		evaluations += 1
		if environment_attack != live_attack or environment_defense != live_defense or skill_defense != live_skill:
			modifier_mismatches += 1
		return super._assault_losses_with_environment(battle, target, defenders, live_attack, live_defense, live_skill)

func verify_observation(observer: int, label: String) -> void:
	var observation := INFORMATION.snapshot_defense(game, observer)
	var counts := INFORMATION.snapshot_incoming(game, observer)
	check(observation.counts == counts, label + ": full destination counts remain fresh")
	for building: WarBuilding in game.buildings:
		if game.FACTIONS.allied(building.faction, observer):
			var expected := INFORMATION.incoming_damage(game, building, counts, observer)
			check(observation.damage.get(building.building_id, 0.0) == expected, label + ": exact per-building observation %d" % building.building_id)
		else:
			check(not observation.damage.has(building.building_id), label + ": damage excludes other owners %d" % building.building_id)

func snapshot_lifecycle() -> void:
	reset()
	set_building(3, 3, 0, 2, 20.0)
	var first := soldier(0, 1)
	first.order.strength = 1.25
	var second := soldier(2, 3)
	second.order.strength = 0.625
	second.order.pig_charge = true
	var friendly := soldier(3, 1)
	friendly.cloaked = true
	friendly.spawn_delay = 8.0
	soldier(4, 4) # A known attack on neutral land still belongs in counts.
	soldier(1, 0) # A known attack on enemy land still belongs in counts.
	var hidden := soldier(4, 1)
	hidden.cloaked = true
	var doomed := soldier(2, 1)
	doomed.alive = false
	var original := INFORMATION.snapshot_defense(game, 1)
	var saved_counts := original.counts.duplicate()
	var saved_damage := original.damage.duplicate()
	check(original.counts.get(Vector2i(1, 3), 0) == 1, "allied concealed departure remains in counts")
	check(original.counts.get(Vector2i(4, 4), 0) == 1 and original.counts.get(Vector2i(0, 1), 0) == 1, "non-defensive destinations remain in the shared observation")
	check(original.counts.get(Vector2i(1, 4), 0) == 0 and original.counts.get(Vector2i(1, 2), 0) == 0, "hidden and dead hostiles are excluded")
	for observer: int in [1, 0, 5, 2, 1]:
		verify_observation(observer, "interleaved observer %d" % observer)

	# Change the membership and target ownership without replacing the march
	# array. Later observations must neither reuse nor mutate earlier results.
	first.cloaked = true
	hidden.cloaked = false
	hidden.order.strength = 1.375
	hidden.rush_remaining = 20.0
	second.alive = false
	friendly.order.faction = 0
	game.by_id[3].faction = 0
	set_building(6, 4, 2, 1, 0.0)
	set_building(7, 1, 2, 1, 0.0)
	game.morale.adjust(4, 1000.25)
	game.morale.adjust(1, 490.5)
	game.shields[1] = 2.0
	game.bear.wards[1] = {"faction": 1, "remaining": 2.0, "shot_clock": 1.0, "pulse": 0.0, "hostile": false}
	game.by_id[1].kind = 1
	game.by_id[1].level = 3
	for observer: int in [0, 1, 4, 3, 1]:
		verify_observation(observer, "changed battlefield observer %d" % observer)
	var changed := INFORMATION.snapshot_defense(game, 1)
	check(changed.counts != saved_counts and changed.damage != saved_damage, "the changed fixture produces distinct observations")
	check(not changed.damage.has(3), "captured allied target leaves the defense map")
	check(original.counts == saved_counts and original.damage == saved_damage, "prior snapshots remain immutable after other observations and mutations")
	game.shields.clear()
	game.bear.wards.clear()
	game.by_id[6].disruption_remaining = 1.0
	game.by_id[7].disruption_remaining = 1.0
	verify_observation(1, "expired defenses and disrupted forges")
	check(INFORMATION.snapshot_defense(game, 1).damage != changed.damage, "defense and forge changes invalidate the next observation")
	game.marches.clear()
	var empty := INFORMATION.snapshot_defense(game, 1)
	check(empty.counts.is_empty() and empty.damage.is_empty(), "empty battlefield cannot retain a previous threat")
	check(original.counts == saved_counts and original.damage == saved_damage, "clearing armies does not alter retained snapshots")

func enemy_distance_lifecycle() -> void:
	reset()
	game.by_id[0].population = 0.0
	game.by_id[1].population = 0.0
	var ai := AI.new(1)
	var source: WarBuilding = game.by_id[1]
	var far: float = game.map.get_building_distance(source, game.by_id[0])
	var close: float = game.map.get_building_distance(source, game.by_id[7])
	check(is_finite(far) and is_finite(close) and far > close, "distance fixture has distinct connected routes")
	ai.take_turn(game)
	check(ai._enemy_distance(game, source) == far, "first turn sees the original enemy")
	game.by_id[0].faction = 3
	set_building(7, 2, 0, 1, 0.0)
	game.elapsed += AI.TURN_INTERVAL
	ai.take_turn(game)
	check(ai._enemy_distance(game, source) == close, "next turn refreshes captured and newly hostile buildings")
	game.by_id[7].faction = -1
	game.elapsed += AI.TURN_INTERVAL
	ai.take_turn(game)
	check(ai._enemy_distance(game, source) == INF, "no enemy caches infinity for this turn")
	game.match_paused = true
	game.by_id[0].faction = 0
	ai.take_turn(game)
	game.match_paused = false
	game.elapsed += AI.TURN_INTERVAL
	ai.take_turn(game)
	check(ai._enemy_distance(game, source) == far, "resumed turn replaces the previous infinity cache")

func skill_then_observation() -> void:
	reset()
	game.by_id[1].population = 20.0
	game.faction_skills[1].cooldowns[2] = 0.0
	for index: int in 24:
		soldier(0, 1)
	var ai := AI.new(1)
	var target: WarBuilding = game.by_id[1]
	var before := INFORMATION.snapshot_defense(game, 1)
	ai.take_turn(game)
	check(game.shields.has(1), "real squirrel AI casts a shield before strategy")
	var shielded := INFORMATION.snapshot_defense(game, 1)
	check(shielded.damage[1] < before.damage[1], "the actual cast changes incoming damage")
	check(ai._reserves[1] == ai._base_reserve(game, target) + shielded.damage[1], "strategy consumes the post-skill observation")
	check(ai._incoming_for(1, 0) == 24, "post-skill observation retains the complete hostile count")
	game.shields.clear()
	game.elapsed += 6.0
	ai.take_turn(game)
	check(not game.shields.has(1), "cooldown prevents an immediate replacement shield")
	check(ai._reserves[1] == ai._base_reserve(game, target) + before.damage[1], "same AI refreshes reserve when defense expires")
	for unit: WarMarches.MarchUnit in game.marches._units:
		unit.order.faction = 1
	game.elapsed += 6.0
	ai.take_turn(game)
	check(ai._incoming_for(1, 0) == 0 and ai._incoming_for(1, 1) == 24, "same AI refreshes converted armies in team counts")
	check(ai._reserves[1] == ai._base_reserve(game, target), "converted allies no longer add hostile damage")

func conquest_modifier_lifecycle() -> void:
	var candidate := AI.new(1)
	var live := LiveModifiersAI.new(1)
	for variant: int in 16:
		reset()
		set_building(1, 1, 0, 4, 1200.0)
		set_building(3, 1, 0, 4, 720.0)
		set_building(0, 0, 1, 1 + variant % 4, 55.5)
		set_building(2, 2 if variant % 2 == 0 else 4, 0, 3, 90.0)
		set_building(7, -1, 0, 3, 35.375)
		set_building(12, 1, 2, 1, 0.0)
		set_building(14, 1 if variant & 2 else 3, 2, 1, 0.0)
		set_building(13, 0, 2, 1, 0.0)
		set_building(15, 0 if variant & 8 else 2, 2, 1, 0.0)
		game.by_id[12].disruption_remaining = 1.0 if variant & 1 else 0.0
		game.by_id[13].disruption_remaining = 1.0 if variant & 4 else 0.0
		game.morale.adjust(1, 500.25 + variant * 500.0)
		game.morale.adjust(0, 490.5 + variant * 250.0)
		if variant % 2 == 0:
			game.shields[0] = 2.0
		if variant % 3 == 0:
			game.bear.wards[0] = {"faction": 0, "remaining": 2.0, "shot_clock": 1.0, "pulse": 0.0, "hostile": false}
		for ai: RefCounted in [candidate, live]:
			ai._reserves.clear()
			ai._incoming_teams.clear()
			ai._departure_delays.clear()
			for building: WarBuilding in game.buildings:
				if building.faction == 1:
					ai._reserves[building.building_id] = 14.0
		for neutral: bool in [true, false]:
			var actual: Dictionary = candidate._conquest(game, neutral)
			var expected: Dictionary = live._conquest(game, neutral)
			check(not expected.is_empty(), "variant %d neutral %s has a real plan" % [variant, neutral])
			check(actual == expected, "variant %d neutral %s preserves exact plan and score" % [variant, neutral])
	check(live.evaluations > 100, "modifier audit covers multiple sources and dispatch percentages")
	check(live.modifier_mismatches == 0, "all hoisted modifiers remain current and preserve float64 values")

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	var session: Node = root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	session.block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	snapshot_lifecycle()
	enemy_distance_lifecycle()
	skill_then_observation()
	conquest_modifier_lifecycle()
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("AI_LIGHTWEIGHT ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
