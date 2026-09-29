extends SceneTree
## Run only on the private desktop with Dummy audio. Input stays in this viewport.
var game: Node3D
var output: String
var pointer := Vector2(16, 350)

func _initialize() -> void:
	_run.call_deferred()

func _physics_process(_delta: float) -> bool:
	var event := InputEventMouseMotion.new()
	event.position = pointer; event.global_position = pointer
	root.push_input(event, true)
	return false

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func fresh() -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false); game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false; game.camera_rig.keyboard_pan = false
	game.ai_enabled = false; game.audio.muted = true
	game.energy = 100
	for building: WarBuilding in game.buildings:
		building.population = 60; building.kind = 0; building.refresh_visual()
	game.select_building(null)
	await create_timer(0.2).timeout

func clip(label: String, frames: int = 42) -> void:
	for frame: int in frames:
		game.simulate(1.0 / 24.0)
		game.overlay.queue_redraw()
		game.update_hud()
		await process_frame
		await capture("%s_%03d" % [label, frame])

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var session := root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"fox"; session.block_war_opponent_commander = &"fox"
	change_scene_to_file("res://scenes/block_war/commander_select.tscn")
	await scene_changed
	await create_timer(0.55).timeout
	await capture("selection_1600")
	root.size = Vector2i(1280, 720)
	await create_timer(0.25).timeout
	await capture("selection_1280")
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await create_timer(0.4).timeout
	await capture("map_1280")
	if OS.get_cmdline_user_args().has("--menus-only"):
		change_scene_to_file("res://scenes/codex/codex.tscn")
		await scene_changed
		current_scene.commander = &"fox"
		current_scene._show_hero()
		current_scene._select_skill(2, false)
		await create_timer(0.4).timeout
		await capture("fox_codex")
		print("FOX_MENU_VISUAL_COMPLETE")
		quit()
		return
	await fresh()
	for index: int in 4:
		if index > 0: await fresh()
		var target: WarBuilding = game.by_id[1]
		target.faction = 1; target.level = 3; target.population = 60; target.refresh_visual()
		game.camera.size = 24
		game.camera_rig.global_position = Vector3(target.global_position.x, 0, target.global_position.z)
		game.hud.hide()
		if index == 1:
			game.morale.adjust(1, 1500)
		elif index == 2:
			var center := Vector3(-20, 0, 3)
			game.camera.size = 24
			game.camera_rig.global_position = center
			game.marches.send(1, 0, 1, 30, PackedVector3Array([center + Vector3(-6, 0, 0), center + Vector3(24, 0, 0)]))
			game.marches.tick(1.4)
			await capture("E_before")
			assert(game.cast_ground_skill(2, center))
			await clip("E")
			continue
		elif index == 3:
			game.by_id[5].faction = 1
			game.by_id[7].faction = 1
		await capture("%s_before" % ["Q", "W", "E", "R"][index])
		assert(game.cast_skill(index, target))
		await clip(["Q", "W", "E", "R"][index], 84 if index == 3 else (48 if index == 1 else 32))
	await fresh()
	game.update_hud()
	await capture("hud")
	for index: int in 4:
		pointer = game.hud.get_node("UI/Skills/Row/Skill%d" % index).get_global_rect().get_center()
		await create_timer(0.7).timeout
		await capture("tooltip_%d" % index)
	await game.prepare_shutdown()
	print("FOX_VISUAL_COMPLETE")
	quit()
