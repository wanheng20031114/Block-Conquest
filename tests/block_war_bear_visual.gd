extends SceneTree
## GPU review on the private desktop. No OS input or audible playback.
var game: Node3D
var output: String

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
	await create_timer(0.3).timeout

func clip(label: String, frames: int) -> void:
	for i: int in frames:
		game.simulate(1.0 / 24.0)
		game.overlay.queue_redraw()
		await process_frame
		await capture("%s_%03d" % [label, i])

func focus(at: Vector3, zoom: float) -> void:
	# Isolate visual inspection from the gameplay camera's map-edge constraint.
	game.camera.size = zoom
	game.camera_rig.global_position = at

func _run() -> void:
	create_timer(140.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var session := root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"bear"
	session.block_war_opponent_commander = &"bear"
	change_scene_to_file("res://scenes/block_war/commander_select.tscn")
	await scene_changed
	await create_timer(0.5).timeout
	await capture("bear_selection_1600")
	root.size = Vector2i(1280, 720)
	await create_timer(0.3).timeout
	await capture("bear_selection_1280")
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await create_timer(0.4).timeout
	await capture("bear_map")
	await reset_game()
	await capture("bear_hud")
	for i: int in 4:
		var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % i)
		var event := InputEventMouseMotion.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event, true)
		await create_timer(0.7).timeout
		await capture("bear_hint_%d" % i)
	await reset_game()
	var home: WarBuilding = game.buildings[0]
	focus(home.global_position, 18.0)
	game.select_building(home)
	game.upgrade_selected()
	game.simulate(1.0)
	assert(game.cast_skill(0, home))
	game.hud.hide()
	await clip("toolbox", 26)
	await reset_game()
	game.hud.hide()
	var locked: WarBuilding = game.buildings[6]
	locked.faction = 1
	locked.population = 80
	locked.refresh_visual()
	focus(locked.global_position, 20.0)
	assert(game.issue_order(locked, game.buildings[0], 100, 1) > 0)
	game.marches.tick(0.2)
	assert(game.cast_skill(1, locked))
	await clip("lock", 150)
	await reset_game()
	home = game.buildings[0]
	var support: WarBuilding = game.buildings[6]
	support.faction = 0
	support.population = 50
	support.refresh_visual()
	focus((home.global_position + support.global_position) * 0.5, 23.0)
	game.request_skill(2, true)
	game._update_skill_drag(game.camera.unproject_position(home.global_position))
	await capture("link_preview")
	game._cancel_skill_drag()
	assert(game.cast_skill(2, home))
	game.hud.hide()
	game._on_unit_arrived(home.building_id, 1, 21.0)
	await clip("link", 48)
	game.camera.size = 58.0
	game.hud.show()
	await capture("link_normal_zoom")
	await reset_game()
	home = game.buildings[0]
	focus(home.global_position + Vector3(2, 0, 0), 22.0)
	game.hud.hide()
	game.marches.send(1, 0, 1, 50, PackedVector3Array([home.global_position + Vector3(11, 0, 4), home.global_position + Vector3(2.6, 0, 0)]))
	game.marches.tick(0.6)
	assert(game.cast_skill(3, home))
	await clip("fortress", 150)
	game.camera.size = 58.0
	game.hud.show()
	game.faction_skills[0].cooldowns[3] = 0
	game.energy = 100
	assert(game.cast_skill(3, home))
	game.simulate(0.3)
	await capture("fortress_normal_zoom")
	await game.prepare_shutdown()
	print("BEAR_VISUAL_COMPLETE")
	quit()
