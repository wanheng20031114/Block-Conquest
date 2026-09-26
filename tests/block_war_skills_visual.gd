extends SceneTree
## Native GPU captures; run only through tools/run_godot_private_desktop.py.

var game: Node3D
var output: String
const FPS := 24.0
const CENTER := Vector3(-22, 0, 10)

func _initialize() -> void:
	_run.call_deferred()

func reset_game(at: Vector3, zoom: float = 22.0) -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.ai_enabled = false
	game.audio.muted = true
	game.select_building(null)
	game.hud.hide()
	game.camera_rig.focus_at(at, true)
	game.camera.size = zoom
	await physics_frame
	await RenderingServer.frame_post_draw

func frame() -> void:
	game.simulate(1.0 / FPS)
	game.overlay.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func clip(label: String, count: int) -> void:
	for index: int in count:
		await frame()
		await capture("%s_%03d" % [label, index])

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(960, 540)
	root.get_node("Session").block_war_map_id = "rift"
	await reset_game(Vector3(-24, 0, -5), 18.0)
	game.cast_skill(0, game.by_id[0])
	await clip("recruit", 72)
	await reset_game(Vector3(-24, 0, -5), 18.0)
	game.cast_skill(2, game.by_id[0])
	await clip("shield", 72)
	await reset_game(CENTER + Vector3(4, 0, 0), 22.0)
	game.marches.send(900, 1, 0, 96, PackedVector3Array([CENTER + Vector3(-8, 0, 0), CENTER + Vector3(35, 0, 0)]))
	game.marches.tick(1.0)
	game.cast_skill(1, null)
	await clip("haste", 72)
	await reset_game(CENTER, 18.0)
	game.marches.send(900, 1, 0, 72, PackedVector3Array([CENTER + Vector3(-7, 0, 0.6), CENTER + Vector3(30, 0, 0.6)]))
	game.marches.send(901, 0, 1, 72, PackedVector3Array([CENTER + Vector3(7, 0, -0.6), CENTER + Vector3(-30, 0, -0.6)]))
	game.marches.tick(1.0)
	game.cast_ground_skill(3, CENTER)
	await clip("fire", 96)
	await game.prepare_shutdown()
	print("BLOCK_WAR_SKILLS_VISUAL native_frames=312 output=", output)
	quit()
