extends RefCounted
## Authored supplies and enemy waves for the continuous core course only.
## Ordinary construction, combat and skills remain in the battle rule engine.
const CONSTRUCTION_SECONDS := 1.2
var game: Node3D
var beat := ""

func _init(battle: Node3D) -> void:
	game = battle

func prepare() -> void:
	beat = str(game.phase.get("beat", ""))
	game.wave_started = false
	game.tower_shots = 0
	game.haste_seen = false
	game.haste_arrived = false
	game.shield_damage_seen = false
	game.burned_enemies = 0
	match beat:
		"make_forge":
			_supply(1, 35.0)
		"forge_trial":
			_supply(0, 40.0)
			_supply(2, 24.0)
			game.percentage = 50
			_reset_morale()
		"energy_demo":
			game.energy = 25.0
		"recruit_defense":
			_supply(2, 4.0)
			game.energy = 100.0
			_reset_morale()
		"counterattack":
			_supply(2, 40.0)
			_supply(3, 65.0)
			game.percentage = 50
		"haste_attack":
			game.energy = 100.0
		"shield_defense":
			_supply(2, 19.0)
			game.energy = 100.0
			_reset_morale()
			_approaching_wave(24, 6)
		"fire_defense":
			_supply(2, 6.0)
			game.energy = 100.0
			_reset_morale()
			# Let the whole column leave before aiming: otherwise impact damage
			# to the source building can cancel queued soldiers without burning
			# them on the road, obscuring the lesson's visible result.
			_approaching_wave(40, 40)
	game.update_hud()

func begin_observation() -> void:
	if beat == "tower_demo" and not game.wave_started:
		_wave(8, 1)

func after_command() -> void:
	if game.phase.action == "convert":
		game.by_id[int(game.phase.target)].construction_remaining = CONSTRUCTION_SECONDS
		game.update_hud()
	elif beat == "recruit_defense":
		_wave(22, 2)

func objective_met() -> bool:
	match beat:
		"make_tower", "make_forge", "make_energy":
			var building: WarBuilding = game.by_id[int(game.phase.target)]
			return game.accepted_action and not building.is_constructing and building.kind == int(game.phase.kind)
		"tower_demo":
			return game.wave_started and game.tower_shots >= 2 and _defended(1) and game.projectiles.is_empty()
		"forge_trial":
			return game.accepted_action and game.by_id[2].faction == 0 and game.marches.incoming_for(2, 0) == 0
		"energy_demo":
			return game.energy >= game.phase_start_energy + 3.0
		"recruit_defense":
			return game.accepted_action and game.wave_started and _defended(2) and game.faction_skills[0].durations[0] <= 0.0
		"counterattack":
			return game.accepted_action and game._army_exposed(0) >= 6
		"haste_attack":
			return game.accepted_action and game.haste_seen and game.haste_arrived and game.marches.incoming_for(3, 0) == 0 and game.by_id[3].faction == 1
		"shield_defense":
			return game.accepted_action and game.shield_damage_seen and _defended(2)
		"fire_defense":
			return game.accepted_action and game.burned_enemies == 40 and _defended(2) and game.fire_states.is_empty()
	return false

func failure_reason() -> String:
	if beat == "fire_defense" and game.accepted_action and game.fire_states.is_empty() and game.burned_enemies < 40:
		return "还有敌军漏过了火焰。\n对准队伍中央，再试一次；不用重学前面的步骤。"
	return ""

func retry_current() -> void:
	assert(beat == "fire_defense")
	# This rehearsal has a fixed opening, so a missed shot restarts only its
	# wave. Cancel queued departures before replenishing either garrison.
	game.marches.clear()
	game.by_id[2].faction = 0
	game.by_id[2].level = 1
	game.by_id[2].refresh_visual()
	game.cooldowns[3] = 0.0

func _defended(target: int) -> bool:
	return game.marches.total_for(1) == 0 and game.by_id[target].faction == 0 and game.by_id[target].population > 0.0

func _supply(id: int, population: float) -> void:
	assert(game.by_id[id].queued_population == 0)
	game.by_id[id].population = population
	game.by_id[id].refresh_visual()

func _reset_morale() -> void:
	for faction: int in 2:
		game.morale.adjust(faction, -game.morale.points(faction))
	game.sync_environment_bonuses()

func _wave(count: int, target: int) -> void:
	_supply(3, float(count))
	var sent: int = game.issue_order(game.by_id[3], game.by_id[target], 100, 1)
	assert(sent == count)
	game.wave_started = true

func _approaching_wave(count: int, exposed: int) -> void:
	# Present a real, already approaching column, then give the player unlimited
	# aiming time. All departures and movement still use the native simulation.
	var was_paused: bool = game.simulation_paused
	game.simulation_paused = false
	_wave(count, 2)
	for tick: int in 100:
		game.simulate(0.05)
		if game._army_exposed(1) >= exposed:
			break
	game.simulation_paused = was_paused
