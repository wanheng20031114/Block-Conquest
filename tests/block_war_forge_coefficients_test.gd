extends SceneTree
## Independent balance examples exercise real faction ownership and combat.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL FORGE_COEFFICIENTS ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.00001, "%s: %s expected %s" % [label, actual, expected])

func reset() -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.shields.clear()
	game.finished = false
	game.morale.configure(game.faction_count)
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.faction = -1
		building.kind = 0
		building.level = 1
		building.population = 100.0
	game.by_id[0].faction = 0
	game.by_id[1].faction = 1
	game.sync_environment_bonuses()

func forge(id: int, faction: int) -> WarBuilding:
	var building: WarBuilding = game.by_id[id]
	building.kind = 2
	building.faction = faction
	return building

func _run() -> void:
	var session: Node = root.get_node("Session")
	var original_map: String = session.block_war_map_id
	session.block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	var attacks := [0.0, 0.3, 0.5, 0.7, 0.8, 0.8, 0.8]
	var defenses := [0.0, 0.15, 0.25, 0.35, 0.4, 0.4, 0.4]
	for count: int in attacks.size():
		reset()
		for index: int in count:
			forge(index + 2, 0)
		game.sync_environment_bonuses()
		near(game.attack_bonus(0), attacks[count], "owned forge attack at count %d" % count)
		near(game.defense_bonus(game.by_id[0]), defenses[count], "owned forge defense at count %d" % count)
		near(game.marches.base_speed(0), WarMarches.SPEED * (1.0 + count * 0.1), "speed keeps growing beyond the fourth forge")
		near(game.attack_bonus(1), 0.0, "enemy does not share forge attack")
		near(game.defense_bonus(game.by_id[1]), 0.0, "enemy does not share forge defense")
		near(game.marches.base_speed(2), WarMarches.SPEED, "ally does not share forge speed")
	reset()
	var defender: WarBuilding = game.by_id[1]
	defender.kind = 1
	for tier: int in 4:
		defender.level = tier + 1
		near(game.defense_bonus(defender), [0.25, 0.4, 0.6, 0.7][tier], "tower's independent defense tier %d" % (tier + 1))
		near(game.combat_multiplier(0, defender), 1.0 / [1.25, 1.4, 1.6, 1.7][tier], "tower defense divides damage instead of subtracting from it")
	forge(2, 0)
	forge(3, 0)
	forge(4, 1)
	game.morale.adjust(0, 1000.0)
	game.morale.adjust(1, 2000.0)
	game.shields[1] = 10.0
	# Attack: 1 + 0.50 + 0.10. Defense: 1 + 0.15 + 0.60 + 0.70.
	# Skill attack: 1 + 1.00 - 0.20. Skill defense: 1 + 0.25.
	var mixed := 1.6 / 2.45 * 1.8 / 1.25
	near(game.combat_multiplier(0, defender, 0.8), mixed, "environment and skills each sum internally and then multiply")
	game._on_unit_arrived(1, 0, 10.0, 0.8)
	near(defender.population, 100.0 - 10.0 * mixed, "actual casualties use both coefficient groups")
	reset()
	var first := forge(2, 0)
	forge(3, 0)
	game.morale.adjust(0, 500.0)
	game.sync_environment_bonuses()
	near(game.marches.base_speed(0), WarMarches.SPEED * 1.3, "two forge speeds and one morale star add within environment")
	first.begin_disruption(0.5)
	game.sync_environment_bonuses()
	near(game.attack_bonus(0), 0.3, "sealed forge loses its attack contribution")
	near(game.defense_bonus(game.by_id[0]), 0.15, "sealed forge loses its defense contribution")
	near(game.marches.base_speed(0), WarMarches.SPEED * 1.2, "sealed forge loses speed immediately")
	game.simulate(0.5)
	near(game.attack_bonus(0), 0.5, "restoration recounts active forges")
	near(game.marches.base_speed(0), WarMarches.SPEED * 1.3, "restoration refreshes speed at the exact boundary")
	first.population = 0.0
	game._on_unit_arrived(2, 1, 1.0)
	near(game.attack_bonus(0), 0.3, "capture removes the former owner's forge")
	near(game.defense_bonus(game.by_id[1]), 0.15, "capture grants the new owner's defensive contribution")
	near(game.marches.base_speed(1), WarMarches.SPEED * 1.1, "capture refreshes the new owner's march speed")
	reset()
	first = forge(2, 0)
	game.sync_environment_bonuses()
	check(game.begin_building_construction(first, 0, 0), "forge uses ordinary paid conversion")
	game.simulate(9.9)
	near(game.marches.base_speed(0), WarMarches.SPEED * 1.1, "outgoing construction retains the forge's speed")
	game.simulate(0.1)
	near(game.attack_bonus(0), 0.0, "completed conversion removes forge attack")
	near(game.defense_bonus(game.by_id[0]), 0.0, "completed conversion removes forge defense")
	near(game.marches.base_speed(0), WarMarches.SPEED, "completed conversion removes forge speed")
	await game.prepare_shutdown()
	session.block_war_map_id = original_map
	print("FORGE_COEFFICIENTS ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
