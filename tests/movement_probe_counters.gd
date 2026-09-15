class_name MovementProbeCounters
extends RefCounted
## Disposable-build instrumentation. Inclusive entries overlap; never add them.
static var enabled: bool = false
static var entries: Dictionary = {}
static var corridors: Dictionary = {}
static var values: Dictionary = {}
static var frame_usec: Dictionary = {}

static func begin(profiled: bool) -> void:
	entries.clear()
	corridors.clear()
	values.clear()
	frame_usec.clear()
	enabled = profiled

static func record(name: StringName, elapsed_usec: int) -> void:
	var item: Dictionary = entries.get(name, {"calls": 0, "usec": 0, "max_usec": 0})
	item.calls += 1
	item.usec += elapsed_usec
	item.max_usec = maxi(item.max_usec, elapsed_usec)
	entries[name] = item
	frame_usec[name] = int(frame_usec.get(name, 0)) + elapsed_usec

static func count(name: StringName, amount: int = 1) -> void:
	values[name] = int(values.get(name, 0)) + amount

static func record_corridor(source: StringName, branch: StringName, elapsed_usec: int, rows: int, span_x: int, span_z: int) -> void:
	var key := String(source) + ":" + String(branch)
	var item: Dictionary = corridors.get(key, {"calls": 0, "usec": 0, "rows": 0, "max_rows": 0, "span_x": 0, "span_z": 0})
	item.calls += 1
	item.usec += elapsed_usec
	item.rows += rows
	item.max_rows = maxi(item.max_rows, rows)
	item.span_x += span_x
	item.span_z += span_z
	corridors[key] = item
	frame_usec[&"corridor"] = int(frame_usec.get(&"corridor", 0)) + elapsed_usec

static func take_frame() -> Dictionary:
	var result := frame_usec.duplicate()
	frame_usec.clear()
	return result

static func finish() -> Dictionary:
	enabled = false
	return {"entries": entries.duplicate(true), "corridors": corridors.duplicate(true), "values": values.duplicate(true)}
