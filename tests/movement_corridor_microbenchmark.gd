extends SceneTree
## CPU-only microbenchmark for the frozen-source corridor implementations.
## The generated fixtures come from movement_corridor_probe.py. This benchmark
## creates no scene, navigation map, worker, renderer, or game simulation.
## Example: --headless --path <isolated-project> --script
## res://tests/movement_corridor_microbenchmark.gd -- --output=<absolute-json-path>
const REFERENCE_PATH := "res://tests/generated/movement_corridor_reference.gd"
const CANDIDATE_PATH := "res://tests/generated/movement_corridor_candidate.gd"
var reference_script
var candidate_script
var batch_calls: int = 2000
var rounds: int = 2
var output_path: String = ""
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--calls="):
			batch_calls = argument.trim_prefix("--calls=").to_int()
		elif argument.begins_with("--rounds="):
			rounds = argument.trim_prefix("--rounds=").to_int()
	if batch_calls < 1 or batch_calls > 100000 or rounds < 1 or rounds > 20:
		printerr("MOVEMENT_CORRIDOR_MICRO invalid parameters: calls must be 1..100000, rounds 1..20")
		quit(2)
		return
	reference_script = load(REFERENCE_PATH)
	candidate_script = load(CANDIDATE_PATH)
	if reference_script == null or candidate_script == null:
		printerr("MOVEMENT_CORRIDOR_MICRO missing generated frozen-source fixtures")
		quit(2)
		return
	var groups: Array[Dictionary] = _query_groups()
	var group_results: Array[Dictionary] = []
	for group: Dictionary in groups:
		group_results.append(_measure_group(group))
	var result := {
		"schema": "movement_corridor_microbenchmark_v1",
		"kind": "CPU corridor microbenchmark, not game frame rate",
		"candidate": "short_axis_scan",
		"engine": Engine.get_version_info(),
		"debug_build": OS.has_feature("debug"),
		"processor": OS.get_processor_name(),
		"reference_source": {"path": REFERENCE_PATH, "sha256": FileAccess.get_sha256(REFERENCE_PATH)},
		"candidate_source": {"path": CANDIDATE_PATH, "sha256": FileAccess.get_sha256(CANDIDATE_PATH)},
		"batch_calls": batch_calls,
		"rounds": rounds,
		"order_per_round": ["reference", "candidate", "candidate", "reference"],
		"timing_scope": "One clock pair around each complete query batch, including identical dispatch and checksum overhead; no per-query clocks",
		"warmup_calls_per_variant_per_group": 200,
		"limitations": "Fixed synthetic queries. The mixed grid uses building-like footprints, not sampled game queries. An earlier blocking cell can favor either scan axis. No FPS or battle improvement is inferred.",
		"groups": group_results,
		"failures": failures,
	}
	var encoded: String = JSON.stringify(result, "\t")
	if not output_path.is_empty():
		var parent_directory: String = output_path.get_base_dir()
		if not parent_directory.is_empty():
			var directory_error: Error = DirAccess.make_dir_recursive_absolute(parent_directory)
			if directory_error != OK:
				printerr("MOVEMENT_CORRIDOR_MICRO could not create output directory: ", directory_error)
				quit(2)
				return
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			printerr("MOVEMENT_CORRIDOR_MICRO could not open output: ", FileAccess.get_open_error())
			quit(2)
			return
		file.store_string(encoded + "\n")
		file.close()
		print("MOVEMENT_CORRIDOR_MICRO output=", output_path, " groups=", group_results.size(), " failures=", failures.size())
	else:
		print(encoded)
	quit(0 if failures.is_empty() else 1)

func _make_pair(blocked_cells: Array[Vector2i]) -> Array:
	var reference = reference_script.new()
	var candidate = candidate_script.new()
	var blocked: Dictionary = {}
	for cell: Vector2i in blocked_cells:
		blocked[cell] = true
	for x: int in range(-40, 41):
		for z: int in range(-40, 41):
			var cell := Vector2i(x, z)
			if not blocked.has(cell):
				reference._walkable_cells[cell] = true
				candidate._walkable_cells[cell] = true
	reference._rebuild_corridor_prefix()
	candidate._rebuild_corridor_prefix()
	return [reference, candidate]

func _group(label: String, description: String, blocked: Array[Vector2i]) -> Dictionary:
	return {"label": label, "description": description, "blocked": blocked, "froms": PackedVector3Array(), "tos": PackedVector3Array(), "radii": PackedFloat32Array()}

func _query(group: Dictionary, from: Vector2, to: Vector2, radius: float) -> void:
	group.froms.append(Vector3(from.x, 0, from.y))
	group.tos.append(Vector3(to.x, 0, to.y))
	group.radii.append(radius)

func _query_groups() -> Array[Dictionary]:
	var empty: Dictionary = _group("empty_rectangle", "No occupied cells. Every valid query returns from the O(1) prefix rectangle check; the scan-axis candidate should do no extra scan work.", [])
	for radius: float in [0.0, 0.4, 0.78, 1.3]:
		_query(empty, Vector2(-30, -20), Vector2(30, 20), radius)
		_query(empty, Vector2(-3.2, 5.1), Vector2(2.1, 8.8), radius)
		_query(empty, Vector2(1.25, -0.25), Vector2(1.25, -0.25), radius)
	var long_z: Dictionary = _group("long_z_sweep", "A 64-unit Z span with a 3–5-unit X span. An off-route obstacle makes the outer rectangle fail; endpoint variants either remain clear or meet an obstacle near the last Z rows.", [Vector2i(2, -25), Vector2i(4, 31)])
	for radius: float in [0.0, 0.2, 0.4]:
		for start_x: float in [0.2, 0.6]:
			_query(long_z, Vector2(start_x, -32), Vector2(3.2, 32), radius)
			_query(long_z, Vector2(start_x, -32), Vector2(4.2, 32), radius)
	var long_x: Dictionary = _group("long_x_sweep", "Transpose of the long-Z fixture. The original Z-row loop already spans the short dimension, so the candidate retains that loop after an extra axis comparison.", [Vector2i(-25, 2), Vector2i(31, 4)])
	for index: int in long_z.froms.size():
		var from: Vector3 = long_z.froms[index]
		var to: Vector3 = long_z.tos[index]
		_query(long_x, Vector2(from.z, from.x), Vector2(to.z, to.x), long_z.radii[index])
	var early: Dictionary = _group("early_blocker", "Every route overlaps a blocked starting cell or reaches it in the first two Z rows. Short-axis scanning may inspect more columns and can be slower despite the long total Z span.", [Vector2i(0, -31), Vector2i(0, -30)])
	for radius: float in [0.0, 0.2, 0.4]:
		for start_x: float in [0.2, 0.8]:
			_query(early, Vector2(start_x, -30.2), Vector2(4.2, 32), radius)
			_query(early, Vector2(start_x, -30.7), Vector2(6.2, 30), radius)
	var mixed_cells: Array[Vector2i] = []
	for z: int in range(-20, 21):
		if z < 4 or z > 7: mixed_cells.append(Vector2i(0, z))
	for rectangle: Rect2i in [Rect2i(-7, -9, 4, 4), Rect2i(12, 12, 4, 4), Rect2i(-20, 8, 5, 5), Rect2i(8, -17, 3, 3)]:
		for x: int in range(rectangle.position.x, rectangle.end.x):
			for z: int in range(rectangle.position.y, rectangle.end.y):
				mixed_cells.append(Vector2i(x, z))
	var mixed: Dictionary = _group("footprint_style_mixed", "Synthetic one-metre building footprints and a wall with a four-cell opening. Fixed local and long queries mix clear space, blocked direct routes, a usable opening, building corners, and reverse directions; this is not a captured battle trace.", mixed_cells)
	var endpoints: Array[Vector2] = [Vector2(-12, 5.5), Vector2(12, 5.5), Vector2(-12, -5), Vector2(12, -5), Vector2(2, 10), Vector2(10, 20), Vector2(-25, 5), Vector2(-12, 15), Vector2(2, -25), Vector2(16, -10), Vector2(-10, -12), Vector2(-2, -4), Vector2(4, 0), Vector2(8, 3), Vector2(-3, 24), Vector2(3, 24)]
	for index: int in range(0, endpoints.size(), 2):
		for radius: float in [0.4, 0.78]:
			_query(mixed, endpoints[index], endpoints[index + 1], radius)
			_query(mixed, endpoints[index + 1], endpoints[index], radius)
	return [empty, long_z, long_x, early, mixed]

func _batch(item, froms: PackedVector3Array, tos: PackedVector3Array, radii: PackedFloat32Array, calls: int) -> Dictionary:
	var query_index: int = 0
	var query_count: int = froms.size()
	var clear_count: int = 0
	var checksum: int = 0
	var began: int = Time.get_ticks_usec()
	for _call_index: int in calls:
		if item.has_clear_corridor(froms[query_index], tos[query_index], radii[query_index]):
			clear_count += 1
			checksum += query_index + 1
		query_index += 1
		if query_index == query_count: query_index = 0
	var elapsed_usec: int = Time.get_ticks_usec() - began
	return {"calls": calls, "clear_count": clear_count, "checksum": checksum, "elapsed_usec": elapsed_usec}

func _measure_group(group: Dictionary) -> Dictionary:
	var pair: Array = _make_pair(group.blocked)
	var froms: PackedVector3Array = group.froms
	var tos: PackedVector3Array = group.tos
	var radii: PackedFloat32Array = group.radii
	var queries: Array[Dictionary] = []
	for index: int in froms.size():
		var expected: bool = pair[0].has_clear_corridor(froms[index], tos[index], radii[index])
		var actual: bool = pair[1].has_clear_corridor(froms[index], tos[index], radii[index])
		if actual != expected:
			failures.append("%s query %d disagrees before measurement" % [group.label, index])
		queries.append({"from_xz": [froms[index].x, froms[index].z], "to_xz": [tos[index].x, tos[index].z], "radius": radii[index], "reference_clear": expected, "candidate_clear": actual})
	# Warm both implementations equally. These batches are deliberately excluded
	# from the measured arrays and from result/checksum comparisons below.
	_batch(pair[0], froms, tos, radii, 200)
	_batch(pair[1], froms, tos, radii, 200)
	var samples: Array[Dictionary] = []
	var reference_usec: Array[int] = []
	var candidate_usec: Array[int] = []
	var expected_checksum: int = -1
	var expected_clear_count: int = -1
	for round_index: int in rounds:
		for slot: int in 4:
			var variant: int = 0 if slot == 0 or slot == 3 else 1
			var sample: Dictionary = _batch(pair[variant], froms, tos, radii, batch_calls)
			sample.round = round_index
			sample.slot = slot
			sample.variant = "reference" if variant == 0 else "candidate"
			if expected_checksum < 0:
				expected_checksum = sample.checksum
				expected_clear_count = sample.clear_count
			if sample.checksum != expected_checksum or sample.clear_count != expected_clear_count:
				failures.append("%s round %d slot %d differs from the first batch's results" % [group.label, round_index, slot])
			samples.append(sample)
			if variant == 0:
				reference_usec.append(sample.elapsed_usec)
			else:
				candidate_usec.append(sample.elapsed_usec)
	pair[0].free()
	pair[1].free()
	return {"label": group.label, "description": group.description, "grid_bounds_inclusive": [-40, -40, 40, 40], "blocked_cell_count": group.blocked.size(), "query_count": froms.size(), "queries": queries, "samples": samples, "reference_usec": reference_usec, "candidate_usec": candidate_usec}
