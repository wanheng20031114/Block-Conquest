extends "res://tests/block_war_replication_test.gd"
## Full _render CPU A/B; native MultiMesh resource readback is a separate mode.
## Resource getters do not verify pixels; frame_post_draw is not a GPU fence.
const CANDIDATES := "res://.local/multiplayer-candidates/render-upload/"
var native_renderer := false
var verify_mode := true
var benchmark_rounds := 3
var benchmark_frames := 120
var benchmark_warmup := 30
var benchmark_sizes: Array[int] = [512, 4096]
var reference_states := {}
var reference_readback := {}

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="): verify_mode = argument.get_slice("=", 1) == "verify"
		if argument.begins_with("--rounds="): benchmark_rounds = int(argument.get_slice("=", 1))
		if argument.begins_with("--frames="): benchmark_frames = int(argument.get_slice("=", 1))
		if argument.begins_with("--warmup="): benchmark_warmup = int(argument.get_slice("=", 1))
		if argument.begins_with("--sizes="):
			benchmark_sizes.clear()
			for size: String in argument.get_slice("=", 1).split(","): benchmark_sizes.append(int(size))
	native_renderer = DisplayServer.get_name() != "headless"
	root.get_node("Session").block_war_map_id = "highland"
	if verify_mode:
		await _verify("baseline")
		await _verify("candidate")
	else:
		for round_index: int in benchmark_rounds:
			var order: Array = ["baseline", "candidate"] if round_index % 2 == 0 else ["candidate", "baseline"]
			for count: int in benchmark_sizes:
				for mixture: String in ["ordinary", "mixed"]:
					for variant: String in order:
						await _benchmark(variant, count, mixture, round_index)
	print("UPLOAD_AB_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _make_variant(variant: String) -> Node3D:
	var game: Node3D = load("res://scenes/block_war/block_war.tscn").instantiate()
	game.get_node("Marches").set_script(load(CANDIDATES + variant + ".gd"))
	root.add_child(game)
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.configure_match(configuration(), 105)
	return game

func _populate(marches: WarMarches, count: int, mixture: String, filtering: bool = false) -> void:
	# Keep previous visible counts and unused resource tail data: _render itself must
	# hide emptied streams and shrink the visible range without stale soldiers.
	marches._units.clear()
	marches._next_order_id = 1
	marches._next_unit_id = 1
	var orders: Array[WarMarches.MarchOrder] = []
	for faction: int in 6:
		var z := -15.0 + faction * 5.5
		var route := PackedVector3Array([Vector3(-32, 0, z), Vector3(-14, 0, z + 6), Vector3(10, 0, z - 5), Vector3(34, 0, z)])
		var order := marches._make_order(faction, faction + 6, faction, route)
		order.returning = faction == 1
		order.airborne = faction == 3
		orders.append(order)
	for index: int in count:
		var unit := WarMarches.MarchUnit.new()
		unit.unit_id = index + 1
		unit.order = orders[index % 6]
		unit.distance = 4.0 + fposmod(index * 0.237, unit.order.length - 12.0)
		unit.lane = (index % 6 - 2.5) * WarMarches.COLUMN_SPACING
		unit.cloaked = mixture == "cloaked" or (mixture == "mixed" and index % 3 == 0)
		unit.rush_remaining = 1.5 if index % 7 == 0 else 0.0
		unit.levitation_remaining = 1.0 if index % 11 == 0 else 0.0
		unit.gait = index * 0.21
		unit.presentation_offset = Vector3(sin(index * 0.43) * 0.22, 0, cos(index * 0.3) * 0.17)
		unit.presentation_gait_offset = sin(index * 0.17) * 0.1
		if filtering:
			match index % 13:
				0: unit.alive = false
				1: unit.pending_departure = true
				2: unit.distance = -0.5
				3: unit.spawn_delay = 0.2
		marches._update_pose(unit)
		marches._units.append(unit)
	marches._ensure_capacity(count)

func _advance_inputs(marches: WarMarches) -> void:
	for unit: WarMarches.MarchUnit in marches._units:
		unit.distance += WarMarches.SPEED / 60.0
		unit.gait += 0.16
		unit.presentation_offset *= 0.997
		unit.presentation_gait_offset *= 0.997
		marches._update_pose(unit)

func _state_hash(marches: WarMarches) -> String:
	var rows: Array = []
	for unit: WarMarches.MarchUnit in marches._units:
		rows.append([unit.unit_id, unit.order.order_id, unit.order.faction, unit.order.returning, unit.order.airborne,
			unit.alive, unit.reserved, unit.intercepted_by, unit.distance, unit.lane, unit.position, unit.heading,
			unit.presentation_offset, unit.presentation_gait_offset, unit.gait, unit.spawn_delay, unit.pending_departure,
			unit.departure_sequence, unit.rush_remaining, unit.levitation_remaining, unit.cloaked, unit.weakened])
	return var_to_bytes(rows).hex_encode().sha256_text()

func _floats(transform: Transform3D, custom: Color) -> PackedFloat32Array:
	# Explicit documented row-major 3x4 matrix + unconstrained custom RGBA.
	return PackedFloat32Array([
		transform.basis.x.x, transform.basis.y.x, transform.basis.z.x, transform.origin.x,
		transform.basis.x.y, transform.basis.y.y, transform.basis.z.y, transform.origin.y,
		transform.basis.x.z, transform.basis.y.z, transform.basis.z.z, transform.origin.z,
		custom.r, custom.g, custom.b, custom.a])

func _expected(marches: WarMarches) -> Array[PackedFloat32Array]:
	var streams: Array[PackedFloat32Array] = [PackedFloat32Array()]
	for unit: WarMarches.MarchUnit in marches._units:
		if not unit.is_exposed() or unit.cloaked: continue
		var yaw := atan2(-unit.heading.x, -unit.heading.z)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * WarMarches.MODEL_SCALE)
		var color := WarMarches.FACTION_COLORS[unit.order.faction].srgb_to_linear()
		var gait := unit.gait + unit.presentation_gait_offset
		color.a = -(gait + 1.0) if unit.rush_remaining > 0.0 else gait
		streams[0].append_array(_floats(Transform3D(basis, marches._presentation_position(unit)), color))
	return streams

func _native_readback(mesh: MultiMesh) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for index: int in mesh.visible_instance_count:
		values.append_array(_floats(mesh.get_instance_transform(index), mesh.get_instance_custom_data(index)))
	return values

func _compare_stream(a: PackedFloat32Array, b: PackedFloat32Array, label: String) -> int:
	check(a.size() == b.size(), label + " float count")
	var errors := 0
	for index: int in mini(a.size(), b.size()):
		if absf(a[index] - b[index]) > 0.0001: errors += 1
	check(errors == 0, label + " every visible transform/custom float; errors=" + str(errors))
	return mini(a.size(), b.size())

func _verify(variant: String) -> void:
	var game := _make_variant(variant)
	var marches: WarMarches = game.marches
	var float_checks := 0
	var cases: Array = [["one", 1, "ordinary", false], ["all_cloaked", 96, "cloaked", false],
		["mixed", 4096, "mixed", false], ["filtered", 257, "mixed", true],
		["expanded", 4097, "ordinary", false], ["expanded_cloaked", 4097, "cloaked", false], ["shrink", 1, "ordinary", false],
		["empty", 0, "mixed", false], ["repopulate", 96, "mixed", false]]
	for row: Array in cases:
		var label: String = row[0]
		_populate(marches, row[1], row[2], row[3])
		var before := _state_hash(marches)
		var expected := _expected(marches)
		marches._render()
		check(_state_hash(marches) == before, variant + " " + label + " render never mutates unit state")
		if native_renderer: await RenderingServer.frame_post_draw
		var meshes: Array[MultiMesh] = [marches._multimesh]
		for index: int in meshes.size():
			var key := label + ":" + str(index)
			var mesh := meshes[index]
			check(mesh.instance_count == (8192 if label in ["expanded", "expanded_cloaked", "shrink", "empty", "repopulate"] else 4096), variant + " " + key + " capacity")
			check(mesh.visible_instance_count == expected[index].size() / 16, variant + " " + key + " visibility")
			if native_renderer:
				var native := _native_readback(mesh)
				float_checks += _compare_stream(native, expected[index], variant + " " + key + " native resource expected")
				if variant == "baseline": reference_readback[key] = native
				else: float_checks += _compare_stream(native, reference_readback[key], variant + " " + key + " native A/B")
			if variant == "candidate":
				var buffer: PackedFloat32Array = marches.get("_normal_upload")
				check(buffer.size() == mesh.instance_count * 16, key + " full-capacity CPU buffer")
				float_checks += _compare_stream(buffer.slice(0, expected[index].size()), expected[index], key + " packed CPU expected")
		if variant == "baseline": reference_states[label] = before
		else: check(before == reference_states[label], label + " exact A/B rule and presentation inputs")
	var report := _context(variant)
	report.merge({"mode": "native_multimesh_resource_readback_after_render" if native_renderer else "cpu_pack_only_no_native_renderer_proof",
		"cases": cases.size(), "float_comparisons": float_checks, "final_state_hash": _state_hash(marches),
		"capacity_each": marches._multimesh.instance_count, "failures": failures.size()})
	print("UPLOAD_AB ", JSON.stringify(report))
	await game.prepare_shutdown()
	game.free()

func _benchmark(variant: String, count: int, mixture: String, round_index: int) -> void:
	var game := _make_variant(variant)
	var marches: WarMarches = game.marches
	_populate(marches, count, mixture)
	var pose_times: Array[float] = []
	var render_times: Array[float] = []
	var total_times: Array[float] = []
	var wall_times: Array[float] = []
	for frame: int in benchmark_warmup + benchmark_frames:
		var begin := Time.get_ticks_usec()
		_advance_inputs(marches)
		var posed := Time.get_ticks_usec()
		# Timed render includes all basis/color construction, float packing and upload.
		# There are no native getters, state hashes or correctness checks in this loop.
		marches._render()
		var submitted := Time.get_ticks_usec()
		if native_renderer: await RenderingServer.frame_post_draw
		var ended := Time.get_ticks_usec()
		if frame >= benchmark_warmup:
			pose_times.append((posed - begin) / 1000.0)
			render_times.append((submitted - posed) / 1000.0)
			total_times.append((submitted - begin) / 1000.0)
			wall_times.append((ended - begin) / 1000.0)
	var state := _state_hash(marches)
	var key := "%d:%s:%d" % [count, mixture, round_index]
	if reference_states.has(key): check(state == reference_states[key], key + " A/B final state hash")
	else: reference_states[key] = state
	check(marches._multimesh.visible_instance_count == marches._units.filter(func(unit: WarMarches.MarchUnit): return unit.is_exposed() and not unit.cloaked).size(), variant + " only exposed non-cloaked units are visible")
	var report := _context(variant)
	report.merge({"mode": "performance_no_readbacks", "round": round_index, "soldiers": count, "mixture": mixture,
		"warmup_frames": benchmark_warmup, "measured_frames": benchmark_frames,
		"pose_cpu_ms": _statistics(pose_times), "render_construct_pack_upload_cpu_ms": _statistics(render_times),
		"pose_and_render_cpu_ms": _statistics(total_times), "wall_frame_ms": _statistics(wall_times),
		"final_state_hash": state, "visible_normal": marches._multimesh.visible_instance_count,
		"capacity_each": marches._multimesh.instance_count,
		"additional_cpu_buffers_bytes": marches._multimesh.instance_count * 16 * 4 if variant == "candidate" else 0})
	print("UPLOAD_AB ", JSON.stringify(report))
	await game.prepare_shutdown()
	game.free()

func _context(variant: String) -> Dictionary:
	return {"variant": variant, "display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info().string,
		"engine_max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode() if native_renderer else -1,
		"frame_limit_note": "CLI requests 24 FPS; settings can override it. Engine max FPS and measured wall timing describe this run; no end-to-end 60 FPS acceptance." if native_renderer else "dummy renderer CPU experiment only",
		"readback_and_timing_scope": "MultiMesh getters verify native resource data, not pixels or completed GPU execution. frame_post_draw is not a GPU fence; timed _render ends before the frame wait."}

func _statistics(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value: float in values: sum += value
	return {"samples": values.size(), "mean": sum / values.size(), "median": sorted[sorted.size() / 2],
		"p95": sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)],
		"p99": sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.99) - 1)], "max": sorted[-1]}
