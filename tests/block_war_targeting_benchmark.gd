extends SceneTree
## Deterministic selection CPU A/B, not a battle simulation or rendered FPS test.
## ReferenceMarches freezes the pre-optimization acquire_targets implementation.
## Both variants share the SAME unit/order references; reservations are restored
## outside each timer. Sequential queries retain reservations within each batch.
const MARCH_SCENE := preload("res://scenes/block_war/marches.tscn")
const MAP := preload("res://data/block_war/maps/islands.tres")

class ReferenceMarches extends WarMarches:
	func acquire_targets(center: Vector3, attacking_faction: int, radius: float, count: int, farthest: bool = false, tower_shot: bool = false) -> Array[MarchUnit]:
		var targets: Array[MarchUnit] = []
		var radius_squared := radius * radius
		for target_index: int in count:
			var nearest := -1
			var nearest_distance := -1.0 if farthest else radius_squared
			for index: int in _units.size():
				var unit := _units[index]
				if FACTIONS.allied(unit.order.faction, attacking_faction) or not unit.is_exposed() or unit.reserved:
					continue
				if tower_shot and not tower_can_target(unit):
					continue
				var distance_squared := Vector2(unit.position.x - center.x, unit.position.z - center.z).length_squared()
				if distance_squared <= radius_squared and ((farthest and distance_squared > nearest_distance) or (not farthest and distance_squared <= nearest_distance)):
					nearest_distance = distance_squared
					nearest = index
			if nearest < 0:
				break
			_units[nearest].reserved = true
			_units[nearest].intercepted_by = attacking_faction
			targets.append(_units[nearest])
		return targets

var reference: WarMarches
var candidate: WarMarches
var checks := 0
var failures: Array[String] = []
var verified_cases: Array[String] = []
var benchmark_mode := "perf"
var benchmark_rounds := 3
var benchmark_samples := 60
var benchmark_warmup := 10
var benchmark_sizes: Array[int] = [200, 600, 1000, 1800, 2000, 4000]
var benchmark_densities: Array[String] = ["sparse", "bridge", "dense", "empty_radius"]
var benchmark_queries: Array[String] = ["tower_mixed", "orb_farthest"]

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var value := argument.get_slice("=", 1)
		if argument.begins_with("--mode="): benchmark_mode = value
		elif argument.begins_with("--rounds="): benchmark_rounds = int(value)
		elif argument.begins_with("--samples="): benchmark_samples = int(value)
		elif argument.begins_with("--warmup="): benchmark_warmup = int(value)
		elif argument.begins_with("--sizes="):
			benchmark_sizes.clear()
			for item: String in value.split(","): benchmark_sizes.append(int(item))
		elif argument.begins_with("--densities="):
			benchmark_densities.assign(value.split(","))
		elif argument.begins_with("--queries="):
			benchmark_queries.assign(value.split(","))
		else:
			printerr("FAIL unknown argument: ", argument)
			quit(2)
			return
	if benchmark_mode not in ["verify", "perf"] or benchmark_rounds < 1 or benchmark_samples < 1 or benchmark_warmup < 0:
		printerr("FAIL invalid benchmark arguments")
		quit(2)
		return
	for count: int in benchmark_sizes:
		if count < 1 or count > 16384:
			printerr("FAIL soldier count must be 1..16384")
			quit(2)
			return
	for density: String in benchmark_densities:
		if density not in ["sparse", "bridge", "dense", "empty_radius"]:
			printerr("FAIL invalid density")
			quit(2)
			return
	for query_mode: String in benchmark_queries:
		if query_mode not in ["tower_mixed", "orb_farthest"]:
			printerr("FAIL invalid query mode")
			quit(2)
			return
	reference = MARCH_SCENE.instantiate()
	reference.set_script(ReferenceMarches)
	candidate = MARCH_SCENE.instantiate()
	root.add_child(reference)
	root.add_child(candidate)
	print("TARGETING_CONTRACT ", JSON.stringify({
		"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"seed": 20261001, "map_geometry": MAP.map_id, "factions": 6,
		"sizes": benchmark_sizes, "densities": benchmark_densities, "queries": benchmark_queries,
		"rounds": benchmark_rounds, "samples": benchmark_samples, "warmup": benchmark_warmup,
		"calls_per_batch": 12, "ordering": "AB/BA alternates every sample and round",
		"timing": "Each call brackets only acquire_targets; batch_call_cpu_ms sums 12 calls. batch_wall_ms includes timer/array bookkeeping. Setup, reservation reset, assertions and hashes are outside timers.",
		"limits": ["synthetic six-faction open-air units using islands bridge geometry, not a replay of screenshot state",
			"screenshot total population includes garrisons; 1800 open-air units is a separate stress case",
			"no movement, AI, actual tower clocks, projectiles, simulation steps or GPU work measured",
			"empty-radius batches retain existing repeated-scan behavior; no tower-clock optimization",
			"same object references and helper methods; exact old selection body vs production candidate",
			"orb_farthest is 12 identical-shape bear targeting queries, not a claim of 12 simultaneous bear ultimates"]}))
	_verify()
	print("TARGETING_VERIFY ", JSON.stringify({"cases": verified_cases, "checks": checks, "failures": failures}))
	if failures.is_empty() and benchmark_mode == "perf":
		for round_index: int in benchmark_rounds:
			for count: int in benchmark_sizes:
				for density: String in benchmark_densities:
					for query_mode: String in benchmark_queries:
						_benchmark_case(count, density, query_mode, round_index)
						# Let the app service its event queue without adding waits to samples.
						await process_frame
	reference.free()
	candidate.free()
	print("TARGETING_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _unit(id: int, faction: int, at: Vector3) -> WarMarches.MarchUnit:
	var unit := WarMarches.MarchUnit.new()
	unit.unit_id = id
	unit.order = WarMarches.MarchOrder.new()
	unit.order.order_id = id
	unit.order.faction = faction
	unit.position = at
	unit.distance = 1.0
	return unit

func _install(units: Array[WarMarches.MarchUnit], zones: Dictionary[int, Dictionary] = {}) -> void:
	reference._units = units
	candidate._units = units
	reference.weak_zones = zones
	candidate.weak_zones = zones

func _reservation_state() -> PackedInt32Array:
	var state := PackedInt32Array()
	state.resize(candidate._units.size() * 2)
	for index: int in candidate._units.size():
		state[index * 2] = int(candidate._units[index].reserved)
		state[index * 2 + 1] = candidate._units[index].intercepted_by
	return state

func _restore(state: PackedInt32Array) -> void:
	for index: int in candidate._units.size():
		candidate._units[index].reserved = state[index * 2] == 1
		candidate._units[index].intercepted_by = state[index * 2 + 1]

func _ids(units: Array[WarMarches.MarchUnit]) -> Array[int]:
	var result: Array[int] = []
	for unit: WarMarches.MarchUnit in units: result.append(unit.unit_id)
	return result

func _compare(label: String, center: Vector3 = Vector3.ZERO, faction: int = 0, radius: float = 10.0, count: int = 3, farthest: bool = false, tower_shot: bool = true, expected: Variant = null) -> Array[WarMarches.MarchUnit]:
	var before := _reservation_state()
	var old := reference.acquire_targets(center, faction, radius, count, farthest, tower_shot)
	var after_reference := _reservation_state()
	_restore(before)
	var current := candidate.acquire_targets(center, faction, radius, count, farthest, tower_shot)
	_check(old == current, label + " identical selected object references/order")
	_check(_ids(old) == _ids(current), label + " identical target IDs/order")
	_check(_reservation_state() == after_reference, label + " identical reserved/intercepted_by for every unit")
	if expected != null: _check(_ids(current) == expected, label + " explicit expected IDs")
	verified_cases.append(label)
	return current

func _three() -> Array[WarMarches.MarchUnit]:
	return [_unit(1, 1, Vector3.ZERO), _unit(2, 3, Vector3.RIGHT), _unit(3, 5, Vector3(2, 0, 0))]

func _verify() -> void:
	_install([])
	_compare("empty army", Vector3.ZERO, 0, 10, 3, false, true, [])
	var ties: Array[WarMarches.MarchUnit] = [_unit(1, 1, Vector3(-2, 0, 0)), _unit(2, 3, Vector3(2, 0, 0)), _unit(3, 5, Vector3(0, 100, 2)), _unit(4, 1, Vector3(0, -100, -2))]
	_install(ties)
	var original := _reservation_state()
	_compare("nearest equal distances later entries first, ignore height", Vector3.ZERO, 0, 2, 3, false, true, [4, 3, 2])
	_restore(original)
	_compare("farthest equal distances earlier entries first", Vector3.ZERO, 0, 2, 3, true, false, [1, 2, 3])
	_restore(original)
	ties.reverse()
	_compare("nearest ties after array reorder", Vector3.ZERO, 0, 2, 3, false, true, [1, 2, 3])
	_install([_unit(1, 1, Vector3(5, 0, 0)), _unit(2, 1, Vector3(5.001, 0, 0)), _unit(3, 1, Vector3(4.999, 0, 0)), _unit(4, 1, Vector3.ZERO)])
	original = _reservation_state()
	_compare("inclusive radius boundary and insufficient targets", Vector3.ZERO, 0, 5, 10, false, true, [4, 3, 1])
	_restore(original)
	_compare("farthest radius boundary", Vector3.ZERO, 0, 5, 10, true, false, [1, 3, 4])
	_restore(original)
	_compare("zero radius", Vector3.ZERO, 0, 0, 3, false, true, [4])
	_restore(original)
	_compare("zero target count", Vector3.ZERO, 0, 5, 0, false, true, [])
	_restore(original)
	_compare("empty radius", Vector3(1000, 0, 0), 0, 5, 3, false, true, [])
	var faction_units: Array[WarMarches.MarchUnit] = []
	for faction: int in 6: faction_units.append(_unit(faction + 1, faction, Vector3(faction, 0, 0)))
	_install(faction_units)
	original = _reservation_state()
	_compare("six factions even alliance", Vector3.ZERO, 0, 10, 6, false, true, [2, 4, 6])
	_restore(original)
	_compare("six factions odd alliance", Vector3.ZERO, 3, 10, 6, false, true, [1, 3, 5])
	for property: String in ["alive", "pending_departure", "distance", "spawn_delay", "reserved", "cloaked", "levitation_remaining"]:
		var units := _three()
		var value: Variant = {"alive": false, "pending_departure": true, "distance": -0.001, "spawn_delay": 0.001, "reserved": true, "cloaked": true, "levitation_remaining": 0.001}[property]
		units[0].set(property, value)
		if property == "reserved": units[0].intercepted_by = 4
		_install(units)
		original = _reservation_state()
		_compare("tower excludes " + property, Vector3.ZERO, 0, 10, 5, false, true, [2, 3])
		_restore(original)
		var expected: Array = [3, 2, 1] if property in ["cloaked", "levitation_remaining"] else [3, 2]
		_compare("orb exposure rule " + property, Vector3.ZERO, 0, 10, 5, true, false, expected)
	for property: String in ["reserved", "cloaked", "levitation_remaining"]:
		var units := _three()
		for unit: WarMarches.MarchUnit in units:
			unit.set(property, 1.0 if property == "levitation_remaining" else true)
		_install(units)
		_compare("all_" + property, Vector3.ZERO, 0, 10, 3, false, true, [])
	var zones: Dictionary[int, Dictionary] = {2: {"at": Vector3.ZERO, "radius": 1.0, "remaining": 1.0}}
	_install(_three(), zones)
	original = _reservation_state()
	_compare("allied mist hides all factions including boundary", Vector3.ZERO, 0, 10, 5, false, true, [3])
	_restore(original)
	_compare("orb ignores mist", Vector3.ZERO, 0, 10, 5, true, false, [3, 2, 1])
	_restore(original)
	zones[2].remaining = 0.0
	_compare("expired mist", Vector3.ZERO, 0, 10, 5, false, true, [1, 2, 3])
	_install(_three())
	_compare("first tower reserves next tower targets", Vector3.ZERO, 0, 10, 2, false, true, [1, 2])
	_compare("second tower honors prior reservations", Vector3.ZERO, 2, 10, 3, false, true, [3])
	_compare("all candidates already reserved", Vector3.ZERO, 4, 10, 3, false, true, [])
	_verify_conversion()
	_verify_random()

func _verify_conversion() -> void:
	var units := _three()
	units[1].order = units[0].order
	_install(units)
	_compare("before immediate conversion", Vector3.ZERO, 0, 10, 1, false, true, [1])
	# The exact production ownership operation used by fox.convert, on only one
	# member of a shared order. No tick/cache reset occurs between either query.
	var old_order := units[0].order
	units[0].order = candidate.transfer_order(old_order, 0)
	_check(units[1].order == old_order and units[1].order.faction == 1, "conversion does not change unselected shared-order member")
	_check(not candidate.hit_target(units[0], Vector3.RIGHT, true), "in-flight shot releases newly allied recruit")
	_check(units[0].alive and not units[0].reserved and units[0].intercepted_by == -1, "conversion hit preserves recruit and clears reservation")
	_compare("immediate conversion excluded from old enemy query", Vector3.ZERO, 0, 10, 1, false, true, [2])
	_compare("immediate conversion included by new enemy", Vector3.ZERO, 1, 10, 1, false, true, [1])
	units[2].alive = false
	_compare("immediate death invalidates remaining candidate", Vector3.ZERO, 0, 10, 3, false, true, [])

func _verify_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	for trial: int in 72:
		var units: Array[WarMarches.MarchUnit] = []
		for index: int in 48:
			var unit := _unit(index + 1, rng.randi_range(0, 5), Vector3(rng.randi_range(-8, 8), rng.randi_range(-3, 3), rng.randi_range(-8, 8)))
			unit.alive = index % 13 != trial % 13
			unit.pending_departure = index % 17 == trial % 17
			unit.distance = -0.1 if index % 19 == trial % 19 else 0.0
			unit.spawn_delay = 0.1 if index % 23 == trial % 23 else 0.0
			unit.reserved = index % 11 == trial % 11
			unit.intercepted_by = rng.randi_range(0, 5) if unit.reserved else -1
			unit.cloaked = index % 7 == trial % 7
			unit.levitation_remaining = 0.2 if index % 5 == trial % 5 else 0.0
			units.append(unit)
		var zones: Dictionary[int, Dictionary] = {0: {"at": Vector3(2, 0, 1), "radius": 3.0, "remaining": 1.0}, 3: {"at": Vector3(-2, 0, -1), "radius": 4.0, "remaining": 0.0 if trial % 3 == 0 else 1.0}}
		_install(units, zones)
		_compare("seeded mixed case %d" % trial, Vector3(trial % 4, 0, trial % 3), trial % 6, [0.0, 2.0, 8.0, 20.0][trial % 4], [0, 1, 2, 3, 7, 64][trial % 6], trial % 2 == 0, trial % 3 != 0)

func _populate(count: int, density: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001 + count
	var units: Array[WarMarches.MarchUnit] = []
	var orders: Array[WarMarches.MarchOrder] = []
	for faction: int in 6:
		var order := WarMarches.MarchOrder.new()
		order.order_id = faction + 1
		order.faction = faction
		orders.append(order)
	for index: int in count:
		var unit := WarMarches.MarchUnit.new()
		unit.unit_id = index + 1
		unit.order = orders[index % 6]
		unit.distance = 1.0
		var bridge: Rect2 = MAP.bridges[(index / 6) % 6]
		var center := bridge.get_center()
		if density == "sparse" or density == "empty_radius":
			unit.position = Vector3(rng.randf_range(-MAP.half_size.x, MAP.half_size.x), 0, rng.randf_range(-MAP.half_size.y, MAP.half_size.y))
		elif density == "bridge":
			unit.position = Vector3(center.x + rng.randf_range(-12, 12), 0, center.y + rng.randf_range(-1.4, 1.4))
		else:
			unit.position = Vector3(center.x + rng.randf_range(-2, 2), 0, center.y + rng.randf_range(-2, 2))
		units.append(unit)
	_install(units)

func _queries(density: String, query_mode: String) -> Array[Dictionary]:
	var queries: Array[Dictionary] = []
	for index: int in 12:
		var bridge: Rect2 = MAP.bridges[index / 2]
		var center := bridge.get_center()
		var at := Vector3(center.x + (-8.0 if index % 2 == 0 else 8.0), 0, center.y)
		if density == "empty_radius": at += Vector3(1000, 0, 1000)
		queries.append({"center": at, "faction": index % 6, "radius": 18.0,
			"count": 1 + index % 3 if query_mode == "tower_mixed" else 3,
			"farthest": query_mode == "orb_farthest", "tower_shot": query_mode == "tower_mixed"})
	return queries

func _batch(marches: WarMarches, queries: Array[Dictionary]) -> Dictionary:
	var calls: Array[float] = []
	var selected: Array = []
	var batch_begun := Time.get_ticks_usec()
	for query: Dictionary in queries:
		var begun := Time.get_ticks_usec()
		var targets := marches.acquire_targets(query.center, query.faction, query.radius, query.count, query.farthest, query.tower_shot)
		var ended := Time.get_ticks_usec()
		calls.append(float(ended - begun) / 1000.0)
		selected.append(targets)
	var batch_ms := float(Time.get_ticks_usec() - batch_begun) / 1000.0
	var sum := 0.0
	for value: float in calls: sum += value
	return {"calls": calls, "sum": sum, "wall": batch_ms, "selected": selected}

func _benchmark_case(count: int, density: String, query_mode: String, round_index: int) -> void:
	_populate(count, density)
	var initial := _reservation_state()
	var queries := _queries(density, query_mode)
	var samples := {"reference": {"calls": [], "sum": [], "wall": []}, "candidate": {"calls": [], "sum": [], "wall": []}}
	var selected_per_batch := 0
	for sample: int in benchmark_warmup + benchmark_samples:
		var order: Array[String] = ["reference", "candidate"]
		if (sample + round_index) % 2 == 1: order.reverse()
		var batches := {}
		var states := {}
		for variant: String in order:
			_restore(initial)
			var result := _batch(reference if variant == "reference" else candidate, queries)
			batches[variant] = result
			states[variant] = _reservation_state()
			if sample >= benchmark_warmup:
				samples[variant].calls.append(result.calls)
				samples[variant].sum.append(result.sum)
				samples[variant].wall.append(result.wall)
		_check(batches.reference.selected == batches.candidate.selected, "%d/%s/%s sample %d selected reference sequence" % [count, density, query_mode, sample])
		_check(states.reference == states.candidate, "%d/%s/%s sample %d full reservation state" % [count, density, query_mode, sample])
		if sample == 0:
			for targets: Array in batches.candidate.selected: selected_per_batch += targets.size()
	if density == "empty_radius": _check(selected_per_batch == 0, "empty-radius performance fixture really selects no targets")
	else: _check(selected_per_batch > 0, "nonempty performance fixture selects targets")
	for variant: String in ["reference", "candidate"]:
		var calls: Array[float] = []
		for row: Array in samples[variant].calls: calls.append_array(row)
		var by_count := {}
		for query_index: int in queries.size():
			var volley_count: int = queries[query_index].count
			if not by_count.has(volley_count): by_count[volley_count] = []
			for row: Array in samples[variant].calls: by_count[volley_count].append(row[query_index])
		var count_statistics := {}
		for volley_count: int in by_count: count_statistics[str(volley_count)] = _statistics(by_count[volley_count])
		print("TARGETING_RESULT ", JSON.stringify({"variant": variant, "round": round_index,
			"open_air_units": count, "density": density, "query_mode": query_mode,
			"calls_per_batch": queries.size(), "selected_per_batch": selected_per_batch,
			"samples": benchmark_samples, "warmup": benchmark_warmup,
			"single_call_cpu_ms": _statistics(calls), "single_call_cpu_ms_by_requested_count": count_statistics,
			"batch_call_cpu_ms": _statistics(samples[variant].sum),
			"batch_wall_ms": _statistics(samples[variant].wall),
			"raw_call_matrix_ms": samples[variant].calls,
			"raw_batch_call_cpu_ms": samples[variant].sum, "raw_batch_wall_ms": samples[variant].wall}))

func _statistics(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in values: total += value
	return {"n": values.size(), "mean": total / values.size(),
		"p50": sorted[maxi(0, ceili(values.size() * 0.50) - 1)],
		"p95": sorted[maxi(0, ceili(values.size() * 0.95) - 1)],
		"p99": sorted[maxi(0, ceili(values.size() * 0.99) - 1)], "max": sorted[-1],
		"quantile": "nearest rank, no outlier removal"}
