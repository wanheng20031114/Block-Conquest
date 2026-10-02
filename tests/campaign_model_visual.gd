extends SceneTree
## Render the native unfolding intro, model details and six-stop motion.
## Run with tools/run_godot_private_desktop.py; output path is its first argument.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	root.get_node("Session").set_meta("campaign_selected_stage", 0)
	change_scene_to_file("res://scenes/campaign/campaign_map.tscn")
	await scene_changed
	var output := OS.get_cmdline_user_args()[0]
	var motion := OS.get_cmdline_user_args().has("--motion")
	if motion:
		DirAccess.make_dir_recursive_absolute(output.path_join("intro"))
		for frame: int in 90:
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("intro/frame-%04d.png" % frame))
	elif current_scene.diorama.intro_running:
		await current_scene.diorama.intro_finished
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("route-map.png"))
	var diorama: SubViewportContainer = current_scene.diorama
	var camera: Camera3D = diorama.camera
	var rig: Node3D = camera.get_parent()
	var viewport: SubViewport = diorama.get_node("World")
	viewport.get_texture().get_image().save_png(output.path_join("landscape.png"))
	if motion:
		root.size = Vector2i(1280, 720)
		DirAccess.make_dir_recursive_absolute(output.path_join("motion"))
		for frame: int in 168:
			if frame in [24, 48, 72, 96, 120]:
				current_scene._select(frame / 24)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("motion/frame-%04d.png" % frame))
	for shot: Dictionary in [
		{"name": "woodland", "at": Vector3(-17, 1.3, 0), "size": 11.0},
		{"name": "bridge", "at": Vector3(0, 1, 0), "size": 10.0},
		{"name": "summit", "at": Vector3(18, 2, -1), "size": 12.0},
	]:
		rig.position = shot.at
		camera.size = shot.size
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join(shot.name + ".png"))
		if shot.name == "woodland" and OS.get_cmdline_user_args().has("--lighting-check"):
			var sun: DirectionalLight3D = diorama.get_node("World/Stage/Sun")
			var environment: Environment = diorama.get_node("World/Stage/Environment").environment
			for disabled: String in ["shadow", "ssao", "ssil"]:
				sun.shadow_enabled = disabled != "shadow"
				environment.ssao_enabled = disabled != "ssao"
				environment.ssil_enabled = disabled != "ssil"
				await create_timer(0.3).timeout
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png(output.path_join("woodland-no-" + disabled + ".png"))
			sun.shadow_enabled = true
			environment.ssao_enabled = true
			environment.ssil_enabled = true
	print("CAMPAIGN_MODEL_VISUAL_COMPLETE")
	quit()
