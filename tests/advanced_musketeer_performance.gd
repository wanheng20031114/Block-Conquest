extends SceneTree
## Short, fixed-camera 500-unit presentation comparison, not a full battle benchmark.
const OUT := "res://.local/advanced-units/performance.json"
var families := PackedStringArray(["musketeer"])
var game: Node3D
var phases: Array[Dictionary] = []
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()
func summary(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"p50": samples[samples.size()/2], "p95": samples[floori(samples.size()*.95)]}
func measure(advanced: bool, label: String) -> void:
	game.set_running(false)
	game.clear_units()
	await physics_frame
	await physics_frame
	for index: int in 500:
		var at := Vector3((index%25-12)*1.7,0,(index/25-10)*1.7)
		var kind := families[index % families.size()]
		if advanced: game.spawn_variant(kind,0,at)
		else: game.spawn_unit(kind,0,at)
	game.set_running(true)
	await create_timer(1.5).timeout
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec() - began < 3000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now-previous)/1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		previous = now
	var batches: UnitRenderBatches = game.get_node("VariantRenderBatches" if advanced else "UnitRenderBatches")
	assert(game.sandbox_unit_count == 500 and batches.registered_models == 500)
	var phase := {"label":label,"frames":frames.size(),"wall_ms":summary(frames),"gpu_ms":summary(gpu),"models":batches.registered_models,"visible_models":batches.visible_models,"submitted_parts":batches.submitted_parts,"batch_nodes":batches.get_child_count(),"draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	phases.append(phase)
	print("ADVANCED_PERFORMANCE ",JSON.stringify(phase))
func _run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():quit(3))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): families = args
	for kind: String in families: assert(UnitVariantCatalog.ADVANCED.has(kind))
	assert(DisplayServer.get_name() != "headless")
	root.size = Vector2i(1600,900)
	AudioServer.set_bus_mute(0,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	game.camera_rig.set_process(false)
	game.camera_rig.position = Vector3.ZERO
	game.camera.position = Vector3(0,50,35)
	game.camera.look_at(Vector3.ZERO,Vector3.UP)
	game.camera.size = 68
	game.hud.hide()
	await measure(false,"normal_before")
	await measure(true,"advanced")
	await measure(false,"normal_after")
	game.clear_units()
	await physics_frame
	await physics_frame
	assert(game.get_node("VariantRenderBatches").registered_models == 0)
	var output := OUT if args.is_empty() else "res://.local/advanced-units/performance-" + "-".join(families) + ".json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"families":families,"phases":phases,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"limitations":"Single short idle-army presentation comparison in the modified sandbox. Not a before/after code baseline, active-combat benchmark, or statistical guarantee."},"\t"))
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit()
