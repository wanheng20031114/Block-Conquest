extends SceneTree
## Rendered performance sample; reports measurements without hardware assumptions.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	var game: Node3D = current_scene
	game.ai_enabled = false
	game.camera_rig.edge_scroll = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for pair: Vector2i in [Vector2i(0, 10), Vector2i(3, 11), Vector2i(1, 10), Vector2i(5, 11)]:
		var source: Node3D = game.by_id[pair.x]
		source.faction = 0 if pair.x in [0, 3] else 1
		source.population = 360.0
		game.issue_order(source, game.by_id[pair.y], 100, source.faction)
	await create_timer(3.0).timeout
	var samples: Array[float] = []
	var peak_visible: int = 0
	var last_time: int = Time.get_ticks_usec()
	var end_time: int = last_time + 8_000_000
	while Time.get_ticks_usec() < end_time:
		await process_frame
		var now: int = Time.get_ticks_usec()
		samples.append(float(now - last_time) / 1000.0)
		last_time = now
		peak_visible = maxi(peak_visible, game.marches.get_node("Militia").multimesh.visible_instance_count)
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	samples.sort()
	print("BLOCK_WAR_RENDER_PERFORMANCE ", JSON.stringify({"frames": samples.size(), "mean_ms": total / samples.size(), "p95_ms": samples[floori(samples.size() * 0.95)], "peak_visible_militia": peak_visible, "resolution": root.size, "gpu": RenderingServer.get_video_adapter_name()}))
	quit()
