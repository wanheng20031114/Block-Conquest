extends SceneTree
## Real match regression for shared energy, independent cooldowns and targeted skills.
## Run headless with Dummy audio; screen events still traverse the native GUI pipeline.

var game: Node3D
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.001, "%s (actual=%s expected=%s)" % [label, actual, expected])


func reset_match() -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.camera_rig.set_process(false)
	await physics_frame
	await process_frame


func motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.relative = at - root.get_mouse_position()
	event.button_mask = Input.get_mouse_button_mask()
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(at: Vector2, down: bool, which: int = MOUSE_BUTTON_LEFT) -> void:
	motion(at)
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_index = which
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and which == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func click(at: Vector2, which: int = MOUSE_BUTTON_LEFT) -> void:
	mouse(at, true, which)
	mouse(at, false, which)


func key_event(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.window_id = root.get_window_id()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func key(code: int) -> void:
	for down: bool in [true, false]:
		key_event(code, down)


func screen(at: Vector3) -> Vector2:
	return game.camera.unproject_position(at)


func _run() -> void:
	create_timer(80.0, true, false, true).timeout.connect(func() -> void:
		printerr("BLOCK_WAR_SKILL_ENERGY timeout")
		quit(3)
	)
	root.size = Vector2i(1600, 900)
	await reset_match()
	_energy_and_cooldowns()
	await reset_match()
	_invalid_casts()
	await reset_match()
	_recruitment_growth()
	await reset_match()
	_recruitment_interruption()
	await reset_match()
	_ground_impact()
	await reset_match()
	await _native_selection_and_hud()
	await game.prepare_shutdown()
	print("BLOCK_WAR_SKILL_ENERGY ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


func _energy_and_cooldowns() -> void:
	near(game.energy, 100.0, "New match starts with full shared energy")
	check(game.SKILL_ENERGY_COSTS == [30.0, 40.0, 35.0, 60.0], "Q/W/E/R expose distinct energy costs")
	game.simulate(0.25)
	near(game.energy, 100.0, "Regeneration cannot exceed the energy cap")
	game.energy = 20.0
	game.simulate(0.125)
	near(game.energy, 20.25, "Energy regenerates continuously at two per second")
	game.simulate(50.0)
	near(game.energy, 100.0, "Long simulation step clamps regenerated energy")
	var home: Node3D = game.by_id[0]
	home.population = home.capacity
	var original_population: float = home.population
	check(game.cast_skill(0, home), "Q can begin on the player's residence")
	near(game.energy, 70.0, "Q spends thirty from the common pool")
	near(home.population, original_population, "Q does not award troops instantly")
	check(game.cast_skill(1, null), "W can cast while Q is cooling")
	near(game.energy, 30.0, "W spends forty from that same pool")
	check(game.cooldowns == [35.0, 28.0, 0.0, 0.0], "Casting Q and W starts only their own cooldowns")
	check(not game.cast_skill(2, home), "E is unaffordable after Q and W despite being off cooldown")
	near(game.energy, 30.0, "Rejected E spends no energy")
	near(game.cooldowns[2], 0.0, "Rejected E starts no cooldown")
	game.energy = 35.0
	check(game.cast_skill(2, home), "Exactly thirty-five energy is sufficient for E")
	near(game.energy, 0.0, "E consumes exactly its cost without going negative")
	check(game.shields.has(home.building_id), "E still creates the residence shield")
	game.simulate(1.0)
	near(game.energy, 2.0, "Energy regeneration continues while all three skills cool")
	check(game.cooldowns == [34.0, 27.0, 44.0, 0.0], "Each cooldown advances independently by elapsed time")
	near(home.population, original_population + 5.0, "Q continues alongside W and E")
	var before_cooldowns: Array = game.cooldowns.duplicate()
	var before_durations: Array = game.active_durations.duplicate()
	var before_time: float = game.elapsed
	var before_population: float = home.population
	game.set_paused(true)
	game.simulate(12.0)
	near(game.energy, 2.0, "Pause freezes energy regeneration")
	near(home.population, before_population, "Pause freezes continuous recruitment")
	near(game.elapsed, before_time, "Pause freezes match time")
	check(game.cooldowns == before_cooldowns and game.active_durations == before_durations, "Pause freezes cooldowns and active skill durations")
	game.energy = 100.0
	check(not game.cast_ground_skill(3, Vector3.ZERO) and not game.can_cast_skill(3), "Pause prevents ground casts even with sufficient energy")
	near(game.energy, 100.0, "Paused cast consumes nothing")
	game.set_paused(false)
	game.simulate(0.25)
	near(home.population, before_population + 1.25, "Resume continues the remaining recruitment duration")
	game.finished = true
	game.energy = 12.0
	game.simulate(5.0)
	near(game.energy, 12.0, "Finished match does not regenerate energy")
	check(not game.cast_ground_skill(3, Vector3.ZERO) and not game.cast_skill(1, null), "Finished match rejects both skill entry points")


func _invalid_casts() -> void:
	var home: Node3D = game.by_id[0]
	var enemy: Node3D = game.by_id[1]
	var neutral: Node3D = game.by_id[2]
	var tower: Node3D = game.by_id[6]
	var forge: Node3D = game.by_id[8]
	tower.kind = 1
	tower.faction = 0
	forge.kind = 2
	forge.faction = 0
	for target: Node3D in [null, enemy, neutral, tower, forge]:
		check(not game.cast_skill(0, target), "Q rejects a target that is not an allied residence")
	for target: Node3D in [null, enemy, neutral]:
		check(not game.cast_skill(2, target), "E rejects missing or non-allied targets")
	for index: int in [-1, 4]:
		check(not game.cast_skill(index, home) and not game.can_cast_skill(index), "Invalid skill index is rejected")
	check(not game.cast_skill(3, enemy), "R cannot bypass ground targeting through the building-cast API")
	check(not game.cast_ground_skill(0, Vector3.ZERO), "Ground-cast API rejects non-R skills")
	for at: Vector3 in [Vector3.INF, Vector3(NAN, 0, 0), Vector3(40.01, 0, 0), Vector3(0, 0, 28.01)]:
		check(not game.cast_ground_skill(3, at), "R rejects non-finite or out-of-map ground coordinates")
	near(game.energy, 100.0, "All invalid targets preserve the common pool")
	check(game.cooldowns == [0.0, 0.0, 0.0, 0.0], "All invalid targets preserve all cooldowns")
	for index: int in 4:
		game.energy = game.SKILL_ENERGY_COSTS[index] - 0.01
		var success: bool = game.cast_ground_skill(index, Vector3.ZERO) if index == 3 else game.cast_skill(index, home)
		check(not success and not game.can_cast_skill(index), "Skill %d rejects even a fractional energy shortfall" % index)
		near(game.energy, game.SKILL_ENERGY_COSTS[index] - 0.01, "Failed skill %d has no partial payment" % index)
		game.energy = 100.0
		game.cooldowns[index] = 0.1
		success = game.cast_ground_skill(index, Vector3.ZERO) if index == 3 else game.cast_skill(index, home)
		check(not success and not game.can_cast_skill(index), "Skill %d must also satisfy its own cooldown" % index)
		near(game.energy, 100.0, "Cooldown rejection %d spends no energy" % index)
		game.cooldowns[index] = 0.0


func _recruitment_growth() -> void:
	var home: Node3D = game.by_id[0]
	var control: Node3D = game.by_id[2]
	control.kind = 0
	control.faction = 0
	control.population = 20.0
	home.population = 20.0
	check(game.cast_skill(0, home), "Q starts its six-second recruitment period")
	near(game.active_durations[0], 6.0, "Q exposes its full duration for HUD feedback")
	game.simulate(0.2)
	near(home.population - control.population, 1.0, "A subsecond frame grants proportional recruitment in addition to normal production")
	# Starting above the soft cap isolates recruitment from ordinary +1/s growth.
	home.population = home.capacity + 10.0
	var baseline: float = home.population
	var recruited_time := 0.0
	for delta: float in [0.1, 0.25, 0.65, 1.35, 5.4]:
		game.simulate(delta)
		recruited_time = minf(5.8, recruited_time + delta)
		near(home.population, baseline + recruited_time * 5.0, "Q integrates exactly the active part of irregular delta %s" % delta)
	near(home.population, baseline + 29.0, "Q's remaining 5.8 seconds produce exactly twenty-nine more troops")
	near(game.active_durations[0], 0.0, "Q ends at exactly six active seconds")
	game.simulate(3.0)
	near(home.population, baseline + 29.0, "Expired recruitment cannot keep granting over-cap troops")
	# A second legal cast after its independent cooldown covers a single long frame.
	game.simulate(35.0)
	baseline = home.population
	check(game.cast_skill(0, home), "Q becomes reusable after its cooldown and energy recover")
	game.simulate(8.0)
	near(home.population, baseline + 30.0, "A frame spanning all six seconds grants thirty, never forty")
	near(game.active_durations[0], 0.0, "Long-frame recruitment also expires cleanly")
	game.energy = 100.0
	game.cooldowns[0] = 0.0
	home.population = home.capacity - 1.0
	check(game.cast_skill(0, home), "Q can start just below the ordinary production cap")
	game.simulate(6.0)
	var whole_step: float = home.population
	near(whole_step, home.capacity + 29.0 + 1.0 / 6.0, "Only the first one-sixth second of ordinary growth contributes while Q crosses the cap")
	game.energy = 100.0
	game.cooldowns[0] = 0.0
	home.population = home.capacity - 1.0
	check(game.cast_skill(0, home), "The same near-cap fixture can use short frames")
	for step: int in 60:
		game.simulate(0.1)
	near(home.population, whole_step, "Recruitment and ordinary production are independent of frame partition at the soft cap")


func _recruitment_interruption() -> void:
	var home: Node3D = game.by_id[0]
	var backup: Node3D = game.by_id[2]
	backup.kind = 0
	backup.faction = 0
	backup.population = 50.0
	home.population = 200.0
	check(game.cast_skill(0, home), "Recruitment begins before a capture")
	game.simulate(1.0)
	home.population = 0.0
	game._on_unit_arrived(home.building_id, 1, 1.0)
	check(home.faction == 1 and game.active_durations[0] == 0.0, "Actual enemy capture immediately cancels the recruitment period")
	near(game.energy, 72.0, "Capture does not refund energy already spent")
	near(game.cooldowns[0], 34.0, "Capture does not reset Q cooldown")
	home.population = 0.0
	game._on_unit_arrived(home.building_id, 0, 1.0)
	home.population = home.capacity
	game.simulate(1.0)
	near(home.population, home.capacity, "Recapturing the residence cannot revive its cancelled recruitment")
	game.cooldowns[0] = 0.0
	game.energy = 100.0
	home.population = 200.0
	check(game.cast_skill(0, home), "A new Q can start after recapture")
	game.select_building(home)
	game.convert_selected(2)
	check(home.kind == 0 and home.is_constructing and game.active_durations[0] == 6.0, "Conversion keeps the residence and its recruitment during construction")
	game.simulate(2.0)
	near(home.population, 190.0, "Conversion costs twenty and the original Q continues recruiting")
	near(game.energy, 74.0, "Conversion preserves the original Q payment and normal regeneration")
	game.simulate(6.0)
	game.cooldowns[0] = 0.0
	game.energy = 100.0
	check(game.cast_skill(0, home), "Residence can begin recruitment late in its conversion")
	game.simulate(2.0)
	check(home.kind == 2 and not home.is_constructing and game.active_durations[0] == 0.0, "Completing conversion into a forge cancels remaining recruitment")
	near(home.population, 220.0, "Recruitment contributes only its two seconds before conversion completes")
	game.simulate(2.0)
	near(home.population, 220.0, "Converted forge cannot receive the remaining four seconds of Q")


func _ground_impact() -> void:
	var center := Vector3(0, 0, 7)
	var ally: Node3D = game.by_id[0]
	var enemy: Node3D = game.by_id[1]
	var neutral: Node3D = game.by_id[2]
	var outside: Node3D = game.by_id[3]
	var edge: Node3D = game.by_id[4]
	# Existing native building instances provide exact inside / edge / outside cases.
	for building: Node3D in game.buildings:
		building.kind = 0
		building.level = 1
		building.population = 100.0
	ally.position = center + Vector3(1, 0, 0)
	enemy.position = center + Vector3(-2, 0, 0)
	enemy.level = 3
	neutral.position = center + Vector3(0, 0, 3)
	neutral.population = 10.0
	outside.position = center + Vector3(4.51, 0, 0)
	outside.faction = 1
	edge.position = center + Vector3(-4.5, 0, 0)
	edge.faction = 1
	check(game.cast_ground_skill(3, center), "R accepts a chosen ground point without requiring a building there")
	near(game.energy, 40.0, "Ground impact spends sixty shared energy")
	check(game.cooldowns == [0.0, 0.0, 0.0, 60.0], "R starts only its sixty-second cooldown")
	near(enemy.population, 100.0, "Ignition does not damage distant buildings before the flame arrives")
	var wave: WarFireWave = game.world_effects.get_node("FireWaves/Fire0")
	check(wave.visible and wave.global_position.is_equal_approx(center), "Native fire effect starts at the requested ground location")
	game.simulate(WarFireWave.WINDUP_TIME + WarFireWave.EXPANSION_TIME)
	near(ally.population, 100.0, "Ground impact leaves friendly buildings unharmed")
	near(enemy.population, 65.0, "Residence level grants no passive defense against ground impact")
	check(neutral.population == 0.0 and neutral.faction == -1, "Ground impact damages neutral garrison but never captures it")
	near(edge.population, 65.0, "A hostile building exactly on the radius is hit")
	near(outside.population, 100.0, "A hostile building just outside the radius is untouched")
	game.simulate(0.5)
	near(enemy.population, 65.0, "The lingering fire does not repeatedly damage the same garrison")
	game.energy = 60.0
	game.cooldowns[3] = 0.0
	var empty := Vector3(0, 0, 26)
	check(game.cast_ground_skill(3, empty), "A valid empty ground location is still a deliberate cast")
	near(game.energy, 0.0, "Casting on empty ground still pays the full cost")
	near(game.cooldowns[3], 60.0, "Casting on empty ground still starts cooldown")
	game.simulate(WarFireWave.WINDUP_TIME + WarFireWave.EXPANSION_TIME)
	near(enemy.population, 65.0, "Empty-ground fire does not damage distant buildings")


func _native_skill_hint(button: Button) -> void:
	motion(button.get_global_rect().get_center())
	await create_timer(0.8).timeout
	var cards := root.find_children("SkillTooltip", "VBoxContainer", true, false)
	check(cards.size() == 1, "native skill hover opens one scene-authored tooltip")
	if cards.size() == 1:
		var card: Control = cards[0]
		check(card.get_parent().size.y < 240, "native tooltip fits its text without a tall empty backplate")
		check(card.get_node("%Title").text == "征召军令" and card.get_node("%Shortcut").text == "[Q]", "hover card separates the skill title and shortcut")
		check(card.get_node("%Description").text.contains("每秒征召 5 人") and card.get_node("%Stats").text.contains("35 秒"), "hover card exposes effect, energy cost and cooldown")
		var identity := card.get_instance_id()
		game.energy = 25.0
		game.update_hud()
		await process_frame
		check(is_instance_valid(card) and card.get_instance_id() == identity, "live energy changes do not restart the tooltip hover delay")
		check(card.get_node("%Energy").text.contains("25 / 100") and card.get_node("%State").text == "缺技力 5", "open tooltip updates its energy and shortfall immediately")
	game.energy = 100.0
	game.update_hud()
	motion(Vector2(800, 100))
	await process_frame
	await process_frame
	check(root.find_children("SkillTooltip", "VBoxContainer", true, false).is_empty(), "leaving the skill releases its native tooltip and signal binding")

func _native_selection_and_hud() -> void:
	# Complete the authored HUD reveal without advancing the manually stepped match.
	await create_timer(0.8).timeout
	var home: Node3D = game.by_id[0]
	var enemy: Node3D = game.by_id[1]
	var home_at := screen(home.get_node("PopulationBadge").global_position)
	var enemy_at := screen(enemy.global_position + Vector3(0, 1.5, 0))
	var empty_at := screen(Vector3(-4, 0, 6))
	var hint: Label = game.hud.get_node("%TargetHint")
	var q: Button = game.hud.get_node("UI/Skills/Row/Skill0")
	var w: Button = game.hud.get_node("UI/Skills/Row/Skill1")
	var e: Button = game.hud.get_node("UI/Skills/Row/Skill2")
	var r: Button = game.hud.get_node("UI/Skills/Row/Skill3")
	var ghost: Control = game.hud.get_node("%SkillDrag")
	var energy_bar: ProgressBar = game.hud.get_node("%EnergyBar")
	near(energy_bar.value, 100.0, "HUD initially exposes the full shared energy bar")
	check(q.hint.energy.contains("100 / 100"), "hover hints retain exact energy without a permanent caption")
	await _native_skill_hint(q)
	click(enemy_at)
	check(game.selected == enemy and game.drag_source == null, "Enemy selection is legal but cannot begin player dispatch")
	var q_at := q.get_global_rect().get_center()
	for invalid_at: Vector2 in [enemy_at, empty_at, q_at, Vector2(-10, -10)]:
		mouse(q_at, true)
		check(game.armed_skill == 0 and hint.visible and ghost.visible and q.button_pressed, "Pressing Q begins a visible drag immediately")
		near(game.energy, 100.0, "Picking up Q does not charge energy")
		mouse(invalid_at, false)
		check(game.armed_skill == -1 and not ghost.visible and not hint.visible and not q.button_pressed, "Invalid Q drop cancels and clears all drag visuals")
		check(game.energy == 100.0 and game.cooldowns[0] == 0.0, "Enemy, ground, icon and offscreen drops consume nothing")
	click(home_at)
	mouse(q_at, true)
	check(game.selected == home and game.cooldowns[0] == 0.0, "An already selected residence never causes an immediate Q cast")
	motion(home_at)
	await process_frame
	check(game.hovered == home and ghost.position.is_equal_approx(home_at + Vector2(24, -48)), "Skill ghost and building target follow the same native mouse position")
	var before_population: float = home.population
	var before_marches: int = game.marches.total_for(0)
	mouse(home_at, false)
	check(game.armed_skill == -1 and game.cooldowns[0] == 35.0 and game.drag_source == null, "Dropping Q on the population badge casts without starting a dispatch")
	check(game.marches.total_for(0) == before_marches and not ghost.visible and not q.button_pressed, "Skill release never dispatches troops or leaves a pressed card")
	near(game.energy, 70.0, "Q drop pays exactly once")
	near(home.population, before_population, "Q drop recruits gradually")
	check(q.disabled and q.get_node("Cooldown").visible and q.hint.status.contains("6"), "Q keeps its cooldown on the button and active duration in its hover hint")
	click(q_at)
	check(game.armed_skill == -1 and game.energy == 70.0, "A cooling card cannot begin a drag or spend twice")
	mouse(e.get_global_rect().get_center(), true)
	check(game.armed_skill == 2 and not game.shields.has(home.building_id), "E also waits for release even with its target selected")
	mouse(home_at, false)
	check(game.shields.has(home.building_id) and game.cooldowns[2] == 45.0 and game.energy == 35.0, "E drop applies its shield and pays once")
	game.energy = 59.0
	game.update_hud()
	check(r.disabled, "HUD disables R when common energy is below sixty")
	near(energy_bar.value, 59.0, "HUD bar reflects the common pool after spending")
	check(r.hint.energy.contains("59 / 100"), "hover hint energy matches its bar")
	game.energy = 100.0
	game.select_building(enemy)
	var r_at := r.get_global_rect().get_center()
	click(r_at)
	check(game.armed_skill == -1 and game.energy == 100.0, "A simple R click cancels on its own icon instead of waiting for a second click")
	mouse(r_at, true)
	check(game.armed_skill == 3 and game.cooldowns[3] == 0.0, "Holding the native R card begins ground targeting")
	near(game.energy, 100.0, "Beginning a ground drag is free")
	check(hint.visible and hint.text.contains("地面"), "R target hint explicitly asks for a ground location")
	motion(r_at)
	game._process(0.0)
	check(game.skill_ground_at(r_at) == Vector3.INF and game.ground_skill_target == Vector3.INF, "Hovering a HUD button suppresses the ground preview")
	var impact_at: Vector3 = enemy.global_position + Vector3(-3.5, 0, 0)
	enemy.population = 100.0
	var impact_screen := screen(impact_at)
	check(game.pick_building(impact_screen) == null and not game.hud.is_pointer_blocked(impact_screen), "R input fixture targets unblocked terrain beside an enemy")
	motion(impact_screen)
	game._process(0.0)
	check(game.ground_skill_target.distance_to(impact_at) < 0.01, "Real mouse motion places the preview on the projected ground plane")
	check(game.overlay.is_visible_in_tree() and game.overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Native aiming overlay remains visible without intercepting clicks")
	var before_enemy: float = enemy.population
	check(game.cooldowns[3] == 0.0, "Moving the held R card never casts early")
	mouse(impact_screen, false)
	check(game.armed_skill == -1 and game.cooldowns[3] == 60.0 and not hint.visible and not ghost.visible, "Terrain release casts R and closes the drag visuals")
	near(game.energy, 40.0, "Terrain release charges R exactly once")
	near(enemy.population, before_enemy, "Distant enemy is not damaged before the flame reaches it")
	var fire: WarFireWave = game.world_effects.get_node("FireWaves/Fire0")
	check(fire.global_position.distance_to(impact_at) < 0.01, "Native fire starts at the exact release point")
	game.simulate(WarFireWave.WINDUP_TIME + WarFireWave.EXPANSION_TIME)
	near(enemy.population, before_enemy - 35.0, "Screen-cast fire reaches the enemy inside its radius")
	game.cooldowns[3] = 0.0
	game.energy = 100.0
	game.update_hud()
	mouse(r_at, true)
	click(empty_at, MOUSE_BUTTON_RIGHT)
	mouse(empty_at, false)
	check(game.armed_skill == -1 and game.ground_skill_target == Vector3.INF, "Cancelling R clears both armed state and ground marker")
	near(game.energy, 100.0, "Cancelling R refunds no phantom charge")
	mouse(r_at, true)
	game._on_focus_exited()
	mouse(impact_screen, false)
	check(game.armed_skill == -1 and not ghost.visible and game.energy == 100.0, "Focus loss cancels a held skill before any later release")
	mouse(r_at, true)
	key(KEY_ESCAPE)
	mouse(impact_screen, false)
	check(game._local_menu and game.armed_skill == -1 and not ghost.visible, "Pause cancels a held skill and suppresses its later release")
	key(KEY_R)
	check(game.armed_skill == -1, "Skill shortcuts cannot arm while paused")
	key(KEY_ESCAPE)
	# Shortcuts use the same hold / aim / release gesture as the cards.
	game._cancel_recruitment() # Artificial cooldown reset must also reset its previous effect.
	game.cooldowns[0] = 0.0
	game.update_hud()
	motion(empty_at)
	key_event(KEY_Q, true)
	check(game.armed_skill == 0 and game.energy == 100.0, "Holding Q starts aiming without automatic use of the selected building")
	motion(home_at)
	key_event(KEY_E, false)
	check(game.armed_skill == 0, "Releasing an unrelated key cannot trigger the held skill")
	key_event(KEY_Q, false)
	check(game.armed_skill == -1 and game.energy == 70.0 and game.cooldowns[0] == 35.0, "Releasing Q over an allied residence casts through the native input pipeline")
	game.energy = 39.5
	game.update_hud()
	check(w.disabled, "W remains visibly unavailable below forty energy")
	game.simulate(0.25)
	game.update_hud()
	check(not w.disabled, "Regeneration makes W available at its exact cost")
	var w_at := w.get_global_rect().get_center()
	click(w_at)
	check(is_equal_approx(game.energy, 40.0) and game.cooldowns[1] == 0.0, "W also requires a battlefield drop instead of a click")
	mouse(w_at, true)
	check(is_equal_approx(game.energy, 40.0) and game.armed_skill == 1, "Holding W waits for release")
	mouse(empty_at, false)
	near(game.energy, 0.0, "Native W drop spends the regenerated common energy")
	check(game.cooldowns[1] == 28.0 and game.active_durations[1] == 8.0 and game.cooldowns[2] > 0.0, "W drop preserves its independent cooldown and active duration")
	for index: int in 4:
		check(game.hud.get_node("UI/Skills/Row/Skill%d" % index).disabled, "Zero shared energy disables skill button %d" % index)
