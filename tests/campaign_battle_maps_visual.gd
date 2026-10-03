extends SceneTree
## Capture the actual playable battle scenes, lighting, UI, and native map picker.

func _initialize() -> void:
	_run.call_deferred()

func _capture(output: String, name: String) -> void:
	for frame: int in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)
	print("CAMPAIGN_BATTLE_CAPTURE ", name,
		" primitives=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		" draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))

func _run() -> void:
	create_timer(110.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	root.gui_disable_input = true
	var output := OS.get_cmdline_user_args()[0]
	var session := root.get_node("Session")
	for index: int in 2:
		session.campaign_active_stage = index
		session.block_war_map_id = session.CAMPAIGN_STAGES[index].map_id
		session.block_war_opponent_commander = session.CAMPAIGN_STAGES[index].opponent_commander
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		var game := current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.camera_rig.edge_scroll = false
		game.ai_enabled = false
		game.audio.muted = true
		game.map.set_visual_paused(true)
		var home_point: Vector2 = game.camera.unproject_position(game.buildings[0].global_position + Vector3(0, 2, 0))
		assert(Rect2(140, 130, 1320, 620).has_point(home_point), "The real opening camera must keep the player's first residence clearly on screen.")
		await _capture(output, session.block_war_map_id + "-opening")
		game.camera.size = 76 if index == 0 else 83
		game.camera_rig.zoom_target = game.camera.size
		game.camera_rig.focus_at(Vector3.ZERO, true)
		await _capture(output, session.block_war_map_id + "-gameplay")
		game.get_node("HUD").visible = false
		game.get_node("Orders").visible = false
		await _capture(output, session.block_war_map_id + "-overview")
		if index == 0:
			game.camera.size = 24
			game.camera_rig.zoom_target = 24
			game.camera_rig.focus_at(Vector3(-14, 0, 18), true)
			await _capture(output, "flower_pool-bridge")
			game.camera_rig.focus_at(Vector3(-5, 0, -30), true)
			await _capture(output, "flower_pool-hydrangeas")
		await game.prepare_shutdown()
	session.campaign_active_stage = -1
	session.block_war_map_id = "flower_pool"
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await _capture(output, "campaign-battle-selection")
	print("CAMPAIGN_BATTLE_VISUAL_COMPLETE")
	quit()
