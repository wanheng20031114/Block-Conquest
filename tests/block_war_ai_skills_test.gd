extends SceneTree
## Shared skill rules, team ownership, tactical choices and fair resource use.

const TACTICS := preload("res://scripts/block_war/war_ai_skills.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var serial := 1000

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.001, "%s: %s = %s" % [label, actual, expected])

func reset_match() -> void:
	if game != null:
		await game.prepare_shutdown()
	root.get_node("Session").block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for building: WarBuilding in game.buildings:
		building.kind = 2
		building.population = 100.0
		building.refresh_visual()
	for faction: int in 6:
		game.by_id[faction].kind = 0
		game.by_id[faction].population = 60.0
		game.by_id[faction].refresh_visual()

func expose(faction: int, count: int, from: Vector3, to: Vector3, target_id: int = 1) -> void:
	# Separate queues deliberately place a fully exposed formation on the map.
	for index: int in count:
		serial += 1
		game.marches.send(serial, target_id, faction, 1, PackedVector3Array([from + Vector3(0, 0, (index % 4) * 0.12), to]))

func visible_units() -> Array[WarMarches.MarchUnit]:
	var result: Array[WarMarches.MarchUnit] = []
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.distance >= 0.0:
			result.append(unit)
	return result

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	await reset_match()
	for faction: int in 6:
		check(game.cast_skill(0, game.by_id[faction], faction), "all six commanders can recruit legally")
		near(game.faction_skills[faction].energy, 70.0, "every commander pays thirty")
		near(game.faction_skills[faction].cooldowns[0], 35.0, "same recruitment cooldown")
	check(game.world_effects.get_node("RecruitRings").multimesh.visible_instance_count == 6, "six independent recruitment visuals coexist")
	game.simulate(6.0)
	for faction: int in 6:
		near(game.by_id[faction].population, 90.0, "recruitment adds exactly thirty beyond natural capacity")
		near(game.faction_skills[faction].energy, 82.0, "independent regeneration is two per second")
		check(game.faction_skills[faction].recruit_target_id == -1, "recruitment releases its target on expiry")
	check(game.world_effects.get_node("RecruitRings").multimesh.visible_instance_count == 0, "expired recruitment removes its ground effect")
	await reset_match()
	check(game.cast_skill(0, game.by_id[0], 2), "ally AI may recruit for the human")
	check(not game.cast_skill(0, game.by_id[0], 4), "allies cannot stack recruitment on one residence")
	near(game.faction_skills[4].energy, 100.0, "rejected support is free")
	check(not game.cast_skill(0, game.by_id[0], 1), "hostile recruitment is rejected")
	game.simulate(2.0)
	near(game.by_id[0].population, 70.0, "ally support belongs to the receiving residence")
	game.by_id[0].population = 0.5
	game._on_unit_arrived(0, 1, 20.0)
	check(game.faction_skills[2].recruit_target_id == -1, "capture cancels the ally's recruitment account")
	await reset_match()
	game.cast_skill(0, game.by_id[2], 4)
	game.by_id[2].begin_construction(1)
	game.by_id[2].construction_remaining = 1.0
	game.simulate(1.2)
	check(game.by_id[2].kind == 1 and game.faction_skills[4].recruit_target_id == -1, "completion of an allied conversion cancels recruitment")
	near(game.by_id[2].population, 65.0, "conversion retains recruitment only until completion")
	await reset_match()
	for faction: int in 6:
		check(game.cast_skill(2, game.by_id[faction], faction), "all commanders can protect distinct buildings")
	check(game.world_effects.get_node("Shield").multimesh.visible_instance_count == 6, "all six shields render at once")
	check(not game.cast_skill(2, game.by_id[0], 2), "active wall cannot be refreshed by another ally")
	game.simulate(10.0)
	check(game.shields.is_empty() and game.world_effects.get_node("Shield").multimesh.visible_instance_count == 0, "all walls expire through simulation")
	await reset_match()
	game.select_building(game.by_id[0])
	game.request_skill(3)
	var player_energy: float = game.energy
	check(game.cast_skill(0, game.by_id[1], 1), "enemy can cast during player aiming")
	check(game.armed_skill == 3 and game.selected == game.by_id[0] and game.energy == player_energy, "enemy skill preserves player gesture, selection and account")
	game._cancel_skill_drag()
	game.drag_source = game.by_id[0]
	game.cast_skill(1, null, 3)
	check(game.drag_source == game.by_id[0], "AI haste preserves a troop dispatch drag")
	check(game.marches._boosts.has(3) and not game.marches._boosts.has(0), "haste applies only to its caster's soldiers")
	game._cancel_drag()
	var before: float = game.faction_skills[1].cooldowns[0]
	game.set_paused(true)
	game.simulate(20.0)
	near(game.faction_skills[1].cooldowns[0], before, "pause freezes computer cooldowns")
	check(not game.cast_skill(2, game.by_id[1], 1), "paused AI casts are rejected")
	check(game.world_effects.get_node("RecruitMotes").speed_scale == 0.0 and game.world_effects.get_node("HasteTrails").speed_scale == 0.0, "pause freezes support particles")
	game.set_paused(false)
	game._finish_match(0)
	check(not game.cast_skill(2, game.by_id[1], 1), "finished match rejects AI casts")
	await reset_match()
	near(game.faction_skills[1].energy, 100.0, "restart resets all independent accounts")
	for faction: int in 6:
		check(game.cast_ground_skill(3, Vector3(-35 + faction * 12, 0, 0), faction), "six simultaneous fires use independent pool entries")
	for faction: int in 6:
		var fire: WarFireWave = game.world_effects.get_node("FireWaves").get_child(faction)
		check(fire.faction == faction and fire.age < 0.0, "every warning retains its caster")
	await reset_match()
	var center := Vector3.ZERO
	for faction: int in 6:
		game.by_id[faction].position = center + Vector3((faction - 3) * 0.2, 0, 0)
		game.by_id[faction].kind = 2 # Isolate damage from post-hit residential regrowth.
	game.cast_ground_skill(3, center, 1)
	game.simulate(0.6)
	near(game.by_id[0].population, 60.0, "warning cannot damage a garrison")
	game.simulate(0.05)
	expose(1, 1, center, center + Vector3(20, 0, 0))
	expose(0, 1, center, center + Vector3(20, 0, 0))
	game.simulate(1.15)
	for faction: int in 6:
		near(game.by_id[faction].population, 60.0 if faction % 2 == 1 else 25.0, "enemy fire protects its own alliance and damages opponents")
	check(game.marches._units.is_empty(), "AI fire burns both exposed factions")
	await reset_match()
	var ai := TACTICS.new(1)
	ai.take_turn(game)
	near(game.faction_skills[1].energy, 100.0, "computer cannot open with an immediate frame-zero cast")
	game.elapsed = 6.0
	ai.take_turn(game)
	check(game.faction_skills[1].recruit_target_id == 1, "idle computer invests recruitment in its residence")
	var spent: float = game.faction_skills[1].energy
	ai.take_turn(game)
	near(game.faction_skills[1].energy, spent, "multiple calls at the same time cannot chain skills")
	await reset_match()
	game.elapsed = 10.0
	game.faction_skills[1].energy = 64.0
	TACTICS.new(1).take_turn(game)
	near(game.faction_skills[1].energy, 64.0, "computer reserves energy rather than spending its final shield budget")
	await reset_match()
	game.elapsed = 10.0
	game.by_id[1].population = 15.0
	expose(0, 20, Vector3(-10, 0, 0), Vector3.ZERO)
	game.faction_skills[1].cooldowns[3] = 100.0
	TACTICS.new(1).take_turn(game)
	check(game.shields.has(1), "imminent dangerous attack chooses defense ahead of economy")
	await reset_match()
	game.elapsed = 10.0
	game.faction_skills[1].cooldowns[0] = 100.0
	expose(1, 30, Vector3(-20, 0, 0), Vector3(20, 0, 0), 0)
	TACTICS.new(1).take_turn(game)
	check(game.faction_skills[1].durations[1] == 8.0, "large distant march receives haste")
	await reset_match()
	game.elapsed = 10.0
	expose(0, 24, Vector3(-3, 0, 2), Vector3(28, 0, 2), 0)
	ai = TACTICS.new(1)
	var shot := ai._fire_target(game, visible_units())
	check(not shot.is_empty(), "dense exposed enemy formation is a useful fire target")
	ai.take_turn(game)
	check(game.faction_skills[1].cooldowns[3] == 60.0, "computer casts paid fire at a dense unescorted formation")
	await reset_match()
	expose(0, 24, Vector3(-3, 0, 2), Vector3(28, 0, 2), 0)
	expose(3, 1, Vector3(1, 0, 2), Vector3(2, 0, 2), 3)
	check(TACTICS.new(1)._fire_target(game, visible_units()).is_empty(), "near-arrival ally still blocks friendly fire")
	game.marches.clear()
	expose(0, 24, Vector3(-3, 0, 2), Vector3(28, 0, 2), 0)
	expose(3, 1, Vector3(10, 0, 2), Vector3(-15, 0, 2), 3)
	check(TACTICS.new(1)._fire_target(game, visible_units()).is_empty(), "friend crossing later in the burn window blocks fire")
	game.marches.clear()
	expose(0, 7, Vector3(-3, 0, 2), Vector3(28, 0, 2), 0)
	check(TACTICS.new(1)._fire_target(game, visible_units()).is_empty(), "computer does not waste sixty energy on scattered small patrols")
	await game.prepare_shutdown()
	print("BLOCK_WAR_AI_SKILLS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
