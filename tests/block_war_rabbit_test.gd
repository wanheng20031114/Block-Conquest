extends SceneTree

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.002, "%s actual=%s expected=%s" % [label, actual, expected])

func reset() -> void:
	if game != null:
		await game.prepare_shutdown()
	root.get_node("Session").block_war_map_id = "rift"
	root.get_node("Session").block_war_commander = &"rabbit"
	root.get_node("Session").block_war_opponent_commander = &"squirrel"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	await physics_frame
	await process_frame

func home() -> WarBuilding:
	return game.buildings[0]

func enemy() -> WarBuilding:
	for building: WarBuilding in game.buildings:
		if building.faction == 1:
			return building
	return null

func refill(faction: int = 0) -> void:
	game.faction_skills[faction].energy = 100.0
	game.faction_skills[faction].cooldowns.fill(0.0)

func tunnel_plan() -> Dictionary:
	home().population = 60.0
	for building: WarBuilding in game.buildings:
		var plan: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, building, 0)
		if not plan.is_empty():
			return plan
	return {}

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	await reset()
	check(game.faction_skills[0].commander == &"rabbit", "selected rabbit reaches match")
	check(game.faction_skills[1].commander == &"squirrel", "opponent independently selected")
	for index: int in 4:
		var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % index)
		check(button.get_node("Icon").texture == RULES.RABBIT_ICONS[index], "rabbit bottom icon %d" % index)
		near(button.custom_minimum_size.x, 84.0, "existing button footprint")
		check(button.hint.title == RULES.RABBIT_NAMES[index], "rabbit tooltip %d" % index)
	check(game.skill_is_ground(0) and not game.skill_is_ground(1) and not game.skill_is_ground(2) and not game.skill_is_ground(3), "rabbit targeting differs from squirrel")
	var center := Vector3(-22, 0, 10)
	check(game.cast_ground_skill(0, center), "rabbit dash casts")
	near(game.energy, 75.0, "dash paid once")
	near(game.cooldowns[0], 24.0, "dash cooldown")
	game.marches.send(0, 1, 0, 1, PackedVector3Array([center, center + Vector3(20, 0, 0)]))
	game.marches.send(1, 0, 1, 1, PackedVector3Array([center, center + Vector3(20, 0, 0)]))
	game.marches.tick(0.2)
	near(game.marches._units[0].distance, 1.054, "local own dash")
	near(game.marches._units[1].distance, 0.62, "hostile unaffected")
	game.marches.tick(6.0)
	check(game.marches.haste_zones.is_empty(), "dash expires")
	for level: int in range(1, 5):
		await reset()
		var target := enemy()
		target.level = level
		target.population = 10.0
		check(game.cast_skill(1, target), "seal residence level %d" % level)
		near(game.energy, 75.0, "seal cost")
		game.simulate(6.0)
		near(target.population, 10.0, "no natural production during entire six seconds")
		near(target.disruption_remaining, 0.0, "exact expiry")
		game.simulate(1.0)
		near(target.population, 10.0 + target.production_rate, "resume without catchup")
	await reset()
	var target := enemy()
	target.population = 5.0
	check(game.cast_skill(0, target, 1), "enemy recruitment begins")
	game.simulate(2.0)
	var population := target.population
	check(game.cast_skill(1, target), "seal ongoing recruitment")
	game.simulate(6.0)
	near(target.population, population, "both natural and recruitment blocked")
	game.simulate(1.0)
	near(target.population, population + 1.0, "expired recruitment not refunded")
	await reset()
	target = enemy()
	target.kind = 2
	target.level = 1
	var second: WarBuilding = game.buildings[2]
	second.faction = 1
	second.kind = 2
	second.level = 1
	near(game.attack_bonus(1), 0.2, "two forges add")
	check(game.cast_skill(1, target), "seal forge")
	near(game.attack_bonus(1), 0.1, "only sealed forge excluded")
	home().kind = 1
	home().level = 1
	home().population = 100.0
	game._on_unit_arrived(home().building_id, 1, 20.0)
	near(home().population, 79.0, "live additive damage 20*(1-.05+.10)")
	game.set_paused(true)
	var visual_age: float = target.get_node("Disruption").age
	game.simulate(20.0)
	near(target.disruption_remaining, 6.0, "pause freezes disable")
	near(target.get_node("Disruption").age, visual_age, "pause freezes seal animation")
	game.set_paused(false)
	game.simulate(6.0)
	near(game.attack_bonus(1), 0.2, "forge bonus restored")
	await reset()
	target = enemy()
	target.kind = 1
	target.level = 3
	target.refresh_visual()
	var start := target.global_position + Vector3(-6, 0, 0)
	game.marches.send(0, target.building_id, 0, 40, PackedVector3Array([start, start + Vector3(50, 0, 0)]))
	game.marches.tick(0.25)
	game._fire_tower(target)
	check(not game.projectiles.is_empty(), "tower starts real projectile")
	var victim: WarMarches.MarchUnit = game.projectiles[0].target
	check(game.cast_skill(1, target), "seal firing tower")
	near(game.defense_bonus(target), 0.15, "tower defense retained")
	game.simulate(0.6)
	check(not victim.alive, "already launched cannonball still hits")
	game.simulate(5.3)
	check(game.projectiles.is_empty(), "no new cannon fire while sealed")
	game.simulate(0.1)
	check(not game.projectiles.is_empty(), "tower resumes at expiry")
	await reset()
	target = enemy()
	target.begin_construction(2)
	game.simulate(8.0)
	check(game.cast_skill(1, target), "seal during conversion")
	game.simulate(2.0)
	check(target.kind == 2, "construction continues")
	near(game.attack_bonus(1), 0.0, "new forge remains sealed")
	game.simulate(4.0)
	near(game.attack_bonus(1), 0.1, "converted forge recovers")
	refill()
	check(game.cast_skill(1, target), "seal before capture")
	target.population = 0.0
	game._on_unit_arrived(target.building_id, 0, 1.0)
	near(target.disruption_remaining, 0.0, "capture clears seal")
	near(game.attack_bonus(0), 0.1, "new owner receives working forge")
	await reset()
	check(not game.cast_skill(1, home()), "reject allied seal")
	check(not game.cast_skill(1, game.buildings[2]), "reject neutral seal")
	near(game.energy, 100.0, "invalid targets cost nothing")
	target = enemy()
	check(game.cast_skill(1, target), "first seal valid")
	refill()
	check(not game.cast_skill(1, target), "cannot refresh seal")
	near(game.energy, 100.0, "duplicate seal does not charge")
	await reset()
	var route: PackedVector3Array = game.map.get_building_route(home(), game.buildings[2])
	game.marches.send(home().building_id, game.buildings[2].building_id, 0, 40, route)
	for unit: WarMarches.MarchUnit in game.marches._units:
		unit.distance = 0.3
		game.marches._update_pose(unit)
	var plans: Array[Dictionary] = game.RABBIT_SKILLS.recall_plan(game, home(), 0)
	check(plans.size() == 24, "recall capped at 24 nearby exposed soldiers")
	var recalled: WarMarches.MarchUnit = plans[0].unit
	var previous_position := recalled.position
	recalled.reserved = true
	var total: int = game.marches.total_for(0)
	check(game.cast_skill(2, home()), "recall casts")
	check(recalled.position.is_equal_approx(previous_position), "no teleport during recall")
	check(recalled.reserved, "in-flight projectile reservation retained")
	check(game.marches.total_for(0) == total, "recall preserves troop count")
	check(game.marches.incoming_for(home().building_id, 0) == 24, "only selected soldiers retarget")
	await reset()
	var plan := tunnel_plan()
	check(not plan.is_empty(), "existing map has eligible local tunnel")
	if not plan.is_empty():
		var before: int = game.total_for(0)
		check(game.cast_skill(3, plan.target), "tunnel casts")
		near(plan.source.population, 30.0, "real garrison pays 30")
		check(game.total_for(0) == before, "hidden passengers remain in faction total")
		near(game.energy, 35.0, "tunnel cost")
		check(game.marches.get_units().size() == 6, "first six passengers appear immediately on release")
		game.simulate(0.15)
		check(game.marches.get_units().size() == 6, "subsequent ranks retain a readable spacing")
		game.simulate(0.02)
		check(game.marches.get_units().size() == 12, "next six arrive after 0.16 seconds")
		game.set_paused(true)
		var delay: float = game.marches._units[-1].spawn_delay
		game.simulate(10.0)
		near(game.marches._units[-1].spawn_delay, delay, "pause freezes tunnel emergence")
		game.set_paused(false)
		game.simulate(0.48)
		check(game.marches.get_units().size() == 30, "all thirty passengers emerge within 0.65 seconds")
	await reset()
	plan = tunnel_plan()
	if not plan.is_empty():
		check(game.cast_skill(3, plan.target), "tunnel into known burning exit setup")
		game.world_effects.start_fire(plan.exit, 4.5, 1)
		game.simulate(3.0)
		check(game.marches.total_for(0) == 0, "exit fire kills all emerging passengers")
	await reset()
	plan = tunnel_plan()
	if not plan.is_empty():
		plan.source.population = 22.0
		check(game.cast_skill(3, plan.target), "minimum tunnel sends twelve")
		near(plan.source.population, 10.0, "source reserve respected")
		check(game.marches.total_for(0) == 12, "minimum batch contains real twelve")
	for detail: String in failures:
		printerr(detail)
	await game.prepare_shutdown()
	print("BLOCK_WAR_RABBIT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
