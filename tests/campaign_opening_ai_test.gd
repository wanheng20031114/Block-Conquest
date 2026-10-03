extends SceneTree
## Exercise the opening opponent's patience with actual paid rabbit skills.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var game: Node3D
var session: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func fixture(stage: int, commander: StringName = &"rabbit") -> void:
	if game != null:
		await game.prepare_shutdown()
	session.campaign_active_stage = stage
	# A compact existing scene isolates the policy from scenic-map rendering.
	session.block_war_map_id = "rift"
	session.block_war_opponent_commander = commander
	change_scene_to_file(session.BATTLE_SCENE)
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.by_id[0].level = 3
	game.by_id[0].kind = 1
	game.by_id[0].population = 0.0
	game.faction_skills[1].cooldowns.fill(100.0)
	game.faction_skills[1].cooldowns[1] = 0.0
	# The tower covers an exposed hostile column, making W tactically valuable.
	var tower: Vector3 = game.by_id[0].global_position
	for index: int in 20:
		game.marches.send(1, 0, 1, 1, PackedVector3Array([tower + Vector3(-6, 0, (index % 4) * 0.1), tower + Vector3(30, 0, 0)]))

func attempt(at: float, energy: float) -> void:
	game.elapsed = at
	game.faction_skills[1].energy = energy
	game._ai_strategy._skills.take_turn(game)

func ready_again() -> void:
	game.by_id[0].disruption_remaining = 0.0
	game.faction_skills[1].cooldowns[1] = 0.0

func _run() -> void:
	create_timer(80.0, true, false, true).timeout.connect(func(): quit(3))
	session = root.get_node("Session")
	var previous := {
		"active": session.campaign_active_stage,
		"map": session.block_war_map_id,
		"opponent": session.block_war_opponent_commander,
	}
	check(session.CAMPAIGN_STAGES[0].map_id == "flower_pool" and session.CAMPAIGN_STAGES[0].opponent_commander == &"rabbit", "first station selects the flower pool and rabbit")
	check(session.CAMPAIGN_STAGES[1].map_id == "forest_fork" and session.CAMPAIGN_STAGES[1].opponent_commander == &"frog", "second station selects the forest fork and frog")
	check(session.CAMPAIGN_STAGES[0].opponent_lazy_skills and not session.CAMPAIGN_STAGES[1].opponent_lazy_skills, "only the first authored opponent uses patient skills")
	await fixture(0)
	check(game._ai_strategy._skills.lazy_full_energy, "campaign initialization applies the opening opponent's policy")
	check(not game._ai_by_faction[0]._skills.lazy_full_energy, "the player's skill account is unaffected")
	attempt(10.0, 99.99)
	check(game.by_id[0].disruption_remaining == 0.0, "an affordable and useful seal waits below full energy")
	attempt(12.0, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == 0.0, "reaching full energy does not trigger an immediate skill")
	attempt(23.99, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == 0.0, "the rabbit rests for the complete twelve seconds")
	attempt(24.0, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == RULES.DISABLE_DURATION, "full energy and the patience window allow a useful real skill")
	check(game.faction_skills[1].energy == 75.0 and game.faction_skills[1].cooldowns[1] == RULES.RABBIT_COOLDOWNS[1], "the occasional seal pays the ordinary energy and cooldown cost")
	ready_again()
	attempt(24.0, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == 0.0, "refilling cannot chain a second cast at the same simulation time")
	attempt(36.0, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == 0.0, "a new patience window cannot bypass the eighteen-second decision gap")
	attempt(42.0, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == RULES.DISABLE_DURATION, "a later full-energy decision can cast again")
	ready_again()
	attempt(45.0, RULES.ENERGY_MAX)
	attempt(48.0, 99.0)
	attempt(57.0, RULES.ENERGY_MAX)
	attempt(68.99, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == 0.0, "losing full energy restarts the complete patience window")
	attempt(69.0, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == RULES.DISABLE_DURATION, "the restarted full-energy window eventually permits casting")
	ready_again()
	game.match_paused = true
	attempt(200.0, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == 0.0, "pause blocks the lazy policy too")
	game.match_paused = false
	game.finished = true
	attempt(220.0, RULES.ENERGY_MAX)
	check(game.by_id[0].disruption_remaining == 0.0, "finished battles never cast skills")
	game.finished = false
	var config := {
		"host_player_id": 77,
		"slots": [
			{"faction_id": 0, "team_id": 0, "player_id": 77, "name": "玩家", "kind": "human", "controller": "human", "commander": "squirrel"},
			{"faction_id": 1, "team_id": 1, "player_id": -1, "name": "兔子", "kind": "bot", "controller": "bot", "commander": "rabbit"},
		],
	}
	game.configure_match(config, 77)
	check(not game._ai_strategy._skills.lazy_full_energy, "online match configuration clears any campaign-only policy")
	attempt(230.0, 25.0)
	check(game.by_id[0].disruption_remaining == RULES.DISABLE_DURATION and game.faction_skills[1].energy == 0.0, "online rabbit skills work normally below full energy")
	await fixture(-1)
	check(not game._ai_strategy._skills.lazy_full_energy, "free play starts without campaign patience")
	attempt(10.0, 25.0)
	check(game.by_id[0].disruption_remaining == RULES.DISABLE_DURATION and game.faction_skills[1].energy == 0.0, "free-play rabbit retains its ordinary paid decisions")
	await fixture(1, &"frog")
	check(not game._ai_strategy._skills.lazy_full_energy and game.faction_skills[1].commander == &"frog", "second campaign opponent keeps normal frog tactics")
	await game.prepare_shutdown()
	session.campaign_active_stage = previous.active
	session.block_war_map_id = previous.map
	session.block_war_opponent_commander = previous.opponent
	print("CAMPAIGN_OPENING_AI checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
