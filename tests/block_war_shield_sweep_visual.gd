extends "res://tests/block_war_rabbit_visual.gd"
## Capture the real shield at fixed simulation times on the private desktop.

func shield_clip(label: String, kind: int, level: int, frames: int) -> void:
	await reset_game()
	game.hud.hide()
	game.energy = 100.0
	var building: WarBuilding = game.buildings[0]
	building.kind = kind
	building.level = level
	building.population = 60.0
	building.refresh_visual()
	game.camera_rig.focus_at(building.global_position + Vector3.UP * 0.9, true)
	game.camera.size = 12.2
	await process_frame
	await capture(label + "_before")
	assert(game.cast_skill(2, building))
	await capture(label + "_000")
	for frame: int in range(1, frames + 1):
		game.simulate(1.0 / FPS)
		await process_frame
		await capture("%s_%03d" % [label, frame])

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(960, 640)
	root.gui_embed_subwindows = true
	var session: Node = root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"squirrel"
	session.block_war_opponent_commander = &"squirrel"
	await shield_clip("house", 0, 1, 72)
	await shield_clip("house4", 0, 4, 24)
	await shield_clip("tower", 1, 3, 24)
	await game.prepare_shutdown()
	print("BLOCK_WAR_SHIELD_SWEEP_VISUAL completed output=", output)
	quit()
