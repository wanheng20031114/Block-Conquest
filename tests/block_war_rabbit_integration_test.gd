extends "res://tests/block_war_rabbit_test.gd"
## Native viewport input, timing boundaries and deliberate AI choices.

const TACTICS := preload("res://scripts/block_war/war_ai_skills.gd")
var serial := 1000

func motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(at: Vector2, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	motion(at)
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.window_id = root.get_window_id()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func icon(index: int) -> Vector2:
	return game.hud.get_node("UI/Skills/Row/Skill%d" % index).get_global_rect().get_center()

func screen(building: WarBuilding) -> Vector2:
	return game.camera.unproject_position(building.global_position + Vector3.UP * 1.5)

func expose(faction: int, count: int, from: Vector3, to: Vector3, target_id: int) -> void:
	for i: int in count:
		serial += 1
		game.marches.send(serial, target_id, faction, 1, PackedVector3Array([from + Vector3(0, 0, (i % 4) * 0.1), to]))

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
	await _selector()
	await game.prepare_shutdown()
	print("BLOCK_WAR_RABBIT_INTEGRATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _native_input() -> void:
	await reset()
	game.select_building(null)
	mouse(icon(0), true)
	check(game.armed_skill == 0, "native Q button press arms the ground skill")
	near(game.energy, 100.0, "button press alone never casts")
	var ground: Vector2 = game.camera.unproject_position(Vector3(-22, 0, 10))
	motion(ground)
	mouse(ground, false)
	check(game.marches.haste_zones.has(0) and game.armed_skill == -1, "native Q drag releases into local haste")
	near(game.energy, 75.0, "native release pays once")
	refill()
	key(KEY_W, true)
	check(game.armed_skill == 1, "held W arms hostile building targeting")
	motion(screen(enemy()))
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
	mouse(icon(2), true)
	motion(screen(home()))
	var recall_count: int = game.recall_preview.size()
	check(recall_count > 0, "native E drag shows real returners")
	mouse(screen(home()), false)
	check(game.marches.incoming_for(home().building_id, 0) == recall_count, "native E release redirects previewed soldiers")
	await reset()
	var plan := tunnel_plan()
	check(not plan.is_empty(), "R native drag setup has a donor")
	game.select_building(null)
	mouse(icon(3), true)
	motion(screen(plan.target))
	check(game._rabbit_preview_source == plan.source.building_id, "R drag locks visible donor")
	plan.source.population = 10.0
	# A second newly eligible donor must never silently replace the previewed one.
	var replacement: WarBuilding
	for building: WarBuilding in game.buildings:
		if building != plan.source and building != plan.target and game.map.get_building_distance(building, plan.target) < RULES.BURROW_RANGE:
			replacement = building
			break
	check(replacement != null, "R invalidation test has an alternative donor")
	if replacement != null:
		replacement.faction = 0
		replacement.population = 60.0
	mouse(screen(plan.target), false)
	near(game.energy, 100.0, "invalidated locked source costs nothing even before preview refresh")
	check(game.marches.total_for(0) == 0, "invalid source does not send alternate garrison")
	mouse(icon(3), true)
	motion(screen(plan.target))
	check(not game.rabbit_preview.is_empty(), "a new gesture can choose the alternative donor")
	mouse(screen(plan.target), true, MOUSE_BUTTON_RIGHT)
	check(game.armed_skill == -1 and game.rabbit_preview.is_empty(), "right-click clears R preview and lock")
	mouse(screen(plan.target), false)
	near(game.energy, 100.0, "canceled tunnel is free")
	plan.source.population = 60.0
	mouse(icon(3), true)
	motion(screen(plan.target))
	mouse(screen(plan.target), false)
	check(game.marches.total_for(0) == 30, "native R release creates thirty real passengers")
	check(game.marches.get_units().size() == 6, "native R release exposes the first rank in the same frame")
	near(game.energy, 35.0, "native R release pays correct energy")

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
		check(game.cast_skill(3, plan.target), "boundary tunnel setup")
		if small_steps:
			for i: int in 720:
				game.simulate(0.01)
		else:
			game.simulate(7.2)
		states.append([target.population, game.total_for(0), plan.target.population, plan.target.faction, game.marches.total_for(0)])
	for i: int in states[0].size():
		near(float(states[0][i]), float(states[1][i]), "long and short step agree %d" % i)
	await reset()
	var plan := tunnel_plan()
	check(game.cast_skill(3, plan.target), "donor capture setup")
	plan.source.population = 0.0
	game._on_unit_arrived(plan.source.building_id, 1, 1.0)
	check(game.marches.total_for(0) == 30, "capturing donor cannot delete paid passengers")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(unit.order.faction == 0, "hidden passenger retains original faction")
	game.simulate(0.33)
	check(game.marches.get_units().size() == 18, "passengers continue emerging promptly after donor capture")
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
	check(game.marches.haste_zones.has(1), "rabbit AI chooses Q over a useful marching group")
	near(game.faction_skills[1].energy, 75.0, "AI pays the player's Q cost")
	ai.take_turn(game)
	near(game.faction_skills[1].energy, 75.0, "same-time AI calls cannot chain casts")
	await reset()
	ai = ai_setup()
	game.faction_skills[0].commander = &"squirrel"
	home().kind = 0
	home().population = 5.0
	check(game.cast_skill(0, home()), "player recruitment creates meaningful suppression target")
	game.request_skill(1)
	ai.take_turn(game)
	near(home().disruption_remaining, 6.0, "rabbit AI seals active recruitment")
	check(game.armed_skill == 1 and game.selected == home(), "AI cast preserves player's held gesture and selection")
	near(game.energy, 70.0, "AI cannot spend player energy")
	near(game.faction_skills[1].energy, 75.0, "AI pays W cost")
	await reset()
	ai = ai_setup()
	home().kind = 1
	home().level = 3
	expose(1, 20, home().global_position + Vector3(-6, 0, 0), home().global_position + Vector3(30, 0, 0), 0)
	ai.take_turn(game)
	near(home().disruption_remaining, 6.0, "rabbit AI seals tower covering its column")
	await reset()
	ai = ai_setup()
	expose(0, 80, enemy().global_position + Vector3(-4, 0, 0), enemy().global_position, enemy().building_id)
	ai.take_turn(game)
	near(home().disruption_remaining, 6.0, "rabbit AI seals forge supporting imminent enemy attack")
	await reset()
	ai = ai_setup()
	var refuge := enemy()
	refuge.population = 10.0
	var route: PackedVector3Array = game.map.get_building_route(refuge, game.buildings[2])
	expose(1, 18, route[0] + (route[1] - route[0]).normalized() * 0.1, route[-1], game.buildings[2].building_id)
	expose(0, 20, refuge.global_position + Vector3(-10, 0, 0), refuge.global_position, refuge.building_id)
	ai.take_turn(game)
	check(game.faction_skills[1].cooldowns[2] > 0.0, "rabbit AI recalls nearby troops to a threatened building")
	check(game.marches.incoming_for(refuge.building_id, 1) > 0, "AI E gives real return orders")
	near(game.faction_skills[1].energy, 80.0, "AI pays E cost")
	for burning: bool in [false, true]:
		await reset()
		ai = ai_setup()
		var attack := {}
		for building: WarBuilding in game.buildings:
			var candidate: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, building, 1)
			if not candidate.is_empty() and candidate.length >= 9.0:
				attack = candidate
				break
		check(not attack.is_empty(), "AI tunnel setup has a useful target")
		if attack.is_empty():
			continue
		attack.target.population = 8.0
		if burning:
			game.world_effects.start_fire(attack.exit, 4.5, 0)
		ai.take_turn(game)
		if burning:
			near(game.faction_skills[1].energy, 100.0, "AI refuses a visibly burning exit")
			check(game.marches.total_for(1) == 0, "unsafe tunnel sends no passengers")
		else:
			near(game.faction_skills[1].energy, 35.0, "AI pays R cost for useful capture")
			check(game.marches.total_for(1) == 30, "AI tunnel contains real thirty soldiers")
			near(attack.source.population, 70.0, "AI donor pays real population")
	await reset()
	ai = ai_setup()
	ai.take_turn(game)
	near(game.faction_skills[1].energy, 100.0, "AI holds skills when the battlefield offers no useful target")

func _selector() -> void:
	await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await process_frame
	var picker := current_scene
	for path: String in ["%PlayerCommander0", "%OpponentCommander1"]:
		var at: Vector2 = picker.get_node(path).get_global_rect().get_center()
		mouse(at, true)
		mouse(at, false)
	var session := root.get_node("Session")
	check(session.block_war_commander == &"squirrel" and session.block_war_opponent_commander == &"rabbit", "selector changes sides independently through native clicks")
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	check(game.faction_skills[0].commander == &"squirrel" and game.faction_skills[1].commander == &"rabbit", "selected sides reach match")
	game.restart()
	await scene_changed
	game = current_scene
	game.set_process(false)
	check(game.faction_skills[0].commander == &"squirrel" and game.faction_skills[1].commander == &"rabbit", "restart retains commander choices")
	while session.transition.busy:
		await process_frame
