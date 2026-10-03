extends RefCounted
## Optional local elapsed-time samples. Nested stages overlap; these are not
## thread CPU timings, GPU timings, or the engine's complete frame duration.

const WINDOW_USEC := 500000
const STAGES: Array[StringName] = [&"frame", &"simulation", &"ai", &"replication", &"presentation"]

var enabled := false
var _window_started := 0
var _samples: Dictionary[StringName, Dictionary] = {}
var _peaks: Dictionary[StringName, int] = {}
var _published: Dictionary = {}

func _init() -> void:
	_reset()

func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	_reset()
	if enabled:
		_window_started = _now_usec()

func begin() -> int:
	return _now_usec() if enabled else 0

func end(stage: StringName, begun: int) -> void:
	if not enabled or begun == 0:
		return
	_record(stage, _now_usec() - begun)

func finish_frame(begun: int) -> void:
	if not enabled or begun == 0:
		return
	var now := _now_usec()
	_record(&"frame", now - begun)
	if now - _window_started < WINDOW_USEC:
		return
	_published = _make_snapshot(float(now - _window_started) / 1000000.0, true)
	_window_started = now
	_clear_window()

func snapshot() -> Dictionary:
	# UI reads never reset a window or share mutable sample dictionaries.
	return _published.duplicate(true)

func _now_usec() -> int:
	return Time.get_ticks_usec()

func _record(stage: StringName, duration: int) -> void:
	var sample: Dictionary = _samples[stage]
	sample.count += 1
	sample.total_usec += duration
	sample.peak_usec = maxi(sample.peak_usec, duration)
	_peaks[stage] = maxi(_peaks[stage], duration)

func _reset() -> void:
	_window_started = 0
	_peaks.clear()
	for stage: StringName in STAGES:
		_peaks[stage] = 0
	_clear_window()
	_published = _make_snapshot(0.0, false)

func _clear_window() -> void:
	for stage: StringName in STAGES:
		_samples[stage] = {"count": 0, "total_usec": 0, "peak_usec": 0}

func _make_snapshot(seconds: float, ready: bool) -> Dictionary:
	var stages: Dictionary = {}
	for stage: StringName in STAGES:
		var sample: Dictionary = _samples[stage]
		stages[stage] = {
			"count": sample.count,
			"mean_ms": float(sample.total_usec) / float(sample.count) / 1000.0 if sample.count > 0 else 0.0,
			"peak_ms": float(sample.peak_usec) / 1000.0,
			"total_ms": float(sample.total_usec) / 1000.0,
			"peak_since_open_ms": float(_peaks[stage]) / 1000.0,
		}
	return {"enabled": enabled, "ready": ready, "window_seconds": seconds, "stages": stages}
