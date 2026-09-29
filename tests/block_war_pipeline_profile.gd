extends "res://tests/block_war_replication_test.gd"
## P0 CPU attribution only. Run tools/profile_block_war_pipeline.py serially.
## The direct-call probes and actual coordinator path are separate experiments;
## their timings must never be added together or reported as rendered FPS.
const PROFILE_STEP := 1.0 / 30.0
const PROBE_REPEATS := 3
const MICRO_STAGES := {
	"simulate_inclusive": "host.simulate: includes rule substeps, effects and current render calls; excludes capture/publish",
	"capture_inclusive": "Codec.capture: includes protocol row allocation and order-cache maintenance",
	"public_projection": "Codec.for_player: public faction redaction, not a full deep copy",
	"diff_inclusive": "Codec.diff: all-group comparison and movement-dependency fanout",
	"candidate_copy_apply": "copy-on-write candidate dictionaries plus apply_delta; excludes validation",
	"full_valid_probe": "Codec.valid over a complete candidate on EVERY probe frame, even an empty diff; per-call cost, not production frequency",
	"install_all_rows_deferred": "Codec.install with a fresh full-army public sample; includes effects/HUD-data setup, defers soldier render",
	"install_identical_rows_deferred": "second Codec.install of identical rows at identical time; stable-row fast-path probe, additional work absent in normal frames",
	"present_fixed_step_inclusive": "Codec.present(STEP): includes movement, pose, render input submission and visual effects; bypasses coordinator clock deliberately",
	"movement_distance_fixed_state_probe": "all-unit movement_distance(STEP), same unit/field state repeated three times; returns distance only, warms existing interval caches; NOT additive to present/install",
	"update_pose_fixed_state_probe": "all-unit _update_pose, same distance/timers repeated three times; NOT additive to present/install",
	"render_fixed_state_probe": "marches._render with identical poses repeated three times; CPU calls, no GPU wait; NOT additive to present/install"
}
const COORDINATOR_STAGES := {
	"host_process_inclusive": "authority.process: includes simulation, capture/diff, encoding through FakeOnline and queue flushing",
	"client_delivery_inclusive": "deliver decoded FakeOnline packets through client._on_message: includes validation/commits; excludes encoding performed by sender",
	"client_process_inclusive": "client.process: includes normal clock step, _apply_view, present, account and UI work",
	"host_delivery_inclusive": "deliver client replies through authority._on_message, including any resulting sends",
	"pair_inclusive": "outer wall timer covering the four stages and timer/virtual-clock bookkeeping; DO NOT add to component stages"
}
var profile_frames := 120
var profile_warmup := 30
var profile_soldiers := 4096
var profile_rounds := 3
var profile_mode := "both"
var virtual_wall := 0.0
var clock_received_at := 0.0
var delivered_packets := 0
var delivered_anchors := 0
var delivered_facts := 0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: profile_rounds = int(args[0])
	if args.size() > 1: profile_frames = int(args[1])
	if args.size() > 2: profile_soldiers = int(args[2])
	if args.size() > 3: profile_warmup = int(args[3])
	if args.size() > 4: profile_mode = args[4]
	if profile_rounds < 1 or profile_frames < 1 or profile_soldiers < 1 or profile_soldiers > 16384 or profile_warmup < 0 or profile_mode not in ["both", "micro", "coordinator"]:
		printerr("PIPELINE_PROFILE invalid arguments: rounds frames soldiers warmup [both|micro|coordinator]")
		quit(2)
		return
	root.get_node("Session").block_war_map_id = "highland"
	print("PIPELINE_PROFILE_CONTRACT ", JSON.stringify({
		"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"step": PROFILE_STEP, "warmup": profile_warmup, "sample_frames": profile_frames,
		"micro_stages": MICRO_STAGES, "coordinator_stages": COORDINATOR_STAGES,
		"limits": ["headless CPU/render inputs, no GPU acceptance", "AI and combat disabled; ordinary march or overlapping fields",
			"micro installs full-army rows every step plus one identical reinstall; not actual anchor cadence",
			"coordinator runs real process methods with a virtual zero-latency clock and serialized in-memory transport",
			"no resync/weak-network throughput or real-time FPS claim", "inclusive call times; fixed-state subprobes and separate experiments are not additive"]}))
	for round_index: int in profile_rounds:
		var modes: Array = ["micro", "coordinator"] if profile_mode == "both" else [profile_mode]
		if round_index % 2 == 1: modes.reverse()
		for fields: bool in ([false, true] if round_index % 2 == 0 else [true, false]):
			for mode: String in modes:
				if mode == "micro": await _micro_case(round_index, fields)
				else: await _coordinator_case(round_index, fields)
	print("PIPELINE_PROFILE_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _prepare_army(fields: bool) -> void:
	# Keep every unit on the route throughout arbitrary sample durations.
	# This isolates marching/fields, not actual battle targeting or construction.
	for building: WarBuilding in host.buildings:
		building.kind = 0
		building.level = 1
		building.population = building.capacity
	var duration := float(profile_frames + profile_warmup) * PROFILE_STEP + 2.0
	var route_length := maxf(500.0, 400.0 + duration * 20.0)
	host.marches.send(0, 1, 0, profile_soldiers, PackedVector3Array([Vector3.ZERO, Vector3(route_length, 0, 0)]))
	for index: int in host.marches._units.size():
		var unit: WarMarches.MarchUnit = host.marches._units[index]
		unit.distance = 0.1 + float(index) / float(profile_soldiers) * 350.0
		host.marches._update_pose(unit)
	if fields:
		host.marches.haste_zones[0] = {"at": Vector3(180, 0, 0), "radius": 180.0, "remaining": duration, "duration": duration, "multiplier": 1.5, "style": &"squirrel"}
		host.marches.slow_zones[1] = {"at": Vector3(240, 0, 0), "radius": 220.0, "remaining": duration, "duration": duration}
		host.marches.weak_zones[1] = {"at": Vector3(100, 0, 0), "radius": 80.0, "remaining": duration, "duration": duration}
	host.marches._render()

func _new_pair(fields: bool) -> void:
	seed(20260930)
	host = make_game(105)
	replica = make_game(102)
	host.simulation_paused = false
	replica.simulation_paused = false
	_prepare_army(fields)

func _micro_case(round_index: int, fields: bool) -> void:
	_new_pair(fields)
	var source := Codec.new()
	var display := Codec.new()
	var previous := Codec.for_player(source.capture(host, 0), -1)
	var committed := previous.duplicate(true)
	check(Codec.valid(previous, replica), "micro initial state is schema-valid")
	display.install(replica, previous, 0.0, true)
	var initial_distance: float = host.marches._units[0].distance
	var samples := _new_samples(MICRO_STAGES)
	var nonempty_diffs := 0
	var all_valid := true
	var final_view: Dictionary = previous
	var checksum_before_presentation := ""
	var last_movement_sum := 0.0
	for frame: int in profile_frames + profile_warmup:
		var record := frame >= profile_warmup
		var begun := Time.get_ticks_usec()
		host.simulate(PROFILE_STEP)
		_sample(samples, "simulate_inclusive", begun, record)
		begun = Time.get_ticks_usec()
		var complete: Dictionary = source.capture(host, frame + 1)
		_sample(samples, "capture_inclusive", begun, record)
		begun = Time.get_ticks_usec()
		var current := Codec.for_player(complete, -1)
		_sample(samples, "public_projection", begun, record)
		begun = Time.get_ticks_usec()
		var patch := Codec.diff(previous, current)
		_sample(samples, "diff_inclusive", begun, record)
		var has_fact: bool = not patch.set.is_empty() or not patch.remove.is_empty() or current.match_control != committed.match_control or current.finished != committed.finished
		if record and has_fact: nonempty_diffs += 1
		begun = Time.get_ticks_usec()
		var candidate := committed.duplicate(false)
		for group: String in Codec.GROUPS:
			if patch.set.has(group) or patch.remove.has(group): candidate[group] = committed[group].duplicate(false)
		Codec.apply_delta(candidate, patch)
		_sample(samples, "candidate_copy_apply", begun, record)
		begun = Time.get_ticks_usec()
		var valid: bool = Codec.valid(candidate, replica)
		_sample(samples, "full_valid_probe", begun, record)
		all_valid = all_valid and valid
		# Real publishing skips empty diffs. The validator above intentionally
		# probes per-call cost even then; report that frequency separately.
		if has_fact: committed = candidate
		previous = current
		final_view = current
		if frame == profile_frames + profile_warmup - 1:
			checksum_before_presentation = Codec.digest(current)
		begun = Time.get_ticks_usec()
		display.install(replica, current, host.elapsed, true, true)
		_sample(samples, "install_all_rows_deferred", begun, record)
		begun = Time.get_ticks_usec()
		display.install(replica, current, host.elapsed, true, true)
		_sample(samples, "install_identical_rows_deferred", begun, record)
		begun = Time.get_ticks_usec()
		display.present(replica, current, PROFILE_STEP)
		_sample(samples, "present_fixed_step_inclusive", begun, record)
		var pose_before_probes := _pose_digest(replica) if frame == profile_frames + profile_warmup - 1 else ""
		# Diagnostic subprobes execute after the measured pipeline. All repeats
		# use identical distances/timers/field clocks; they do not advance time.
		for _repeat: int in PROBE_REPEATS:
			begun = Time.get_ticks_usec()
			var distance_sum := 0.0
			for unit: WarMarches.MarchUnit in replica.marches._units:
				distance_sum += replica.marches.movement_distance(unit, PROFILE_STEP)
			_sample(samples, "movement_distance_fixed_state_probe", begun, record)
			last_movement_sum = distance_sum
			begun = Time.get_ticks_usec()
			for unit: WarMarches.MarchUnit in replica.marches._units:
				replica.marches._update_pose(unit)
			_sample(samples, "update_pose_fixed_state_probe", begun, record)
			begun = Time.get_ticks_usec()
			replica.marches._render()
			_sample(samples, "render_fixed_state_probe", begun, record)
		if not pose_before_probes.is_empty():
			check(_pose_digest(replica) == pose_before_probes, "micro fixed-state repeats preserve rendered positions and gait")
	check(all_valid, "micro full validation accepts every candidate")
	check(host.marches._units.size() == profile_soldiers and replica.marches._units.size() == profile_soldiers, "micro full armies remain alive")
	check(host.marches._units[0].distance > initial_distance and replica.marches._units[0].distance > initial_distance, "micro simulate and present both perform movement")
	check(absf(host.elapsed - float(profile_frames + profile_warmup) * PROFILE_STEP) < 0.00001, "micro rule clock advances all fixed steps")
	check(absf(replica.elapsed - host.elapsed - PROFILE_STEP) < 0.00001, "micro direct presentation clock is explicitly one step ahead")
	check(_exposed_count(replica) > 0 and not display._render_pending, "micro produces nonempty submitted render inputs")
	check(Codec.digest(final_view) == checksum_before_presentation, "micro presentation preserves immutable protocol rows")
	check(last_movement_sum > 0.0, "micro movement probe returns nonempty advancement")
	_emit_result("micro", round_index, fields, samples, {
		"sampled_nonempty_diffs": nonempty_diffs, "validation_probe_calls": profile_frames,
		"fixed_state_probe_repeats_per_frame": PROBE_REPEATS, "last_movement_probe_distance_sum": last_movement_sum,
		"install_policy": "full sample each fixed step plus identical-row probe; not network cadence",
		"host_rule_hash": Codec.digest(source.capture(host, profile_frames + profile_warmup)),
		"committed_hash": Codec.digest(committed), "view_hash": Codec.digest(final_view)})
	await _free_pair(false)

func _coordinator_case(round_index: int, fields: bool) -> void:
	_new_pair(fields)
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	check(not client._snapshot_loading and not replica.is_rule_paused(), "coordinator starts with an installed, active replica")
	var initial_distance: float = replica.marches._units[0].distance
	var initial_resyncs: int = client.resync_count
	virtual_wall = 0.0
	clock_received_at = 0.0
	delivered_packets = 0
	delivered_anchors = 0
	delivered_facts = 0
	var samples := _new_samples(COORDINATOR_STAGES)
	var zero_steps := 0
	var greatest_pending := 0
	for frame: int in profile_frames + profile_warmup:
		var record := frame >= profile_warmup
		var pair_begun := Time.get_ticks_usec()
		virtual_wall += PROFILE_STEP
		var begun := Time.get_ticks_usec()
		authority.process(PROFILE_STEP)
		_sample(samples, "host_process_inclusive", begun, record)
		begun = Time.get_ticks_usec()
		_deliver_virtual(host_wire, client, true)
		_sample(samples, "client_delivery_inclusive", begun, record)
		# Real process() computes its rate/limit normally. Only wall-time age and
		# RTT are deterministic, so CPU speed cannot masquerade as network delay.
		client._host_received_ms = Time.get_ticks_msec() - roundi((virtual_wall - clock_received_at) * 1000.0)
		client.rtt_ms = 0.0
		var before: float = replica.elapsed
		begun = Time.get_ticks_usec()
		client.process(PROFILE_STEP)
		_sample(samples, "client_process_inclusive", begun, record)
		begun = Time.get_ticks_usec()
		_deliver_virtual(client_wire, authority, false)
		_sample(samples, "host_delivery_inclusive", begun, record)
		_sample(samples, "pair_inclusive", pair_begun, record)
		if record and replica.elapsed <= before: zero_steps += 1
		greatest_pending = maxi(greatest_pending, client._pending.size())
	var render_elapsed: float = replica.elapsed
	var final_pose := _pose_digest(replica)
	# Flush outside measured frames solely for canonical convergence checks.
	flush()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "coordinator reliable facts converge")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "coordinator serializes valid packet contracts")
	check(client.resync_count == initial_resyncs, "coordinator does not hide work behind repeated recovery")
	check(host.marches._units.size() == profile_soldiers and replica.marches._units.size() == profile_soldiers, "coordinator keeps both full armies")
	check(replica.marches._units[0].distance > initial_distance and _exposed_count(replica) > 0, "coordinator process advances nonempty render inputs")
	check(render_elapsed > 0.0 and zero_steps < profile_frames, "coordinator timing does not profile a wholly frozen replica")
	check(authority._tick == profile_frames + profile_warmup, "coordinator executes the fixed number of rule ticks")
	if profile_frames + profile_warmup >= 17: check(delivered_anchors > 0, "coordinator includes normal paced anchor delivery")
	_emit_result("coordinator", round_index, fields, samples, {
		"clock_path": "real client.process with virtual packet age and zero RTT", "zero_display_steps": zero_steps,
		"sample_end_display_time": render_elapsed, "sample_end_pose_hash": final_pose,
		"delivered_packets_including_warmup": delivered_packets, "delivered_anchors_including_warmup": delivered_anchors,
		"delivered_facts_including_warmup": delivered_facts, "max_pending_transactions": greatest_pending,
		"resync_delta": client.resync_count - initial_resyncs, "event_seq": authority._seq,
		"host_rule_hash": Codec.digest(authority.codec.capture(host, authority._tick)),
		"public_rule_hash": Codec.digest(authority._published), "mirror_hash": Codec.digest(client._mirror)})
	await _free_pair(true)

func _deliver_virtual(wire: FakeOnline, target: RefCounted, to_client: bool) -> void:
	var outgoing: Array[Dictionary] = wire.sent
	wire.sent = []
	for packet: Dictionary in outgoing:
		if int(packet.target) >= 0 and int(packet.target) != target.online.player_id: continue
		var old_received: int = client._host_received_ms
		if to_client: client._host_received_ms = -1
		target._on_message(int(packet.sender), str(packet.kind), packet.payload)
		if to_client:
			delivered_packets += 1
			if packet.kind == "anchors": delivered_anchors += 1
			if packet.kind == "events" and packet.payload.has("seq"): delivered_facts += 1
			if client._host_received_ms >= 0: clock_received_at = virtual_wall
			else: client._host_received_ms = old_received

func _new_samples(definitions: Dictionary) -> Dictionary:
	var samples := {}
	for key: String in definitions: samples[key] = []
	return samples

func _sample(samples: Dictionary, stage: String, begun: int, record: bool) -> void:
	var duration := float(Time.get_ticks_usec() - begun) / 1000.0
	if record: samples[stage].append(duration)

func _statistics(values: Array) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value: float in values: total += value
	return {"count": values.size(), "mean_ms": total / values.size(), "p50_ms": ordered[ceili(values.size() * 0.5) - 1],
		"p95_ms": ordered[ceili(values.size() * 0.95) - 1], "p99_ms": ordered[ceili(values.size() * 0.99) - 1], "max_ms": ordered.back()}

func _exposed_count(game: Node) -> int:
	var count := 0
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.is_exposed(): count += 1
	return count

func _pose_digest(game: Node) -> String:
	var values := {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		values[str(unit.unit_id)] = [Codec.v3(game.marches._presentation_position(unit)), unit.gait + unit.presentation_gait_offset]
	return Codec.digest(values)

func _emit_result(mode: String, round_index: int, fields: bool, samples: Dictionary, extra: Dictionary) -> void:
	var stages := {}
	for stage: String in samples:
		var expected := profile_frames * PROBE_REPEATS if stage.ends_with("fixed_state_probe") else profile_frames
		check(samples[stage].size() == expected, "%s %s has every requested sample" % [mode, stage])
		stages[stage] = _statistics(samples[stage])
	var result := {"mode": mode, "round": round_index, "case": "overlapping_fields" if fields else "ordinary_march",
		"soldiers": profile_soldiers, "frames": profile_frames, "warmup": profile_warmup, "step": PROFILE_STEP,
		"host_time": host.elapsed, "display_time": replica.elapsed, "stages": stages, "raw_samples_ms": samples,
		"render_evidence": "CPU render inputs only; no GPU readback or real-time FPS", "extra": extra}
	print("PIPELINE_PROFILE ", JSON.stringify(result))

func _free_pair(with_transport: bool) -> void:
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	if with_transport:
		host_wire.free()
		client_wire.free()
		authority = null
		client = null
