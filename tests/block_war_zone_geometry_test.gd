extends "res://tests/block_war_replication_test.gd"
## Exact zone-span regression. The inherited helpers only create native battle
## scenes for the real snapshot install checks; no replication suite is run.
## Optional CPU microbenchmarks do not establish simulate() or frame-time gains.
const MARCH_SCENE := preload("res://scenes/block_war/marches.tscn")
const ELEVATED_MAP := preload("res://data/block_war/maps/terraces.tres")

class ReferenceMarches extends WarMarches:
	func _zone_intervals(order: MarchOrder, lane: float, zone: Dictionary) -> PackedVector2Array:
		var intervals := PackedVector2Array()
		var center := Vector2(zone.at.x, zone.at.z)
		var count := ceili(order.length / 0.24)
		var from := order.sample(0.0)
		for index: int in count:
			var low := order.length * float(index) / count
			var high := order.length * float(index + 1) / count
			var to := _formation_position(order, high, lane, _route_heading(order, high))
			var a := Vector2(from.x, from.z)
			var b := Vector2(to.x, to.z)
			var start := 0.0 if a.distance_to(center) <= zone.radius else Geometry2D.segment_intersects_circle(a, b, center, zone.radius)
			if start >= 0.0:
				var end := 1.0 if b.distance_to(center) <= zone.radius else 1.0 - Geometry2D.segment_intersects_circle(b, a, center, zone.radius)
				var span := Vector2(lerpf(low, high, start), lerpf(low, high, end))
				if span.y > span.x:
					if not intervals.is_empty() and absf(intervals[-1].y - span.x) < 0.00001:
						intervals[-1] = Vector2(intervals[-1].x, span.y)
					else:
						intervals.append(span)
			from = to
		return intervals

var geometry_reference: WarMarches
var geometry_candidate: WarMarches
var geometry_pairs := 0
var nonempty_pairs := 0
var lane_point_pairs := 0
var verified_labels: Array[String] = []
var benchmark_mode := "verify"
var benchmark_samples := 40
var benchmark_warmup := 5
var benchmark_rounds := 2

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var value := argument.get_slice("=", 1)
		if argument.begins_with("--mode="): benchmark_mode = value
		elif argument.begins_with("--samples="): benchmark_samples = int(value)
		elif argument.begins_with("--warmup="): benchmark_warmup = int(value)
		elif argument.begins_with("--rounds="): benchmark_rounds = int(value)
		else:
			printerr("FAIL unknown zone geometry argument: ", argument)
			quit(2)
			return
	if benchmark_mode not in ["verify", "perf"] or benchmark_samples < 1 or benchmark_warmup < 0 or benchmark_rounds < 1:
		printerr("FAIL invalid zone geometry arguments")
		quit(2)
		return
	geometry_reference = MARCH_SCENE.instantiate()
	geometry_reference.set_script(ReferenceMarches)
	geometry_candidate = MARCH_SCENE.instantiate()
	root.add_child(geometry_reference)
	root.add_child(geometry_candidate)
	print("ZONE_GEOMETRY_CONTRACT ", JSON.stringify({
		"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"equivalence": "frozen old _zone_intervals, exact span count/endpoints, and every cached XZ point against raw first sample plus current _formation_position; no tolerance",
		"isolation": "independent orders/curves for A/B; shared current formation, terrain and circle-intersection helpers",
		"network": "real Codec.capture/valid/install, including field-only changes and replacement of order geometry",
		"benchmark": "six lanes per batch; cold uses newly built orders, hot reuses order geometry but clears existing per-field interval caches outside timing",
		"limits": ["synthetic CPU geometry microbenchmark, not frame time or GPU measurements",
			"reference intentionally shares all non-zone production helpers; this is not historical full-project replay",
			"verification runs before optional timings; external runner must own timeout and process cleanup"]}))
	_verify_geometry()
	_verify_lifecycle()
	_verify_field_rebuilds()
	await _verify_network_install()
	check(nonempty_pairs > 0, "geometry comparisons include actual occupied spans")
	print("ZONE_GEOMETRY_VERIFY ", JSON.stringify({"labels": verified_labels, "geometry_pairs": geometry_pairs, "nonempty_pairs": nonempty_pairs,
		"lane_point_pairs": lane_point_pairs, "checks": checks, "failures": failures}))
	if failures.is_empty() and benchmark_mode == "perf":
		for round_index: int in benchmark_rounds:
			for length: float in [32.0, 96.0]:
				for mode: String in ["cold_six_lanes", "hot_repeated_zone", "hot_changing_zone"]:
					_benchmark(length, mode, round_index)
					await process_frame
	geometry_reference.free()
	geometry_candidate.free()
	print("ZONE_GEOMETRY_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _ordinary_route(scale: float = 1.0) -> PackedVector3Array:
	return PackedVector3Array([Vector3(-20, 0, -8) * scale, Vector3(-8, 0, -8) * scale,
		Vector3(-2, 0, 3) * scale, Vector3(2, 0, -5) * scale,
		Vector3(12, 0, 1) * scale, Vector3(24, 0, 1) * scale])

func _lanes() -> Array[float]:
	var values: Array[float] = []
	for index: int in 6: values.append((float(index) - 2.5) * WarMarches.COLUMN_SPACING)
	return values

func _new_order(marches: WarMarches, route: PackedVector3Array, faction: int = 0, airborne: bool = false, returning: bool = false, exit_distance: float = 0.0) -> WarMarches.MarchOrder:
	var order := marches._make_order(0, 1, faction, route)
	order.airborne = airborne
	order.returning = returning
	order.departure_distance = minf(exit_distance, order.length)
	return order

func _clone_order(order: WarMarches.MarchOrder) -> WarMarches.MarchOrder:
	var route := PackedVector3Array()
	for index: int in order.curve.point_count: route.append(order.curve.get_point_position(index))
	return _new_order(geometry_reference, route, order.faction, order.airborne, order.returning, order.departure_distance)

func _zones(order: WarMarches.MarchOrder) -> Array[Dictionary]:
	return [{"at": order.sample(0.0), "radius": 1.1},
		{"at": order.sample(order.length * 0.23), "radius": 2.6},
		{"at": order.sample(order.length * 0.5) + Vector3(0.4, 12, 0.7), "radius": 4.7},
		{"at": order.sample(order.length * 0.81), "radius": 0.031},
		{"at": order.sample(order.length), "radius": 1.35},
		{"at": Vector3.ZERO, "radius": 1000.0},
		{"at": Vector3(10000, 0, 10000), "radius": 0.5}]

func _exact(label: String, expected: PackedVector2Array, actual: PackedVector2Array) -> void:
	geometry_pairs += 1
	if not expected.is_empty(): nonempty_pairs += 1
	check(actual.size() == expected.size(), label + " exact span count")
	if actual.size() != expected.size(): return
	for index: int in actual.size():
		check(actual[index].x == expected[index].x and actual[index].y == expected[index].y,
			"%s span %d exact endpoints: %s / %s" % [label, index, actual[index], expected[index]])

func _exact_lane_points(label: String, old: WarMarches.MarchOrder, marches: WarMarches, current: WarMarches.MarchOrder, lane: float) -> void:
	# Calling the real pose formula is deliberate: if it changes later, this
	# test detects an out-of-date copy in the geometry-cache implementation.
	var actual: PackedVector2Array = marches._zone_lane_points(current, lane)
	var count := ceili(old.length / 0.24)
	check(actual.size() == count + 1, label + " exact lane point count")
	if actual.size() != count + 1: return
	var first := old.sample(0.0)
	lane_point_pairs += 1
	check(actual[0] == Vector2(first.x, first.z), label + " exact raw first route point")
	for index: int in count:
		var high := old.length * float(index + 1) / count
		var point := geometry_reference._formation_position(old, high, lane, geometry_reference._route_heading(old, high))
		var expected := Vector2(point.x, point.z)
		lane_point_pairs += 1
		check(actual[index + 1] == expected, "%s exact cached XZ point %d: %s / %s" % [label, index + 1, actual[index + 1], expected])

func _compare_order(label: String, old: WarMarches.MarchOrder, current: WarMarches.MarchOrder, lanes: Array[float], zones: Array[Dictionary]) -> void:
	check(old != current and old.curve != current.curve, label + " independent order and curve objects")
	check(old.length == current.length, label + " exact baked length")
	for pass_index: int in 2:
		for lane: float in lanes:
			for zone_index: int in zones.size():
				var zone := zones[zone_index]
				_exact("%s pass %d lane %.9f zone %d" % [label, pass_index, lane, zone_index],
					geometry_reference._zone_intervals(old, lane, zone), geometry_candidate._zone_intervals(current, lane, zone))
			_exact_lane_points("%s pass %d lane %.9f" % [label, pass_index, lane], old, geometry_candidate, current, lane)
	verified_labels.append(label)

func _verify_geometry() -> void:
	var flat := WarMapDefinition.new()
	var route := _ordinary_route()
	var elevated_route := PackedVector3Array()
	for point: Vector3 in route: elevated_route.append(ELEVATED_MAP.surface_point(point))
	check(ELEVATED_MAP.has_elevation(), "elevated fixture uses real authored terrain")
	var flight := geometry_candidate.make_flight_route(Vector3(-20, 0, -8), Vector3(24, 3, 1), 5.0)
	var fixtures: Array[Dictionary] = [
		{"label": "ordinary bent ground", "route": route, "map": flat, "air": false, "return": false, "exit": 0.0},
		{"label": "authored elevation", "route": elevated_route, "map": ELEVATED_MAP, "air": false, "return": false, "exit": 0.0},
		{"label": "returning bent ground", "route": route, "map": flat, "air": false, "return": true, "exit": 0.0},
		{"label": "returning elevation", "route": elevated_route, "map": ELEVATED_MAP, "air": false, "return": true, "exit": 0.0},
		{"label": "airborne vertical takeoff and landing", "route": flight, "map": ELEVATED_MAP, "air": true, "return": false, "exit": 0.0},
		{"label": "airborne returning", "route": flight, "map": ELEVATED_MAP, "air": true, "return": true, "exit": 0.0},
		{"label": "tunnel emergence gate", "route": route, "map": flat, "air": false, "return": false, "exit": 47.25},
		{"label": "returning tunnel gate", "route": route, "map": flat, "air": false, "return": true, "exit": 47.25},
		{"label": "subsample short route", "route": PackedVector3Array([Vector3.ZERO, Vector3(0.13, 0, 0.02)]), "map": flat, "air": false, "return": false, "exit": 0.0}]
	var lanes := _lanes()
	# Odd final rows and dense formation produce lane values absent from a full
	# ordinary six-column row. Include the actual send(11) values below too.
	lanes.append_array([0.0, -WarMarches.COLUMN_SPACING, WarMarches.COLUMN_SPACING, -0.44, 0.44, -0.88, 0.88])
	for fixture: Dictionary in fixtures:
		geometry_reference.map_definition = fixture.map
		geometry_candidate.map_definition = fixture.map
		var old := _new_order(geometry_reference, fixture.route, 0, fixture.air, fixture["return"], fixture.exit)
		var current := _new_order(geometry_candidate, fixture.route, 0, fixture.air, fixture["return"], fixture.exit)
		_compare_order(fixture.label, old, current, lanes, _zones(old))
	geometry_reference.map_definition = flat
	geometry_candidate.map_definition = flat
	geometry_reference.send(0, 1, 0, 11, route)
	geometry_candidate.send(0, 1, 0, 11, route)
	var odd_lanes: Array[float] = []
	for index: int in 11:
		var lane: float = geometry_reference._units[index].lane
		check(lane == geometry_candidate._units[index].lane, "actual odd-row dispatch lane %d" % index)
		if not odd_lanes.has(lane): odd_lanes.append(lane)
	check(odd_lanes.has(0.0), "eleven-soldier final row includes center lane")
	_compare_order("actual eleven-soldier odd final row", geometry_reference._units[0].order, geometry_candidate._units[0].order, odd_lanes, _zones(geometry_reference._units[0].order))
	geometry_reference.clear()
	geometry_candidate.clear()

func _verify_lifecycle() -> void:
	var route := _ordinary_route()
	var old := _new_order(geometry_reference, route, 1, false, false, 16.75)
	var current := _new_order(geometry_candidate, route, 1, false, false, 16.75)
	var zones := _zones(old)
	_compare_order("lifecycle warm outbound", old, current, _lanes(), zones)
	var transferred_old := geometry_reference.transfer_order(old, 2)
	var transferred_current := geometry_candidate.transfer_order(current, 2)
	check(transferred_old.curve == old.curve and transferred_current.curve == current.curve, "conversion shares route with its own original")
	_compare_order("conversion creates independently owned cached geometry", transferred_old, transferred_current, _lanes(), zones)
	var return_old := geometry_reference.return_order(transferred_old)
	var return_current := geometry_candidate.return_order(transferred_current)
	_compare_order("return order after conversion and warm geometry", return_old, return_current, _lanes(), zones)
	var old_unit := WarMarches.MarchUnit.new()
	old_unit.order = transferred_old; old_unit.distance = old.length * 0.41; old_unit.lane = 0.56
	var current_unit := WarMarches.MarchUnit.new()
	current_unit.order = transferred_current; current_unit.distance = current.length * 0.41; current_unit.lane = 0.56
	geometry_reference.redirect(old_unit, return_old)
	geometry_candidate.redirect(current_unit, return_current)
	check(old_unit.distance == current_unit.distance and old_unit.lane == current_unit.lane and old_unit.position == current_unit.position, "actual redirect preserves equivalent distance, mirrored lane and position")
	_exact("redirected unit lane", geometry_reference._zone_intervals(return_old, old_unit.lane, zones[1]), geometry_candidate._zone_intervals(return_current, current_unit.lane, zones[1]))

func _add_units(marches: WarMarches, order: WarMarches.MarchOrder) -> void:
	for lane: float in _lanes():
		var unit := WarMarches.MarchUnit.new()
		unit.unit_id = marches._units.size() + 1
		unit.order = order
		unit.distance = 1.5
		unit.lane = lane
		marches._update_pose(unit)
		marches._units.append(unit)

func _field_steps(label: String) -> void:
	for index: int in geometry_reference._units.size():
		var old: WarMarches.MarchUnit = geometry_reference._units[index]
		var current: WarMarches.MarchUnit = geometry_candidate._units[index]
		var old_step := geometry_reference.movement_distance(old, 1.25)
		var current_step := geometry_candidate.movement_distance(current, 1.25)
		check(old_step == current_step, "%s unit %d exact integrated movement" % [label, index])
		check(old.order.haste_intervals == current.order.haste_intervals and old.order.slow_intervals == current.order.slow_intervals, "%s unit %d exact rebuilt field interval dictionaries" % [label, index])
	verified_labels.append(label)

func _verify_field_rebuilds() -> void:
	var route := _ordinary_route()
	for faction: int in 6:
		_add_units(geometry_reference, _new_order(geometry_reference, route, faction))
		_add_units(geometry_candidate, _new_order(geometry_candidate, route, faction))
	for marches: WarMarches in [geometry_reference, geometry_candidate]:
		for faction: int in 6:
			marches.create_haste_zone(faction, Vector3(-8 + faction, 0, -7), 4.5, 8.0, 1.6)
		marches.create_slow_zone(1, Vector3(-5, 0, -3), 4.5, 8.0)
		marches.create_slow_zone(2, Vector3(5, 0, -3), 5.0, 8.0)
	_field_steps("six factions overlapping haste and hostile slow")
	for marches: WarMarches in [geometry_reference, geometry_candidate]:
		marches.create_haste_zone(0, Vector3(12, 0, 1), 2.35, 8.0, 1.6)
		marches.create_slow_zone(1, Vector3(-2, 0, 3), 3.125, 8.0)
		marches.create_slow_zone(3, Vector3(-13, 0, -8), 1.75, 8.0)
	_field_steps("recast zones and added hostile faction rebuild intervals")
	for marches: WarMarches in [geometry_reference, geometry_candidate]:
		marches.apply_frog_field(0, 2, Vector3(-8, 0, -8))
	for index: int in geometry_reference._units.size():
		var old: WarMarches.MarchUnit = geometry_reference._units[index]
		var current: WarMarches.MarchUnit = geometry_candidate._units[index]
		check(geometry_reference._touches_mist(old, 5.0) == geometry_candidate._touches_mist(current, 5.0), "mist rebuild exact contact unit %d" % index)
		check(old.order.mist_intervals == current.order.mist_intervals, "mist rebuild exact interval cache unit %d" % index)
	verified_labels.append("mist cache rebuild after several zone and faction geometries")
	geometry_reference.clear()
	geometry_candidate.clear()

func _network_spans(label: String) -> void:
	geometry_reference.map_definition = replica.marches.map_definition
	var seen := {}
	for unit: WarMarches.MarchUnit in replica.marches._units:
		if seen.has(unit.order): continue
		seen[unit.order] = true
		var old := _clone_order(unit.order)
		for lane: float in _lanes():
			for kind: String in ["haste_zones", "slow_zones", "weak_zones"]:
				var zones: Dictionary = replica.marches.get(kind)
				for faction: int in zones:
					_exact("%s %s faction %d lane %.9f" % [label, kind, faction, lane],
						geometry_reference._zone_intervals(old, lane, zones[faction]), replica.marches._zone_intervals(unit.order, lane, zones[faction]))
			_exact_lane_points("%s lane %.9f" % [label, lane], old, replica.marches, unit.order, lane)
	verified_labels.append(label)

func _verify_network_install() -> void:
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	host.marches.clear()
	var route := _ordinary_route()
	host.marches.send(0, 1, 0, 11, route)
	for unit: WarMarches.MarchUnit in host.marches._units:
		unit.distance = 1.5
		host.marches._update_pose(unit)
	host.marches.create_haste_zone(0, Vector3(-12, 0, -8), 4.5, 8.0, 1.6)
	host.marches.create_slow_zone(1, Vector3(-2, 0, 3), 4.5, 8.0)
	var writer := Codec.new()
	var reader := Codec.new()
	var state: Dictionary = writer.capture(host, 1)
	check(Codec.valid(state, replica), "network geometry fixture validates")
	reader.install(replica, state, 0.0, true, true)
	_network_spans("initial real snapshot install")
	var installed: WarMarches.MarchOrder = replica.marches._units[0].order
	for unit: WarMarches.MarchUnit in replica.marches._units: replica.marches.movement_distance(unit, 0.5)
	check(not installed.haste_intervals.is_empty() and not installed.slow_intervals.is_empty(), "network fixture really primes per-field interval caches")
	var cached_haste := installed.haste_intervals.duplicate()
	reader.install(replica, state, 0.0, true, true)
	check(replica.marches._units[0].order == installed and installed.haste_intervals == cached_haste, "identical install retains order and field cache")
	var changed: Dictionary = state.duplicate(true)
	changed.fields["haste:0"][2] = [12.0, 0.0, 1.0]
	changed.fields["haste:0"][3] = 2.125
	changed.fields["slow:1"][2] = [-10.0, 0.0, -8.0]
	check(Codec.valid(changed, replica), "changed field geometry snapshot validates")
	reader.install(replica, changed, 0.0, true, true)
	check(replica.marches._units[0].order == installed, "field-only install retains the geometric order")
	check(installed.haste_intervals.is_empty() and installed.slow_intervals.is_empty() and installed.mist_intervals.is_empty(), "changed fields clear old per-field intervals before reuse")
	_network_spans("field-only install after warmed order")
	for unit: WarMarches.MarchUnit in replica.marches._units: replica.marches.movement_distance(unit, 0.5)
	var order_key := str(installed.order_id)
	var altered: Dictionary = changed.duplicate(true)
	var points: Array = altered.orders[order_key][6]
	points[1] = [-7.0, 0.0, -3.0]
	altered.orders[order_key][5] = 12.375
	check(Codec.valid(altered, replica), "changed route and tunnel exit snapshot validates")
	reader.install(replica, altered, 0.0, true, true)
	check(replica.marches._units[0].order != installed, "changed route row installs a fresh order")
	check(replica.marches._units[0].order.departure_distance == 12.375, "installed departure gate changes")
	_network_spans("changed route and tunnel departure distance")
	installed = replica.marches._units[0].order
	var returning: Dictionary = altered.duplicate(true)
	returning.orders[order_key][4] = true
	returning.orders[order_key][1] = returning.orders[order_key][0]
	check(Codec.valid(returning, replica), "returning order row validates")
	reader.install(replica, returning, 0.0, true, true)
	check(replica.marches._units[0].order != installed and replica.marches._units[0].order.returning, "returning row replaces warmed outbound order")
	_network_spans("returning order network install")
	var converted: WarMarches.MarchOrder = host.marches.transfer_order(host.marches._units[0].order, 2)
	for unit: WarMarches.MarchUnit in host.marches._units: unit.order = converted
	var recruited: Dictionary = writer.capture(host, 2)
	check(Codec.valid(recruited, replica), "actual ownership-transfer snapshot validates")
	reader.install(replica, recruited, 0.0, true, true)
	check(replica.marches._units[0].order.faction == 2, "network conversion installs current allegiance")
	_network_spans("actual conversion order network install")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host = null
	replica = null
	geometry_reference.map_definition = WarMapDefinition.new()
	geometry_candidate.map_definition = geometry_reference.map_definition

func _clear_intervals(order: WarMarches.MarchOrder) -> void:
	order.haste_intervals.clear()
	order.slow_intervals.clear()
	order.mist_intervals.clear()

func _timed_six(marches: WarMarches, order: WarMarches.MarchOrder, zone: Dictionary, lanes: Array[float]) -> Dictionary:
	var results: Array[PackedVector2Array] = []
	var begun := Time.get_ticks_usec()
	for lane: float in lanes: results.append(marches._zone_intervals(order, lane, zone))
	var elapsed := float(Time.get_ticks_usec() - begun) / 1000.0
	return {"ms": elapsed, "spans": results}

func _benchmark(length: float, mode: String, round_index: int) -> void:
	var route := _ordinary_route(length / 44.0)
	var lanes := _lanes()
	var old := _new_order(geometry_reference, route)
	var current := _new_order(geometry_candidate, route)
	var zone := {"at": old.sample(old.length * 0.45), "radius": 4.5}
	if mode != "cold_six_lanes":
		_timed_six(geometry_reference, old, zone, lanes)
		_timed_six(geometry_candidate, current, zone, lanes)
	var measurements := {"reference": [], "candidate": []}
	for sample: int in benchmark_samples + benchmark_warmup:
		if mode == "cold_six_lanes":
			old = _new_order(geometry_reference, route)
			current = _new_order(geometry_candidate, route)
		elif mode == "hot_changing_zone":
			zone = {"at": old.sample(old.length * (0.25 + 0.05 * (sample % 10))), "radius": 1.5 + 0.5 * (sample % 7)}
		# Field caches are reset outside timers. Hot cases deliberately retain any
		# lane-independent geometry and lane samples on the same live orders.
		_clear_intervals(old)
		_clear_intervals(current)
		var variants: Array[String] = ["reference", "candidate"]
		if (sample + round_index) % 2 == 1: variants.reverse()
		var results := {}
		for variant: String in variants:
			results[variant] = _timed_six(geometry_reference if variant == "reference" else geometry_candidate, old if variant == "reference" else current, zone, lanes)
			if sample >= benchmark_warmup: measurements[variant].append(results[variant].ms)
		for index: int in lanes.size():
			_exact("micro %s length %.1f sample %d lane %d" % [mode, length, sample, index], results.reference.spans[index], results.candidate.spans[index])
	for variant: String in ["reference", "candidate"]:
		print("ZONE_GEOMETRY_BENCHMARK ", JSON.stringify({"variant": variant, "mode": mode, "round": round_index,
			"route_extent": length, "baked_route_length": old.length, "sample_segments": ceili(old.length / 0.24),
			"lanes_per_batch": lanes.size(), "samples": benchmark_samples, "warmup": benchmark_warmup,
			"six_lane_cpu_ms": _statistics(measurements[variant]), "raw_six_lane_cpu_ms": measurements[variant]}))

func _statistics(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in values: total += value
	return {"n": values.size(), "mean": total / values.size(),
		"p50": sorted[maxi(0, ceili(values.size() * 0.50) - 1)],
		"p95": sorted[maxi(0, ceili(values.size() * 0.95) - 1)],
		"p99": sorted[maxi(0, ceili(values.size() * 0.99) - 1)], "max": sorted[-1]}
