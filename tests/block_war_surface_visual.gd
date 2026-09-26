extends SceneTree
## Reproducible surface review: animation/pause, native SSR and frame cost.
## Godot_console.exe --path . --audio-driver Dummy --script tests/block_war_surface_visual.gd

const OUTPUT := "res://artifacts/map_style/"
var game: Node3D

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-20000, -20000))
	_run.call_deferred()

func frames(count: int) -> void:
	for frame: int in count:
		await process_frame

func capture(label: String) -> Image:
	await frames(24)
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	assert(result.save_png(OUTPUT + label + ".png") == OK)
	print("SURFACE_CAPTURE ", label)
	return result

func cost(label: String) -> void:
	await frames(45)
	var samples: Array[float] = []
	var gpu_samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame: int in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		previous = now
	samples.sort()
	gpu_samples.sort()
	print("SURFACE_FRAME_MS ", label, " median=", samples[60], " p95=", samples[114])
	print("SURFACE_GPU_MS ", label, " median=", gpu_samples[60], " p95=", gpu_samples[114])

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1600, 900)
	root.gui_disable_input = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	for map_id: String in ["lake", "rift", "islands", "highland"]:
		session.block_war_map_id = map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		game = current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.ai_enabled = false
		game.audio.muted = true
		game.get_node("HUD").hide()
		game.get_node("Orders").hide()
		game.camera.size = 30.0
		game.camera_rig.zoom_target = 30.0
		var focus := Vector3.ZERO
		if map_id == "rift":
			focus = Vector3(-12, 0, -10)
		elif map_id == "islands":
			focus = Vector3(-18, 0, -21)
		game.camera_rig.focus_at(focus, true)
		game.map.set_visual_paused(true)
		game.map._flow_time = 7.0
		for material: ShaderMaterial in game.map._water_materials:
			material.set_shader_parameter("flow_time", 7.0)
		await frames(60)
		await capture(map_id + "_detail")
		if map_id == "lake":
			var environment: Environment = game.get_node("WorldEnvironment").environment
			await cost("SSR_ON")
			environment.ssr_enabled = false
			await capture("lake_without_ssr")
			await cost("SSR_OFF")
			environment.ssr_enabled = true
			game.map.set_visual_paused(false)
			await frames(90)
			await capture("lake_flow")
			assert(game.map._flow_time > 7.0, "Unpaused water must animate")
			game.map.set_visual_paused(true)
			var first := await capture("lake_paused")
			await frames(36)
			var second := await capture("lake_paused_later")
			# TAA may converge for a few pixels; uniform time must remain exact.
			var stopped_at: float = game.map._flow_time
			await frames(36)
			assert(game.map._flow_time == stopped_at, "Paused water must not advance")
			print("SURFACE_PAUSE_OK images=", first.get_size(), "/", second.get_size())
		if map_id == "highland":
			var environment: Environment = game.get_node("WorldEnvironment").environment
			environment.ssr_enabled = false
			await capture("highland_without_ssr")
			environment.ssr_enabled = true
		await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	quit()
