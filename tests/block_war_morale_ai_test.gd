extends SceneTree
## Compare the AI's segmented estimate with actual sequential troop arrivals.

const AI := preload("res://scripts/block_war/war_ai.gd")

var game: Node3D
var ai: RefCounted
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func reset(attacking: float, defending: float, population: float, neutral := false) -> WarBuilding:
	game.morale.configure(game.faction_count)
	game.morale.adjust(0, attacking)
	game.morale.adjust(1, defending)
	game.shields.clear()
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
	var target: WarBuilding = game.by_id[1]
	target.faction = -1 if neutral else 1
	target.population = population
	return target

func compare_arrivals(target: WarBuilding, label: String) -> void:
	var attack_before: float = game.morale.points(0)
	var defense_before: float = game.morale.points(1)
	var population_before := target.population
	var owner := target.faction
	var predicted: float = ai._assault_losses(game, target, target.population)
	check(game.morale.points(0) == attack_before and game.morale.points(1) == defense_before and target.population == population_before, label + ": planning is read-only")
	for unit: int in floori(predicted):
		game._on_unit_arrived(target.building_id, 0, 1.0)
	check(target.faction == owner, label + ": floor of predicted casualties does not capture")
	game._on_unit_arrived(target.building_id, 0, 1.0)
	check(target.faction == 0, label + ": next soldier captures")

func _run() -> void:
	var session: Node = root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"squirrel"
	session.block_war_opponent_commander = &"squirrel"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	ai = AI.new(0)

	var target := reset(0.0, 490.0, 160.0)
	var old_requirement: float = target.population / game.combat_multiplier(0, target) * 1.35 + 10.0
	var updated_requirement: float = ai._assault_losses(game, target, target.population) * 1.35 + 10.0
	for unit: int in ceili(old_requirement):
		game._on_unit_arrived(1, 0, 1.0)
	check(target.faction == 1 and target.population > 9.0, "old static estimate fails despite its existing safety margin")
	check(updated_requirement > old_requirement, "defensive kills increase the predicted assault requirement")
	var required := ceili(old_requirement)
	while target.faction != 0 and required < 1000:
		game._on_unit_arrived(1, 0, 1.0)
		required += 1
	check(required == 243, "160 defenders starting at 490 morale require 243 real arrivals")
	check(updated_requirement >= required, "updated estimate and unchanged margin cover the proven underestimation")

	for attacking: float in [0.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]:
		for defending: float in [0.0, 490.0, 990.0, 1990.0, 3990.0, 7990.0, 8000.0]:
			target = reset(attacking, defending, 160.0)
			compare_arrivals(target, "morale %s/%s" % [attacking, defending])
	for attacking: float in [0.0, 500.0, 1000.25, 8000.0]:
		target = reset(attacking, 0.0, 80.0, true)
		compare_arrivals(target, "neutral target, attacking morale %s" % attacking)
	target = reset(500.25, 490.5, 55.5)
	target.kind = 1
	target.level = 3
	game.by_id[0].kind = 2
	game.shields[target.building_id] = 10.0
	compare_arrivals(target, "fractional morale with forge, tower and active shield")
	target = reset(8000.0, 8000.0, 0.0)
	compare_arrivals(target, "empty garrison still needs a capturing soldier")

	target = reset(0.0, 490.0, 160.0)
	for building: WarBuilding in game.buildings:
		if building != target:
			building.faction = 0
			building.population = 0.0
		ai._reserves[building.building_id] = 0.0
	var source: WarBuilding = game.by_id[0]
	source.population = 310.0
	check(ai._conquest(game, false).is_empty(), "AI rejects a wave that only satisfies the old static estimate")
	source.population = 500.0
	var plan: Dictionary = ai._conquest(game, false)
	check(not plan.is_empty() and plan.source == source and plan.target == target and plan.percent == 75, "AI attacks after gathering enough troops for changing morale")
	await game.prepare_shutdown()
	print("BLOCK_WAR_MORALE_AI ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
