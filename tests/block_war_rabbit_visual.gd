extends SceneTree
## Native GPU capture on a never-activated private desktop, using viewport input only.
var game: Node3D
var output: String
const FPS := 24.0

func _initialize() -> void:
	_run.call_deferred()

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func reset_game() -> void:
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
	await physics_frame
	await create_timer(0.5).timeout

func clip(label: String, frames: int, follow_rush: bool = false) -> void:
	for index: int in frames:
		game.simulate(1.0 / FPS)
		if follow_rush:
			var focus := Vector3.ZERO
			var count := 0
			for unit: WarMarches.MarchUnit in game.marches._units:
				if unit.is_exposed() and unit.rush_remaining > 0.0:
					focus += unit.position
					count += 1
			if count > 0:
				game.camera_rig.focus_at(focus / float(count), true)
		game.overlay.queue_redraw()
		await process_frame
		if index % 2 == 0:
			await capture("%s_%03d" % [label, index])
		if index == 12:
			var close_zoom: float = game.camera.size
			game.camera.size = 58.0
			await capture(label + "_normal_zoom")
			game.camera.size = close_zoom

func _run() -> void:
	create_timer(160.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var session: Node = root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"rabbit"
	session.block_war_opponent_commander = &"squirrel"
	if "--battle-only" not in OS.get_cmdline_user_args():
		change_scene_to_file("res://scenes/block_war/map_select.tscn")
		await scene_changed
		await create_timer(0.8).timeout
		await capture("rabbit_selection")
	await reset_game()
	await capture("rabbit_hud")
	for index: int in 4:
		var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % index)
		var event := InputEventMouseMotion.new()
		event.window_id = root.get_window_id()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event, true)
		await create_timer(0.7).timeout
		await capture("rabbit_hint_%d" % index)
	await reset_game()
	game.hud.hide()
	var center := Vector3(-22, 0, 10)
	game.camera_rig.focus_at(center, true)
	game.camera.size = 19.0
	game.marches.send(0, 1, 0, 66, PackedVector3Array([center + Vector3(-5, 0, 0), center + Vector3(55, 0, 0)]))
	game.marches.tick(1.6)
	var rushed: Array[WarMarches.MarchUnit] = game.marches.rush_targets(0, center, game.SKILL_RULES.RABBIT_RUSH_RADIUS)
	assert(rushed.size() > 0 and rushed.size() < 66)
	await capture("dash_before")
	assert(game.cast_ground_skill(0, center))
	await clip("dash", 162, true)
	await reset_game()
	game.hud.hide()
	var target: WarBuilding
	for building: WarBuilding in game.buildings:
		if building.faction == 1:
			target = building
	target.kind = 2
	target.level = 1
	target.refresh_visual()
	game.camera_rig.focus_at(target.global_position + Vector3(0, 0, 1), true)
	game.camera.size = 13.0
	assert(game.cast_skill(1, target))
	await clip("seal", 162)
	await reset_game()
	game.hud.hide()
	var home: WarBuilding = game.buildings[0]
	var other_home: WarBuilding = game.by_id[2]
	other_home.faction = 1
	other_home.population = 60.0
	other_home.refresh_visual()
	var route: PackedVector3Array = game.map.get_building_route(home, other_home)
	var reverse_route: PackedVector3Array = game.map.get_building_route(other_home, home)
	center = (home.global_position + other_home.global_position) * 0.5
	game.camera_rig.focus_at(center, true)
	game.camera.size = 24.0
	game.marches.send(home.building_id, other_home.building_id, 0, 36, route)
	game.marches.send(other_home.building_id, home.building_id, 1, 36, reverse_route)
	game.marches.tick(3.0)
	await capture("recall_before")
	var recalled: Array[Dictionary] = game.RABBIT_SKILLS.recall_plan(game, center)
	assert(recalled.size() > 24)
	assert(game.cast_ground_skill(2, center))
	await clip("recall", 48)
	await reset_game()
	home = game.buildings[0]
	home.population = 70.0
	target = game.by_id[1]
	var plan: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, home, target, 100)
	assert(not plan.is_empty())
	assert(home.global_position.distance_to(target.global_position) > 30.0)
	game.camera_rig.focus_at(home.global_position, true)
	game.camera.size = 24.0
	await process_frame
	game.request_skill(3)
	game._update_skill_drag(game.camera.unproject_position(home.global_position + Vector3.UP * 1.5))
	game.overlay.queue_redraw()
	await capture("rabbit_burrow_aim")
	game._cancel_skill_drag()
	game.hud.hide()
	assert(game.cast_skill(3, home))
	await clip("burrow_ready", 24)
	game.camera_rig.focus_at((plan.entrance + plan.exit) * 0.5, true)
	game.camera.size = 58.0
	assert(game.issue_order(home, target, 100) == 50)
	await clip("burrow_dig", 36)
	game.camera_rig.focus_at(plan.exit, true)
	game.camera.size = 24.0
	await clip("burrow_exit", 60)
	await game.prepare_shutdown()
	print("BLOCK_WAR_RABBIT_VISUAL completed output=", output)
	quit()
