extends "res://tests/block_war_rabbit_visual.gd"
## Exact release frames and normal-speed motion on the isolated native renderer.

func release_clip(label: String, frames: int) -> void:
	await capture(label + "_000")
	for index: int in range(1, frames + 1):
		game.simulate(1.0 / FPS)
		await process_frame
		await capture("%s_%03d" % [label, index])

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var session: Node = root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"squirrel"
	session.block_war_opponent_commander = &"squirrel"
	await reset_game()
	var button: Button = game.hud.get_node("UI/Skills/Row/Skill2")
	var event := InputEventMouseMotion.new()
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	root.push_input(event, true)
	await create_timer(0.8).timeout
	await capture("shield_hint")
	game.hud.hide()
	var home: WarBuilding = game.buildings[0]
	game.camera_rig.focus_at(home.global_position + Vector3.UP, true)
	game.camera.size = 15.0
	assert(game.cast_skill(2, home))
	await release_clip("shield", 72)
	home.level = 4
	home.refresh_visual()
	await capture("shield_level4")
	await reset_game()
	game.hud.hide()
	var center := Vector3(-22, 0, 10)
	game.camera_rig.focus_at(center, true)
	game.camera.size = 16.0
	game.marches.send(0, 1, 0, 24, PackedVector3Array([center + Vector3(-3, 0, 0), center + Vector3(30, 0, 0)]))
	game.marches.send(1, 0, 1, 24, PackedVector3Array([center + Vector3(2, 0, 1), center + Vector3(-30, 0, 1)]))
	game.marches.tick(0.35)
	assert(game.cast_ground_skill(3, center))
	await release_clip("fire", 72)
	session.block_war_commander = &"rabbit"
	await reset_game()
	game.hud.hide()
	home = game.buildings[0]
	home.population = 60.0
	var plan := {}
	for building: WarBuilding in game.buildings:
		plan = game.RABBIT_SKILLS.burrow_plan(game, building, 0)
		if not plan.is_empty():
			break
	assert(not plan.is_empty())
	game.camera_rig.focus_at((plan.entrance + plan.exit) * 0.5, true)
	game.camera.size = 23.0
	assert(game.cast_skill(3, plan.target))
	await release_clip("burrow", 48)
	await reset_game()
	game.hud.hide()
	var target: WarBuilding = game.buildings[1]
	game.camera_rig.focus_at(target.global_position, true)
	game.camera.size = 13.0
	assert(game.cast_skill(1, target))
	await release_clip("seal", 6)
	await reset_game()
	game.hud.hide()
	home = game.buildings[0]
	var route: PackedVector3Array = game.map.get_building_route(home, game.buildings[2])
	game.camera_rig.focus_at(home.global_position, true)
	game.camera.size = 14.0
	game.marches.send(0, game.buildings[2].building_id, 0, 24, route)
	game.marches.tick(0.3)
	assert(game.cast_skill(2, home))
	await release_clip("recall", 6)
	await game.prepare_shutdown()
	print("BLOCK_WAR_RESPONSIVENESS_VISUAL completed output=", output)
	quit()
