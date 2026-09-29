extends "res://tests/block_war_replication_test.gd"
## Run via tools/benchmark_multiplayer.py, which generates a same-gameplay reference.
var sample_frames := 120
var soldier_count := 4096

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var rounds := int(args[0]) if args.size() > 0 else 3
	if args.size() > 1: sample_frames = int(args[1])
	if args.size() > 2: soldier_count = int(args[2])
	root.get_node("Session").block_war_map_id = "highland"
	var reference: GDScript = load("res://.local/multiplayer-ab/reference/war_network_match.gd")
	var variants := {"A": reference, "B": Coordinator}
	for round_index: int in rounds:
		for fields: bool in [false, true]:
			var pair := {}
			# Reverse pair order to reduce warm-up / system-load bias.
			for label: String in (["A", "B"] if round_index % 2 == 0 else ["B", "A"]):
				pair[label] = await run_case(variants[label], label, round_index, fields)
			for key: String in ["rule_hash", "view_hash", "visual_hash", "large_event_hash", "raw_rule_bytes", "event_sequence", "units"]:
				check(pair.A[key] == pair.B[key], "A/B %s matches in round %d fields=%s" % [key, round_index, fields])
	print("NETWORK_AB_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func run_case(script: GDScript, label: String, round_index: int, fields: bool) -> Dictionary:
	seed(20260929)
	host = make_game(105)
	replica = make_game(102)
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = script.new()
	client = script.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	host.marches.send(0, 1, 0, soldier_count, PackedVector3Array([Vector3.ZERO, Vector3(500, 0, 0)]))
	for index: int in host.marches._units.size():
		var unit: WarMarches.MarchUnit = host.marches._units[index]
		unit.distance = 0.1 + float(index) / float(soldier_count) * 350.0
		host.marches._update_pose(unit)
	if fields:
		host.marches.haste_zones[0] = {"at": Vector3(180, 0, 0), "radius": 180.0, "remaining": 8.0, "duration": 8.0, "multiplier": 1.5, "style": &"squirrel"}
		host.marches.slow_zones[1] = {"at": Vector3(240, 0, 0), "radius": 220.0, "remaining": 8.0, "duration": 8.0}
		host.marches.weak_zones[1] = {"at": Vector3(100, 0, 0), "radius": 80.0, "remaining": 8.0, "duration": 8.0}
	authority._publish_step(0.0)
	flush()
	var samples := {"host_simulate_publish": [], "client_receive": [], "client_install_present": [], "host_receive": [], "pair": [], "large_event_encode": []}
	for frame: int in sample_frames + 30:
		var total_begun := Time.get_ticks_usec()
		var begun := total_begun
		authority.process(Coordinator.STEP)
		var timings := {"host_simulate_publish": elapsed_ms(begun)}
		begun = Time.get_ticks_usec()
		deliver(host_wire, client, false, frame % 2 == 0)
		timings.client_receive = elapsed_ms(begun)
		begun = Time.get_ticks_usec()
		# Fixed presentation time makes A/B visual states comparable regardless of
		# how much wall time the two implementations spend computing this frame.
		client._set_transport_paused(client._recovery_waiting)
		client._apply_view()
		client.codec.present(replica, client._view, Coordinator.STEP)
		client._apply_account()
		timings.client_install_present = elapsed_ms(begun)
		begun = Time.get_ticks_usec()
		deliver(client_wire, authority)
		timings.host_receive = elapsed_ms(begun)
		timings.pair = elapsed_ms(total_begun)
		if frame >= 30:
			for stage: String in timings: samples[stage].append(timings[stage])
	flush()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "%s replica agrees after lost anchors" % label)
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "%s respects packet contracts" % label)
	check(not replica.is_rule_paused() and replica.elapsed >= host.elapsed, "%s actively extrapolates client presentation" % label)
	var visual_rows := {}
	for unit: WarMarches.MarchUnit in replica.marches._units:
		visual_rows[str(unit.unit_id)] = [Codec.v3(unit.position), Codec.v3(unit.presentation_offset), unit.distance, unit.gait, unit.pending_departure, unit.cloaked, unit.weakened]
	var result := {"variant": label, "round": round_index, "fields": fields, "frames": sample_frames,
		"units": replica.marches._units.size(), "rule_hash": Codec.digest(authority._published),
		"view_hash": Codec.digest(client._view), "visual_hash": Codec.digest(visual_rows),
		"raw_rule_bytes": authority.sent_rule_bytes, "event_sequence": authority._seq}
	# Identical large reliable payload, including unchanged ordering and counters.
	var current := Codec.for_player(authority.codec.capture(host, authority._tick), -1)
	var patch := Codec.diff(current, current, true)
	patch["seq"] = authority._seq + 1
	patch["visuals"] = []
	for iteration: int in 18:
		authority._outbox.clear()
		authority._outbox_bytes = 0
		authority._blob_serial = 0
		var begun := Time.get_ticks_usec()
		authority._send_payload("events", patch)
		var duration := elapsed_ms(begun)
		if iteration >= 2: samples.large_event_encode.append(duration)
	result["large_event_hash"] = Codec.digest({"queue": authority._outbox, "bytes": authority._outbox_bytes})
	result["stages"] = {}
	for stage: String in samples: result.stages[stage] = statistics(samples[stage])
	print("NETWORK_AB ", JSON.stringify(result, "", true, true))
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	return result

func elapsed_ms(begun: int) -> float:
	return float(Time.get_ticks_usec() - begun) / 1000.0

func statistics(samples: Array) -> Dictionary:
	var ordered := samples.duplicate()
	ordered.sort()
	var total := 0.0
	for value: float in samples: total += value
	return {"mean_ms": total / samples.size(), "p95_ms": ordered[ceili(samples.size() * 0.95) - 1],
		"p99_ms": ordered[ceili(samples.size() * 0.99) - 1], "max_ms": ordered[-1]}
