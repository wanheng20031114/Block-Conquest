extends SceneTree
## Thirteen GPU review images. Run on the private desktop with Dummy audio.
## Only native viewport events are injected; preferences are never saved.

var game: Node3D
var output: String
var pointer := Vector2(12, 350)
var captures := 0

func _initialize() -> void:
	_run.call_deferred()

func _physics_process(_delta: float) -> bool:
	var event := InputEventMouseMotion.new()
	event.position = pointer
	event.global_position = pointer
	root.push_input(event, true)
	return false

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)
	captures += 1

func fresh() -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.ai_enabled = false
	game.audio.muted = true
	game.energy = 100.0
	game.select_building(null)
	pointer = Vector2(12, 350)
	await create_timer(0.2).timeout

func focus(at: Vector3, extent: float = 27.0) -> void:
	game.camera.size = extent
	game.camera_rig.global_position = at

func advance(seconds: float) -> void:
	var left := seconds
	while left > 0.000001:
		var step := minf(1.0 / 30.0, left)
		game.simulate(step)
		game.overlay.queue_redraw()
		game.update_hud()
		left -= step
		await process_frame

func own(id: int, population: float) -> WarBuilding:
	var building: WarBuilding = game.by_id[id]
	building.faction = 0
	building.population = population
	building.refresh_visual()
	return building

func _run() -> void:
	create_timer(140.0, true, false, true).timeout.connect(func(): quit(3))
	output = ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var session := root.get_node("Session")
	session.block_war_map_id = "terraces"
	session.block_war_commander = &"pig"
	session.block_war_opponent_commander = &"pig"
	change_scene_to_file("res://scenes/block_war/commander_select.tscn")
	await scene_changed
	await create_timer(0.55).timeout
	assert(current_scene.get_node("%AnimalName").text == "猪猪")
	var charge_text: String = current_scene.get_node("%SkillDetail0").text
	assert("50%" in charge_text and "30%" in charge_text and "20" in charge_text)
	assert("60" in current_scene.get_node("%SkillDetail1").text)
	assert(current_scene.get_node("%SkillName2").text == "猪降临")
	assert("40" in current_scene.get_node("%SkillDetail2").text and "2" in current_scene.get_node("%SkillDetail2").text)
	assert("65" in current_scene.get_node("%SkillCost2").text)
	await capture("01_selection_1600")
	root.size = Vector2i(1280, 720)
	await create_timer(0.25).timeout
	await capture("02_selection_1280")
	if "--selection-only" in OS.get_cmdline_user_args():
		print("PIG_SELECTION_VISUAL PASS current_rule_text=true captures=2")
		quit()
		return
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await create_timer(0.4).timeout
	assert(current_scene.get_node("%OpponentCommander5").button_pressed)
	var map_bounds: Rect2 = current_scene.get_global_rect()
	for index: int in 6:
		var choice: Button = current_scene.get_node("%%OpponentCommander%d" % index)
		assert(map_bounds.encloses(choice.get_global_rect()), "all six opponent choices fit")
		assert(choice.size.x >= choice.get_minimum_size().x, "opponent text and icon fit")
	await capture("02b_map_1280")
	root.size = Vector2i(1600, 900)

	await fresh()
	var home := own(15, 70.0)
	focus(home.global_position + Vector3(1, 0, 1), 24.0)
	for index: int in 2:
		assert(game.cast_skill(index, home))
	await advance(0.25)
	assert(game.pig.ready[15].x > 0.0 and game.pig.ready[15].y > 0.0 and game.pig.ready[15].z == 0.0)
	await capture("03_two_preparations")
	assert(game.issue_order(home, game.by_id[1], 100) == 20)
	await advance(0.30)
	await capture("04_takeoff")
	await advance(4.0)
	focus(Vector3(6, 4.5, -5), 33.0)
	game.hud.hide()
	await capture("05_flight_over_highland")

	await fresh()
	home = own(15, 80.0)
	assert(game.cast_skill(2, home))
	assert(game.pig.airlifts.size() == 1)
	focus(Vector3(0, 4.5, -7), 24.0)
	game.hud.hide()
	await advance(1.65)
	await capture("06_airlift_batches")

	await fresh()
	var target: WarBuilding = game.by_id[10]
	# Central raised tower gives a real rooftop and a non-zero terrain surface.
	target.faction = 1
	target.population = 60.0
	target.refresh_visual()
	focus(target.global_position + Vector3(0, 3, 0), 31.0)
	game.hud.hide()
	assert(game.cast_ground_skill(3, target.global_position))
	await advance(0.43)
	await capture("07_giant_fall_rooftop")
	await advance(0.29)
	assert(target.population == 30.0)
	await capture("08_giant_impact_rooftop")
	await advance(0.9)
	assert(game.pig.drops.is_empty())
	await capture("09_giant_cleared")

	# A separate sloping surface verifies the ground decal uses baked heights.
	game.energy = 100.0
	game.faction_skills[0].cooldowns[3] = 0.0
	var slope := Vector3.ZERO
	for x: int in range(-24, -8):
		var point: Vector3 = game.map.definition.surface_point(Vector3(float(x), 0, 0))
		if point.y > 1.0 and point.y < 3.5:
			slope = point
			break
	assert(slope.y > 1.0 and slope.y < 3.5, "landing review uses an actual sloping terrain sample")
	focus(slope + Vector3(0, 2, 0), 23.0)
	assert(game.cast_ground_skill(3, slope))
	await advance(0.33)
	await capture("10_slope_landing_circle")
	await fresh()
	game.update_hud()
	pointer = game.hud.get_node("UI/Skills/Row/Skill3").get_global_rect().get_center()
	await create_timer(0.7).timeout
	await capture("11_giant_tooltip")
	await game.prepare_shutdown()
	game = null
	pointer = Vector2(12, 350)
	change_scene_to_file("res://scenes/codex/codex.tscn")
	await scene_changed
	current_scene.commander = &"pig"
	current_scene._filter_entries("")
	current_scene._select_skill(3, false)
	await create_timer(1.55).timeout
	await capture("12_pig_codex")
	print("PIG_VISUAL_COMPLETE ", captures)
	quit()
