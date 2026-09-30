extends SceneTree
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const TACTICS := preload("res://scripts/block_war/war_ai_skills.gd")
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
	check(absf(actual - expected) < 0.002, "%s: %s expected %s" % [label, actual, expected])

func reset(map_id: String = "rift") -> void:
	if game != null:
		await game.prepare_shutdown()
	root.get_node("Session").block_war_map_id = map_id
	root.get_node("Session").block_war_commander = &"bear"
	root.get_node("Session").block_war_opponent_commander = &"bear"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	for state: RefCounted in game.faction_skills:
		state.energy = 100.0
	await process_frame

func refill(faction: int = 0) -> void:
	game.faction_skills[faction].energy = 100.0
	game.faction_skills[faction].cooldowns.fill(0.0)

func pair(faction: int = 0) -> Array[WarBuilding]:
	var a: WarBuilding = game.buildings[0]
	var b: WarBuilding = game.buildings[2]
	a.faction = faction
	b.faction = faction
	# Fixed-level non-defensive buildings isolate the link's casualty splitting.
	a.kind = 3
	b.kind = 3
	a.population = 100.0
	b.population = 100.0
	b.global_position = a.global_position + Vector3(10, 0, 0)
	return [a, b]

func drag_skill(index: int, at: Vector2) -> void:
	game.update_hud()
	var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % index)
	for down: bool in [true, false]:
		var point := button.get_global_rect().get_center() if down else at
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		root.push_input(motion, true)
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		if down:
			check(game.armed_skill == index, "native hold arms bear skill %d" % index)

func _run() -> void:
	create_timer(110.0, true, false, true).timeout.connect(func(): quit(3))
	await reset()
	check(game.faction_skills[0].commander == RULES.BEAR, "bear reaches battle")
	game.energy = 30.0
	check(game.can_cast_skill(0), "Q available from the funded thirty-energy fixture")
	for i: int in 4:
		check(game.skill_is_ground(i) == (i == 1), "bear target kind %d" % i)
		check(game.hud.get_node("UI/Skills/Row/Skill%d/Icon" % i).texture == RULES.BEAR_ICONS[i], "bottom icon %d" % i)
	var home: WarBuilding = game.buildings[0]
	check(not game.cast_skill(0, home), "idle construction rejects Q")
	near(game.energy, 30.0, "invalid Q is free")
	for kind: int in [0, 1]:
		for level: int in range(1, 4 if kind == 0 else 3):
			refill()
			home.kind = kind
			home.level = level
			home.population = 100.0
			game.select_building(home)
			var cost := home.upgrade_cost
			game.upgrade_selected()
			check(home.construction_cost == cost and home.is_constructing, "player records actual paid cost")
			check(game.cast_skill(0, home), "Q completes paid upgrade %d/%d" % [kind, level])
			near(home.population, 100.0 - cost + floorf(cost * 0.5), "half refund from actual cost rounds down to whole troops")
			check(home.level == level + 1 and not home.is_constructing and home.construction_cost == 0, "level changes immediately and consumes receipt")
			refill()
			check(not game.cast_skill(0, home), "completed task cannot refund twice")
			near(game.energy, 100.0, "duplicate invalid Q stays free")
	for kind: int in [2, 0, 1]:
		refill()
		home.population = 100.0
		game.convert_selected(kind)
		check(game.cast_skill(0, home), "Q completes conversion %d" % kind)
		near(home.population, 90.0, "conversion always refunds 10 of paid 20")
		check(home.kind == kind and home.level == 1, "conversion shape/function takes effect immediately")
	refill()
	home.population = 100.0
	game.upgrade_selected()
	game._on_unit_arrived(home.building_id, 1, 300)
	check(home.construction_cost == 0 and not home.is_constructing, "capture invalidates construction receipt")
	check(not game.cast_skill(0, home), "enemy captured building cannot be refunded")

	await reset()
	var buildings := pair()
	var a := buildings[0]
	var b := buildings[1]
	check(game.cast_skill(2, a), "E finds nearby own support")
	check(not game._valid_skill_target(2, b), "cannot create reverse/cyclic link")
	game._on_unit_arrived(a.building_id, 1, 21.0)
	near(a.population, 90.0, "21 damage leaves target losing 10")
	near(b.population, 89.0, "21 damage leaves support losing 11")
	game._on_unit_arrived(b.building_id, 1, 2.0)
	near(a.population, 90.0, "support being attacked does not transfer backward")
	near(b.population, 87.0, "support direct damage remains ordinary")
	await reset()
	buildings = pair()
	a = buildings[0]
	b = buildings[1]
	game.cast_skill(2, a)
	for i: int in 21:
		game._on_unit_arrived(a.building_id, 1, 1.0)
		check(a.population == floorf(a.population) and b.population == floorf(b.population), "every linked casualty integer %d" % i)
	near(a.population, 90, "separate arrivals preserve target half")
	near(b.population, 89, "separate arrivals preserve odd extra on support")
	await reset()
	buildings = pair()
	a = buildings[0]
	b = buildings[1]
	a.kind = 1
	a.level = 1
	b.kind = 1
	b.level = 3
	var forge: WarBuilding = game.buildings[3]
	forge.faction = 1
	forge.kind = 2
	game.cast_skill(2, a)
	for i: int in 20:
		game._on_unit_arrived(a.building_id, 1, 1.0)
	near(a.population, 90, "20 times 1.30 divided by 1.25 settles twenty whole casualties")
	near(b.population, 90, "support does not apply its own tower defense again")
	var before := float(game.bear.links[a.building_id].remaining)
	game.set_paused(true)
	game.simulate(2.0)
	near(game.bear.links[a.building_id].remaining, before, "pause freezes link")
	near(game.world_effects.get_node("Bear/Motes").speed_scale, 0, "pause freezes native particles")
	game.set_paused(false)
	game.simulate(8.0)
	check(game.bear.links.is_empty(), "link expires exactly at eight seconds")
	near(game.active_durations[2], 0.0, "expired link clears HUD timer")

	await reset()
	buildings = pair()
	a = buildings[0]
	b = buildings[1]
	b.population = 3.0
	game.cast_skill(2, a)
	game._on_unit_arrived(a.building_id, 1, 21.0)
	near(a.population, 82, "unfunded share returns to receiver")
	near(b.population, 0, "support loses only its three actual soldiers")
	check(b.faction == 0 and game.bear.links.is_empty(), "sharing does not capture support, exhausted link ends")
	near(game.active_durations[2], 0.0, "early exhaustion clears HUD timer")
	await reset()
	buildings = pair()
	a = buildings[0]
	b = buildings[1]
	game.cast_skill(2, a)
	refill()
	game.cast_skill(3, b)
	game._on_unit_arrived(a.building_id, 1, 21.0)
	near(a.population, 90, "E+R target still takes its own integer half")
	near(b.population, 89, "warded support pays its assigned half without applying defense a second time")
	game._on_unit_arrived(a.building_id, 1, 500.0)
	check(a.faction == 1 and game.bear.links.is_empty(), "capture clears link immediately")
	await reset()
	buildings = pair()
	a = buildings[0]
	b = buildings[1]
	game.cast_skill(2, a)
	game.world_effects.start_fire(a.global_position, 4.5, 1)
	game._tick_fire_buildings()
	near(a.population, 88, "25 fire damage assigns 12 to selected building")
	near(b.population, 87, "25 fire damage assigns 13 to support")
	refill()
	game.cast_skill(3, a)
	game.world_effects.start_fire(a.global_position, 4.5, 1)
	game._tick_fire_buildings()
	near(a.population, 82, "ward halves the next fire hit before integer link sharing")
	near(b.population, 81, "warded target shares the reduced fire damage with support")

	await reset("highland")
	var center := Vector3(-22, 0, 10)
	var route := PackedVector3Array([center, center + Vector3(60, 0, 0)])
	game.marches.send(1, 0, 1, 1, route)
	game.marches.send(0, 1, 0, 1, route)
	game.marches.send(2, 1, 2, 1, route)
	check(game.cast_ground_skill(1, center), "W ground drag casts")
	near(game.marches.speed_multiplier(game.marches._units[0]), 0.4, "W slow immediate")
	game.marches.tick(1.0)
	near(game.marches._units[0].distance, 1.24, "enemy is 60 percent slower")
	near(game.marches._units[1].distance, 3.1, "own soldier unaffected")
	near(game.marches._units[2].distance, 3.1, "allied soldier unaffected")
	game.marches.tick(3.0)
	check(game.marches.slow_zones.is_empty(), "W expires at four seconds")
	game.marches.clear()
	route = PackedVector3Array([center - Vector3(8, 0, 0), center + Vector3(60, 0, 0)])
	game.marches.send(1, 0, 1, 1, route)
	game.marches.create_slow_zone(0, center, 4.5, 4.0)
	game.marches.create_haste_zone(1, center, 6.0, 3.0, 1.6)
	game.marches.apply_rush(1, center - Vector3(8, 0, 0), 4.0, 6.0)
	var long_distance: float = game.marches.movement_distance(game.marches._units[0], 8.0)
	for i: int in 160:
		game.marches.tick(0.05)
	near(game.marches._units[0].distance, long_distance, "slow/haste/rush entry, exit and expiry independent of frame size")

	await _ward_defense_checks()
	await _ward_projectile_checks()
	await _ward_arrival_checks()

	for ability: int in 4:
		await reset()
		buildings = pair(1)
		a = buildings[0]
		b = buildings[1]
		game.faction_skills[1].cooldowns.fill(100.0)
		game.faction_skills[1].cooldowns[ability] = 0.0
		if ability == 0:
			a.population -= 20
			a.begin_construction(0, 20)
		else:
			a.population = 10
			var start := a.global_position + Vector3(7, 0, 0)
			game.marches.send(1, a.building_id, 0, 30, PackedVector3Array([start, a.global_position + Vector3(2.5, 0, 0)]))
			game.marches.tick(0.7)
		var tactics := TACTICS.new(1)
		game.elapsed = 20.0
		tactics.take_turn(game)
		check(game.faction_skills[1].cooldowns[ability] > 0.0, "AI uses bear ability %d" % ability)
		near(game.faction_skills[1].energy, 100.0 - RULES.BEAR_COSTS[ability], "AI pays ability %d" % ability)
	await reset()
	buildings = pair()
	a = buildings[0]
	b = buildings[1]
	game.select_building(a)
	game.convert_selected(0)
	root.size = Vector2i(1600, 900)
	await create_timer(0.6).timeout
	await physics_frame
	var aim: Vector2 = game.camera.unproject_position(a.get_node("PopulationBadge").global_position)
	drag_skill(0, aim)
	check(not a.is_constructing and game.cooldowns[0] > 0.0, "native Q release completes construction")
	refill()
	drag_skill(1, game.camera.unproject_position(Vector3(-22, 0, 10)))
	check(game.marches.slow_zones.has(0), "native W release creates ground slow")
	refill()
	drag_skill(2, aim)
	check(game.bear.links.has(a.building_id), "native E release connects buildings")
	refill()
	drag_skill(3, aim)
	check(game.bear.wards.has(a.building_id) and is_equal_approx(game.skill_defense_bonus(a), 1.0), "native R release raises the picked building's skill defense")
	check(game.armed_skill == -1 and not game.hud.get_node("%SkillDrag").visible, "release clears held icon without lingering aim state")
	await game.prepare_shutdown()
	print("Bear checks: %d, failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _ward_defense_checks() -> void:
	await reset()
	var a := pair()[0]
	check(RULES.names_for(&"bear")[3] == "震庭威慑", "R uses its revised name")
	check(game.cast_skill(3, a), "R casts on own building")
	near(game.energy, 30.0, "R keeps its seventy-energy cost")
	near(game.cooldowns[3], 70.0, "R keeps its seventy-second cooldown")
	near(game.active_durations[3], 5.0, "R lasts five seconds")
	near(game.defense_bonus(a), 0.0, "ward does not enter the environment defense group")
	near(game.skill_defense_bonus(a), 1.0, "ward grants plus one skill defense")
	near(game.combat_multiplier(1, a), 0.5, "ward halves otherwise unmodified incoming melee")
	game._on_unit_arrived(a.building_id, 1, 20.0)
	near(a.population, 90.0, "ordinary attackers inflict reduced damage during R")
	game.shields[a.building_id] = 10.0
	near(game.skill_defense_bonus(a), 1.25, "ward and shield add inside the skill group")
	near(game.combat_multiplier(1, a), 1.0 / 2.25, "combined defenses divide by 2.25 rather than multiply 2 by 1.25")
	game._on_unit_arrived(a.building_id, 1, 22.5)
	near(a.population, 80.0, "actual shield-plus-ward casualties use the additive skill group")
	game.set_paused(true)
	game.simulate(2.0)
	near(game.bear.wards[a.building_id].remaining, 5.0, "pause freezes ward expiration")
	game.set_paused(false)
	game.simulate(4.999)
	check(game.bear.wards.has(a.building_id), "ward remains active immediately before five seconds")
	game.simulate(0.001)
	check(not game.bear.wards.has(a.building_id), "ward expires at five seconds")
	near(game.active_durations[3], 0.0, "expiration clears the R HUD timer")
	near(game.skill_defense_bonus(a), 0.25, "ward expiration preserves the longer shield")
	near(game.combat_multiplier(1, a), 1.0 / 1.25, "expired ward no longer reduces incoming damage")
	await reset()
	a = pair()[0]
	a.population = 10.0
	check(game.cast_skill(3, a), "capture fixture starts with an active ward")
	game.shields[a.building_id] = 10.0
	game._on_unit_arrived(a.building_id, 1, 30.0)
	check(a.faction == 1, "a defended building can be captured during the ward")
	near(a.population, 7.5, "capture survivors account for the combined 2.25 defense divisor")
	check(not game.bear.wards.has(a.building_id) and not game.shields.has(a.building_id), "capture clears both temporary defenses")
	near(game.skill_defense_bonus(a), 0.0, "new owner inherits no old-owner skill defense")
	near(game.faction_skills[0].durations[3], 0.0, "capture clears the previous owner's R timer")

func _orb_soldier(building: WarBuilding, distance: float, faction: int = 1) -> WarMarches.MarchUnit:
	var at := building.global_position + Vector3(distance, 0, 0)
	game.marches.send(1, building.building_id, faction, 1, PackedVector3Array([at, at + Vector3(40, 0, 0)]))
	return game.marches._units[-1]

func _ward_projectile_checks() -> void:
	await reset("highland")
	var a := pair()[0]
	var near_unit := _orb_soldier(a, 4.0)
	var middle := _orb_soldier(a, 10.0)
	var far_unit := _orb_soldier(a, 16.0)
	var boundary := _orb_soldier(a, 18.0)
	var outside := _orb_soldier(a, 18.01)
	var own := _orb_soldier(a, 17.9, 0)
	var ally := _orb_soldier(a, 17.8, 2)
	var pending := _orb_soldier(a, 17.7)
	pending.spawn_delay = 1.0
	check(game.cast_skill(3, a), "R accepts a populated projectile fixture")
	check(game.bear.shots.size() == 3, "release immediately fires three projectiles at most")
	var first: Array[WarMarches.MarchUnit] = []
	for shot: Dictionary in game.bear.shots:
		first.append(shot.target)
	check(first == [boundary, far_unit, middle], "first volley takes the three farthest legal targets including exactly eighteen meters")
	check(not outside.reserved and not near_unit.reserved, "outside eighteen meters and the fourth-nearest unit stay unreserved")
	check(not own.reserved and not ally.reserved and not pending.reserved, "friendly, allied and unexposed soldiers are excluded")
	game.bear.advance(game, 0.499)
	check(game.bear.shots.size() == 3, "no second volley before half a second")
	game.bear.advance(game, 0.001)
	check(game.bear.shots.size() == 4 and game.bear.shots[-1].target == near_unit, "half-second volley takes only the remaining legal target")
	var extras: Array[WarMarches.MarchUnit] = []
	for distance: float in [6.0, 8.0, 9.0]:
		extras.append(_orb_soldier(a, distance))
	game.bear.advance(game, 0.5)
	check(game.bear.shots.size() == 7, "next half-second fires another complete three-target volley")
	var targeted := {}
	for shot: Dictionary in game.bear.shots:
		check(not targeted.has(shot.target.unit_id), "outstanding projectiles never reserve the same soldier twice")
		targeted[shot.target.unit_id] = true
	game.bear.tick_projectiles(game, 0.5)
	check(not boundary.alive and not far_unit.alive and not middle.alive and not near_unit.alive, "real projectiles kill all four original reserved enemies")
	for unit: WarMarches.MarchUnit in extras:
		check(not unit.alive, "subsequent volley also resolves real projectile damage")
	check(outside.alive and own.alive and ally.alive and pending.alive, "untargeted soldiers survive every volley")
	check(game.bear.shots.is_empty(), "resolved projectiles leave no stale shot reservations")

func _ward_arrival_checks() -> void:
	await reset()
	var a := pair()[0]
	check(game.cast_skill(3, a), "arrival fixture activates R before any enemy is exposed")
	for index: int in 30:
		game.marches.send(1, a.building_id, 1, 1, PackedVector3Array([a.global_position + Vector3(1, 0, 0), a.global_position + Vector3(0.2, 0, 0)]))
	game.simulate(0.3)
	check(game.bear.wards.has(a.building_id), "arrivals resolve while the ward remains active")
	check(game.marches.total_for(1) == 0, "real incoming soldiers enter immediately without waiting outside")
	near(a.population, 85.0, "thirty real arrivals inflict fifteen garrison casualties during R")
