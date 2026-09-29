extends SceneTree
## Paired decisions must not change when only unobservable enemy state changes.

const INFORMATION := preload("res://scripts/block_war/war_ai_information.gd")
const AI := preload("res://scripts/block_war/war_ai.gd")
const TACTICS := preload("res://scripts/block_war/war_ai_skills.gd")

var game: Node3D
var checks := 0
var failures: Array[String] = []
var actions: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL AI_INFORMATION ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %s expected %s" % [label, actual, expected])

func reset() -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.shields.clear()
	game.bear.links.clear()
	game.bear.wards.clear()
	game.bear.shots.clear()
	game.bear.damage_remainders.clear()
	game.morale.configure(game.faction_count)
	game.finished = false
	game.elapsed = 30.0
	for state: RefCounted in game.faction_skills:
		state.commander = &"squirrel"
		state.energy = 100.0
		state.cooldowns.fill(999.0)
		state.durations.fill(0.0)
		state.recruit_target_id = -1
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
		building.faction = -1
		building.kind = 0
		building.level = 1
		building.population = 1000.0
		building.refresh_visual()
	set_building(0, 0, 0, 1, 60.0)
	set_building(1, 1, 0, 1, 60.0)
	actions.clear()

func set_building(id: int, faction: int, kind: int, level: int, population: float) -> WarBuilding:
	var building: WarBuilding = game.by_id[id]
	building.faction = faction
	building.kind = kind
	building.level = level
	building.population = population
	building.refresh_visual()
	return building

func soldier(faction: int = 0, target: int = 1) -> WarMarches.MarchUnit:
	var source := 0 if faction % 2 == 0 else 3
	var finish: Vector3 = game.by_id[target].global_position
	game.marches.send(source, target, faction, 1, PackedVector3Array([finish + Vector3(-10, 0, 0), finish]))
	return game.marches._units[-1]

func hidden_army(mode: String, count: int = 24) -> void:
	if mode == "cloak":
		for index: int in count:
			var unit := soldier()
			unit.cloaked = true
			unit.rush_remaining = 8.0
	elif mode in ["queue", "dig"]:
		var first: int = game.marches._units.size()
		var source: WarBuilding = game.by_id[0]
		var target: WarBuilding = game.by_id[1]
		var route := PackedVector3Array([source.global_position, target.global_position])
		game.marches.queue_tunnel_departure(0, 1, 0, count, route, 0.16, 1.0)
		if mode == "queue":
			for unit: WarMarches.MarchUnit in game.marches._units.slice(first):
				unit.spawn_delay = 0.0
				unit.distance = -0.1
		for unit: WarMarches.MarchUnit in game.marches._units.slice(first):
			unit.rush_remaining = 8.0

func observation_contract() -> void:
	reset()
	var building: WarBuilding = game.by_id[0]
	for owner: int in [-1, 0, 1, 2, 3, 4, 5]:
		building.faction = owner
		building.population = 43.25
		for observer: int in 6:
			var known: bool = owner < 0 or game.FACTIONS.allied(owner, observer)
			near(INFORMATION.garrison_estimate(game, building, observer), 43.25 if known else 15.0, "garrison observation for owner %d observer %d" % [owner, observer])
	for specification: Array in [[0, 1, 15.0], [0, 4, 40.0], [1, 1, 20.0], [1, 3, 40.0], [2, 1, 20.0], [3, 1, 20.0]]:
		set_building(0, 0, specification[0], specification[1], 1.0)
		var estimate: float = INFORMATION.garrison_estimate(game, building, 1)
		building.population = 9999.0
		near(estimate, specification[2], "enemy type/level has an explicit coarse estimate")
		near(INFORMATION.garrison_estimate(game, building, 1), estimate, "hidden reinforcements never update the estimate")
	reset()
	var ordinary := soldier()
	ordinary.order.strength = 1.25
	var floating := soldier()
	floating.levitation_remaining = 3.0
	check(INFORMATION.is_unit_known(game, floating, 1), "visible levitation remains observable")
	near(game.marches.movement_distance(floating, 2.0), 0.0, "visible levitation delays its arrival")
	var before := INFORMATION.snapshot_incoming(game, 1)
	var damage: float = INFORMATION.incoming_damage(game, game.by_id[1], before, 1)
	near(damage, 2.25, "known strength contributes once to the threat")
	var hidden := soldier()
	hidden.cloaked = true
	hidden.rush_remaining = 8.0
	check(not INFORMATION.is_unit_known(game, hidden, 1), "enemy cloak is unobservable")
	var dead := soldier()
	dead.alive = false
	check(not INFORMATION.is_unit_known(game, dead, 1), "dead army entries are unobservable")
	hidden_army("dig", 5)
	check(INFORMATION.snapshot_incoming(game, 1) == before, "hidden and digging enemies do not appear in incoming counts")
	near(INFORMATION.incoming_damage(game, game.by_id[1], INFORMATION.snapshot_incoming(game, 1), 1), damage, "hidden rush bonuses cannot leak through threat corrections")
	set_building(3, 3, 0, 1, 20.0)
	var route := PackedVector3Array([game.by_id[3].global_position, game.by_id[1].global_position])
	game.marches.queue_tunnel_departure(3, 1, 3, 4, route, 0.16, 1.0)
	var friendly: WarMarches.MarchUnit = game.marches._units[-1]
	friendly.cloaked = true
	check(INFORMATION.is_unit_known(game, friendly, 1), "allied cloaked doorway queues stay known")
	check(INFORMATION.snapshot_incoming(game, 1).get(Vector2i(1, 3), 0) == 4, "allied queue reservations remain in the shared plan")
	near(INFORMATION.team_strength(game, 1, 1), 80.0, "allied pending soldiers are counted exactly once")
	var enemy_strength: float = INFORMATION.team_strength(game, 0, 1)
	game.by_id[0].population = 9876.0
	near(INFORMATION.team_strength(game, 0, 1), enemy_strength, "team estimates exclude hidden garrisons and queues")

func strategy_signature(population: float, hidden_mode: String) -> Dictionary:
	reset()
	for id: int in [1, 3, 5]:
		set_building(id, 1, 0, 4, 180.0)
	game.by_id[1].population = 500.0
	set_building(0, 0, 0, 4, population)
	set_building(2, 0, 2, 1, population)
	hidden_army(hidden_mode)
	var ai := AI.new(1)
	for building: WarBuilding in game.buildings:
		if building.faction == 1:
			ai._reserves[building.building_id] = 14.0
	var plan: Dictionary = ai._conquest(game, false)
	var normalized := {}
	if not plan.is_empty():
		normalized = {"source":plan.source.building_id,"target":plan.target.building_id,"percent":plan.percent,"score":plan.score}
	ai.take_turn(game)
	return {"conquest":normalized,"actions":actions.duplicate(true)}

func strategy_pairs() -> void:
	var baseline := strategy_signature(40.0, "")
	check(not baseline.conquest.is_empty(), "the fairness fixture offers a real offensive decision")
	check(not baseline.actions.is_empty(), "the fairness fixture performs a real paid action")
	for population: float in [1.0, 999.0]:
		check(strategy_signature(population, "") == baseline, "enemy stockpile %s cannot alter conquest or paid actions" % population)
	for hidden_mode: String in ["cloak", "queue", "dig"]:
		check(strategy_signature(40.0, hidden_mode) == baseline, "unseen %s armies cannot alter strategy" % hidden_mode)

func skill_signature(commander: StringName, index: int, population: float, account_energy: float) -> Array[Dictionary]:
	reset()
	game.faction_skills[1].commander = commander
	game.faction_skills[1].cooldowns[index] = 0.0
	game.faction_skills[0].energy = account_energy
	game.faction_skills[0].cooldowns.fill(account_energy * 10.0)
	if commander == &"frog":
		for building: WarBuilding in game.buildings:
			if building.faction < 0:
				building.population = 0.0
		set_building(0, 0, 0, 4, population)
		set_building(2, 0, 0, 3, 510.0 - population)
	elif index == 1:
		set_building(0, 0, 0, 4, population)
	else:
		set_building(1, 1, 0, 4, 80.0)
		set_building(0, 0, 2, 1, population)
	TACTICS.new(1).take_turn(game)
	return actions.duplicate(true)

func skill_pairs() -> void:
	for profile: Array in [[&"frog", 3], [&"rabbit", 1], [&"rabbit", 3]]:
		var baseline := skill_signature(profile[0], profile[1], 10.0, 0.0)
		check(not baseline.is_empty(), "%s skill %d fairness fixture actually casts" % profile)
		check(skill_signature(profile[0], profile[1], 500.0, 0.0) == baseline, "%s skill %d ignores hidden enemy garrison differences" % profile)
		check(skill_signature(profile[0], profile[1], 10.0, 100.0) == baseline, "%s skill %d ignores private enemy energy and cooldowns" % profile)

func hud_information() -> void:
	reset()
	game.local_faction = 1
	set_building(3, 3, 0, 1, 0.4)
	set_building(5, 5, 0, 1, 0.4)
	game.by_id[1].population = 0.4
	game.update_hud()
	var bar: Control = game.hud.get_node("%Balance")
	var before: PackedFloat32Array = bar._targets.duplicate()
	check(game.hud.get_node("%PlayerTotal").text == "1", "HUD keeps the known alliance's aggregate fractional population")
	check(game.hud.get_node("%EnemyTotal").text == "未知", "HUD never exposes an enemy army total")
	game.by_id[0].population = 9999.0
	hidden_army("cloak")
	hidden_army("dig")
	game.update_hud()
	check(bar._targets == before, "hidden army and garrison changes cannot change the territory bar")
	check(game.hud.get_node("%EnemyTotal").text == "未知", "new hidden armies keep the enemy total unknown")
	check(bar.get_node("Stars/Faction0").tooltip_text.contains("据点占比"), "the bar explains its public territory measure")
	# Remove enemy pending orders before changing their source for later cleanup.
	game.marches.clear()
	game.by_id[0].faction = 3
	game.update_hud()
	check(bar._targets != before and bar._targets[0] == 0.0, "visible ownership changes update the territory bar")

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	session.block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.presentation_event.connect(func(kind: String, payload: Dictionary):
		if kind in ["dispatch", "construction", "skill"] and int(payload.faction) == 1:
			actions.append({"kind":kind,"payload":payload.duplicate(true)}))
	observation_contract()
	strategy_pairs()
	skill_pairs()
	hud_information()
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("AI_INFORMATION ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
