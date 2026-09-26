extends "res://tests/block_war_rabbit_visual.gd"
## Render the in-game attribution footer without activating a user desktop.

func _run() -> void:
	create_timer(35.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	root.get_node("Session").block_war_map_id = "rift"
	await reset_game()
	game.hud._open_help()
	await create_timer(.3).timeout
	await capture("audio_credits")
	await game.prepare_shutdown()
	root.get_node("Session/UIFeedback").stop_all()
	print("BLOCK_WAR_AUDIO_CREDITS_VISUAL completed")
	quit()
