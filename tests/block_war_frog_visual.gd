extends SceneTree
## Render only on the private desktop: no system input or audible playback.
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

func _run() -> void:
	create_timer(170.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var session := root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"frog"
	session.block_war_opponent_commander = &"frog"
	change_scene_to_file("res://scenes/block_war/commander_select.tscn")
	await scene_changed
	await create_timer(0.5).timeout
	await capture("frog_selection_1600")
	root.size = Vector2i(1280, 720)
	await create_timer(0.3).timeout
	await capture("frog_selection_1280")
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await create_timer(0.4).timeout
	await capture("frog_map_1280")
	root.size = Vector2i(1600, 900)
	await create_timer(0.3).timeout
	await capture("frog_map_1600")
	root.size = Vector2i(1280, 720)
	await reset_game()
	await capture("frog_hud")
	for i: int in 4:
		var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % i)
		var event := InputEventMouseMotion.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event, true)
		await create_timer(0.7).timeout
		await capture("frog_hint_%d" % i)
	await reset_game()
	var home: WarBuilding = game.buildings[0]
	home.population = 100
	var center := home.global_position + Vector3(3, 0, 0)
	game.camera_rig.focus_at(center, true)
	game.camera.size = 22.0
	game.marches.send(1, home.building_id, 1, 36, PackedVector3Array([center + Vector3(5, 0, 0), home.global_position + Vector3(2.4, 0, 0)]))
	game.marches.tick(0.5)
	assert(game.cast_ground_skill(0, center))
	game.hud.hide()
	game.camera.size = 58.0
	await capture("mist_normal_zoom")
	game.camera.size = 22.0
	await clip("mist", 88)
	await reset_game()
	center = Vector3(-23, 0, 7)
	game.camera_rig.focus_at(center, true)
	game.camera.size = 22.0
	game.marches.send(0, 1, 0, 36, PackedVector3Array([center + Vector3(-2, 0, 0), center + Vector3(30, 0, 0)]))
	game.marches.send(1, 0, 1, 24, PackedVector3Array([center + Vector3(2, 0, 2), center + Vector3(-30, 0, 2)]))
	game.marches.tick(0.5)
	game.hud.hide()
	await capture("float_before")
	assert(game.cast_ground_skill(1, center))
	await clip("float", 88)
	await reset_game()
	center = Vector3(-23, 0, 0)
	game.camera_rig.focus_at(center + Vector3(0, 0, 8), true)
	game.camera.size = 32.0
	game.marches.send(0, 1, 0, 24, PackedVector3Array([center + Vector3(0, 0, -4), center + Vector3(0, 0, 35)]))
	game.marches.send(1, 0, 1, 12, PackedVector3Array([center + Vector3(-6, 0, 23), center + Vector3(-6, 0, -20)]))
	game.marches.tick(1.8)
	game.hud.hide()
	await capture("cloak_before")
	assert(game.cast_ground_skill(2, center))
	assert(game.marches.get_node("CloakedMilitia").multimesh.visible_instance_count == 24)
	game.camera.size = 58.0
	await capture("cloak_normal_zoom")
	game.camera.size = 32.0
	await clip("cloak", 164)
	await reset_game()
	var target: WarBuilding = game.buildings[1]
	target.faction = 1
	target.kind = 0
	target.level = 4
	target.population = 100
	target.refresh_visual()
	game.camera_rig.focus_at(target.global_position, true)
	game.camera.size = 22.0
	game.hud.hide()
	await capture("strike_before")
	assert(game.cast_skill(3, target))
	assert(target.level == 1 and is_equal_approx(target.population, 20))
	await capture("strike_release")
	await clip("strike", 32)
	game.faction_skills[0].cooldowns[3] = 0.0
	game.energy = 100
	target.population = 100
	target.level = 4
	target.refresh_visual()
	game.camera.size = 58.0
	assert(game.cast_skill(3, target))
	game.simulate(0.075)
	await capture("strike_normal_zoom")
	game.hud.show()
	await capture("frog_normal_zoom")
	await game.prepare_shutdown()
	print("FROG_VISUAL_COMPLETE")
	quit()
