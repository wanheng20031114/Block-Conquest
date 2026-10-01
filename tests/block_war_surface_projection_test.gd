extends SceneTree
## Isolated candidate C2. Only elevated ground reprojection gains an offset check.
## Authored terrain, native Marches scenes, synthetic fixed unit poses.
const MARCHES := preload("res://scenes/block_war/marches.tscn")
const MAPS := preload("res://scripts/block_war/war_map_catalog.gd")
const MAP_IDS: Array[String] = ["highland", "terraces", "switchback", "crown"]
const CASES: Array[String] = ["zero_ground", "mixed_ground", "nonzero_ground", "zero_levitating", "mixed_levitating", "zero_airborne", "nonzero_airborne"]
const POSITION_EPSILON := 0.000002
var rounds := 3
var iterations := 100
var soldiers := 4096
var warmup := 10
var verify_only := false
var readback := false
var checks := 0
var failures: Array[String] = []
var scripts: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# The desktop runner supplies its output directory as a positional argument.
	# Benchmark options are named so that directory never changes the workload.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--rounds="): rounds = int(argument.get_slice("=", 1))
		elif argument.begins_with("--iterations="): iterations = int(argument.get_slice("=", 1))
		elif argument.begins_with("--soldiers="): soldiers = int(argument.get_slice("=", 1))
		elif argument.begins_with("--warmup="): warmup = int(argument.get_slice("=", 1))
		elif argument == "--verify-only": verify_only = true
	if rounds < 1 or iterations < 1 or soldiers < 8 or soldiers > 16384 or warmup < 0:
		printerr("SURFACE_PROJECTION invalid arguments: --rounds=N --iterations=N --soldiers=N --warmup=N [--verify-only]")
		quit(2)
		return
	scripts = {"baseline": load("res://.local/surface-projection/reference.gd"), "candidate": load("res://.local/surface-projection/candidate.gd")}
	if scripts.baseline == null or scripts.candidate == null:
		printerr("SURFACE_PROJECTION missing generated scripts; run tools/benchmark_surface_projection.py")
		quit(2)
		return
	readback = DisplayServer.get_name() != "headless"
	print("SURFACE_PROJECTION_CONTRACT ", JSON.stringify({"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"gpu_readback": readback, "verify_only": verify_only, "position_epsilon_world_units": POSITION_EPSILON,
		"candidate": "C2_elevated_ground_zero_offset",
		"change": "Terrain reprojection additionally requires a nonzero offset; the initial position addition and flat/airborne short-circuit paths are preserved",
		"limits": ["fixed synthetic poses on actual authored terrain, not a full gameplay benchmark",
			"times include the full selected method and identical outer loop overhead",
			"render timing is CPU submission only; no GPU wait inside timer",
			"headless checks render inputs and resource identity; GPU readback only when an actual renderer is active",
			"projection is included in render; the two measurements must not be added",
			"no production source or scene modifications"]}))
	for map_id: String in MAP_IDS:
		var definition: WarMapDefinition = MAPS.find_map(map_id)
		_check(definition.has_elevation() == (map_id != "highland"), map_id + " has the expected flat/elevated surface")
		for scenario: String in CASES:
			await _case(map_id, definition, scenario)
	print("SURFACE_PROJECTION_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _make_marches(script: GDScript, definition: WarMapDefinition, scenario: String) -> Node3D:
	var marches: Node3D = MARCHES.instantiate()
	# Both copies instantiate the same authored scene. Only the root script is
	# substituted before _ready; children, materials and shadows are untouched.
	marches.set_script(script)
	root.add_child(marches)
	marches.map_definition = definition
	marches.send(0, 1, 0, soldiers, PackedVector3Array([Vector3.ZERO, Vector3(500, 0, 0)]))
	var columns := ceili(sqrt(float(soldiers)))
	var half: Vector2 = definition.half_size
	var airborne := scenario.ends_with("airborne")
	var levitating := scenario.ends_with("levitating")
	for index: int in soldiers:
		var unit: RefCounted = marches._units[index]
		var fraction_x := (float(index % columns) + 0.371) / float(columns)
		var fraction_z := (float(index / columns) + 0.619) / float(columns)
		var xz := Vector2(lerpf(-half.x, half.x, fraction_x), lerpf(-half.y, half.y, fraction_z))
		var at: Vector3 = definition.surface_point(Vector3(xz.x, 0, xz.y))
		# Include the exact terrain edge and a nearby exterior point as well as
		# irregular fractional samples crossing native triangle diagonals.
		if index == 0: at = definition.surface_point(Vector3(-half.x, 0, -half.y))
		elif index == 1: at = definition.surface_point(Vector3(half.x + 0.001, 0, half.y + 0.001))
		unit.order.airborne = airborne
		unit.distance = 1.0 + float(index) * 0.01
		unit.position = at + Vector3.UP * (4.0 + sin(index * 0.37) if airborne else (1.3 + sin(index * 0.23) * 0.03 if levitating else 0.0))
		unit.levitation_remaining = 0.6 if levitating else 0.0
		unit.presentation_offset = Vector3.ZERO
		if scenario.begins_with("nonzero") or (scenario.begins_with("mixed") and index % 2 == 1):
			# Include tiny-but-nonzero offsets to reject approximate-zero guards.
			unit.presentation_offset = Vector3(0.00000001, 0, -0.00000001) if index % 7 == 0 else Vector3(sin(index * 0.7) * 0.6, 0.15, cos(index * 0.43) * 0.6)
		unit.heading = Vector3(sin(index * 0.19), 0, cos(index * 0.19))
		unit.gait = float(index) * 0.117
		unit.presentation_gait_offset = 0.07 if index % 3 == 0 else 0.0
		unit.cloaked = index % 4 == 0
		unit.rush_remaining = 1.0 if index % 5 == 0 else 0.0
		unit.pending_departure = index % 31 == 0
		unit.spawn_delay = 0.2 if index % 37 == 0 else 0.0
		unit.alive = index % 41 != 0
	marches._render()
	return marches

func _case(map_id: String, definition: WarMapDefinition, scenario: String) -> void:
	var nodes := {"baseline": _make_marches(scripts.baseline, definition, scenario), "candidate": _make_marches(scripts.candidate, definition, scenario)}
	var label := map_id + "/" + scenario
	var before_baseline := _unit_digest(nodes.baseline)
	var before_candidate := _unit_digest(nodes.candidate)
	_check(before_baseline == before_candidate, label + " starts from identical unit state")
	var baseline_resources := _render_resources(nodes.baseline)
	var candidate_resources := _render_resources(nodes.candidate)
	_check(baseline_resources == candidate_resources, label + " preserves authored mesh/material/shadow configuration")
	var max_error := 0.0
	var nonidentical := 0
	var zero_offsets := 0
	var raised_positions := 0
	for index: int in soldiers:
		var left: Vector3 = nodes.baseline._presentation_position(nodes.baseline._units[index])
		var right: Vector3 = nodes.candidate._presentation_position(nodes.candidate._units[index])
		max_error = maxf(max_error, left.distance_to(right))
		if left != right: nonidentical += 1
		if nodes.baseline._units[index].presentation_offset == Vector3.ZERO: zero_offsets += 1
		if nodes.baseline._units[index].position.y > 0.5: raised_positions += 1
	_check(max_error <= POSITION_EPSILON, label + " actual projection coordinates retain float precision")
	if scenario.begins_with("zero"): _check(zero_offsets == soldiers, label + " all offsets are exactly zero")
	elif scenario.begins_with("nonzero"): _check(zero_offsets == 0, label + " every offset takes the original branch")
	else: _check(zero_offsets > 0 and zero_offsets < soldiers, label + " exercises both branches")
	if definition.has_elevation() or scenario.ends_with("levitating") or scenario.ends_with("airborne"):
		_check(raised_positions > 0, label + " covers nonzero surface/lift heights")
	else:
		_check(raised_positions == 0, label + " exercises the flat ground control")
	var inputs := {"baseline": _render_inputs(nodes.baseline), "candidate": _render_inputs(nodes.candidate)}
	var render_error := _compare_inputs(inputs.baseline, inputs.candidate, label)
	nodes.baseline._render()
	nodes.candidate._render()
	for variant: String in ["baseline", "candidate"]:
		_check(nodes[variant]._multimesh.visible_instance_count == inputs[variant].normal.size(), label + " " + variant + " submits only visible soldiers")
	var gpu_samples := 0
	if readback:
		await RenderingServer.frame_post_draw
		gpu_samples += _verify_readback(nodes.baseline, inputs.baseline, label + " baseline")
		gpu_samples += _verify_readback(nodes.candidate, inputs.candidate, label + " candidate")
	var timings: Array[Dictionary] = []
	if not verify_only:
		for round_index: int in rounds:
			var samples := {"baseline": {"projection": [], "render": []}, "candidate": {"projection": [], "render": []}}
			var checksums := {"baseline": Vector3.ZERO, "candidate": Vector3.ZERO}
			for iteration: int in iterations + warmup:
				var order: Array = ["baseline", "candidate"] if (iteration + round_index) % 2 == 0 else ["candidate", "baseline"]
				for variant: String in order:
					var node: Node3D = nodes[variant]
					var begun := Time.get_ticks_usec()
					var checksum := Vector3.ZERO
					for unit: RefCounted in node._units: checksum += node._presentation_position(unit)
					var projection_ms := float(Time.get_ticks_usec() - begun) / 1000.0
					begun = Time.get_ticks_usec()
					node._render()
					var render_ms := float(Time.get_ticks_usec() - begun) / 1000.0
					checksums[variant] = checksum
					if iteration >= warmup:
						samples[variant].projection.append(projection_ms)
						samples[variant].render.append(render_ms)
			var stats := {}
			for variant: String in ["baseline", "candidate"]:
				_check(checksums[variant].is_finite(), label + " " + variant + " produces finite timed results")
				stats[variant] = {"projection": _statistics(samples[variant].projection), "render": _statistics(samples[variant].render)}
			timings.append({"round": round_index, "stages": stats, "raw_samples_ms": samples})
	_check(_unit_digest(nodes.baseline) == before_baseline and _unit_digest(nodes.candidate) == before_candidate, label + " projection/render do not mutate units")
	_check(_render_resources(nodes.baseline) == baseline_resources and _render_resources(nodes.candidate) == candidate_resources, label + " rendering preserves materials and shadow settings")
	print("SURFACE_PROJECTION ", JSON.stringify({"map": map_id, "case": scenario, "soldiers": soldiers,
		"zero_offsets": zero_offsets, "raised_positions": raised_positions, "max_position_error": max_error,
		"nonidentical_positions": nonidentical, "max_render_input_position_error": render_error, "gpu_readback_samples": gpu_samples,
		"position_epsilon": POSITION_EPSILON, "timings": timings}))
	nodes.baseline.free()
	nodes.candidate.free()
	await process_frame

func _render_inputs(marches: Node3D) -> Dictionary:
	var result := {"normal": []}
	for unit: RefCounted in marches._units:
		if not unit.is_exposed() or unit.cloaked: continue
		var yaw := atan2(-unit.heading.x, -unit.heading.z)
		var transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * marches.MODEL_SCALE), marches._presentation_position(unit))
		var color: Color = marches.FACTION_COLORS[unit.order.faction].srgb_to_linear()
		var gait: float = unit.gait + unit.presentation_gait_offset
		color.a = -(gait + 1.0) if unit.rush_remaining > 0.0 else gait
		result.normal.append([transform, color])
	return result

func _compare_inputs(first: Dictionary, second: Dictionary, label: String) -> float:
	var max_error := 0.0
	var exact_other := true
	for bucket: String in ["normal"]:
		_check(first[bucket].size() == second[bucket].size() and not first[bucket].is_empty(), label + " keeps nonempty " + bucket + " bucket")
		for index: int in first[bucket].size():
			var left: Array = first[bucket][index]
			var right: Array = second[bucket][index]
			max_error = maxf(max_error, left[0].origin.distance_to(right[0].origin))
			exact_other = exact_other and left[0].basis == right[0].basis and left[1] == right[1]
	_check(max_error <= POSITION_EPSILON and exact_other, label + " render inputs retain orientation/scale/custom data and position precision")
	return max_error

func _verify_readback(marches: Node3D, inputs: Dictionary, label: String) -> int:
	var samples := 0
	var errors := 0
	for bucket: String in ["normal"]:
		var mesh: MultiMesh = marches._multimesh
		_check(mesh.visible_instance_count == inputs[bucket].size(), label + " actual visible count matches " + bucket)
		for index: int in inputs[bucket].size():
			var expected: Transform3D = inputs[bucket][index][0]
			var actual := mesh.get_instance_transform(index)
			var color: Color = mesh.get_instance_custom_data(index)
			var expected_color: Color = inputs[bucket][index][1]
			if actual.origin.distance_to(expected.origin) > POSITION_EPSILON or not actual.basis.is_equal_approx(expected.basis) or not color.is_equal_approx(expected_color): errors += 1
			samples += 1
	_check(errors == 0 and samples > 0, label + " actual GPU-backed MultiMesh agrees with render inputs")
	return samples

func _render_resources(marches: Node3D) -> Array:
	var result: Array = []
	for child: String in ["Militia"]:
		var node: MultiMeshInstance3D = marches.get_node(child)
		result.append([node.material_override.get_instance_id(), node.multimesh.mesh.get_instance_id(), node.cast_shadow,
			node.multimesh.transform_format, node.multimesh.use_custom_data, node.multimesh.use_colors, node.multimesh.custom_aabb,
			node.physics_interpolation_mode])
	return result

func _unit_digest(marches: Node3D) -> String:
	var values: Array = []
	for unit: RefCounted in marches._units:
		values.append([unit.unit_id, unit.position, unit.presentation_offset, unit.heading, unit.gait, unit.presentation_gait_offset,
			unit.distance, unit.lane, unit.levitation_remaining, unit.rush_remaining, unit.cloaked, unit.pending_departure,
			unit.spawn_delay, unit.alive, unit.order.airborne])
	return var_to_bytes(values).hex_encode().sha256_text()

func _statistics(values: Array) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value: float in values: total += value
	return {"count": values.size(), "mean_ms": total / values.size(), "p50_ms": ordered[ceili(values.size() * 0.5) - 1],
		"p95_ms": ordered[ceili(values.size() * 0.95) - 1], "p99_ms": ordered[ceili(values.size() * 0.99) - 1], "max_ms": ordered.back()}

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL SURFACE_PROJECTION ", label)
