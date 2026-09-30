extends SceneTree
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const TACTICS := preload("res://scripts/block_war/war_ai_skills.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.002, "%s: %.5f expected %.5f" % [label, actual, expected])

func reset(map_id: String = "rift") -> void:
	if game != null:
		await game.prepare_shutdown()
	var session := root.get_node("Session")
	session.block_war_map_id = map_id
	session.block_war_commander = &"frog"
	session.block_war_opponent_commander = &"frog"
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
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
		building.population = 100.0
		building.refresh_visual()
	await process_frame

func refill(faction: int = 0) -> void:
	game.faction_skills[faction].energy = 100.0
	game.faction_skills[faction].cooldowns.fill(0.0)

func soldier(faction: int, at: Vector3, destination: int = 0, length: float = 50.0) -> WarMarches.MarchUnit:
	game.marches.send(0, destination, faction, 1, PackedVector3Array([at, at + Vector3(length, 0, 0)]))
	return game.marches._units[-1]

func drag(index: int, at: Vector2) -> void:
	game.update_hud()
	var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % index)
	for down: bool in [true, false]:
		var point := button.get_global_rect().get_center() if down else at
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		root.push_input(motion, true)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event, true)
		if down:
			check(game.armed_skill == index, "native hold arms frog %d" % index)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	await reset()
	check(game.faction_skills[0].commander == RULES.FROG, "frog enters battle")
	for i: int in 4:
		check(game.skill_is_ground(i) == (i != 3), "target mode %d" % i)
		check(game.hud.get_node("UI/Skills/Row/Skill%d/Icon" % i).texture == RULES.FROG_ICONS[i], "existing bottom card uses frog icon %d" % i)
	game.energy = 30.0
	check(game.can_cast_skill(0), "opening Q affordable")
	var home: WarBuilding = game.buildings[0]
	var center := home.global_position
	check(game.cast_ground_skill(0, center), "mist ground release")
	near(game.energy, 10.0, "Q actual energy cost")
	for i: int in 20:
		game.marches.send(1, home.building_id, 1, 1, PackedVector3Array([center + Vector3(5, 0, 0), center + Vector3(2.4, 0, 0)]))
	game.marches.tick(1.0)
	near(home.population, 84.0, "20 attackers in mist cause 16 casualties")
	for i: int in 20:
		game.marches.send(0, home.building_id, 0, 1, PackedVector3Array([center + Vector3(5, 0, 0), center + Vector3(2.4, 0, 0)]))
	game.marches.tick(1.0)
	near(home.population, 104.0, "friendly transport preserves all 20 population")
	game.marches.tick(1.0)
	check(game.marches.weak_zones.is_empty(), "mist ends at three seconds")
	await reset()
	home = game.buildings[1]
	home.faction = 1
	center = home.global_position
	game.marches.apply_frog_field(0, 0, center)
	for i: int in 20:
		game.marches.send(1, home.building_id, 1, 1, PackedVector3Array([center + Vector3(5, 0, 0), center + Vector3(2.4, 0, 0)]))
	game.marches.tick(1.0)
	near(home.population, 120.0, "weakened enemy reinforcements still carry their full population")
	for entry_time: float in [2.98, 3.02]:
		for short_steps: bool in [false, true]:
			await reset()
			home = game.buildings[0]
			center = home.global_position
			game.marches.apply_frog_field(0, 0, center)
			game.marches.send(1, home.building_id, 1, 1, PackedVector3Array([center + Vector3(3.5 + entry_time * 3.1, 0, 0), center + Vector3(2.4, 0, 0)]))
			for step: int in (72 if short_steps else 1):
				game.marches.tick(0.05 if short_steps else 3.6)
			near(home.population, 99.2 if entry_time < 3.0 else 99.0, "fog expiry samples entry, with lasting weakness after arrival in long and short frames")
	await reset("highland")
	center = Vector3(-22, 0, 10)
	var enemy := soldier(1, center, 0, 2.0)
	game.marches.apply_frog_field(0, 0, center)
	game.marches.apply_frog_field(0, 2, center)
	near(game.marches.projected_attack_bonus(enemy), -0.2, "overlapping hostile mist does not stack")
	enemy.rush_remaining = 6.0
	near(game.marches.projected_attack_bonus(enemy), RULES.RABBIT_RUSH_ATTACK_BONUS - 0.2, "mist subtracts20 percentage points from the current rush bonus")
	game.buildings[0].kind = 1
	game.buildings[0].level = 3
	game.buildings[1].kind = 2
	game.buildings[1].faction = 1
	game.shields[0] = 8.0
	near(game.combat_multiplier(1, game.buildings[0], game.marches.projected_attack_bonus(enemy)), 1.3 / 1.6 * 1.3 / 1.25, "forge and tower sum in environment; fifty-percent rush, mist and shield form the separate skill coefficient")
	game.marches.weak_zones.clear()
	near(game.marches.projected_attack_bonus(enemy), RULES.RABBIT_RUSH_ATTACK_BONUS - 0.2, "weakness remains after the cloud disappears")
	var unaffected := soldier(1, center, 0, 2.0)
	near(game.marches.projected_attack_bonus(unaffected), 0.0, "a later troop receives no vanished mist debuff")
	await reset("highland")
	var own := soldier(0, center)
	enemy = soldier(1, center + Vector3(0, 0, 1))
	var ally := soldier(2, center + Vector3(0, 0, -1))
	check(game.cast_ground_skill(1, center), "float selects both sides")
	for unit: WarMarches.MarchUnit in [own, enemy, ally]:
		near(unit.levitation_remaining, 3, "all exposed teams levitate")
		near(game.marches.speed_multiplier(unit), 0, "floating prevents movement immediately")
	game.marches.tick(0.2)
	check(own.position.y > 1.5, "actual soldier is lifted above ground")
	near(own.distance, 0, "levitation freezes route progress")
	check(game.marches.acquire_targets(center, 0, 12.0, 5, false, true).is_empty(), "cannon cannot lock airborne enemy")
	var orb_targets: Array = game.marches.acquire_targets(center, 0, 12.0, 1, true)
	check(orb_targets.size() == 1 and orb_targets[0] == enemy, "orb still follows its normal spell rules")
	check(not game.marches.hit_target(enemy, Vector3.UP, true) and enemy.alive and not enemy.reserved, "in-flight cannonball misses and releases reservation")
	var late := soldier(1, center)
	near(late.levitation_remaining, 0, "units entering after release do not levitate")
	game.marches.tick(2.8)
	near(own.distance, 0, "exact three-second freeze")
	near(own.position.y, 0, "lands at expiry")
	game.marches.tick(0.5)
	near(own.distance, 1.55, "original route resumes at normal speed")
	check(not game.marches.acquire_targets(center, 0, 12.0, 2, false, true).is_empty(), "cannons can lock after landing")
	await reset()
	var tower: WarBuilding = game.buildings[0]
	tower.kind = 1
	tower.refresh_visual()
	enemy = soldier(1, tower.global_position + Vector3(5, 0, 0))
	game._fire_tower(tower)
	check(game.projectiles.size() == 1 and enemy.reserved, "actual cannonball launches before levitation")
	game.marches.apply_frog_field(1, 0, enemy.position)
	game._tick_projectiles(1.0)
	check(game.projectiles.is_empty() and enemy.alive and not enemy.reserved, "already-fired cannonball misses floated target without leaving a reservation")
	game._fire_tower(tower)
	check(game.projectiles.is_empty(), "actual tower will not fire at floating target")
	game.marches.tick(3.0)
	game._fire_tower(tower)
	game._tick_projectiles(1.0)
	check(not enemy.alive, "same soldier can be shot after landing")
	await reset()
	for faction: int in 2:
		own = soldier(faction, center)
		game.marches.apply_frog_field(1, 0, center)
	game.faction_skills[1].commander = RULES.COMMANDER_ID
	check(game.cast_ground_skill(3, center, 1), "fire can be cast through a floating group")
	game.simulate(0.15)
	check(game.marches._units.is_empty(), "fire still kills airborne soldiers of both teams")
	await reset()
	home = game.buildings[0]
	enemy = soldier(1, home.global_position + Vector3(5, 0, 0))
	game.marches.apply_frog_field(1, 0, enemy.position)
	game.faction_skills[0].commander = RULES.BEAR
	check(game.cast_skill(3, home), "bear orb can launch against levitated enemy")
	game.bear.tick_projectiles(game, 0.5)
	check(not enemy.alive and game.bear.shots.is_empty(), "real magic orb hits airborne soldier")
	await reset()
	var long_unit := soldier(0, center)
	long_unit.rush_remaining = 6.0
	game.marches.apply_frog_field(1, 0, center)
	game.marches.create_haste_zone(0, center, 4.5, 4.0, 1.6)
	var predicted: float = game.marches.movement_distance(long_unit, 8.0)
	for i: int in 160:
		game.marches.tick(0.05)
	near(long_unit.distance, predicted, "float, rush and haste expiry agree across long/short frames")
	await reset("highland")
	own = soldier(0, center)
	enemy = soldier(1, center + Vector3(0, 0, 1))
	ally = soldier(2, center + Vector3(0, 0, -1))
	check(game.cast_ground_skill(2, center), "cloak casts on own exposed troops")
	check(own.cloaked, "cloak starts immediately")
	check(not enemy.cloaked, "cloak excludes enemy")
	check(not ally.cloaked, "cloak excludes teammate owned army")
	check(game.marches.get_node("CloakedMilitia").multimesh.visible_instance_count == 1, "transparent pool holds hidden unit")
	check(game.marches.get_node("Militia").multimesh.visible_instance_count == 2, "opaque pool keeps ordinary soldiers")
	var cloak_targets: Array = game.marches.acquire_targets(center, 1, 12.0, 3, false, true)
	check(own not in cloak_targets and ally in cloak_targets, "tower skips invisible soldiers and still targets visible enemies")
	check(game.marches.get_node("CloakedMilitia").cast_shadow == 0, "hidden soldier casts no revealing solid shadow")
	game.marches.apply_frog_field(1, 0, center)
	game.world_effects.get_node("Frog").sync(game.marches, 0.0)
	check(game.world_effects.get_node("Frog/Bubbles").multimesh.visible_instance_count == 2, "float membrane does not reveal cloaked unit")
	game.set_paused(true)
	game.simulate(1.0)
	check(own.cloaked, "pause preserves invisibility")
	near(game.world_effects.get_node("Frog/Puffs").speed_scale, 0, "pause freezes native fog particles")
	game.set_paused(false)
	game.marches.tick(6.0)
	check(own.cloaked, "cloak remains after six seconds")
	check(game.marches.get_node("CloakedMilitia").multimesh.visible_instance_count == 1, "permanent cloak stays in transparent pool")
	check(game.marches.get_node("Militia").multimesh.visible_instance_count == 2, "ordinary soldiers remain separate")
	refill()
	check(not game.cast_ground_skill(2, center - Vector3(10, 0, 0)), "empty cloak rejects")
	near(game.energy, 100, "empty cast does not consume energy")
	await reset("highland")
	var target: WarBuilding = game.buildings[1]
	target.faction = 1
	target.level = 4
	target.population = 100
	check(game.cast_skill(3, target), "R targets hostile building")
	near(target.population, 20, "R loses exactly80 of100")
	check(target.level == 1 and target.faction == 1, "R downgrades without capturing")
	near(game.energy, 15, "R pays85 energy")
	refill()
	target.population = 21
	game.cast_skill(3, target)
	near(target.population, 5, "21 loses16 whole people, no fractional casualties")
	refill()
	target.population = 1
	check(not game.cast_skill(3, target), "R rejects a no-effect one-person level1 target")
	near(game.energy, 100, "no-effect R is free")
	target.faction = 2
	target.population = 100
	check(not game.cast_skill(3, target), "R cannot hurt teammate building")
	target.faction = -1
	target.level = 3
	check(game.cast_skill(3, target), "R can target neutral building")
	check(target.faction == -1 and target.level == 1, "neutral stays neutral")
	refill()
	target.faction = 1
	target.population = 100
	target.level = 3
	target.begin_construction(-1, 30)
	game.cast_skill(3, target)
	check(not target.is_constructing and target.construction_cost == 0, "R cancels pre-strike construction and receipt")
	target.advance_construction(10)
	check(target.level == 1, "cancelled old upgrade cannot restore a level")
	refill()
	target.population = 100.75
	target.kind = 1
	target.level = 3
	target.begin_construction(2, 20)
	check(game.cast_skill(3, target), "R can strike a converting tower")
	near(target.population, 20.75, "whole casualties preserve existing fractional production")
	target.advance_construction(10)
	check(target.kind == 1 and target.level == 1 and target.conversion_target == -1 and target.construction_cost == 0, "R keeps original kind and cancels conversion without a stale refund")
	await reset()
	target = game.buildings[1]
	target.faction = 1
	var support: WarBuilding = game.buildings[2]
	support.faction = 1
	support.global_position = target.global_position + Vector3(8, 0, 0)
	game.faction_skills[1].commander = RULES.BEAR
	check(game.cast_skill(2, target, 1), "bear E active on R target")
	check(game.cast_skill(3, target), "frog R bypasses the link")
	near(target.population, 20, "linked target still loses its full80")
	near(support.population, 100, "linked support loses nobody to R")
	refill(1)
	check(game.cast_skill(3, target, 1), "bear defensive ward active")
	refill()
	target.level = 3
	game.shields[target.building_id] = 10.0
	check(game.cast_skill(3, target), "frog R remains legal against ward plus shield")
	near(target.population, 4, "percentage strike bypasses both temporary defense bonuses")
	check(target.level == 1, "defensive ward does not prevent the strike's downgrade")
	near(game.energy, 15, "successful defended-target strike pays eighty-five energy")
	await reset()
	target = game.buildings[1]
	target.faction = 1
	target.population = 100
	var route: PackedVector3Array = game.map.get_building_route(target, game.buildings[0])
	game.marches.queue_departure(target.building_id, 0, 1, 80, route)
	game.cast_skill(3, target)
	check(target.queued_population <= 20 and game.marches.total_for(1) <= 20, "R trims reservations to actual survivors")
	for ability: int in 4:
		await reset()
		game.faction_skills[1].cooldowns.fill(100.0)
		game.faction_skills[1].cooldowns[ability] = 0.0
		target = game.buildings[1]
		target.faction = 1
		if ability in [0, 1]:
			for i: int in 12:
				game.marches.send(0, target.building_id, 0, 1, PackedVector3Array([target.global_position + Vector3(5, 0, 0), target.global_position + Vector3(2.5, 0, 0)]))
		elif ability == 2:
			for i: int in 12:
				soldier(1, center)
		game.elapsed = 15.0
		TACTICS.new(1).take_turn(game)
		check(game.faction_skills[1].cooldowns[ability] > 0.0, "AI casts frog ability%d" % ability)
		near(game.faction_skills[1].energy, 100 - RULES.FROG_COSTS[ability], "AI pays cost%d" % ability)
	await reset()
	root.size = Vector2i(1600, 900)
	await create_timer(0.5).timeout
	await physics_frame
	for index: int in 3:
		refill()
		game.marches.clear()
		soldier(0, center)
		soldier(1, center + Vector3(0, 0, 1))
		drag(index, game.camera.unproject_position(center))
		check(game.cooldowns[index] > 0, "native ground release applies%d" % index)
	refill()
	target = game.buildings[1]
	target.faction = 1
	target.level = 3
	game.camera_rig.focus_at(target.global_position, true)
	await process_frame
	await physics_frame
	drag(3, game.camera.unproject_position(target.global_position + Vector3(0, 1.5, 0)))
	check(target.level == 1 and game.cooldowns[3] > 0, "native R release selects actual building")
	check(game.armed_skill == -1 and not game.hud.get_node("%SkillDrag").visible, "release clears drag state")
	await game.prepare_shutdown()
	print("FROG checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
