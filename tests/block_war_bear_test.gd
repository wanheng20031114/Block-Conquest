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

func reset() -> void:
	if game != null:
		await game.prepare_shutdown()
	root.get_node("Session").block_war_map_id = "rift"
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
	a.kind = 2
	b.kind = 2
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
	check(game.can_cast_skill(0), "Q available at starting energy")
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
			near(home.population, 100.0 - cost * 0.5, "half refund from actual cost")
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
	near(a.population, 90, "20 times 1.05 becomes 21 integer casualties")
	near(b.population, 89, "support does not apply its own tower defense again")
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
	near(b.population, 100, "invulnerable support absorbs its assigned integer half")
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
	near(a.population, 88, "invulnerability blocks fire garrison damage")
	near(b.population, 87, "blocked fire does not spill into support")

	await reset()
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

	await reset()
	buildings = pair()
	a = buildings[0]
	game.marches.send(1, a.building_id, 1, 1, PackedVector3Array([a.global_position + Vector3(4, 0, 0), a.global_position + Vector3(40, 0, 0)]))
	game.marches.send(1, a.building_id, 1, 1, PackedVector3Array([a.global_position + Vector3(10, 0, 0), a.global_position + Vector3(40, 0, 0)]))
	var distant: WarMarches.MarchUnit = game.marches._units[1]
	check(game.cast_skill(3, a), "R casts on own building")
	check(game.bear.shots.size() == 1 and game.bear.shots[0].target == distant, "orb immediately reserves farther enemy")
	game._on_unit_arrived(a.building_id, 1, 500.0)
	near(a.population, 100, "R prevents direct damage and capture")
	game.simulate(0.45)
	check(not distant.alive, "actual orb projectile hits reserved soldier")
	game.marches.clear()
	# Restore the active ward's arrival barrier after clearing the fixture march.
	game.marches.blocked_destinations[a.building_id] = 0
	game.marches.send(1, a.building_id, 1, 30, PackedVector3Array([a.global_position + Vector3(5, 0, 0), a.global_position + Vector3(2.5, 0, 0)]))
	game.simulate(4.55)
	check(not game.bear.is_invulnerable(a.building_id), "R ends at five seconds")
	near(a.population, 100, "arriving enemies wait outside instead of being consumed")
	check(game.marches.total_for(1) > 0, "waiting enemies remain real exposed soldiers")
	game.simulate(0.2)
	check(a.population < 100, "surviving enemies resume attacks after R")

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
	check(game.bear.is_invulnerable(a.building_id), "native R release protects the picked building")
	check(game.armed_skill == -1 and not game.hud.get_node("%SkillDrag").visible, "release clears held icon without lingering aim state")
	await game.prepare_shutdown()
	print("Bear checks: %d, failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
