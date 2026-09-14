extends SceneTree
## Visible native scene capture; closes the battle and process after one image.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func(): quit(3))
	var session: Node = root.get_node("Session")
	session.rogue.state = RogueRunState.new()
	session.rogue.state.start_new("ranged", "steady", 24681)
	session.rogue.state.data.phase = "battle"
	session.rogue.state.data.battle_kind = "siege" if "--siege" in OS.get_cmdline_user_args() else "outpost"
	change_scene_to_file("res://scenes/rogue/battle.tscn")
	await scene_changed
	var game: Node3D = current_scene
	while not game._match_ready:
		await process_frame
	game.camera_rig.edge_scroll = false
	if "--play" in OS.get_cmdline_user_args():
		game.skip_intro()
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://artifacts/rogue_battle_%s_%s.png" % [game.battle_kind, "play" if "--play" in OS.get_cmdline_user_args() else "intro"])
	await game.prepare_shutdown()
	quit()
