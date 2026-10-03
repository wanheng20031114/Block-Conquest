extends SceneTree
## Repeatable local diagnostics microbenchmark. No sockets, AI or simulation.
## -- --label=before --rounds=5 --batches=64 --out=res://.local/debug-overhead

const DATA := preload("res://scripts/block_war/war_debug_data.gd")
const METRICS := preload("res://scripts/block_war/war_debug_metrics.gd")
const COORDINATOR := preload("res://scripts/network/war_network_match.gd")
const BATTLE := preload("res://scenes/block_war/block_war.tscn")
const UNIT_COUNTS: Array[int] = [0, 1000, 5000, 10000]
const TIMER_ITERATIONS := 256
const UI_ITERATIONS := 8
const HUD_ITERATIONS := 4
const WARMUP_BATCHES := 8
const SOURCES: Array[String] = [
	"res://tests/block_war_debug_overhead_benchmark.gd",
	"res://scripts/block_war/war_debug_metrics.gd",
	"res://scripts/block_war/war_debug_data.gd",
	"res://scripts/block_war/war_debug_panel.gd",
	"res://scripts/block_war/block_war.gd",
	"res://scripts/block_war/war_marches.gd",
	"res://scripts/network/war_network_match.gd",
	"res://scripts/network/war_online.gd",
	"res://scenes/block_war/block_war.tscn",
	"res://scenes/block_war/debug_panel.tscn",
]

var rounds := 5
var batches := 64
var label := ""
var output := "res://.local/debug-overhead"
var baseline_path := ""
var baseline_data: Script
var capture_script: Script = DATA
var game: Node3D
var panel: Control
var coordinator: RefCounted
var network_config: Dictionary = {}
var render_samples: Array[Dictionary] = []
var records: Array[Dictionary] = []
var checks := 0
var failures: Array[String] = []
var sink := 0
var finishing := false
var source_before: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES:
		result[path] = FileAccess.get_sha256(path)
	if not baseline_path.is_empty(): result[baseline_path] = FileAccess.get_sha256(baseline_path)
	return result

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		elif argument.begins_with("--rounds="): rounds = int(argument.trim_prefix("--rounds="))
		elif argument.begins_with("--batches="): batches = int(argument.trim_prefix("--batches="))
		elif argument.begins_with("--out="): output = argument.trim_prefix("--out=")
		elif argument.begins_with("--baseline-data="): baseline_path = argument.trim_prefix("--baseline-data=")
	if label.is_empty(): label = "run-%d" % OS.get_process_id()
	if rounds < 1 or rounds > 20 or batches < 16 or batches > 256 or label.validate_filename() != label:
		printerr("DEBUG_OVERHEAD invalid arguments")
		quit(2)
		return
	output = ProjectSettings.globalize_path(output)
	if not baseline_path.is_empty():
		baseline_data = load(baseline_path)
		if baseline_data == null:
			printerr("DEBUG_OVERHEAD could not load explicit baseline data script")
			quit(2)
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK or FileAccess.file_exists(output.path_join(label + ".json")):
		printerr("DEBUG_OVERHEAD output unavailable or label already exists")
		quit(2)
		return
	source_before = _source_hashes()
	create_timer(180.0, true, false, true).timeout.connect(func():
		check(false, "benchmark deadline")
		await _finish())
	seed(20261003)
	root.size = Vector2i(1600, 900)
	root.get_node("Session").block_war_map_id = "highland"
	game = BATTLE.instantiate()
	game.get_node("Audio").muted = true
	root.add_child(game)
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.world_effects.set_running(false)
	game.map.set_visual_paused(true)
	game.hud.get_node("%DebugRefresh").stop()
	panel = game.hud.get_node("%DebugPanel")
	panel.visible = true
	coordinator = COORDINATOR.new()
	coordinator.game = game
	coordinator.online = root.get_node("Session/Online")
	var slots: Array[Dictionary] = []
	for faction: int in game.faction_count:
		slots.append({"faction_id": faction, "team_id": faction % 2, "name": "诊断基准%d" % faction, "controller": "human"})
	network_config = {"slots": slots}
	check(game.faction_count == 6 and game.network_match == null, "real six-faction authored offline battle")
	check(coordinator.online.connection_state == "disconnected", "benchmark never opens a transport")
	await process_frame
	_timer_cases()
	for round_index: int in rounds:
		var populations := UNIT_COUNTS.duplicate()
		if round_index % 2 == 1: populations.reverse()
		for population: int in populations:
			_prepare_army(population)
			if not failures.is_empty():
				await _finish()
				return
			var stages: Array[String] = ["capture_offline", "capture_network_disconnected", "panel_stable", "panel_changing", "capture_and_panel", "update_hud_debug_closed"]
			if round_index % 2 == 1: stages.reverse()
			for stage: String in stages:
				if baseline_data != null and stage.begins_with("capture"):
					var variants: Array[String] = ["baseline", "candidate", "candidate", "baseline"]
					if round_index % 2 == 1: variants = ["candidate", "baseline", "baseline", "candidate"]
					for variant: String in variants: _ui_case(stage, population, round_index, variant)
				else:
					_ui_case(stage, population, round_index)
			check(game.marches._units.size() == population and game.elapsed == 0.0, "sampling preserves army count and rule time %d/%d" % [round_index, population])
			print("DEBUG_OVERHEAD_PROGRESS round=%d units=%d" % [round_index, population])
			await process_frame
	await _finish()

func _timer_cases() -> void:
	var metrics := METRICS.new()
	for round_index: int in rounds:
		var modes: Array[String] = ["timer_empty_loop", "timer_disabled", "timer_enabled"]
		if round_index % 2 == 1: modes.reverse()
		for mode: String in modes:
			metrics.set_enabled(mode == "timer_enabled")
			for warmup: int in WARMUP_BATCHES:
				_timer_batch(metrics, mode)
			var values: Array[float] = []
			for batch: int in batches:
				var started := Time.get_ticks_usec()
				_timer_batch(metrics, mode)
				values.append(float(Time.get_ticks_usec() - started) / TIMER_ITERATIONS)
			_record(mode, -1, round_index, TIMER_ITERATIONS, values)
	metrics.set_enabled(false)

func _timer_batch(metrics: RefCounted, mode: String) -> void:
	if mode == "timer_empty_loop":
		for index: int in TIMER_ITERATIONS: sink += 1
		return
	for index: int in TIMER_ITERATIONS:
		var frame: int = metrics.begin()
		var simulation: int = metrics.begin()
		var ai: int = metrics.begin()
		metrics.end(&"ai", ai)
		metrics.end(&"simulation", simulation)
		var replication: int = metrics.begin()
		metrics.end(&"replication", replication)
		var presentation: int = metrics.begin()
		metrics.end(&"presentation", presentation)
		metrics.finish_frame(frame)
		sink += 1

func _prepare_army(population: int) -> void:
	game.network_match = null
	game.match_config = {}
	game.debug_metrics.set_enabled(false)
	game.marches.clear()
	var homes: Array[WarBuilding] = []
	for faction: int in game.faction_count:
		for building: WarBuilding in game.buildings:
			if building.faction == faction and building.kind == 0:
				homes.append(building)
				break
	check(homes.size() == 6, "authored homes exist for every fixture faction")
	if homes.size() != 6: return
	for faction: int in game.faction_count:
		var amount: int = population / game.faction_count + (1 if faction < population % game.faction_count else 0)
		if amount == 0: continue
		var source := homes[faction]
		var target := homes[(faction + 1) % game.faction_count]
		var route: PackedVector3Array = game.dispatch_route(source, target)
		check(route.size() >= 2, "authored route joins each fixture order")
		if route.size() < 2: return
		game.marches.send(source.building_id, target.building_id, faction, amount, route)
	game.select_building(homes[game.local_faction])
	# Keep the production HUD's existing aggregate cache fresh, outside timing.
	# This remains the same fixture when DATA.capture later reuses that cache.
	game.update_hud()
	check(game.marches._units.size() == population, "native send creates requested live MarchUnits")
	var data: Dictionary = DATA.capture(game)
	check(data.marching == ceili(float(population) / 6.0), "diagnostic local marching count agrees with native six-faction fixture")
	render_samples.clear()
	for changed: int in 2:
		var sample: Dictionary = data.duplicate(true)
		sample.mode = "联机客户端"
		sample.energy = 73.0 + changed
		sample.sim_time = 100.0 + changed
		sample.network = {"connection_state": "match", "transport": {
			"connected": true, "relay_rtt_ms": 25.0 + changed, "relay_jitter_ms": 3.0,
			"loss_percent": 0.25, "sent_bytes": 1048576, "received_bytes": 2097152,
			"bulk_queue_bytes": 2048, "last_received_age_ms": 10},
			"match": {"ready": true, "is_host": false, "host_rtt_ms": 90.0,
			"authority_age_ms": 15, "snapshot_loading": false, "recovery_waiting": false,
			"pending_events": 2, "outbox_bytes": 4096, "resync_count": 1}}
		sample.timings.ready = true
		sample.timings.enabled = true
		sample.timings.window_seconds = 0.5
		for stage: StringName in METRICS.STAGES:
			sample.timings.stages[stage] = {"count": 30, "mean_ms": 1.25 + changed * 0.1,
				"peak_ms": 2.0, "total_ms": 37.5, "peak_since_open_ms": 4.5}
		render_samples.append(sample)

func _ui_case(stage: String, population: int, round_index: int, variant: String = "candidate") -> void:
	capture_script = baseline_data if variant == "baseline" else DATA
	var network := stage == "capture_network_disconnected" or stage == "capture_and_panel"
	game.network_match = coordinator if network else null
	game.match_config = network_config if network else {}
	panel.visible = stage != "update_hud_debug_closed"
	var iterations := HUD_ITERATIONS if stage == "update_hud_debug_closed" else UI_ITERATIONS
	for warmup: int in WARMUP_BATCHES:
		_ui_batch(stage, iterations)
	var values: Array[float] = []
	for batch: int in batches:
		var started := Time.get_ticks_usec()
		_ui_batch(stage, iterations)
		values.append(float(Time.get_ticks_usec() - started) / iterations)
	_record(stage, population, round_index, iterations, values, variant)
	game.network_match = null
	game.match_config = {}
	panel.visible = true

func _ui_batch(stage: String, iterations: int) -> void:
	match stage:
		"capture_offline", "capture_network_disconnected":
			for index: int in iterations:
				var data: Dictionary = capture_script.capture(game)
				sink += int(data.marching)
		"panel_stable":
			for index: int in iterations: panel.update_data(render_samples[0])
		"panel_changing":
			for index: int in iterations: panel.update_data(render_samples[index % 2])
		"capture_and_panel":
			for index: int in iterations: panel.update_data(capture_script.capture(game))
		"update_hud_debug_closed":
			for index: int in iterations: game.update_hud()

func _record(stage: String, population: int, round_index: int, iterations: int, values: Array[float], variant: String = "candidate") -> void:
	records.append({"stage": stage, "variant": variant, "units": population, "round": round_index,
		"iterations_per_batch": iterations, "raw_batch_mean_usec": values, "statistics": _statistics(values)})

func _statistics(values: Array[float]) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value: float in values: total += value
	return {"batches": values.size(), "mean_usec": total / values.size(),
		"median_usec": (ordered[(ordered.size() - 1) / 2] + ordered[ordered.size() / 2]) * 0.5,
		"p95_usec": ordered[ceili(ordered.size() * 0.95) - 1],
		"p99_usec": ordered[ceili(ordered.size() * 0.99) - 1], "max_usec": ordered[-1]}

func _summary() -> Dictionary:
	var samples: Dictionary = {}
	for record: Dictionary in records:
		var key := "%s/%s/units=%d" % [record.stage, record.variant, record.units]
		if not samples.has(key): samples[key] = []
		samples[key].append_array(record.raw_batch_mean_usec)
	var result := {}
	for key: String in samples:
		var typed: Array[float] = []
		typed.assign(samples[key])
		result[key] = _statistics(typed)
	return result

func _finish() -> void:
	if finishing: return
	finishing = true
	var source_after := _source_hashes()
	check(source_before == source_after, "measured source files remain unchanged throughout the run")
	if is_instance_valid(game):
		game.network_match = null
		game.match_config = {}
		game.hud.get_node("%DebugRefresh").stop()
		game.debug_metrics.set_enabled(false)
		await game.prepare_shutdown()
		game.free()
		game = null
		panel = null
	coordinator = null
	render_samples.clear()
	await process_frame
	var result := {"label": label, "pid": OS.get_process_id(), "engine": Engine.get_version_info().string,
		"display": DisplayServer.get_name(), "rounds": rounds, "batches_per_round": batches,
		"timer_iterations_per_batch": TIMER_ITERATIONS, "ui_iterations_per_batch": UI_ITERATIONS,
		"hud_iterations_per_batch": HUD_ITERATIONS, "warmup_batches": WARMUP_BATCHES,
		"seed": 20261003, "map": "highland", "units": UNIT_COUNTS,
		"baseline_data": baseline_path,
		"source_sha256_before": source_before, "source_sha256_after": source_after,
		"source_stable": source_before == source_after, "records": records, "summary": _summary(),
		"checks": checks, "failures": failures, "sink": sink,
		"limits": [
			"Microsecond wall elapsed time includes OS scheduling; it is not thread CPU time or an FPS/GPU measurement.",
			"Percentiles describe batch mean per-call cost, not individual-call tail latency. Raw batch means and per-round summaries are retained.",
			"Timer modes execute identical five-stage sampling call sites; enabled minus disabled isolates recording, disabled minus empty loop estimates dormant instrumentation.",
			"Timer benchmark uses real clocks and natural half-second cache publication; no virtual-clock override.",
			"Capture uses real authored battle/buildings and native MarchUnits. HUD aggregate refresh follows fixture creation outside timing.",
			"With explicit baseline-data, capture and capture-plus-panel use both immutable old DATA and current DATA in the same process/fixture, ABBA then BAAB on alternating rounds; all other production code is shared.",
			"Network capture uses the actual disconnected Online diagnostics and coordinator API without opening sockets or running replication.",
			"Panel cases measure synchronous update_data formatting/native Label assignment, not deferred GPU draws or a full game frame.",
			"Panel stable/changing cases use explicitly synthetic fully populated network/timing display rows; fixture construction is excluded.",
			"Capture-and-panel uses actual disconnected network capture. update_hud_debug_closed measures the existing full HUD path with diagnostic visibility and timing disabled.",
			"Authored timers and automatic simulation are stopped. Round order alternates; allocations, fixture setup, checks, output and cleanup are excluded from timing.",
		]}
	var file := FileAccess.open(output.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t", true, true))
	file.close()
	print("BLOCK_WAR_DEBUG_OVERHEAD_RESULT ", JSON.stringify({"path": output.path_join(label + ".json"), "checks": checks, "failures": failures.size(), "source_stable": source_before == source_after, "cases": records.size()}))
	quit(0 if failures.is_empty() else 1)
