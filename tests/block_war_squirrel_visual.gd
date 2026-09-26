extends SceneTree
## Native viewport only. Launch via run_godot_private_desktop.py, never foreground.

var game: Node3D
var output: String

func _initialize() -> void:
	_run.call_deferred()

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func hover(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await create_timer(0.85).timeout

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	root.get_node("Session").block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.ai_enabled = false
	game.audio.muted = true
	game.select_building(null)
	await create_timer(0.9).timeout
	await capture("squirrel_default")
	for index: int in 4:
		var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % index)
		await hover(button.get_global_rect().get_center())
		await capture("squirrel_hint_%d" % index)
	await hover(Vector2(640, 120))
	var center := Vector3(-22, 0, 10)
	game.camera_rig.focus_at(center, true)
	game.camera.size = 23.0
	await process_frame
	var at: Vector2 = game.camera.unproject_position(center)
	game.request_skill(1)
	game._update_skill_drag(at)
	game.overlay.queue_redraw()
	await capture("squirrel_haste_aim")
	game.release_skill_drag(at)
	game.marches.send(900, 1, 0, 42, PackedVector3Array([center + Vector3(-7, 0, 0), center + Vector3(28, 0, 0)]))
	game.marches.send(901, 0, 1, 42, PackedVector3Array([center + Vector3(-7, 0, -6), center + Vector3(28, 0, -6)]))
	for frame: int in 72:
		game.simulate(1.0 / 24.0)
		game.update_hud()
		await process_frame
		if frame in [12, 36, 60]:
			await capture("squirrel_haste_%d" % frame)
	await game.prepare_shutdown()
	print("BLOCK_WAR_SQUIRREL_VISUAL completed")
	quit()
