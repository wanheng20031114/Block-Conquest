extends SceneTree
## GPU screenshots of actual reference geometry and interactive campaign UI.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(55.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	root.get_node("Session").set_meta("campaign_selected_stage", 0)
	change_scene_to_file("res://scenes/campaign/campaign_map.tscn")
	await scene_changed
	var output := OS.get_cmdline_user_args()[0]
	var diorama: SubViewportContainer = current_scene.diorama
	if diorama.intro_running:
		await diorama.intro_finished
	await _capture(output, "route-map")
	var viewport: SubViewport = diorama.get_node("World")
	viewport.get_texture().get_image().save_png(output.path_join("meadow.png"))
	for shot: Dictionary in [
		{"name": "village", "at": Vector3(18, 10, 22), "distance": 68.0},
		{"name": "castle", "at": Vector3(-7, 13, 6), "distance": 48.0},
		{"name": "river", "at": Vector3(63, 10, 20), "distance": 70.0},
		{"name": "foothill", "at": Vector3(83, 13, 23), "distance": 65.0},
		{"name": "summit", "at": Vector3(108, 19, 18), "distance": 78.0},
	]:
		diorama._set_view(shot.at, shot.distance, false)
		await _capture(output, shot.name + "-ui")
		viewport.get_texture().get_image().save_png(output.path_join(shot.name + ".png"))
	diorama.show_overview(false)
	await _capture(output, "overview-ui")
	viewport.get_texture().get_image().save_png(output.path_join("overview.png"))
	root.size = Vector2i(1280, 720)
	diorama.focus_station(1, false)
	await _capture(output, "village-1280")
	print("CAMPAIGN_MODEL_VISUAL_COMPLETE")
	quit()

func _capture(output: String, name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
