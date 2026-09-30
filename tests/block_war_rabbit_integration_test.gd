extends "res://tests/block_war_rabbit_test.gd"
## Native viewport input, timing boundaries and deliberate AI choices.

const TACTICS := preload("res://scripts/block_war/war_ai_skills.gd")
var _input_viewport: Viewport

func motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	(_input_viewport if _input_viewport != null else root).push_input(event, true)

func mouse(at: Vector2, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	motion(at)
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
	(_input_viewport if _input_viewport != null else root).push_input(event, true)

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.window_id = root.get_window_id()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	(_input_viewport if _input_viewport != null else root).push_input(event, true)

func icon(index: int) -> Vector2:
	return game.hud.get_node("UI/Skills/Row/Skill%d" % index).get_global_rect().get_center()

func screen(building: WarBuilding) -> Vector2:
	return game.camera.unproject_position(building.global_position + Vector3.UP * 1.5)

func expose(faction: int, count: int, from: Vector3, to: Vector3, target_id: int) -> void:
	var source_id := -1
	for building: WarBuilding in game.buildings:
		if building.faction == faction:
			source_id = building.building_id
			break
	assert(source_id >= 0, "Exposed troops need their real original source for recall.")
	for i: int in count:
		game.marches.send(source_id, target_id, faction, 1, PackedVector3Array([from + Vector3(0, 0, (i % 4) * 0.1), to]))

func ai_setup() -> RefCounted:
	game.faction_skills[1].commander = RULES.RABBIT
	for building: WarBuilding in game.buildings:
		building.kind = 2
		building.population = 100.0
	game.elapsed = 10.0
	return TACTICS.new(1)

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	await _native_input()
	await _boundaries()
	await _ai_decisions()
	var battle_only := OS.get_cmdline_user_args().has("--battle-only")
	if not battle_only:
		await _selector()
	await game.prepare_shutdown()
	print("BLOCK_WAR_RABBIT_INTEGRATION checks=%d failures=%d scope=%s" % [checks, failures.size(), "battle-only" if battle_only else "full"])
	quit(0 if failures.is_empty() else 1)

func _native_input() -> void:
	await reset()
	# Native Windows roots query the physical OS cursor even after push_input.
	# A SubViewport keeps the injected pointer position, so the real keyboard
	# release path can run on an inactive private desktop without OS input.
	var input_view := SubViewport.new()
	input_view.size = root.size
	input_view.own_world_3d = true
	input_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(input_view)
	game.reparent(input_view)
	_input_viewport = input_view
	await physics_frame
	await process_frame
	game.select_building(null)
	var center := Vector3(-22, 0, 10)
	expose(0, 6, center, center + Vector3(30, 0, 0), enemy().building_id)
	mouse(icon(0), true)
	check(game.armed_skill == 0, "native Q button press arms the ground skill")
	near(game.energy, 100.0, "button press alone never casts")
	var ground: Vector2 = game.camera.unproject_position(center)
	motion(ground)
	mouse(ground, false)
	check(game.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.rush_remaining == 8.0) and game.marches.haste_zones.is_empty() and game.armed_skill == -1, "native Q release empowers the selected squad without placing a persistent field")
	near(game.energy, 75.0, "native release pays twenty-five energy once")
	game.marches.clear()
	refill()
	key(KEY_W, true)
	check(game.armed_skill == 1, "held W arms hostile building targeting")
	motion(screen(enemy()))
	check(game.get_viewport().get_mouse_position().is_equal_approx(screen(enemy())), "native viewport tracks the injected target for keyboard release")
	near(enemy().disruption_remaining, 0.0, "held key and motion cannot cast early")
	key(KEY_W, false)
	near(enemy().disruption_remaining, 6.0, "releasing W disables the hovered building")
	near(game.energy, 75.0, "keyboard release pays once")
	refill()
	game.select_building(null)
	mouse(icon(1), true)
	mouse(screen(home()), false)
	near(game.energy, 100.0, "invalid allied W release is free")
	check(game.armed_skill == -1, "invalid drag cancels cleanly")
	var route: PackedVector3Array = game.map.get_building_route(home(), game.buildings[2])
	game.marches.send(0, game.buildings[2].building_id, 0, 12, route)
	game.marches.tick(0.3)
	var recall_at: Vector2 = game.camera.unproject_position(game.marches._units[0].position)
	mouse(icon(2), true)
	motion(recall_at)
	var recall_count: int = game.recall_preview.size()
	check(recall_count > 0 and game.skill_is_ground(2), "native E ground drag shows real returners")
	mouse(recall_at, false)
	check(game.marches.incoming_for(home().building_id, 0) == recall_count, "native E release redirects previewed soldiers")
	game.reparent(root)
	current_scene = game
	_input_viewport = null
	input_view.queue_free()
	await physics_frame
	await reset()
	var plan := tunnel_plan()
	check(not plan.is_empty(), "R native drag setup has a source and destination")
	game.select_building(null)
	mouse(icon(3), true)
	mouse(screen(plan.target), false)
	near(game.energy, 100.0, "R cannot enchant a neutral destination")
	check(game.marches.total_for(0) == 0 and plan.source.burrow_remaining == 0.0, "invalid R drop cannot pick an alternative source")
	mouse(icon(3), true)
	motion(screen(plan.source))
	mouse(screen(plan.source), true, MOUSE_BUTTON_RIGHT)
	check(game.armed_skill == -1, "right-click cancels the source enchantment gesture")
	mouse(screen(plan.source), false)
	near(game.energy, 100.0, "canceled enchantment is free")
	mouse(icon(3), true)
	mouse(screen(plan.source), false)
	check(plan.source.burrow_remaining == 15.0 and game.marches.total_for(0) == 0, "native R release enchants only the selected own source")
	near(game.energy, 35.0, "native R release pays correct energy")
	game.set_percentage(100)
	mouse(screen(plan.source), true)
	motion(screen(plan.target))
	mouse(screen(plan.target), false)
	check(plan.source.burrow_remaining == 0.0 and game.marches.total_for(0) == 50 and plan.source.queued_population == 50, "next native building drag consumes R and reserves up to fifty")
	check(game.marches.get_units().is_empty() and plan.source.population == 60.0, "native tunnel order starts digging before soldiers depart")

func _boundaries() -> void:
	var states: Array[Array] = []
	for small_steps: bool in [false, true]:
		await reset()
		var target := enemy()
		target.population = 8.0
		check(game.cast_skill(1, target), "boundary house seal setup")
		var plan := tunnel_plan()
		# Isolate transport from the ordinary substep rounding of post-capture growth.
		plan.target.kind = 2
		refill()
		check(game.cast_skill(3, plan.source) and game.issue_order(plan.source, plan.target, 100) == 50, "boundary tunnel setup")
		if small_steps:
			for i: int in 720:
				game.simulate(0.01)
		else:
			game.simulate(7.2)
		states.append([target.population, game.total_for(0), plan.target.population, plan.target.faction, game.marches.total_for(0), plan.source.population, plan.source.queued_population])
	for i: int in states[0].size():
		near(float(states[0][i]), float(states[1][i]), "long and short step agree %d" % i)
	states.clear()
	for small_steps: bool in [false, true]:
		await reset()
		home().population = 29.9
		var destination: WarBuilding = game.buildings[2]
		destination.kind = 2
		destination.population = 1000.0
		check(game.cast_skill(3, home()) and game.issue_order(home(), destination, 100) == 29, "near-full productive residence prepares twenty-nine tunnel departures")
		if small_steps:
			for i: int in 240:
				game.simulate(0.01)
		else:
			game.simulate(2.4)
		check(home().queued_population == 0 and home().population > 1.0, "all reserved soldiers leave and the original home resumes production")
		states.append([home().population, home().queued_population, destination.population, game.total_for(0), game.marches.total_for(0)])
	for i: int in states[0].size():
		near(float(states[0][i]), float(states[1][i]), "near-cap production and staged departures are frame independent %d" % i)
	await reset()
	var plan := tunnel_plan()
	check(game.cast_skill(3, plan.source), "source capture while awaiting an order setup")
	game._on_unit_arrived(plan.source.building_id, 1, (plan.source.population + 1.0) / game.combat_multiplier(1, plan.source))
	check(plan.source.faction == 1 and plan.source.burrow_remaining == 0.0 and game.marches.total_for(0) == 0, "capture clears the unused source enchantment and its remaining duration")
	check(game.issue_order(plan.source, plan.target, 100) == 0, "the former owner cannot consume a captured source's enchantment")
	await reset()
	plan = tunnel_plan()
	check(game.cast_skill(3, plan.source) and game.issue_order(plan.source, plan.target, 100) == 50, "capture during digging setup")
	game.simulate(plan.dig_duration * 0.5)
	game._on_unit_arrived(plan.source.building_id, 1, (plan.source.population + 1.0) / game.combat_multiplier(1, plan.source))
	check(plan.source.faction == 1 and plan.source.burrow_remaining == 0.0 and plan.source.queued_population == 0 and game.marches.total_for(0) == 0, "capture during digging cancels every passenger before anyone leaves")
	game.simulate(2.0)
	check(game.marches.total_for(0) == 0, "a canceled digging operation cannot later spawn an army")
	await reset()
	plan = tunnel_plan()
	check(game.cast_skill(3, plan.source) and game.issue_order(plan.source, plan.target, 100) == 50, "source capture during staged departure setup")
	game.simulate(plan.dig_duration + 0.01)
	check(plan.source.queued_population == 44, "only the first six have left before source capture")
	game._on_unit_arrived(plan.source.building_id, 1, (plan.source.population + 1.0) / game.combat_multiplier(1, plan.source))
	check(game.marches.total_for(0) == 6 and plan.source.queued_population == 0, "capturing source cancels waiting passengers and preserves the six departed")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(unit.order.faction == 0, "departed passenger retains original faction")
	game.simulate(0.33)
	check(game.marches.get_units().size() == 6, "captured source never sends canceled later ranks")
	await reset()
	var forge := enemy()
	forge.kind = 2
	forge.refresh_visual()
	check(forge.get_node("Visual/Smithy/HearthLight").visible, "working forge is lit")
	game.cast_skill(1, forge)
	check(not forge.get_node("Visual/Smithy/HearthLight").visible and not forge.get_node("Visual/Smithy/Embers").visible, "sealed forge stops both furnace light and embers")
	game.simulate(6.0)
	check(forge.get_node("Visual/Smithy/HearthLight").visible, "furnace relights at expiry")

func _ai_decisions() -> void:
	await reset()
	var ai := ai_setup()
	var center := Vector3(-22, 0, 10)
	expose(1, 18, center, center + Vector3(20, 0, 0), 0)
	ai.take_turn(game)
	check(game.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.rush_remaining > 0.0) and game.marches.haste_zones.is_empty(), "rabbit AI chooses Q on the actual exposed squad")
	near(game.faction_skills[1].energy, 75.0, "AI pays the player's twenty-five energy Q cost")
	ai.take_turn(game)
	near(game.faction_skills[1].energy, 75.0, "same-time AI calls cannot chain casts")
	await reset()
	ai = ai_setup()
	expose(1, 6, center, center + Vector3(20, 0, 0), 0)
	for energy: float in [20.0, 24.99, 25.0]:
		game.faction_skills[1].energy = energy
		game.elapsed += 3.0
		ai.take_turn(game)
		if energy < 25.0:
			check(game.faction_skills[1].energy == energy and game.faction_skills[1].cooldowns[0] == 0.0, "AI cannot spend opening or fractional energy below twenty-five on Q")
			check(game.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.rush_remaining == 0.0), "underfunded AI leaves its exposed squad unbuffed")
		else:
			check(game.faction_skills[1].energy == 0.0 and game.faction_skills[1].cooldowns[0] == 25.0, "AI casts Q at exactly twenty-five energy")
			check(game.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.rush_remaining == 8.0), "funded AI buffs the actual squad for eight seconds")
	await reset()
	ai = ai_setup()
	game.elapsed = 6.0
	game.faction_skills[1].energy = 30.0
	enemy().population = 30.0
	var expansion_target: WarBuilding
	var nearest := INF
	for building: WarBuilding in game.buildings:
		if building.faction == -1:
			var distance: float = game.map.get_building_distance(enemy(), building)
			if distance < nearest:
				nearest = distance
				expansion_target = building
	expansion_target.population = 8.0
	check(game.issue_order(enemy(), expansion_target, 50, 1) == 15, "opening AI sends a legal fifteen-person neutral expansion")
	game.marches.tick(0.1)
	ai.take_turn(game)
	near(game.faction_skills[1].energy, 5.0, "AI with thirty energy can fund rush for its first expansion squad")
	check(game.faction_skills[1].cooldowns[0] == 25.0, "opening squad triggers twenty-five seconds of Q cooldown")
	var rushed := 0
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.is_exposed():
			rushed += int(unit.rush_remaining == 8.0)
		else:
			check(unit.rush_remaining == 0.0, "queued ranks in the same opening order cannot inherit the first squad's rush")
	check(rushed == 6 and game.marches.total_for(1) == 15, "all six exposed opening soldiers are rushed without changing the fifteen-person army")
	await reset()
	ai = ai_setup()
	game.faction_skills[0].commander = &"squirrel"
	home().kind = 0
	home().level = 4
	home().population = 5.0
	for index: int in [0, 2, 3]:
		game.faction_skills[1].cooldowns[index] = 100.0
	check(game.cast_skill(0, home()), "player recruitment creates meaningful suppression target")
	game.request_skill(1)
	ai.take_turn(game)
	near(home().disruption_remaining, 6.0, "rabbit AI seals a publicly developed residence without reading its recruitment clock")
	check(game.armed_skill == 1 and game.selected == home(), "AI cast preserves player's held gesture and selection")
	near(game.energy, 70.0, "AI cannot spend player energy")
	near(game.faction_skills[1].energy, 75.0, "AI pays W cost")
	await reset()
	ai = ai_setup()
	home().kind = 1
	home().level = 3
	game.faction_skills[1].cooldowns[0] = 100.0 # Isolate suppression from the snapshot rush.
	expose(1, 20, home().global_position + Vector3(-6, 0, 0), home().global_position + Vector3(30, 0, 0), 0)
	ai.take_turn(game)
	near(home().disruption_remaining, 6.0, "rabbit AI seals tower covering its column")
	await reset()
	ai = ai_setup()
	game.faction_skills[1].cooldowns[2] = 100.0 # Isolate the forge-suppression decision from the new area recall.
	expose(0, 80, enemy().global_position + Vector3(-4, 0, 0), enemy().global_position, enemy().building_id)
	ai.take_turn(game)
	near(home().disruption_remaining, 6.0, "rabbit AI seals forge supporting imminent enemy attack")
	await reset()
	ai = ai_setup()
	var refuge := enemy()
	refuge.population = 10.0
	var route: PackedVector3Array = game.map.get_building_route(refuge, game.buildings[2])
	expose(1, 18, route[0] + (route[1] - route[0]).normalized() * 0.1, route[-1], game.buildings[2].building_id)
	var threat_route: PackedVector3Array = game.map.get_building_route(home(), refuge)
	game.marches.send(home().building_id, refuge.building_id, 0, 20, threat_route)
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.order.faction == 0:
			unit.distance = unit.order.length - 3.0
			game.marches._update_pose(unit)
	ai.take_turn(game)
	check(game.faction_skills[1].cooldowns[2] > 0.0, "rabbit AI uses area recall to repel a dangerous local attack")
	check(game.marches.incoming_for(home().building_id, 0) > 0, "AI E sends hostile soldiers back to their original source")
	near(game.faction_skills[1].energy, 80.0, "AI pays E cost")
	await reset()
	ai = ai_setup()
	for index: int in [0, 1, 3]:
		game.faction_skills[1].cooldowns[index] = 100.0
	var mixed_route: PackedVector3Array = game.map.get_building_route(home(), enemy())
	game.marches.send(home().building_id, enemy().building_id, 0, 8, mixed_route)
	mixed_route.reverse()
	game.marches.send(enemy().building_id, home().building_id, 1, 40, mixed_route)
	for unit: WarMarches.MarchUnit in game.marches._units:
		unit.distance = unit.order.length * 0.5
		game.marches._update_pose(unit)
	ai.take_turn(game)
	check(game.faction_skills[1].cooldowns[2] == 0.0 and game.faction_skills[1].energy == 100.0, "AI rejects a mixed circle whose retreat would recall forty allies merely to repel eight enemies")
	check(game.marches.incoming_for(home().building_id, 1) == 40 and game.marches.incoming_for(enemy().building_id, 0) == 8, "declining a harmful recall preserves both original marches")
	# Identical public targets give identical plans even when their hidden
	# garrisons differ. Actual combat still applies that unknown resistance.
	for scenario: Dictionary in [{"burning": false, "population": 8.0}, {"burning": false, "population": 1000.0}, {"burning": true, "population": 1000.0}]:
		await reset()
		ai = ai_setup()
		var burning: bool = scenario.burning
		var attack := {}
		for building: WarBuilding in game.buildings:
			var candidate: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, enemy(), building, 100)
			if not candidate.is_empty() and candidate.length >= 9.0:
				attack = candidate
				break
		check(not attack.is_empty(), "AI tunnel setup has a useful target")
		if attack.is_empty():
			continue
		check(game.FACTIONS.hostile(attack.target.faction, 1), "tunnel fixture targets a hidden enemy garrison")
		attack.target.population = scenario.population
		if burning:
			game.world_effects.start_fire(attack.exit, 4.5, 0)
		ai.take_turn(game)
		if burning:
			near(game.faction_skills[1].energy, 100.0, "AI refuses a visibly burning exit")
			check(game.marches.total_for(1) == 0, "unsafe tunnel sends no passengers")
		else:
			near(game.faction_skills[1].energy, 35.0, "AI pays R for the same public opportunity regardless of hidden garrison size")
			check(game.marches.total_for(1) == 50 and attack.source.queued_population == 50, "AI enchants its source and reserves fifty through an ordinary order")
			near(attack.source.population, 100.0, "AI source keeps soldiers inside during digging")
			check(attack.source.burrow_remaining == 0.0, "AI command consumes its prepared tunnel once")
	await reset()
	ai = ai_setup()
	for building: WarBuilding in game.buildings:
		building.faction = 1
	ai.take_turn(game)
	near(game.faction_skills[1].energy, 100.0, "AI holds skills when only safe allied buildings are present")

func _selector() -> void:
	await game.prepare_shutdown()
	var session := root.get_node("Session")
	check(session.change_scene("res://scenes/block_war/commander_select.tscn") == OK, "selector uses the normal covered scene transition")
	await scene_changed
	await session.transition.completed
	var animal: Button = current_scene.get_node("%Animal0")
	mouse(animal.get_global_rect().get_center(), true)
	mouse(animal.get_global_rect().get_center(), false)
	var next: Button = current_scene.get_node("%Next")
	mouse(next.get_global_rect().get_center(), true)
	mouse(next.get_global_rect().get_center(), false)
	await scene_changed
	await session.transition.completed
	var picker := current_scene
	for path: String in ["%OpponentCommander1"]:
		var at: Vector2 = picker.get_node(path).get_global_rect().get_center()
		mouse(at, true)
		mouse(at, false)
	check(session.block_war_commander == &"squirrel" and session.block_war_opponent_commander == &"rabbit", "selector changes sides independently through native clicks")
	var start: Button = picker.get_node("%Start")
	mouse(start.get_global_rect().get_center(), true)
	mouse(start.get_global_rect().get_center(), false)
	await scene_changed
	game = current_scene
	game.set_process(false)
	check(game.faction_skills[0].commander == &"squirrel" and game.faction_skills[1].commander == &"rabbit", "selected sides reach match")
	await session.transition.completed
	game.restart()
	await scene_changed
	game = current_scene
	game.set_process(false)
	check(game.faction_skills[0].commander == &"squirrel" and game.faction_skills[1].commander == &"rabbit", "restart retains commander choices")
	while session.transition.busy:
		await process_frame
