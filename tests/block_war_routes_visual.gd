extends SceneTree
## Native corridor/flow comparison. Pass -- --video to capture 24 FPS movie frames.

var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _capture(name: String) -> void:
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://artifacts/block_war_route_" + name + ".png") == OK)

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(3))
	root.size = Vector2i(1280, 720)
	root.gui_disable_input = true
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.map.set_visual_paused(true)
	for building: WarBuilding in game.buildings:
		building.set_visual_paused(true)
	game.hud.get_node("%Toast").hide()
	game.camera_rig.focus_at(Vector3(-16, 0, -9), true)
	game.camera.size = 30.0
	var source: WarBuilding = game.by_id[0]
	var target: WarBuilding = game.by_id[10]
	var motion := InputEventMouseMotion.new()
	motion.position = game.camera.unproject_position(target.global_position)
	motion.global_position = motion.position
	root.push_input(motion, true)
	for variant: String in ["corridor", "flow"]:
		game.marches.clear()
		var route: PackedVector3Array = game.map._compute_building_route(source, target) if variant == "corridor" else game.map.get_building_route(source, target)
		game.marches.send(0, 10, 0, 180, route)
		game.marches.tick(7.0)
		game.drag_source = source
		game.hovered = target
		game._drag_start = Vector2(-1000, -1000)
		game.order_route = route
		game.overlay.queue_redraw()
		await _capture(variant)
	if OS.get_cmdline_user_args().has("--video"):
		DirAccess.make_dir_recursive_absolute("res://artifacts/route_flow_frames")
		game.marches.clear()
		game.marches.send(0, 10, 0, 180, game.order_route)
		game.marches.tick(4.0)
		for frame: int in 144:
			game.marches.tick(1.0 / 24.0)
			await process_frame
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png("res://artifacts/route_flow_frames/%04d.png" % frame) == OK)
	print("BLOCK_WAR_ROUTES_VISUAL corridor and shaped guide captured with 180 actual marchers")
	await game.prepare_shutdown()
	quit()
