class_name SandboxMovementPerformance
extends SceneTree
## Real sandbox scene, native orders and rendered wall-clock sampling.
const PROBE := preload("res://tests/skirmish_profile_probe.tscn")
const ROSTER := {"shield_guard": 80, "musketeer": 80, "swordsman": 20, "spearman": 20}
var game: Node3D
var probe: Node
var run_id := "baseline"
var output := ""
var profiled := false
var natural_health := false
var short_check := false
var map_mode := "1v1"
var seconds := 20.0
var phases: Array[Dictionary] = []
var failures: Array[String] = []
var checks := 0
var damage_events := 0
var damage_amount := 0.0
var done := false
var quality: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--run-id="): run_id = argument.trim_prefix("--run-id=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--seconds="): seconds = argument.trim_prefix("--seconds=").to_float()
		if argument.begins_with("--map="): map_mode = argument.trim_prefix("--map=")
	profiled = ProjectSettings.get_setting("movement_probe/profiled", false)
	natural_health = "--natural-health" in OS.get_cmdline_user_args()
	short_check = "--harness-check" in OS.get_cmdline_user_args()
	_check(not output.is_empty(), "explicit evidence output directory")
	_check(DisplayServer.get_name() != "headless" or short_check, "rendered performance measurements")
	if not failures.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(160.0, true, false, true).timeout.connect(_watchdog)
	seed(1509400)
	root.get_node("Session").online = false
	root.get_node("Session").config = {"mode": map_mode}
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready or not game.get_node("ConstructionNavigation").paths_ready():
		await process_frame
	await physics_frame
	await physics_frame
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	game.tests_running = true
	game.set_placing(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.focus_at(Vector3.ZERO, true)
	game.camera_rig.zoom_target = 65.0
	game.camera.size = 65.0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	probe = PROBE.instantiate()
	game.add_child(probe)
	quality = {"msaa": root.msaa_3d, "taa": root.use_taa, "scale": root.scaling_3d_scale,
		"tps": Engine.physics_ticks_per_second, "max_physics_steps": Engine.max_physics_steps_per_frame,
		"batching": game.unit_batches_enabled, "path_map_cache": game.get_node("PathBudget").cache_map_iterations,
		"static_motion": game.get_node("StaticMotionGrid").fast_path_enabled,
		"user_data_dir": OS.get_user_data_dir()}
	_check(Engine.physics_ticks_per_second == 30, "unchanged thirty-tick simulation")
	await _populate()
	if not failures.is_empty():
		await _finish()
		return
	await create_timer(1.0 if short_check else 4.0).timeout
	game.set_running(true)
	for owner: int in 2:
		var army: Array = game.owned_entities(owner, "units")
		var command := {"kind": "move", "units": army.map(func(unit: BattleUnit): return unit.entity_id),
			"seq": game.next_command_sequence(owner), "at": game.vector_data(Vector3(5.0 if owner == 0 else -5.0, 0, 0)), "attack_move": true}
		var response: Dictionary = game.submit_command(command, owner)
		_check(response.ok, "native attack-move command accepted")
	await _measure("opening", 2.0 if short_check else 8.0)
	await _measure("sustained", 2.0 if short_check else seconds)
	game.camera_rig.zoom_target = 38.0
	game.camera.size = 38.0
	await _measure("close", 2.0 if short_check else 12.0)
	await _finish()

func _populate() -> void:
	var occupied: Array[Dictionary] = []
	for owner: int in 2:
		var roster: Array[String] = []
		for kind: String in ROSTER:
			for _index: int in int(ROSTER[kind]): roster.append(kind)
		roster.shuffle()
		for index: int in roster.size():
			var kind: String = roster[index]
			var desired := Vector3((-1.0 if owner == 0 else 1.0) * (8.0 + floori(index / 16.0) * 1.7), 0, (index % 16 - 7.5) * 1.7)
			var radius: float = BalanceCatalog.unit(kind).radius
			var at := _find_position(desired, radius, occupied)
			if not at.is_finite():
				_check(false, "fixture fits separated walkable infantry")
				return
			var unit: BattleUnit = game.spawn_unit(kind, owner, at)
			unit.hp *= 1.0 if natural_health else 100.0
			unit.max_hp *= 1.0 if natural_health else 100.0
			unit.hold()
			unit.damaged.connect(_damaged)
			occupied.append({"at": at, "radius": radius})
	_check(game.sandbox_unit_count == 400, "exactly four hundred sandbox infantry")
	print("SANDBOX_PROBE_SPAWN count=", game.sandbox_unit_count, " roster=", ROSTER)

func _find_position(desired: Vector3, radius: float, occupied: Array[Dictionary]) -> Vector3:
	var navigation: ConstructionNavigation = game.get_node("ConstructionNavigation")
	for ring: int in 16:
		for slot: int in (1 if ring == 0 else ring * 8):
			var angle := slot * TAU / maxf(1.0, ring * 8.0)
			var at := desired + Vector3(cos(angle), 0, sin(angle)) * ring * 1.1
			if not navigation.has_clear_corridor(at, at, radius): continue
			var valid := true
			for other: Dictionary in occupied:
				if at.distance_squared_to(other.at) < pow(radius + float(other.radius) + 0.08, 2.0):
					valid = false
					break
			if valid: return at
	return Vector3.INF

func _damaged(_unit: Node3D, amount: float) -> void:
	damage_events += 1
	damage_amount += amount

func _measure(label: String, duration: float) -> void:
	var since := Time.get_ticks_usec()
	var previous := since
	var first_tick := Engine.get_physics_frames()
	var previous_tick := first_tick
	var first_damage := damage_events
	var samples: Array[Dictionary] = []
	var intervals: Array[float] = []
	var steps: Array[float] = []
	var gpu: Array[float] = []
	var next_monitor := since
	var monitors: Array[Dictionary] = []
	probe.begin_sample()
	MovementProbeCounters.begin(profiled)
	while Time.get_ticks_usec() - since < int(duration * 1000000):
		await process_frame
		var now := Time.get_ticks_usec()
		var tick := Engine.get_physics_frames()
		var frame_ms := (now - previous) / 1000.0
		var tick_count := tick - previous_tick
		intervals.append(frame_ms)
		steps.append(float(tick_count))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		samples.append({"frame_ms": frame_ms, "physics_steps": tick_count, "entries_usec": MovementProbeCounters.take_frame()})
		previous = now
		previous_tick = tick
		if now >= next_monitor:
			next_monitor = now + 1000000
			var alive := 0
			var moving := 0
			var waiting := 0
			for unit: BattleUnit in get_nodes_in_group("units"):
				if not unit.alive: continue
				alive += 1
				if unit.velocity.length_squared() > 0.01: moving += 1
				if unit._congestion_wait > 0.0: waiting += 1
			monitors.append({"alive": alive, "moving": moving, "waiting": waiting, "damage": damage_events - first_damage})
	var elapsed := (Time.get_ticks_usec() - since) / 1000000.0
	var counters := MovementProbeCounters.finish()
	var logic: Array[float] = probe.end_sample()
	var phase := {"name": label, "duration_s": elapsed, "frames": intervals.size(), "ticks": Engine.get_physics_frames() - first_tick,
		"fps": intervals.size() / elapsed, "tps": (Engine.get_physics_frames() - first_tick) / elapsed,
		"frame_ms": distribution(intervals), "physics_steps": distribution(steps), "gpu_ms": distribution(gpu),
		"scene_physics_ms": distribution(logic), "path_query_ms": distribution(probe.path_query_ms),
		"path_queries": distribution(probe.path_query_count), "counters": counters, "samples": samples, "monitors": monitors,
		"damage_events": damage_events - first_damage}
	phases.append(phase)
	_check(damage_events > first_damage, "real combat during " + label)
	if not natural_health:
		_check(monitors.all(func(item: Dictionary): return item.alive == 400), "four hundred alive throughout " + label)
	_check(Engine.max_fps == 0 and Engine.physics_ticks_per_second == 30, "unchanged simulation and uncapped rendering")
	print("SANDBOX_PROBE_PHASE ", run_id, " ", label, " fps=", phase.fps, " p95=", phase.frame_ms.p95, " tps=", phase.tps, " steps_max=", phase.physics_steps.max, " damage=", phase.damage_events)

static func distribution(input: Array[float]) -> Dictionary:
	if input.is_empty(): return {"mean": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var data := input.duplicate()
	data.sort()
	var total := 0.0
	for value: float in data: total += value
	return {"mean": total / data.size(), "p50": data[mini(data.size() - 1, floori(data.size() * 0.5))],
		"p95": data[mini(data.size() - 1, floori(data.size() * 0.95))], "p99": data[mini(data.size() - 1, floori(data.size() * 0.99))], "max": data[-1]}

func _watchdog() -> void:
	if done: return
	_check(false, "external wall-clock limit")
	await _finish()

func _finish() -> void:
	if done: return
	done = true
	MovementProbeCounters.enabled = false
	var report := {"schema": 1, "run_id": run_id, "scenario": "sandbox_400_infantry", "map": map_mode,
		"roster_per_side": ROSTER, "seed": 1509400, "profiled": profiled, "natural_health": natural_health,
		"godot": Engine.get_version_info(), "debug_build": OS.is_debug_build(), "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "quality": quality, "checks": checks, "failures": failures, "phases": phases,
		"notes": "Measured entries are inclusive and overlap; profiling changes runtime cost. Physics steps are counted per rendered frame. Scene probe excludes native server work outside SceneTree callbacks. Instrumented runs are attribution evidence, not speedup evidence."}
	FileAccess.open(output.path_join(run_id + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	if is_instance_valid(game):
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
		await process_frame
	print("SANDBOX_PROBE_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
