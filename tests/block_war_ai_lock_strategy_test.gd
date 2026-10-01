extends "res://tests/block_war_ai_information_test.gd"
## A trapped source cannot consume its whole faction's military turn or cadence.

class StalePlanAI extends "res://scripts/block_war/war_ai.gd":
	var neutral_plan := false
	var fallback_calls := 0
	func _reinforce(_battle: Node3D) -> bool: return false
	func _development(_battle: Node3D, _homes: int, _constructing: int) -> Dictionary: return {}
	func _conquest(battle: Node3D, neutral: bool) -> Dictionary:
		if neutral != neutral_plan: return {}
		# Deliberately stale candidate exercises real authoritative rejection,
		# independently of the candidate filters tested below.
		return {"source": battle.by_id[1], "target": battle.by_id[2 if neutral else 0], "percent": 50, "score": 100.0}
	func _consolidate(_battle: Node3D) -> void: fallback_calls += 1

func fixture() -> RefCounted:
	reset()
	game.bear.locks.clear()
	game.bear.combat_damage_remainders.clear()
	set_building(0, 0, 3, 1, 10.0)
	set_building(1, 1, 3, 1, 400.0)
	set_building(2, -1, 0, 1, 1.0)
	set_building(3, 1, 3, 1, 200.0)
	set_building(4, 1, 3, 1, 200.0)
	game.sync_environment_bonuses()
	var ai := AI.new(1)
	for building: WarBuilding in game.buildings:
		if building.faction == 1: ai._reserves[building.building_id] = 10.0
	return ai

func trap(id: int) -> void:
	game.bear.locks[id] = {"faction": 0, "remaining": game.SKILL_RULES.BEAR_DURATIONS[1]}

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	_conquest_choices()
	_reinforcement_choices()
	_consolidation_choices()
	_failed_action_cadence()
	await game.prepare_shutdown()
	print("AI_LOCK_STRATEGY checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _conquest_choices() -> void:
	for neutral: bool in [true, false]:
		var ai := fixture()
		var original: Dictionary = ai._conquest(game, neutral)
		check(not original.is_empty(), "unlocked fixture has a viable " + ("expansion" if neutral else "attack"))
		if original.is_empty(): continue
		var blocked_id: int = original.source.building_id
		trap(blocked_id)
		var alternate: Dictionary = ai._conquest(game, neutral)
		check(not alternate.is_empty(), "one trapped building does not block all conquest choices")
		if alternate.is_empty(): continue
		check(alternate.source.building_id != blocked_id, "conquest selects a different unlocked source")
		var trapped_population: float = game.by_id[blocked_id].population
		check(game.issue_order(alternate.source, alternate.target, alternate.percent, 1) > 0, "alternate conquest produces real soldiers")
		check(game.by_id[blocked_id].queued_population == 0 and game.by_id[blocked_id].population == trapped_population, "alternate conquest preserves the trapped garrison")
		game.marches.clear()
		for id: int in [1, 3, 4]: trap(id)
		check(ai._conquest(game, neutral).is_empty(), "all trapped sources produce no conquest candidate")

func _reinforcement_choices() -> void:
	var ai := fixture()
	game.by_id[3].population = 100.0
	game.by_id[4].population = 0.0
	ai._reserves[4] = 200.0
	ai._incoming_teams[4] = Vector2i(150, 0)
	check(ai._reinforce(game), "unlocked reinforcement fixture commits a real rescue")
	check(game.marches._units[0].order.source_id == 1, "large source is the preferred rescue before locking")
	ai = fixture()
	game.by_id[3].population = 100.0
	game.by_id[4].population = 0.0
	ai._reserves[4] = 200.0
	ai._incoming_teams[4] = Vector2i(150, 0)
	trap(1)
	check(ai._reinforce(game), "another building can rescue while the preferred source is trapped")
	check(game.marches.incoming_for(4, 1) > 0, "alternative rescue has a real destination army")
	check(game.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.order.source_id == 3), "every rescuer comes from the unlocked alternative")
	check(game.by_id[1].population == 400.0 and game.by_id[1].queued_population == 0, "rescue never spends the trapped garrison")

func _consolidation_choices() -> void:
	var ai := fixture()
	ai._consolidate(game)
	check(not game.marches._units.is_empty(), "unlocked consolidation fixture gathers a real column")
	if game.marches._units.is_empty(): return
	var preferred: int = game.marches._units[0].order.source_id
	ai = fixture()
	trap(preferred)
	ai._consolidate(game)
	check(not game.marches._units.is_empty(), "trapped preferred donor does not block another donor")
	check(game.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.order.source_id != preferred), "consolidation never queues from the trapped donor")
	check(game.by_id[preferred].queued_population == 0, "trapped consolidation source keeps its reservations empty")

func _failed_action_cadence() -> void:
	for neutral: bool in [true, false]:
		fixture()
		trap(1)
		var ai := StalePlanAI.new(1)
		ai.neutral_plan = neutral
		ai.take_turn(game)
		check(game.marches._units.is_empty(), "authoritative dispatch rejects the stale locked-source plan")
		near(ai._next_attack_at, 0.0, "failed order cannot consume the attack interval")
		near(ai._next_expansion_at, 0.0, "failed order cannot consume the expansion interval")
		check(ai.fallback_calls == 1, "a failed order still reaches another decision in the same turn")
		game.bear.locks.clear()
		ai.take_turn(game)
		check(not game.marches._units.is_empty(), "the same plan succeeds immediately once legal")
		var deadline: float = ai._next_expansion_at if neutral else ai._next_attack_at
		near(deadline, game.elapsed + (AI.EXPANSION_INTERVAL if neutral else AI.ATTACK_INTERVAL), "only the successful order starts its cadence")
		check(ai.fallback_calls == 1, "successful order consumes exactly one military action")
