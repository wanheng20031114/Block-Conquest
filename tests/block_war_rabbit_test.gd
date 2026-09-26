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
	# Skill scenarios begin funded, independently of the match's opening energy.
	for faction: int in game.faction_skills.size():
		refill(faction)
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
	home().kind = 2 # Isolate staged transport from natural production.
	var target: WarBuilding = game.buildings[2]
	var plan: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, home(), target, 100)
	plan.source = home()
	plan.target = target
	return plan

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
	check(game.skill_is_ground(0) and not game.skill_is_ground(1) and game.skill_is_ground(2) and not game.skill_is_ground(3), "rabbit Q and E target ground while W and R target buildings")
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
	var route: PackedVector3Array = game.map.get_building_route(home(), enemy())
	game.marches.send(home().building_id, enemy().building_id, 0, 40, route)
	var reverse := route.duplicate()
	reverse.reverse()
	game.marches.send(enemy().building_id, home().building_id, 1, 40, reverse)
	for unit: WarMarches.MarchUnit in game.marches._units:
		unit.distance = unit.order.length * 0.5
		game.marches._update_pose(unit)
	var recall_center: Vector3 = game.marches._units[0].order.curve.sample_baked(game.marches._units[0].distance)
	game.issue_order(home(), game.buildings[2], 25)
	var plans: Array[Dictionary] = game.RABBIT_SKILLS.recall_plan(game, recall_center)
	check(plans.size() == 80, "ground recall includes both factions without a twenty-four-person cap and excludes pending departures")
	var recalled: WarMarches.MarchUnit = plans[0].unit
	var previous_position := recalled.position
	recalled.reserved = true
	var total: int = game.marches.total_for(0)
	check(game.cast_ground_skill(2, recall_center), "ground recall casts across the battlefield")
	check(recalled.position.is_equal_approx(previous_position), "no teleport during recall")
	check(recalled.reserved, "in-flight projectile reservation retained")
	check(game.marches.total_for(0) == total, "recall preserves troop count")
	check(game.marches.incoming_for(home().building_id, 0) == 40 and game.marches.incoming_for(enemy().building_id, 1) == 40, "each faction returns to its own original source")
	game.marches.tick(0.1)
	refill()
	game.cast_ground_skill(2, recall_center)
	for plan: Dictionary in plans:
		check(plan.unit.order.target_id == plan.unit.order.source_id, "repeated recall retains the original source rather than the last destination")
	await reset()
	route = game.map.get_building_route(home(), game.buildings[2])
	game.marches.send(home().building_id, game.buildings[2].building_id, 0, 1, route)
	game.marches.tick(0.01)
	var nearby: WarMarches.MarchUnit = game.marches._units[0]
	check(game.cast_ground_skill(2, nearby.position), "a soldier just outside its own doorway can return")
	game.marches.tick(1.0)
	check(game.marches.total_for(0) == 0 and home().population == 61.0, "a short return enters its source exactly once")
	await reset()
	route = game.map.get_building_route(home(), game.buildings[2])
	game.marches.send(home().building_id, game.buildings[2].building_id, 0, 4, route)
	for unit: WarMarches.MarchUnit in game.marches._units:
		unit.distance = 0.5
		game.marches._update_pose(unit)
	var returning_at: Vector3 = game.marches._units[0].position
	home().population = 0.0
	game._on_unit_arrived(home().building_id, 1, 3.0)
	check(home().faction == 1 and home().population == 3.0, "recall source was captured by three hostile survivors")
	check(game.cast_ground_skill(2, returning_at), "soldiers still recall toward their captured original source")
	game.marches.tick(2.0)
	check(home().faction == 0 and game.marches.total_for(0) == 0, "returning soldiers fight the captured source and can recapture it")
	near(home().population, 1.0, "three returners trade with the hostile garrison and only one survivor enters")
	await reset()
	var plan := tunnel_plan()
	plan.source.population = 70.0
	check(not game.cast_skill(3, enemy()) and not game.cast_skill(3, plan.target), "R rejects hostile and neutral source buildings")
	var before: int = game.total_for(0)
	check(game.cast_skill(3, plan.source), "R enchants the chosen own source")
	near(plan.source.burrow_remaining, 15.0, "source waits fifteen seconds for a command")
	near(game.energy, 35.0, "source enchantment pays R once")
	check(game.marches.total_for(0) == 0 and plan.source.population == 70.0, "enchanting alone neither dispatches nor spends troops")
	check(game.issue_order(plan.source, plan.source, 100) == 0 and plan.source.burrow_remaining == 15.0, "an invalid self order preserves the enchantment")
	check(game.issue_order(plan.source, plan.target, 100) == 50, "next legal order caps the tunnel at fifty")
	check(plan.source.burrow_remaining == 0.0 and plan.source.population == 70.0 and plan.source.queued_population == 50 and plan.source.available_population == 20.0, "a seventy-person garrison reserves fifty and keeps twenty at home")
	check(game.total_for(0) == before and game.marches.get_units().is_empty(), "digging conserves the army without exposing passengers early")
	check(game.RABBIT_SKILLS.recall_plan(game, plan.entrance).is_empty() and game.RABBIT_SKILLS.recall_plan(game, plan.exit).is_empty(), "area recall excludes hidden tunnel reservations at either end")
	check(not game.cast_ground_skill(2, plan.exit) and game.energy == 35.0 and plan.source.queued_population == 50, "an empty exit recall cannot spend energy or redirect waiting tunnel troops")
	game.simulate(plan.dig_duration - 0.01)
	check(plan.source.population == 70.0 and game.marches.get_units().is_empty(), "no soldier leaves before digging completes")
	game.simulate(0.011)
	check(game.marches.get_units().size() == 6 and plan.source.population == 64.0, "digging completion releases and pays the first six")
	game.simulate(0.15)
	check(game.marches.get_units().size() == 6, "subsequent ranks retain a readable spacing")
	game.simulate(0.011)
	check(game.marches.get_units().size() == 12 and plan.source.population == 58.0, "the next six depart after 0.16 seconds")
	game.set_paused(true)
	var delay: float = game.marches._units[-1].spawn_delay
	game.simulate(10.0)
	near(game.marches._units[-1].spawn_delay, delay, "pause freezes tunnel emergence")
	game.set_paused(false)
	game.simulate(1.2)
	check(plan.source.queued_population == 0 and plan.source.population == 20.0, "all fifty leave in staged groups while twenty excess soldiers stay")
	game.simulate(1.0)
	check(plan.source.queued_population == 0 and plan.source.population == 20.0, "completion never dispatches the remaining twenty as an overflow march")
	await reset()
	plan = tunnel_plan()
	check(game.cast_skill(3, plan.source) and game.issue_order(plan.source, plan.target, 100) == 50, "burning-exit tunnel setup")
	game.simulate(plan.dig_duration - 0.01)
	game.world_effects.start_fire(plan.exit, 4.5, 1)
	game.simulate(3.0)
	check(game.marches.total_for(0) == 0 and plan.source.population == 10.0, "exit fire kills emerging passengers after their real departure")
	await reset()
	plan = tunnel_plan()
	plan.source.population = 101.0
	check(game.cast_skill(3, plan.source) and game.issue_order(plan.source, enemy(), 25) == 25, "a distant tunnel uses the ordinary percentage and floors fractional soldiers")
	check(plan.source.available_population == 76.0, "unselected soldiers remain available at the source")
	await reset()
	plan = tunnel_plan()
	plan.source.population = 1.0
	check(game.cast_skill(3, plan.source), "one soldier is enough to prepare a tunnel")
	check(game.issue_order(plan.source, plan.target, 25) == 0 and plan.source.burrow_remaining == 15.0, "a rounded-zero order does not consume the prepared tunnel")
	check(game.issue_order(plan.source, plan.target, 100) == 1, "tunnels no longer require twelve troops or ten left behind")
	await reset()
	plan = tunnel_plan()
	check(game.cast_skill(3, plan.source), "expiry setup")
	game.simulate(14.99)
	check(plan.source.burrow_remaining > 0.0, "enchantment remains just before fifteen seconds")
	game.set_paused(true)
	game.simulate(10.0)
	near(plan.source.burrow_remaining, 0.01, "pause freezes the pending enchantment")
	game.set_paused(false)
	game.simulate(0.02)
	check(plan.source.burrow_remaining == 0.0 and game.issue_order(plan.source, plan.target, 100) == 60, "expired enchantment leaves the next order as a full ordinary march")
	for detail: String in failures:
		printerr(detail)
	await game.prepare_shutdown()
	print("BLOCK_WAR_RABBIT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
