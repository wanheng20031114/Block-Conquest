extends SceneTree
## Drives actual simulation decisions, then captures native viewport rendering.
## All 24 cases must cast successfully and change the corresponding rule state.

const CATALOG := preload("res://scripts/codex/codex_catalog.gd")
var checks := 0
var failures: Array[String] = []
var output := ""
var session: Node
var page: Control

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL CODEX_NATIVE ", label)

func frames(count: int) -> void:
	for frame: int in count:
		await RenderingServer.frame_post_draw

func snapshot() -> Array:
	var online: Node = session.get_node("Online")
	return [session.block_war_commander, session.block_war_opponent_commander, session.block_war_map_id, session.settings.snapshot(), online.match_config.duplicate(true), get_tree_auto_quit()]

func get_tree_auto_quit() -> bool:
	return auto_accept_quit

func save(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " screenshot")

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	output = ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	session = root.get_node("Session")
	var original := snapshot()
	page = load("res://scenes/codex/codex.tscn").instantiate()
	root.add_child(page)
	await frames(12)
	var demo: Control = page.get_node("%Demo")
	for hero: StringName in CATALOG.HEROES:
		var row := CATALOG.HEROES.find(hero)
		page.get_node("%Entries").select(row)
		page._select_entry(row)
		for index: int in 4:
			page._select_skill(index, false)
			demo.set_playing(false)
			var game: Node3D = demo.world
			game.set_running(true)
			game.set_process(false)
			demo.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var label := "%s_%d" % [hero, index + 1]
			var initial_energy: float = game.energy
			game._process(game.cast_at + 0.001)
			check(game.cast_succeeded and game.cast_count == 1, label + " uses real cast once")
			check(game.cooldowns[index] > 0.0 and game.energy < initial_energy, label + " actual cooldown and energy")
			check(game.network_match == null and game.match_config.is_empty() and not game.ai_enabled, label + " no session network or AI")
			check(demo.viewport.own_world_3d and demo.viewport.gui_disable_input and not game.is_processing_input(), label + " isolated world and input")
			check(not game.away.get_node("PopulationLabel").visible, label + " enemy population stays hidden")
			verify_effect(game, hero, index, label)
			var capture_at: float = maxf(game.cast_at + 0.45, game.dispatch_at + 1.0)
			while game.elapsed < capture_at:
				game._process(1.0 / 24.0)
				demo._update_caption()
				await frames(1)
			await save(label)
			check(page.get_global_rect().grow(1).encloses(demo.get_global_rect()), label + " demo fits page")
			check(page.get_global_rect().grow(1).encloses(page.get_node("Margin").get_global_rect()), label + " all page margins fit")
			check(demo.viewport.size.x >= 480 and demo.viewport.size.y >= 270, label + " readable native render size")
			check(demo.get_node("%Stage").size.x >= demo.size.x * 0.9, label + " battlefield fills the panel width")
			for building: WarBuilding in game.buildings:
				check(Rect2(Vector2.ZERO, Vector2(demo.viewport.size)).grow(-8).has_point(game.camera.unproject_position(building.position + Vector3(0, 3, 0))), label + " building roof inside camera")
				if building.faction == 0:
					check(Rect2(Vector2.ZERO, Vector2(demo.viewport.size)).grow(-25).has_point(game.camera.unproject_position(building.get_node("PopulationLabel").global_position)), label + " own population badge inside camera")
			check(snapshot() == original, label + " session preserved")
			# Run through arrivals and expiry as well as the first impact frame.
			game._process(7.0 - game.elapsed)
			check(is_equal_approx(game.elapsed, 7.0) and not game.finished, label + " actual arrival and duration simulation remains live")
			if hero == &"bear" and index == 1:
				check(not game.bear.is_locked(1) and game.away.queued_population == 0, "bear lock expires without reviving a cancelled order")
				game._process(0.6)
				check(game.followup_dispatched and game.marches.total_for(1) > 0, "bear lock demonstration explicitly issues a new order after expiry")
			if hero == &"pig" and index == 2:
				verify_airlift_framing(game, demo, "friendly airlift")
				check(game.home.population == 80.0 and game.away.population == 20.0, "friendly pig airlift adds forty soldiers without a source withdrawal")
				check(game.marches._units.is_empty() and game.pig.airlifts.is_empty(), "friendly airlift finishes without a fake marching order")
			game.set_running(false)
			var stopped: float = game.elapsed
			await frames(2)
			check(is_equal_approx(game.elapsed, stopped), label + " paused simulation freezes")
	# The ultimate alternates two genuine casts across separate clean worlds.
	# Each variant must pay its own ordinary cost and choose the correct target.
	var bear_row := CATALOG.HEROES.find(&"bear")
	page.get_node("%Entries").select(bear_row)
	page._select_entry(bear_row)
	page._select_skill(3, false)
	demo.bear_hostile = true
	demo.replay()
	demo.set_playing(false)
	var hostile_game: Node3D = demo.world
	hostile_game.set_running(true)
	hostile_game.set_process(false)
	demo.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hostile_game._process(hostile_game.cast_at + 0.001)
	check(hostile_game.cast_succeeded and hostile_game.bear.wards.has(1), "bear hostile demonstration casts onto the enemy building")
	check(hostile_game.bear.wards[1].hostile and hostile_game.bear.wards[1].faction == 0, "hostile fireball belongs to the casting side")
	check(is_equal_approx(hostile_game.skill_defense_bonus(hostile_game.away), hostile_game.SKILL_RULES.BEAR_CURSE_DEFENSE), "hostile demonstration uses actual defense reduction")
	check(is_equal_approx(hostile_game.energy, 100.0 - hostile_game.SKILL_RULES.BEAR_COSTS[3] + 0.001), "hostile demonstration pays its full energy cost")
	for frame: int in 12:
		hostile_game._process(1.0 / 24.0)
		demo._update_caption()
		await frames(1)
	await save("bear_4_hostile")
	hostile_game.set_running(false)
	demo._repeat()
	await frames(2)
	check(not demo.bear_hostile and not demo.world.bear_hostile, "automatic repeat returns to the friendly demonstration")
	var frog_row := CATALOG.HEROES.find(&"frog")
	page.get_node("%Entries").select(frog_row)
	page._select_entry(frog_row)
	page._select_skill(0, false)
	demo.frog_siege = true
	demo.replay()
	demo.set_playing(false)
	var siege_game: Node3D = demo.world
	siege_game.set_running(true)
	siege_game.set_process(false)
	demo.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	siege_game._process(siege_game.cast_at + 0.001)
	check(siege_game.cast_succeeded and siege_game.marches.weak_zones.has(0), "frog siege demonstration casts actual mist")
	check(is_equal_approx(siege_game.skill_defense_bonus(siege_game.away), siege_game.SKILL_RULES.FROG_BUILDING_DEFENSE), "siege demonstration weakens its enemy building")
	check(siege_game.marches.total_for(0) > 0 and siege_game.away.faction == 1, "siege cast precedes the real army's arrival")
	for frame: int in 12:
		siege_game._process(1.0 / 24.0)
		demo._update_caption()
		await frames(1)
	await save("frog_1_siege")
	siege_game._process(10.0 - siege_game.elapsed)
	check(siege_game.away.faction == 0, "real troops capture the weakened siege-demo building")
	check(is_zero_approx(siege_game.skill_defense_bonus(siege_game.away)), "siege demo does not retain a stale building debuff")
	siege_game.set_running(false)
	demo._repeat()
	await frames(2)
	check(not demo.frog_siege and not demo.world.frog_siege, "automatic repeat returns to mist's field-weakening demonstration")
	var pig_row := CATALOG.HEROES.find(&"pig")
	page.get_node("%Entries").select(pig_row)
	page._select_entry(pig_row)
	page._select_skill(2, false)
	check(not demo.pig_hostile, "pig airlift demonstration begins with friendly reinforcement")
	demo._repeat()
	await frames(2)
	check(demo.pig_hostile and demo.world.pig_hostile, "next pig airlift cycle switches to the enemy building")
	demo.set_playing(false)
	var airlift_game: Node3D = demo.world
	airlift_game.set_running(true)
	airlift_game.set_process(false)
	demo.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	airlift_game._process(airlift_game.cast_at + 0.001)
	check(airlift_game.cast_succeeded and airlift_game.pig.airlifts[0].target == 1, "enemy airlift demonstration uses the actual destination")
	verify_airlift_framing(airlift_game, demo, "enemy airlift")
	check(airlift_game.pig.airlifts[0].landed == 0 and airlift_game.home.population == 40.0, "enemy airlift has no early landings or source cost")
	for frame: int in 12:
		airlift_game._process(1.0 / 24.0)
		demo._update_caption()
		await frames(1)
	await save("pig_3_hostile")
	airlift_game._process(4.0 - airlift_game.elapsed)
	check(airlift_game.away.faction == 0 and airlift_game.away.population >= 20.0, "airlift soldiers capture and reinforce the enemy building through real combat")
	check(airlift_game.home.population == 40.0 and airlift_game.marches._units.is_empty(), "capturing airlift creates no source dispatch")
	airlift_game.set_running(false)
	page._set_category(1)
	await frames(3)
	check(demo.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and demo.world.process_mode == Node.PROCESS_MODE_DISABLED, "reading mechanics disables rendering and simulation")
	page._set_category(0)
	demo.replay()
	check(demo.world.cast_count == 0 and is_zero_approx(demo.progress), "replay creates a clean actual battlefield")
	root.size = Vector2i(960, 540)
	await frames(8)
	check(page.get_global_rect().grow(1).encloses(demo.get_global_rect()), "small window retains complete demo")
	check(root.get_visible_rect().grow(1).encloses(page.get_global_rect()), "small window retains the complete page")
	check(page.get_global_rect().grow(1).encloses(page.get_node("Margin").get_global_rect()), "small window retains top and bottom margins")
	verify_airlift_framing(demo.world, demo, "small-window airlift")
	await save("small_window")
	page.queue_free()
	await process_frame
	check(snapshot() == original, "exit preserves session, online state, preferences and window lifecycle")
	print("CODEX_NATIVE_RESULTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func verify_airlift_framing(game: Node3D, demo: Control, label: String) -> void:
	# Include the entire perimeter and the wind above soldiers' initial height.
	var frame := Rect2(Vector2.ZERO, Vector2(demo.viewport.size)).grow(-8)
	for building: WarBuilding in game.buildings:
		for height: float in [0.0, 9.0]:
			for index: int in 8:
				var angle := TAU * index / 8.0
				var point := building.position + Vector3(cos(angle) * 3.2, height, sin(angle) * 3.2)
				check(frame.has_point(game.camera.unproject_position(point)), label + " complete descent stays inside camera")

func verify_effect(game: Node3D, hero: StringName, index: int, label: String) -> void:
	var active := false
	match hero:
		&"squirrel": active = [game.faction_skills[0].recruit_target_id == 0, game.marches.haste_zones.has(0), game.shields.has(0), not game.fire_states.is_empty()][index]
		&"rabbit":
			if index == 0:
				for unit: WarMarches.MarchUnit in game.marches._units: active = active or unit.rush_remaining > 0.0
			elif index == 1: active = game.away.disruption_remaining > 0.0
			elif index == 2:
				for unit: WarMarches.MarchUnit in game.marches._units: active = active or unit.order.target_id == unit.order.source_id
			else: active = game.home.burrow_remaining > 0.0
		&"bear":
			active = [game.home.level == 2 and not game.home.is_constructing, game.bear.locks.has(1), game.bear.links.has(0), game.bear.wards.has(1 if game.bear_hostile else 0)][index]
			if index == 0:
				check(game.home.population >= 20.0, "bear Q demonstration upgrades without paying population")
			elif index == 1:
				check(game.away.queued_population == 0 and game.marches.total_for(1) > 0, "bear W cancels doorway queues while departed soldiers continue")
		&"frog":
			if index == 0: active = game.marches.weak_zones.has(0)
			elif index in [1, 2]:
				for unit: WarMarches.MarchUnit in game.marches._units: active = active or (unit.levitation_remaining > 0.0 if index == 1 else unit.cloaked)
				if index == 2:
					var complete_column := true
					for unit: WarMarches.MarchUnit in game.marches._units:
						complete_column = complete_column and unit.is_exposed() and unit.cloaked
					check(game.marches.total_for(0) == 20 and complete_column, "cloak demonstration selects the entire departed column")
			else: active = game.away.level == 1 and game.after_population < game.before_population * 0.3
		&"fox":
			if index == 0: active = game.after_population < game.before_population
			elif index == 1: active = game.morale.level(0) == 1 and game.morale.level(1) == 1
			elif index == 2: active = game.marches.total_for(0) > 0
			else: active = game.marches.total_for(1) > 0 and game.after_population < game.before_population
		&"pig":
			if index < 2: active = game.pig.flags_for(0)[index] > 0.0
			elif index == 2:
				active = not game.pig.airlifts.is_empty() and game.pig.airlifts[0].target == 0
				check(game.home.population == 40.0 and game.marches._units.is_empty(), "friendly airlift starts without spending or moving existing troops")
			else: active = not game.pig.drops.is_empty()
	check(active, label + " changes the real skill state")
