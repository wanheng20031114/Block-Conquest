extends "res://tests/block_war_ai_information_test.gd"
## Departure previews and AI planning use the same skill attack as real soldiers.

const CATALOG := preload("res://scripts/codex/codex_catalog.gd")

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	var output := ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	session.block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	_preview()
	_ai()
	await game.prepare_shutdown()
	game.free()
	game = null
	await _catalog(output)
	session.block_war_map_id = previous_map
	print("BURROW_PREVIEW ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _preview() -> void:
	reset()
	var source := set_building(0, 0, 3, 1, 40.0)
	var target := set_building(1, 1, 3, 1, 100.0)
	var second := set_building(2, 0, 3, 1, 40.0)
	game.drag_source = source
	game.drag_sources.assign([source])
	game.hovered = target
	game.order_previews.clear()
	game.order_previews.append({"source": source, "count": 20, "route": PackedVector3Array()})
	check(game.overlay.dispatch_advantage() == 0, "ordinary dispatch retains equal exchange")
	source.begin_burrow(15.0)
	check(game.overlay.dispatch_advantage() == 3, "burrow's fifty attack points appear in single-source preview")
	game.overlay._update_dispatch_hint()
	check(game.overlay.hint_label.text == "20", "attack changes no displayed soldier count")
	game.shields[target.building_id] = 8.0
	check(game.overlay.dispatch_advantage() == 1, "burrow skill attack divides by skill defense")
	game.shields.clear()
	game.drag_sources.append(second)
	game.order_previews.append({"source": second, "count": 20, "route": PackedVector3Array()})
	check(game.overlay.dispatch_advantage() == 2, "mixed dispatch weights enhanced and ordinary soldiers separately")
	game.order_previews[0].count = 10
	game.order_previews[1].count = 40
	check(game.overlay.dispatch_advantage() == 1, "mixed preview uses actual departure counts rather than source count")
	game.overlay._update_dispatch_hint()
	check(game.overlay.hint_label.text == "50", "mixed attack preview preserves actual total population")
	for owner: int in [0, 2]:
		target.faction = owner
		check(game.overlay.dispatch_advantage() == 0, "burrow reinforcements show no combat advantage")
	target.faction = 1
	source.clear_burrow()
	check(game.overlay.dispatch_advantage() == 0, "expired readiness removes the speculative attack bonus")
	game.pig.ready[source.building_id] = Vector3(15, 0, 0)
	check(game.overlay.dispatch_advantage() == 1, "pig charge retains its existing weighted preview")
	game.pig.ready.clear()
	game._cancel_drag()

func _ai() -> void:
	reset()
	var source := set_building(1, 1, 3, 1, 34.0)
	var target := set_building(2, -1, 2, 1, 30.0)
	set_building(0, 0, 1, 4, 1000.0)
	game.faction_skills[1].commander = &"rabbit"
	game.faction_skills[1].cooldowns[3] = 0.0
	game.sync_environment_bonuses()
	var plan: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, source, target, 75)
	check(not plan.is_empty() and plan.length >= 9.0 and plan.count == 25, "neutral fixture allows a twenty-five-person distant tunnel")
	check(25.0 * game.combat_multiplier(1, target) <= 32.0, "ordinary attack cannot satisfy the target's capture margin")
	check(25.0 * game.combat_multiplier(1, target, game.SKILL_RULES.BURROW_ATTACK_BONUS) > 32.0, "burrow attack can satisfy that same public capture margin")
	TACTICS.new(1).take_turn(game)
	check(game.marches.incoming_for(target.building_id, 1) == 25, "AI commits the enhanced army to the newly viable target")
	check(source.population == 34.0 and source.queued_population == 25, "AI attack bonus does not invent or withdraw soldiers during digging")
	near(game.faction_skills[1].energy, 35.0, "AI pays the unchanged rabbit ultimate cost")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(unit.order.rabbit_burrow and unit.order.strength == 1.0, "AI tunnel uses real skill attack with ordinary population strength")

func _catalog(output: String) -> void:
	var page: Control = load("res://scenes/codex/codex.tscn").instantiate()
	root.add_child(page)
	for frame: int in 8: await process_frame
	var row := CATALOG.HEROES.find(&"rabbit")
	page.get_node("%Entries").select(row)
	page._select_entry(row)
	page._select_skill(3, false)
	var demo: Control = page.get_node("%Demo")
	demo.set_playing(false)
	var world: Node3D = demo.world
	world.set_running(true)
	world.set_process(false)
	demo.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame: int in 68:
		world._process(1.0 / 24.0)
		demo._update_caption()
		await process_frame
	check(world.cast_succeeded and world.dispatched, "codex uses an actual cast and subsequent tunnel dispatch")
	check("+50%" in world.caption and "0.16" not in world.caption, "codex caption explains attack without departure-interval text")
	var description: String = page.get_node("%SkillDescription").text
	check("+50%" in description and "0.16" not in description, "skill description shows new attack with the requested concise wording")
	check(not world.marches._units.is_empty(), "live codex frame contains actual tunnel soldiers")
	for unit: WarMarches.MarchUnit in world.marches._units:
		check(unit.order.rabbit_burrow and unit.order.strength == 1.0, "codex soldiers use real tunnel attack without population inflation")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join("rabbit_r.png")) == OK, "save native rabbit ultimate screenshot")
	page.queue_free()
	await process_frame
