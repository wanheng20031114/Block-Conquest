extends SceneTree
## Run with tools/run_godot_private_desktop.py. No foreground input or audible output.
var output: String

func _initialize() -> void:
	_run.call_deferred()

func capture(label: String) -> void:
	for frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)
	print("CAMPAIGN_CAPTURE ", label)

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var session := root.get_node("Session")
	var settings: GameSettings = session.settings
	session.block_war_commander = &"squirrel"
	change_scene_to_file("res://scenes/block_war/commander_select.tscn")
	await scene_changed
	await capture("01_squirrel")
	var move := InputEventMouseMotion.new()
	move.position = current_scene.get_node("%SkillIcon2").get_global_rect().get_center()
	move.global_position = move.position
	root.push_input(move, true)
	await create_timer(0.8).timeout
	await capture("01_skill_description")
	move.position = Vector2(100, 100)
	move.global_position = move.position
	root.push_input(move, true)
	current_scene.get_node("%Animal1").pressed.emit()
	await capture("02_rabbit")
	root.size = Vector2i(1280, 720)
	await capture("03_rabbit_720")
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await capture("04_map_small")
	current_scene.get_node("%Size2").pressed.emit()
	current_scene.get_node("%Map1").pressed.emit()
	await capture("05_map_large")
	settings.open_menu()
	for page: String in ["Graphics", "Audio", "Controls", "Hotkeys"]:
		settings.menu.show_page(page)
		await capture("06_settings_" + page.to_lower())
		if page == "Graphics":
			var at: Vector2 = settings.menu.get_node("%WindowMode").get_global_rect().get_center()
			for down: bool in [true, false]:
				var event := InputEventMouseButton.new()
				event.position = at
				event.global_position = at
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = down
				root.push_input(event, true)
			await capture("06_settings_dropdown")
			settings.menu.get_node("%WindowMode").get_popup().hide()
	settings.display_timer.start(15.0)
	settings.menu.show_display_confirmation()
	await capture("06_settings_display_confirmation")
	settings.display_timer.stop()
	settings.menu.hide_display_confirmation()
	settings.close_menu()
	session.block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.camera_rig.set_process(false)
	game.set_paused(true)
	await capture("07_pause")
	game.hud._open_help()
	await capture("08_help")
	game.hud._close_help()
	game.hud._open_settings()
	settings.menu.show_page("Audio")
	await capture("09_pause_settings")
	settings.close_menu()
	game.hud.show_result(true)
	await capture("10_victory")
	game.hud.show_result(false)
	await capture("11_defeat")
	root.size = Vector2i(1280, 720)
	game.hud.show_draw()
	await capture("12_draw_720")
	await game.prepare_shutdown()
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	settings.open_menu()
	await capture("13_lobby_settings_unchanged")
	settings.close_menu()
	quit()
