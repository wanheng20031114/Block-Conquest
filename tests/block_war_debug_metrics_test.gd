extends SceneTree
## Deterministic windows; no sleeps, scene fixtures or game-state mutation.

class ClockMetrics extends "res://scripts/block_war/war_debug_metrics.gd":
	var now := 1000000
	var clock_calls := 0

	func _now_usec() -> int:
		clock_calls += 1
		return now

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func sample(metrics: ClockMetrics, stage: StringName, microseconds: int) -> void:
	var begun := metrics.begin()
	metrics.now += microseconds
	metrics.end(stage, begun)

func all_zero(snapshot: Dictionary) -> bool:
	return snapshot.stages.values().all(func(row: Dictionary):
		return row.count == 0 and row.mean_ms == 0.0 and row.peak_ms == 0.0 and row.total_ms == 0.0 and row.peak_since_open_ms == 0.0)

func _run() -> void:
	var metrics := ClockMetrics.new()
	check(metrics.clock_calls == 0, "constructing disabled metrics never reads the clock")
	check(metrics.begin() == 0, "disabled begin returns its inactive token")
	metrics.end(&"simulation", 1)
	metrics.finish_frame(1)
	metrics.set_enabled(false)
	var initial := metrics.snapshot()
	check(metrics.clock_calls == 0, "all disabled sampling and reads skip clock access")
	check(not initial.enabled and not initial.ready and initial.window_seconds == 0.0 and initial.stages.size() == 5 and all_zero(initial), "disabled snapshot explicitly contains five empty stages")

	metrics.set_enabled(true)
	check(metrics.clock_calls == 1, "opening diagnostics starts one wall-clock window")
	check(metrics.snapshot().enabled and not metrics.snapshot().ready and all_zero(metrics.snapshot()), "opening starts with clean unpublished statistics")
	var frame := metrics.begin()
	sample(metrics, &"simulation", 2000)
	sample(metrics, &"simulation", 4000)
	sample(metrics, &"ai", 8000)
	sample(metrics, &"replication", 500)
	sample(metrics, &"replication", 500)
	metrics.finish_frame(frame)
	check(not metrics.snapshot().ready and all_zero(metrics.snapshot()), "a partial window remains unpublished")
	metrics.now = 1490000
	frame = metrics.begin()
	metrics.now = 1500000
	metrics.finish_frame(frame)
	var first := metrics.snapshot()
	check(first.ready and first.window_seconds == 0.5, "half a second publishes the completed window")
	check(first.stages.simulation.count == 2 and first.stages.simulation.mean_ms == 3.0 and first.stages.simulation.total_ms == 6.0 and first.stages.simulation.peak_ms == 4.0, "simulation aggregates actual samples in milliseconds")
	check(first.stages.ai.count == 1 and first.stages.ai.mean_ms == 8.0 and first.stages.ai.peak_since_open_ms == 8.0, "sparse AI turns use calls rather than frame count as their denominator")
	check(first.stages.replication.count == 2 and first.stages.replication.mean_ms == 0.5 and first.stages.replication.total_ms == 1.0, "sub-millisecond replication durations retain precision")
	check(first.stages.frame.count == 2 and first.stages.frame.mean_ms == 12.5 and first.stages.frame.peak_ms == 15.0, "battle-frame samples have their own inclusive mean and peak")
	check(first.stages.presentation.count == 0 and first.stages.presentation.peak_ms == 0.0, "unused client presentation has no invented samples")
	var calls_before_read := metrics.clock_calls
	check(metrics.snapshot() == first and metrics.snapshot() == first, "reading a report never consumes it")
	first.stages.ai.mean_ms = -1.0
	first.stages.erase(&"frame")
	check(metrics.snapshot().stages.ai.mean_ms == 8.0 and metrics.snapshot().stages.has(&"frame"), "external changes cannot mutate the cached report")
	metrics.set_enabled(true)
	check(metrics.clock_calls == calls_before_read and metrics.snapshot().ready, "repeated enabling and read-only access do not restart windows or read the clock")

	metrics.now = 1995000
	frame = metrics.begin()
	sample(metrics, &"simulation", 1000)
	metrics.now = 2000000
	metrics.finish_frame(frame)
	var second := metrics.snapshot()
	check(second.stages.simulation.count == 1 and second.stages.simulation.mean_ms == 1.0 and second.stages.simulation.peak_ms == 1.0, "the next half-second contains only its own samples")
	check(second.stages.simulation.peak_since_open_ms == 4.0 and second.stages.frame.peak_since_open_ms == 15.0, "session peaks survive smaller later windows")
	check(second.stages.ai.count == 0 and second.stages.ai.mean_ms == 0.0 and second.stages.ai.peak_ms == 0.0 and second.stages.ai.peak_since_open_ms == 8.0, "a window without AI remains empty while preserving its earlier spike")

	var before_close := metrics.clock_calls
	metrics.set_enabled(false)
	metrics.end(&"replication", frame)
	metrics.finish_frame(frame)
	check(metrics.begin() == 0 and metrics.clock_calls == before_close, "closing stops every additional timing clock read immediately")
	check(not metrics.snapshot().enabled and not metrics.snapshot().ready and all_zero(metrics.snapshot()), "closing clears all cached and lifetime values")
	metrics.now = 3000000
	metrics.set_enabled(true)
	check(not metrics.snapshot().ready and all_zero(metrics.snapshot()), "reopening never carries old peaks into the next session")
	metrics.now = 3500000
	frame = metrics.begin()
	metrics.finish_frame(frame)
	check(metrics.snapshot().ready and metrics.snapshot().window_seconds == 0.5 and metrics.snapshot().stages.frame.count == 1 and metrics.snapshot().stages.ai.peak_since_open_ms == 0.0, "the reopened session starts a fresh independent window")
	metrics.set_enabled(false)
	print("BLOCK_WAR_DEBUG_METRICS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
