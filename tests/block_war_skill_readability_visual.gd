extends SceneTree
## Native GPU review on a private desktop; viewport events only, no OS input.
var game: Node3D
var output: String
const FPS := 24.0

func _initialize() -> void:
	run.call_deferred()

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func point_at(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func stars() -> void:
	game.hud.get_node("UI/Top/Balance").update_factions([100, 100], [3.5, 5.0], 2)

func reset() -> void:
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
	game.update_hud()
	stars()
	await create_timer(0.8).timeout

func run() -> void:
	create_timer(140.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var session := root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"bear"
	await reset()
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = resolution
		await create_timer(0.2).timeout
		point_at(Vector2(24, 220))
		await create_timer(0.2).timeout
		await capture("hud_%d" % resolution.x)
		for index: int in 4:
			var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % index)
			point_at(button.get_global_rect().get_center())
			await create_timer(0.75).timeout
			await capture("tooltip_%d_%d" % [resolution.x, index])
	root.size = Vector2i(1600, 900)
	point_at(Vector2(24, 220))
	await create_timer(0.4).timeout
	for frame: int in 56:
		await process_frame
		await capture("stars_%03d" % frame)
	# Readability at low energy, during cooldown, and the transition back to ready.
	game.energy = 0.0
	game.update_hud()
	await capture("unavailable")
	game.energy = 100.0
	game.cooldowns.fill(1.0)
	game.update_hud()
	await capture("cooldown")
	game.cooldowns.fill(0.0)
	game.update_hud()
	await capture("ready_pulse")
	# Film a real squad reversing on the authored river route, then a tunnel squad.
	session.block_war_commander = &"rabbit"
	await reset()
	game.hud.hide()
	var home: WarBuilding = game.buildings[0]
	var target: WarBuilding = game.by_id[1]
	var route: PackedVector3Array = game.map.get_building_route(home, target)
	game.marches.send(home.building_id, target.building_id, home.faction, 36, route)
	var order: WarMarches.MarchOrder = game.marches._units[0].order
	game.marches.tick((order.length * 0.38) / WarMarches.SPEED)
	var center: Vector3 = game.marches._units[18].position
	game.camera_rig.focus_at(center, true)
	game.camera.size = 17.0
	for frame: int in 84:
		if frame == 18:
			center = game.marches._units[18].position
			assert(game.RABBIT_SKILLS.recall(game, center, 0) == 36)
		game.marches.tick(1.0 / FPS)
		game.world_effects.tick(1.0 / FPS)
		await process_frame
		await capture("recall_%03d" % frame)
	game.marches.clear()
	game.marches.send_tunnel(home.building_id, target.building_id, home.faction, 18, route, 0.16)
	game.marches.tick(0.55)
	game.camera_rig.focus_at(game.marches._units[6].position - game.marches._units[6].heading * 2.0, true)
	for frame: int in 72:
		if frame == 12:
			assert(game.RABBIT_SKILLS.recall(game, game.marches._units[0].position, 0) == 18)
		if frame >= 12:
			game.marches.tick(1.0 / FPS)
		game.world_effects.tick(1.0 / FPS)
		await process_frame
		await capture("tunnel_%03d" % frame)
	await game.prepare_shutdown()
	print("BLOCK_WAR_SKILL_READABILITY_VISUAL complete")
	quit()
