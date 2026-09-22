extends SceneTree
## Reproducible native-render captures of opening, bridge traffic and militia.

var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func capture(name: String) -> void:
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/block_war_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("BLOCK_WAR_CAPTURE ", path)

func run() -> void:
	create_timer(75.0, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.ai_enabled = false
	game.camera_rig.edge_scroll = false
	game.set_process(false)
	game.audio.muted = true
	await create_timer(0.8).timeout
	await capture("opening")
	for id: int in [0, 2, 3, 6, 8]:
		game.by_id[id].faction = 0
		game.by_id[id].population = 200
		game.by_id[id].refresh_visual()
	for id: int in [1, 4, 5, 7, 9]:
		game.by_id[id].faction = 1
		game.by_id[id].population = 200
		game.by_id[id].refresh_visual()
	game.issue_order(game.by_id[0], game.by_id[10], 75, 0)
	game.issue_order(game.by_id[3], game.by_id[11], 75, 0)
	game.issue_order(game.by_id[1], game.by_id[10], 75, 1)
	game.issue_order(game.by_id[5], game.by_id[11], 75, 1)
	for step: int in 400:
		game.simulate(0.02)
	game.update_hud()
	game.overlay.queue_redraw()
	await capture("marches")
	game.camera_rig.zoom_target = 37.0
	game.camera.size = 37.0
	game.camera_rig.focus_at(Vector3(-12, 0, 14), true)
	await capture("bridge_detail")
	game.camera_rig.zoom_target = 58.0
	game.camera.size = 58.0
	game.camera_rig.focus_at(Vector3(0, 0, 2), true)
	game.hud._open_help()
	await capture("help")
	quit()
