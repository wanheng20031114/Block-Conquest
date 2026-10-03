extends SceneTree
## Real renderer F12 ABBA benchmark. Run on the private desktop with --real-time.
## Wall frame intervals include drawing/pacing; they are not isolated GPU times.

const COORDINATOR := preload("res://scripts/network/war_network_match.gd")
const SOURCES: Array[String] = [
	"res://tests/block_war_debug_frame_benchmark.gd",
	"res://scripts/block_war/block_war.gd",
	"res://scripts/block_war/war_marches.gd",
	"res://scripts/block_war/war_hud.gd",
	"res://scripts/block_war/war_debug_data.gd",
	"res://scripts/block_war/war_debug_panel.gd",
	"res://scripts/block_war/war_debug_metrics.gd",
	"res://scripts/network/war_network_match.gd",
	"res://scripts/network/war_online.gd",
	"res://scenes/block_war/block_war.tscn",
	"res://scenes/block_war/hud.tscn",
	"res://scenes/block_war/debug_panel.tscn",
]

var game: Node3D
var output := ""
var soldiers := 1000
var rounds := 2
var window_seconds := 2.0
var settle_seconds := 0.75
var driving := false
var clock_start_us := 0
var refreshes := 0
var failures: Array[String] = []
var windows: Array[Dictionary] = []
var source_before: Dictionary = {}
var viewport_rid: RID


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if driving:
		var seconds := (Time.get_ticks_usec() - clock_start_us) / 1000000.0
		# Rules stay frozen, but the ordinary HUD and actual DebugRefresh timer
		# still receive changing content and perform native text/layout work.
		game.elapsed = 70.0 + seconds
		game.energy = 60.0 + sin(seconds * 0.8) * 25.0
	return false


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		printerr("FAIL DEBUG_FRAME ", label)


func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES:
		result[path] = FileAccess.get_sha256(path)
	return result


func _wait_wall(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await process_frame


func _populate() -> void:
	game.marches.clear()
	for faction: int in game.faction_count:
		var count := soldiers / int(game.faction_count)
		if faction < soldiers % int(game.faction_count):
			count += 1
		var source: WarBuilding = game.by_id[faction]
		var target: WarBuilding = game.by_id[(faction + 1) % int(game.faction_count)]
		var route: PackedVector3Array = game.map.get_building_route(source, target)
		var begin: int = game.marches._units.size()
		game.marches.send(source.building_id, target.building_id, faction, count, route)
		for index: int in count:
			var unit: WarMarches.MarchUnit = game.marches._units[begin + index]
			unit.distance = unit.order.length * (0.05 + 0.9 * float(index) / maxf(1.0, count - 1.0))
			game.marches._update_pose(unit)
	game.marches._render()
	game.update_hud()
	check(game.marches._units.size() == soldiers, "fixture contains requested unit count")
	check(game.marches._multimesh.visible_instance_count == soldiers, "all fixture soldiers are exposed")


func _summary(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "mean_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in values:
		total += value
	return {"count": values.size(), "mean_ms": total / values.size(),
		"p95_ms": sorted[ceili(values.size() * 0.95) - 1],
		"p99_ms": sorted[ceili(values.size() * 0.99) - 1], "max_ms": sorted.back()}


func _sample(visible: bool, round_index: int, position: int) -> void:
	game.hud.set_debug_visible(visible)
	await _wait_wall(settle_seconds)
	var timer: Timer = game.hud.get_node("%DebugRefresh")
	check(game.hud.debug_visible() == visible and timer.is_stopped() != visible,
		"native panel visibility and refresh timer agree")
	var first_refresh := refreshes
	var first_draw := Engine.get_frames_drawn()
	var started := Time.get_ticks_usec()
	var previous := started
	var frame_ms: Array[float] = []
	var render_cpu_ms: Array[float] = []
	var render_gpu_ms: Array[float] = []
	var setup_cpu_ms: Array[float] = []
	# Godot's TIME_PROCESS publishes process_max once per second. Keep only
	# changes; these are window peak observations, not independent frame samples.
	var process_peak_values_ms: Array[float] = []
	var previous_process_peak := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	while Time.get_ticks_usec() - started < int(window_seconds * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - previous) / 1000.0)
		render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
		render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
		setup_cpu_ms.append(RenderingServer.get_frame_setup_time_cpu())
		var process_peak := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		if process_peak != previous_process_peak:
			process_peak_values_ms.append(process_peak)
			previous_process_peak = process_peak
		previous = now
	var draws := Engine.get_frames_drawn() - first_draw
	var refresh_count := refreshes - first_refresh
	check(draws > 0, "native renderer produced frames during sampled window")
	check(frame_ms.size() >= 20, "sample window contains at least 20 real frames")
	check(refresh_count >= 4 if visible else refresh_count == 0, "only visible panel runs periodic captures")
	check(game.marches._units.size() == soldiers, "paused rules preserve fixture population")
	check(render_cpu_ms.max() > 0.0 and render_gpu_ms.max() > 0.0, "native viewport render timing is active")
	var record := {"round": round_index, "position": position, "debug_visible": visible,
		"seconds": (previous - started) / 1000000.0, "frames_drawn": draws,
		"debug_refreshes": refresh_count, "frame": _summary(frame_ms),
		"render_cpu": _summary(render_cpu_ms), "render_gpu": _summary(render_gpu_ms), "setup_cpu": _summary(setup_cpu_ms),
		"frame_samples_ms": frame_ms, "render_cpu_samples_ms": render_cpu_ms,
		"render_gpu_samples_ms": render_gpu_ms, "setup_cpu_samples_ms": setup_cpu_ms,
		"process_peak_monitor_changes_ms": process_peak_values_ms}
	windows.append(record)
	print("DEBUG_FRAME_WINDOW ", JSON.stringify({"round": round_index, "position": position,
		"open": visible, "frame": record.frame, "render_cpu": record.render_cpu,
		"render_gpu": record.render_gpu, "refreshes": refresh_count}))


func _pooled(visible: bool) -> Dictionary:
	var frames: Array[float] = []
	var render_cpus: Array[float] = []
	var render_gpus: Array[float] = []
	var setup_cpus: Array[float] = []
	var frame_means: Array[float] = []
	var render_cpu_means: Array[float] = []
	var render_gpu_means: Array[float] = []
	for record: Dictionary in windows:
		if record.debug_visible == visible:
			frames.append_array(record.frame_samples_ms)
			render_cpus.append_array(record.render_cpu_samples_ms)
			render_gpus.append_array(record.render_gpu_samples_ms)
			setup_cpus.append_array(record.setup_cpu_samples_ms)
			frame_means.append(record.frame.mean_ms)
			render_cpu_means.append(record.render_cpu.mean_ms)
			render_gpu_means.append(record.render_gpu.mean_ms)
	return {"frame": _summary(frames), "render_cpu": _summary(render_cpus),
		"render_gpu": _summary(render_gpus), "setup_cpu": _summary(setup_cpus),
		"window_frame_means_ms": frame_means, "window_render_cpu_means_ms": render_cpu_means,
		"window_render_gpu_means_ms": render_gpu_means}


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	for argument: String in args:
		if argument.begins_with("--soldiers="): soldiers = int(argument.trim_prefix("--soldiers="))
		elif argument.begins_with("--rounds="): rounds = int(argument.trim_prefix("--rounds="))
		elif argument.begins_with("--window="): window_seconds = float(argument.trim_prefix("--window="))
	if DisplayServer.get_name() == "headless" or output.is_empty() or soldiers < 6 or rounds < 1 or window_seconds < 1.0:
		printerr("DEBUG_FRAME needs a renderer, output directory, >=6 soldiers, >=1 round and >=1 second windows")
		quit(2)
		return
	output = ProjectSettings.globalize_path(output)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("DEBUG_FRAME output directory unavailable")
		quit(2)
		return
	create_timer(90.0, true, false, true).timeout.connect(func():
		printerr("DEBUG_FRAME deadline")
		quit(3))
	source_before = _source_hashes()
	seed(20261003)
	var settings: GameSettings = root.get_node("Session/Settings")
	var original := settings.snapshot()
	var preferences := settings.defaults()
	preferences.music_enabled = false
	preferences.muted = true
	preferences.vsync = false
	preferences.fps_limit = 0
	settings._apply_values(preferences, false)
	root.size = Vector2i(1600, 900)
	root.get_node("Session").block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.ai_enabled = false
	game.audio.muted = true
	game.simulation_paused = true
	game.camera_rig.set_process(false)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, root.get_window_id())
	viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	check(game.is_processing() and game.is_rule_paused(), "battle presentation stays active while rules are paused")
	check(game.faction_count == 6 and game.network_match == null, "native offline highland fixture")
	_populate()
	# An unstarted real coordinator supplies the full network diagnostics text.
	# Do not call setup(): this rendering fixture opens no socket, connects no
	# network signals and never starts replication or authoritative simulation.
	var coordinator := COORDINATOR.new()
	coordinator.game = game
	coordinator.online = root.get_node("Session/Online")
	game.network_match = coordinator
	var slots: Array[Dictionary] = []
	for faction: int in game.faction_count:
		slots.append({"faction_id": faction, "team_id": faction % 2,
			"name": "诊断基准%d" % faction, "controller": "human"})
	game.match_config = {"slots": slots}
	game.select_building(game.by_id[game.local_faction])
	check(coordinator.online.connection_state == "disconnected", "diagnostics fixture has no transport connection")
	game.hud.debug_refresh_requested.connect(func(): refreshes += 1)
	clock_start_us = Time.get_ticks_usec()
	driving = true
	# Warm both the world and the panel's glyphs/pipelines before either condition.
	game.hud.set_debug_visible(true)
	await _wait_wall(3.0)
	for frame: int in 8:
		await process_frame
	var performance_text: String = game.hud.get_node("%DebugPanel").get_node("%PerformanceValue").text
	check((performance_text.contains("经中继到房主 RTT") or performance_text.contains("本机为房主")) and performance_text.contains("同步队列")
		and performance_text.contains("客机呈现"), "native timer renders complete network and CPU diagnostic rows")
	print("DEBUG_FRAME_WARM_TEXT ", JSON.stringify(performance_text))
	for round_index: int in rounds:
		var order: Array[bool] = [false, true, true, false]
		for position: int in order.size():
			await _sample(order[position], round_index, position)
	driving = false
	check(Engine.max_fps == 0, "frame limit is disabled")
	check(DisplayServer.window_get_vsync_mode(root.get_window_id()) == DisplayServer.VSYNC_DISABLED, "VSync is disabled")
	check(source_before == _source_hashes(), "benchmark source files stayed unchanged during measurement")
	check(not coordinator._started and coordinator.online.connection_state == "disconnected",
		"network fixture stayed unstarted and disconnected throughout measurement")
	var closed := _pooled(false)
	var opened := _pooled(true)
	var comparison := {"frame_mean_delta_ms": opened.frame.mean_ms - closed.frame.mean_ms,
		"render_cpu_mean_delta_ms": opened.render_cpu.mean_ms - closed.render_cpu.mean_ms,
		"render_gpu_mean_delta_ms": opened.render_gpu.mean_ms - closed.render_gpu.mean_ms,
		"setup_cpu_mean_delta_ms": opened.setup_cpu.mean_ms - closed.setup_cpu.mean_ms}
	var report := {"engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(),
		"window_size": [root.size.x, root.size.y], "render_scale": root.scaling_3d_scale,
		"soldiers": soldiers, "rounds": rounds, "window_seconds": window_seconds, "settle_seconds": settle_seconds,
		"max_fps": Engine.max_fps, "vsync": DisplayServer.window_get_vsync_mode(root.get_window_id()),
		"source_sha256": source_before, "closed": closed, "open": opened,
		"comparison": comparison, "windows": windows, "failures": failures,
		"warm_performance_text": performance_text,
		"scope": "Paused rules, active native HUD/presentation and changing elapsed/energy; unstarted real network coordinator shows complete disconnected diagnostics without opening sockets; ABBA closed/open; wall intervals include private desktop pacing. Native viewport CPU/GPU measurements are milliseconds for rendering only, excluding scripts and other engine subsystems. TIME_PROCESS changes are engine-published approximately one-second maxima, not per-frame CPU samples."}
	var file := FileAccess.open(output.path_join("debug_frame_benchmark.json"), FileAccess.WRITE)
	check(file != null, "benchmark result can be written")
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	game.hud.set_debug_visible(false)
	game.network_match = null
	await game.prepare_shutdown()
	settings._apply_values(original, false)
	print("DEBUG_FRAME_RESULTS ", JSON.stringify({"closed": closed, "open": opened, "comparison": comparison, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
