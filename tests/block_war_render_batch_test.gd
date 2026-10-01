extends "res://tests/block_war_replication_test.gd"
## Experimental pair only: generate dependencies with benchmark_render_batch.py.
## Assertions, event capture, snapshots and GPU readback are outside CPU samples.
const EXPERIMENT := "res://.local/render-batch/"
const ROUTE := [Vector3(-20, 0, 0), Vector3(480, 0, 0)]
var sample_count := 80
var warmup_count := 8
var soldier_count := 2048
var round_index := 0
var capture_events := false
var readback_enabled := false
var readback_samples := 0

func configuration() -> Dictionary:
	var value := super.configuration()
	value.match_id = "render-batch-experiment"
	# A single eligible human teammate makes surrender deterministic.
	value.slots[3].kind = "human"
	value.slots[3].controller = "human"
	value.slots[3].player_id = 103
	return value

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func(): quit(3))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--samples="): sample_count = int(argument.get_slice("=", 1))
		elif argument.begins_with("--warmup="): warmup_count = int(argument.get_slice("=", 1))
		elif argument.begins_with("--soldiers="): soldier_count = int(argument.get_slice("=", 1))
		elif argument.begins_with("--round="): round_index = int(argument.get_slice("=", 1))
	check(sample_count > 0 and warmup_count >= 0 and soldier_count > 0, "positive benchmark arguments")
	if not failures.is_empty(): quit(1); return
	root.get_node("Session").block_war_map_id = "highland"
	readback_enabled = DisplayServer.get_name() != "headless"
	print("RENDER_BATCH_MODE ", "real_multimesh_readback" if readback_enabled else "headless_render_inputs_only_no_gpu_acceptance")
	for label: String in ["ordinary", "simulate_substeps", "dense_hits_dispatch", "host_eight_steps"]:
		await _case(label)
	await _boundaries()
	print("RENDER_BATCH checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _fixture(variant: String, amount: int, networked: bool) -> Dictionary:
	seed(78613)
	var game: Node3D = load(EXPERIMENT + variant + "/block_war.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.audio.muted = true
	game.ai_enabled = false
	game.configure_match(configuration(), 105)
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
		building.population = building.capacity
	_add_background(game, amount)
	var events: Array = []
	game.presentation_event.connect(func(kind: String, payload: Dictionary):
		if capture_events: events.append(["presentation", kind, payload.duplicate(true)]))
	game.marches.unit_arrived.connect(func(target_id: int, faction: int, strength: float, bonus: float, origin: bool):
		if capture_events: events.append(["arrived", target_id, faction, strength, bonus, origin]))
	game.marches.unit_defeated.connect(func(at: Vector3, heading: Vector3, faction: int, impulse: Vector3, burning: bool):
		if capture_events: events.append(["defeated", at, heading, faction, impulse, burning]))
	game.marches.combat_death.connect(func(faction: int, target: int, killer: int):
		if capture_events: events.append(["combat_death", faction, target, killer]))
	game.marches.departure_queue_changed.connect(func(source: int, faction: int, change: int):
		if capture_events: events.append(["departure_queue", source, faction, change]))
	game.marches.unit_departed.connect(func(source: int, faction: int):
		if capture_events: events.append(["departed", source, faction]))
	var value := {"game": game, "events": events, "codec": Codec.new(), "networked": networked,
		"coordinator": null, "wire": null, "command_seq": 0, "variant": variant}
	if networked:
		value.wire = make_wire(105)
		value.coordinator = load(EXPERIMENT + variant + "/war_network_match.gd").new()
		value.coordinator.setup(game, value.wire)
		# Finish the ordinary initial snapshot queue before timing host ticks.
		for _index: int in 200:
			value.coordinator._flush_outbox(0.1)
			value.coordinator._flush_anchors(0.1)
			value.wire.sent.clear()
			if value.coordinator._outbox.is_empty() and value.coordinator._anchor_outbox.is_empty(): break
	return value

func _add_background(game: Node3D, amount: int) -> void:
	if amount <= 0: return
	var first: int = game.marches._units.size()
	game.marches.send(0, 1, 0, amount, PackedVector3Array(ROUTE))
	for index: int in range(first, game.marches._units.size()):
		var unit: WarMarches.MarchUnit = game.marches._units[index]
		unit.distance = 8.0 + float(index % 256) * 0.12
		game.marches._update_pose(unit)
	game.marches._render()

func _pair(amount: int, networked: bool) -> Array[Dictionary]:
	return [_fixture("reference", amount, networked), _fixture("candidate", amount, networked)]

func _case(label: String) -> void:
	var pair := _pair(soldier_count, label in ["dense_hits_dispatch", "host_eight_steps"])
	capture_events = true
	for frame: int in 8:
		for fixture: Dictionary in pair:
			_stage(fixture, label)
			seed(91271 + frame)
			_operation(fixture, label)
		await _compare(pair, "%s correctness %d" % [label, frame])
	if label == "dense_hits_dispatch":
		check(pair[0].events.any(func(event: Array): return event[0] == "combat_death"), "dense correctness actually includes projectile deaths")
		check(pair[0].events.any(func(event: Array): return event[0] == "departed"), "dense correctness actually includes queued departures")
		check(pair[0].events.any(func(event: Array): return event[0] == "presentation" and event[1] == "dispatch"), "dense correctness actually includes dispatch presentation")
	for fixture: Dictionary in pair: fixture.events.clear()
	capture_events = false
	var samples: Array[Array] = [[], []]
	var commits := [0, 0]
	var requests := [0, 0]
	var ticks_before := [0, 0]
	for frame: int in warmup_count + sample_count:
		for fixture: Dictionary in pair:
			_stage(fixture, label)
			fixture.game.marches.render_calls = 0
			fixture.game.marches.render_requests = 0
		if frame == warmup_count:
			for index: int in 2:
				if pair[index].networked: ticks_before[index] = pair[index].coordinator._tick
		var order := [0, 1] if (frame + round_index) % 2 == 0 else [1, 0]
		for index: int in order:
			seed(71381 + frame)
			var began := Time.get_ticks_usec()
			_operation(pair[index], label)
			var cpu_ms := float(Time.get_ticks_usec() - began) / 1000.0
			if frame >= warmup_count:
				samples[index].append(cpu_ms)
				commits[index] += pair[index].game.marches.render_calls
				requests[index] += pair[index].game.marches.render_requests
		# Real-renderer runs yield after both samples. Rendering and waiting are
		# excluded from CPU time; this remains a CPU benchmark, not GPU timing.
		if readback_enabled: await RenderingServer.frame_post_draw
	await _compare(pair, label + " performance final")
	check(requests[0] == requests[1], label + " issues exactly the same original render requests")
	check(commits[1] == sample_count, label + " commits once per simulated API boundary")
	if label == "ordinary": check(commits[0] == commits[1], "ordinary single tick needs no extra render")
	else: check(commits[0] > commits[1], label + " actually avoids repeated render work")
	if label == "host_eight_steps":
		for index: int in 2: check(pair[index].coordinator._tick - ticks_before[index] == sample_count * 8, "host catchup executes eight real fixed ticks per sample")
	var reference_mean := _mean(samples[0])
	var candidate_mean := _mean(samples[1])
	var metadata := {"case": label, "round": round_index, "samples": sample_count, "warmup": warmup_count,
		"initial_soldiers": soldier_count, "final_units": pair[0].game.marches._units.size(),
		"mode": "real_multimesh_readback" if readback_enabled else "headless_inputs",
		"multimesh_readback_samples": readback_samples, "reference_mean_ms": reference_mean,
		"candidate_mean_ms": candidate_mean, "reference_p95_ms": _percentile(samples[0], 0.95),
		"candidate_p95_ms": _percentile(samples[1], 0.95), "mean_speedup": reference_mean / maxf(candidate_mean, 0.000001),
		"reference_render_calls": commits[0], "candidate_render_calls": commits[1], "render_requests": requests[0],
		"rule_hash": Codec.digest(pair[0].codec.capture(pair[0].game, 0)),
		"measurement": "synchronous operation CPU only; staging/assertions/snapshots/event trace/readback excluded"}
	print("RENDER_BATCH_METRICS ", JSON.stringify(metadata))
	await _dispose(pair)

func _stage(fixture: Dictionary, label: String) -> void:
	if fixture.networked: fixture.wire.sent.clear()
	if label != "dense_hits_dispatch": return
	var game: Node3D = fixture.game
	var available := 0
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.order.faction == 0 and unit.is_exposed(): available += 1
	# Restore only the eight fixture victims outside the measured operation.
	_add_background(game, maxi(0, maxi(soldier_count, 8) - available))
	var staged := 0
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.order.faction != 0 or not unit.is_exposed(): continue
		unit.reserved = true
		unit.intercepted_by = 1
		var at := unit.position + Vector3(0.0, 1.0, -2.0)
		game.projectiles.append({"target": unit, "at": at, "position": at, "previous": at,
			"to": unit.position + Vector3(0, 0.65, 0), "tracking": true, "age": 0.0, "duration": 0.005})
		staged += 1
		if staged == 8: break
	game.by_id[5].population = float(game.by_id[5].queued_population + 12)
	_command(fixture, {"type": "dispatch", "source": 5, "target": 11, "percent": 100})

func _operation(fixture: Dictionary, label: String) -> void:
	match label:
		"ordinary": fixture.game.simulate(1.0 / 60.0)
		"simulate_substeps": fixture.game.simulate(0.2)
		"dense_hits_dispatch": fixture.coordinator.process(Coordinator.STEP * 4.0)
		"host_eight_steps": fixture.coordinator.process(Coordinator.STEP * 8.0)

func _command(fixture: Dictionary, command: Dictionary, player: int = 105) -> void:
	fixture.command_seq += 1
	fixture.coordinator._receive_command(player, {"seq": fixture.command_seq, "epoch": 1, "command": command})

func _compare(pair: Array[Dictionary], label: String) -> void:
	if readback_enabled: await RenderingServer.frame_post_draw
	var reference: Dictionary = pair[0].codec.capture(pair[0].game, 0)
	var candidate: Dictionary = pair[1].codec.capture(pair[1].game, 0)
	check(reference == candidate, label + " exact rule state")
	check(Codec.digest(reference) == Codec.digest(candidate), label + " canonical rule digest")
	check(_unit_state(pair[0].game.marches) == _unit_state(pair[1].game.marches), label + " complete ordered unit pose/status state")
	check(pair[0].events == pair[1].events, label + " signal and presentation event order/payload")
	var first_inputs := _render_inputs(pair[0].game.marches)
	var second_inputs := _render_inputs(pair[1].game.marches)
	check(first_inputs == second_inputs, label + " last-frame transform/color/gait inputs")
	for index: int in 2:
		var fixture: Dictionary = pair[index]
		var marches: Node3D = fixture.game.marches
		check(marches.render_batch_depth == 0 and not marches.render_pending, label + " returns with closed clean batch " + fixture.variant)
		if readback_enabled: _check_readback(marches, first_inputs if index == 0 else second_inputs, label + " " + fixture.variant)
	if pair[0].networked:
		var a: RefCounted = pair[0].coordinator
		var b: RefCounted = pair[1].coordinator
		check(a._published == b._published and a._seq == b._seq and a._tick == b._tick, label + " host fact stream and fixed ticks")
		check(a.sent_rule_bytes == b.sent_rule_bytes and a._command_results == b._command_results, label + " byte accounting and command results")
		check(pair[0].wire.invalid_packets == 0 and pair[1].wire.invalid_packets == 0, label + " valid transport packets")

func _unit_state(marches: Node3D) -> Array:
	var rows: Array = []
	for unit: WarMarches.MarchUnit in marches._units:
		rows.append([unit.unit_id, unit.order.order_id, unit.alive, unit.reserved, unit.intercepted_by,
			unit.distance, unit.lane, unit.position, unit.presentation_offset, unit.presentation_gait_offset,
			unit.heading, unit.gait, unit.spawn_delay, unit.pending_departure, unit.departure_sequence,
			unit.rush_remaining, unit.levitation_remaining, unit.cloaked, unit.weakened])
	return rows

func _render_inputs(marches: Node3D) -> Array[Array]:
	var pools: Array[Array] = [[]]
	for unit: WarMarches.MarchUnit in marches._units:
		if not unit.is_exposed() or unit.cloaked: continue
		var yaw := atan2(-unit.heading.x, -unit.heading.z)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * WarMarches.MODEL_SCALE)
		var transform := Transform3D(basis, marches._presentation_position(unit))
		var color := WarMarches.FACTION_COLORS[unit.order.faction].srgb_to_linear()
		var gait := unit.gait + unit.presentation_gait_offset
		color.a = -(gait + 1.0) if unit.rush_remaining > 0.0 else gait
		pools[0].append([transform, color])
	return pools

func _check_readback(marches: Node3D, pools: Array[Array], label: String) -> void:
	var meshes: Array[MultiMesh] = [marches._multimesh]
	for pool: int in meshes.size():
		var mesh: MultiMesh = meshes[pool]
		var valid := mesh.visible_instance_count == pools[pool].size()
		for index: int in mini(maxi(0, mesh.visible_instance_count), pools[pool].size()):
			readback_samples += 1
			var expected: Transform3D = pools[pool][index][0]
			var color: Color = pools[pool][index][1]
			valid = valid and mesh.get_instance_transform(index).is_equal_approx(expected)
			valid = valid and mesh.get_instance_custom_data(index).is_equal_approx(color)
		check(valid, "%s real MultiMesh pool %d matches last-frame inputs" % [label, pool])

func _boundaries() -> void:
	var pair := _pair(32, true)
	capture_events = true
	# Guarded and sub-tick calls must not leave a batch open or invent a render.
	for fixture: Dictionary in pair:
		var before: int = fixture.game.marches.render_calls
		fixture.game.simulate(0.0)
		fixture.coordinator.process(0.0)
		check(fixture.game.marches.render_calls == before, fixture.variant + " zero step has no render")
	await _compare(pair, "zero-step boundary")
	# Direct APIs still commit immediately when no enclosing transaction exists.
	for fixture: Dictionary in pair:
		var marches: Node3D = fixture.game.marches
		var before: int = marches.render_calls
		marches.tick(0.01)
		check(marches.render_calls == before + 1, fixture.variant + " standalone tick renders immediately")
		before = marches.render_calls
		marches.send(0, 1, 0, 3, PackedVector3Array(ROUTE))
		check(marches.render_calls == before + 1, fixture.variant + " standalone send renders immediately")
		var unit: WarMarches.MarchUnit = marches._units[0]
		unit.intercepted_by = 1
		before = marches.render_calls
		marches.hit_target(unit, Vector3.FORWARD)
		check(marches.render_calls == before + 1, fixture.variant + " standalone hit renders immediately")
	await _compare(pair, "standalone APIs")
	# Nested batching and a non-default pool/shader encoding remain equivalent.
	for fixture: Dictionary in pair:
		var marches: Node3D = fixture.game.marches
		var before: int = marches.render_calls
		marches.begin_render_batch()
		marches.begin_render_batch()
		var exposed: Array[WarMarches.MarchUnit] = []
		for unit: WarMarches.MarchUnit in marches._units:
			if unit.is_exposed(): exposed.append(unit)
		check(exposed.size() >= 2, fixture.variant + " fixture has exposed cloak and rush targets")
		exposed[0].cloaked = true
		exposed[1].rush_remaining = 1.0
		exposed[1].presentation_offset = Vector3(0.05, 0, 0.1)
		exposed[1].presentation_gait_offset = 0.2
		marches._render()
		marches._render()
		marches.end_render_batch()
		if fixture.variant == "candidate": check(marches.render_calls == before and marches.render_pending, "inner batch keeps dirty render until outer end")
		marches.end_render_batch()
		check(marches.render_calls == before + (1 if fixture.variant == "candidate" else 2), fixture.variant + " nested batch expected commits")
		var inputs := _render_inputs(marches)
		check(marches._units.filter(func(unit: WarMarches.MarchUnit): return unit.is_exposed() and not unit.cloaked).size() == inputs[0].size(), fixture.variant + " nested boundary excludes cloaked soldiers from rendering")
		check(inputs[0].any(func(row: Array): return row[1].a < 0.0), fixture.variant + " nested boundary actually exercises rush shader encoding")
	await _compare(pair, "nested cloaked/rush pool")
	# A dispatch followed by pause breaks Host's fixed-step loop before simulate.
	for fixture: Dictionary in pair:
		fixture.game.by_id[5].population = 30.0
		_command(fixture, {"type": "dispatch", "source": 5, "target": 11, "percent": 100})
		_command(fixture, {"type": "pause", "paused": true})
		var before: int = fixture.game.marches.render_calls
		fixture.coordinator.process(Coordinator.STEP * 8.0)
		check(fixture.game.match_paused and not fixture.game.marches._units.is_empty(), fixture.variant + " dispatch then pause executed")
		check(fixture.game.marches.render_calls == before + 1, fixture.variant + " pause break flushes dispatch")
	await _compare(pair, "host dispatch then pause break")
	# While paused, surrender changes troop ownership without any simulate call.
	for fixture: Dictionary in pair:
		_command(fixture, {"type": "surrender"})
		var before: int = fixture.game.marches.render_calls
		seed(6191)
		fixture.coordinator.process(0.0)
		check(fixture.game.has_surrendered(5) and not fixture.game.finished, fixture.variant + " paused surrender transfers to teammate")
		check(fixture.game.marches.render_calls == before + 1, fixture.variant + " paused command flushes changed colors")
	await _compare(pair, "paused host command branch")
	# Clear keeps its native immediate visible-count reset; the final dirty flush
	# must render the empty state, not resurrect stale instances after finishing.
	for fixture: Dictionary in pair:
		var marches: Node3D = fixture.game.marches
		marches.begin_render_batch()
		marches.send(0, 1, 0, 4, PackedVector3Array(ROUTE))
		marches.clear()
		fixture.game._finish_match(0)
		marches.end_render_batch()
		var before: int = marches.render_calls
		fixture.game.simulate(1.0)
		fixture.coordinator.process(1.0)
		check(marches.render_calls == before and marches._units.is_empty(), fixture.variant + " finished empty tail stays empty")
		check(marches._multimesh.visible_instance_count == 0, fixture.variant + " empty visible pool cleared")
	await _compare(pair, "finished empty dirty tail")
	await _dispose(pair)
	capture_events = false

func _dispose(pair: Array[Dictionary]) -> void:
	for fixture: Dictionary in pair:
		await fixture.game.prepare_shutdown()
		fixture.game.free()
		if fixture.networked: fixture.wire.free()

func _mean(values: Array) -> float:
	var total := 0.0
	for value: float in values: total += value
	return total / maxi(1, values.size())

func _percentile(values: Array, fraction: float) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * fraction) - 1, 0, ordered.size() - 1)]
