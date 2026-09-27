extends SceneTree
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const TACTICS := preload("res://scripts/block_war/war_ai_skills.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.001, "%s: %.5f expected %.5f" % [label, actual, expected])

func reset() -> void:
	if game != null:
		await game.prepare_shutdown()
	var session := root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"frog"
	session.block_war_opponent_commander = &"frog"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for state: RefCounted in game.faction_skills:
		state.energy = 100.0
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
		building.population = 100.0
		building.refresh_visual()

func soldier(faction: int, at: Vector3, destination: int = 0, length: float = 100.0) -> WarMarches.MarchUnit:
	game.marches.send(1 - faction if faction in [0, 1] else 0, destination, faction, 1, PackedVector3Array([at, at + Vector3(length, 0, 0)]))
	return game.marches._units[-1]

func verify_lifetime() -> void:
	await reset()
	var center := Vector3(-22, 0, 10)
	var own := soldier(0, center)
	var enemy := soldier(1, center + Vector3(0, 0, 1))
	var ally := soldier(2, center + Vector3(0, 0, -1))
	game.marches.apply_frog_field(0, 0, center)
	check(enemy.weakened and not own.weakened and not ally.weakened, "mist weakens only hostile soldiers immediately")
	for unit: WarMarches.MarchUnit in [own, enemy, ally]:
		check(not game.marches.tower_can_target(unit), "mist blocks cannon sight for every faction")
	game.marches.apply_frog_field(2, 0, center)
	check(own.cloaked and not enemy.cloaked and not ally.cloaked, "cloak affects own faction only")
	check(game.marches.apply_frog_field(2, 0, center) == 0, "already hidden squad cannot consume another cloak")
	var late := soldier(0, center)
	check(not late.cloaked, "late entrants do not inherit the instant cloak cast")
	game.marches.tick(1.2)
	check(not game.marches.weak_zones.is_empty(), "cloud is still active after squad leaves")
	check(game.marches.tower_can_target(enemy), "uncloaked enemy can be targeted after leaving cloud")
	check(enemy.weakened, "leaving the cloud does not remove weakness")
	game.marches.tick(18.8)
	check(game.marches.weak_zones.is_empty(), "the cloud itself still lasts only three seconds")
	check(own.alive and own.cloaked and not game.marches.tower_can_target(own), "cloak remains effective after twenty seconds and leaving selection circle")
	check(enemy.weakened, "weakness persists long after the cloud expires")
	near(game.marches.projected_attack_bonus(enemy), -0.2, "lasting weakness is included in arrival prediction")
	var population: float = game.by_id[0].population
	game.marches.tick(20.0)
	check(game.marches._units.is_empty(), "all four march objects are consumed at entry")
	near(game.by_id[0].population, population + 3.0 - 0.8, "weak enemy attack and full allied transport resolve once")
	var fresh := soldier(0, center)
	check(not fresh.cloaked and not fresh.weakened, "new departures start without old march statuses")
	check(game.marches.get_node("CloakedMilitia").multimesh.visible_instance_count == 0, "entry removes all transparent instances")

func verify_crossings() -> void:
	var center := Vector3(-22, 0, 10)
	for boosted: bool in [false, true]:
		for small_steps: bool in [false, true]:
			await reset()
			var unit := soldier(1, center - Vector3(5, 0, 0))
			if boosted:
				unit.rush_remaining = 8.0
			game.marches.apply_frog_field(0, 0, center)
			near(game.marches.projected_attack_bonus(unit), -0.2, "AI predicts weakness acquired while crossing cloud")
			check(not unit.weakened, "prediction does not prematurely apply future weakness")
			for step: int in (80 if small_steps else 1):
				game.marches.tick(0.05 if small_steps else 4.0)
			check(unit.weakened and unit.alive and unit.position.x > center.x + 3.5, "whole-cloud crossing persists with rush and long/short ticks")
			check(game.marches.weak_zones.is_empty(), "crossing result survives the same tick expiring fog")
	await reset()
	var delayed := soldier(1, center)
	delayed.spawn_delay = 4.0
	game.marches.apply_frog_field(0, 0, center)
	check(not delayed.weakened, "hidden tunnel passenger is not selected by fog")
	game.marches.tick(5.0)
	check(not delayed.weakened, "fog that expires before emergence cannot poison the passenger")
	await reset()
	var floating := soldier(1, center - Vector3(5, 0, 0))
	game.marches.apply_frog_field(1, 0, floating.position)
	game.marches.apply_frog_field(0, 0, center)
	near(game.marches.projected_attack_bonus(floating), 0.0, "arrival forecast respects levitation preventing entry before expiry")
	game.marches.tick(5.0)
	check(not floating.weakened, "crossing after landing and fog expiry remains unaffected")
	await reset()
	var waiting := soldier(1, center - Vector3(5, 0, 0))
	waiting.distance = -12.0
	game.marches.apply_frog_field(0, 0, center)
	game.marches.tick(6.0)
	check(not waiting.weakened, "queued ranks cannot be affected before real doorway exposure")
	await reset()
	var replaced := soldier(1, center - Vector3(5, 0, 0))
	game.marches.apply_frog_field(0, 0, center)
	near(game.marches.projected_attack_bonus(replaced), -0.2, "original cloud is cached in route forecast")
	game.marches.apply_frog_field(0, 0, center + Vector3(25, 0, 0))
	near(game.marches.projected_attack_bonus(replaced), 0.0, "replacing a cloud invalidates previous path intersections")

func verify_towers() -> void:
	for cloak: bool in [false, true]:
		await reset()
		var tower: WarBuilding = game.buildings[0]
		tower.kind = 1
		tower.refresh_visual()
		var unit := soldier(1, tower.global_position + Vector3(5, 0, 0))
		game._fire_tower(tower)
		check(game.projectiles.size() == 1 and unit.reserved, "cannon has a real shot in flight before concealment")
		game.marches.apply_frog_field(2 if cloak else 0, 1, unit.position)
		game._tick_projectiles(1.0)
		check(unit.alive and not unit.reserved and unit.intercepted_by == -1 and game.projectiles.is_empty(), "concealment defeats an in-flight shot and releases target reservation")
		game._fire_tower(tower)
		check(game.projectiles.is_empty(), "tower cannot start another shot against protected soldier")
		var visible := soldier(1, tower.global_position - Vector3(5, 0, 0))
		game._fire_tower(tower)
		check(game.projectiles.size() == 1 and game.projectiles[0].target == visible, "tower still attacks another visible enemy")
		game._tick_projectiles(1.0)
		check(not visible.alive and unit.alive, "visible enemy dies while hidden soldier survives")
		if not cloak:
			# Let fog expire with the soldier held inside it, then test sight alone.
			unit.levitation_remaining = 3.0
			game.marches.tick(3.0)
			check(game.marches.tower_can_target(unit), "fog expiry restores cannon sight without waiting for entry")
			game._fire_tower(tower)
			game._tick_projectiles(1.0)
			check(not unit.alive, "an uncloaked soldier is vulnerable once its cloud dissipates")
	await reset()
	var tower: WarBuilding = game.buildings[0]
	tower.kind = 1
	tower.refresh_visual()
	var edge := soldier(1, tower.global_position + Vector3(5, 0, 0))
	game._fire_tower(tower)
	game.marches.apply_frog_field(0, 1, edge.position - Vector3(3.45, 0, 0))
	game._tick_projectiles(0.01)
	game.marches.tick(0.05)
	check(game.marches.tower_can_target(edge), "soldier reappears after crossing the cloud edge")
	game._tick_projectiles(1.0)
	check(edge.alive and not edge.reserved, "a lost cannonball cannot reacquire when target reappears")
	game._fire_tower(tower)
	game._tick_projectiles(1.0)
	check(not edge.alive, "a new shot can acquire the reappeared soldier normally")
	await reset()
	var home: WarBuilding = game.buildings[0]
	var hidden := soldier(1, home.global_position + Vector3(5, 0, 0))
	game.marches.apply_frog_field(2, 1, hidden.position)
	game.marches.apply_frog_field(0, 0, hidden.position)
	game.faction_skills[0].commander = RULES.BEAR
	check(game.cast_skill(3, home), "bear orb can launch through cloak and mist")
	game.bear.tick_projectiles(game, 0.5)
	check(not hidden.alive, "magic orb still kills a concealed soldier")
	var burned := soldier(0, home.global_position)
	game.marches.apply_frog_field(2, 0, burned.position)
	game.marches.ignite_at(burned.position, 1.0, 1)
	check(not burned.alive, "fire still kills cloaked soldiers")

func verify_recall_and_ai() -> void:
	await reset()
	var home: WarBuilding = game.buildings[0]
	var target: WarBuilding = game.buildings[1]
	game.marches.send(home.building_id, target.building_id, 0, 6, game.map.get_building_route(home, target))
	game.marches.tick(4.0)
	var unit: WarMarches.MarchUnit = game.marches._units[0]
	game.marches.apply_frog_field(2, 0, unit.position)
	game.marches.apply_frog_field(0, 1, unit.position)
	check(game.RABBIT_SKILLS.recall(game, unit.position, 0) == 6, "recall selects a squad carrying both lasting effects")
	game.marches.tick(1.0)
	check(unit.cloaked and unit.weakened, "turning back retains cloak and weakness")
	var before := home.population
	game.marches.tick(5.0)
	near(home.population, before + 6.0, "weakened cloaked returners deliver full population")
	await reset()
	game.faction_skills[1].cooldowns.fill(100.0)
	game.faction_skills[1].cooldowns[2] = 0.0
	var tower: WarBuilding = game.buildings[0]
	tower.kind = 1
	for index: int in 8:
		soldier(1, tower.global_position + Vector3(5, 0, index * 0.15), 1)
	game.elapsed = 15.0
	TACTICS.new(1).take_turn(game)
	check(game.faction_skills[1].cooldowns[2] > 0.0, "AI uses cloak to protect a reinforcing squad from a tower")
	near(game.faction_skills[1].energy, 80.0, "AI pays ordinary cloak cost")
	game.faction_skills[1].cooldowns[2] = 0.0
	TACTICS.new(1).take_turn(game)
	near(game.faction_skills[1].energy, 80.0, "AI does not spend again on an already invisible squad")

func run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	await verify_lifetime()
	await verify_crossings()
	await verify_towers()
	await verify_recall_and_ai()
	await game.prepare_shutdown()
	print("FROG_PERSISTENCE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
