extends "res://tests/block_war_pipeline_profile.gd"
## Two independent real host/client pairs interleaved within the same process.
## Only generated dependencies inject a deterministic transport wall clock.
const AB_ROOT := "res://.local/pipeline-ab/"
const VERIFY_FRAMES := 8
const RENDER_TOLERANCE := 0.000002
const AB_STAGES := {
	"host_process_inclusive": "real Host process: rules, presentation, capture/diff, encoding and output queues",
	"client_receive_inclusive": "real client message delivery: validation, facts, anchors and any snapshot installation",
	"client_process_inclusive": "real client process: view installation, interpolation, rendering, account and HUD",
	"host_receive_inclusive": "real Host receives serialized client commands and acknowledgements",
	"pair_inclusive": "whole four-stage transaction including nested timer bookkeeping; not additive to component stages",
	"client_install_inclusive": "nested codec.install time summed per frame; already included in receive/process",
	"client_present_inclusive": "nested codec.present time summed per frame; already included in client process"
}
var ab_frames := 60
var ab_warmup := 10
var ab_rounds := 3
var ab_soldiers := 4096
var ab_map := "crown"
var recording_events := false
var ab_max_render_error := 0.0
var ab_initialization_failed := false

func configuration() -> Dictionary:
	var config: Dictionary = super.configuration()
	config.map_id = ab_map
	config.match_id = "pipeline-ab"
	return config

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--rounds="): ab_rounds = int(argument.get_slice("=", 1))
		elif argument.begins_with("--frames="): ab_frames = int(argument.get_slice("=", 1))
		elif argument.begins_with("--warmup="): ab_warmup = int(argument.get_slice("=", 1))
		elif argument.begins_with("--soldiers="): ab_soldiers = int(argument.get_slice("=", 1))
		elif argument.begins_with("--map="): ab_map = argument.get_slice("=", 1)
	if ab_rounds < 1 or ab_frames < 1 or ab_warmup < 0 or ab_soldiers < 1 or ab_soldiers > 16384 or ab_map not in ["highland", "crown"]:
		printerr("PIPELINE_AB invalid arguments")
		quit(2)
		return
	root.get_node("Session").block_war_map_id = ab_map
	print("PIPELINE_AB_CONTRACT ", JSON.stringify({"engine": Engine.get_version_info().string,
		"display": DisplayServer.get_name(), "map": ab_map, "rounds": ab_rounds, "sample_frames": ab_frames,
		"warmup": ab_warmup, "correctness_frames": VERIFY_FRAMES, "initial_background_soldiers": ab_soldiers,
		"step": PROFILE_STEP, "stages": AB_STAGES,
		"workload": "Six-faction authored map, unchanged native route with reserved travel distance, live ordinary/overlapping fields; 12-soldier serialized client dispatch every 15 frames creates real departure/presentation facts",
		"clock": "Identical generated millisecond clock for all coordinator clock reads; CPU microsecond timers remain real",
		"comparison": "Paired exact rule/mirror/unit-state/event hashes; render input positions within 2e-6; opposite order each frame and round",
		"limits": ["Headless CPU/render inputs, no GPU/FPS claim", "Same canonical WarMarches nested types; reference overrides the three original optimized methods",
			"Assertions, state hashing, fixture staging and event capture excluded from performance samples",
			"install/present timers are inclusive substages and must not be added to their parent stages",
			"Events are traced during eight correctness frames; performance continues with event tracing disabled"]}))
	for round_index: int in ab_rounds:
		var cases: Array = [false, true] if round_index % 2 == 0 else [true, false]
		for fields: bool in cases:
			await _ab_case(round_index, fields)
			if ab_initialization_failed:
				print("PIPELINE_AB_CHECKS checks=", checks, " failures=", failures.size())
				quit(1)
				return
	print("PIPELINE_AB_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _make_ab_game(variant: String, player: int) -> Node3D:
	var game: Node3D = load(AB_ROOT + variant + "/block_war.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.audio.muted = true
	game.ai_enabled = false
	game.configure_match(configuration(), player)
	return game

func _seed_ab_army(game: Node3D, fields: bool) -> bool:
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
		building.population = building.capacity
	# Keep the unchanged native route within the protocol's point limit. Repeating
	# dense terrain guides can exceed that limit even for a very small army.
	var route: PackedVector3Array = game.map.get_building_route(game.by_id[0], game.by_id[1])
	check(route.size() >= 2 and route.size() <= 2048, "native fixture route satisfies the protocol point limit")
	if route.size() < 2 or route.size() > 2048: return false
	var duration := float(VERIFY_FRAMES + ab_warmup + ab_frames) * PROFILE_STEP + 2.0
	var route_length := 0.0
	for index: int in range(1, route.size()): route_length += route[index - 1].distance_to(route[index])
	var initial_span := route_length - duration * WarMarches.SPEED * 3.0 - WarMarches.GATE_LENGTH * 2.0
	check(initial_span > 1.0, "native route reserves enough travel for every benchmark frame")
	if initial_span <= 1.0: return false
	print("PIPELINE_AB_ROUTE ", JSON.stringify({"map": ab_map, "points": route.size(), "length": route_length, "initial_span": initial_span,
		"old_repeated_recipe_points": 1 + ceili((450.0 + (duration - 2.0) * 20.0) / route_length) * (route.size() - 1)}))
	game.marches.send(0, 1, 0, ab_soldiers, route)
	for index: int in game.marches._units.size():
		var unit: WarMarches.MarchUnit = game.marches._units[index]
		unit.distance = 0.1 + float(index) / ab_soldiers * initial_span
		if fields and index % 5 == 0: unit.rush_remaining = duration
		game.marches._update_pose(unit)
	if fields:
		var start: Vector3 = game.by_id[0].global_position
		var end: Vector3 = game.by_id[1].global_position
		var radius := maxf(3.0, start.distance_to(end) * 0.4)
		game.marches.create_haste_zone(0, start.lerp(end, 0.45), radius, duration, 1.5)
		game.marches.create_slow_zone(1, start.lerp(end, 0.60), radius, duration)
		game.marches.weak_zones[1] = {"at": start.lerp(end, 0.50), "radius": radius * 0.6, "remaining": duration, "duration": duration}
	game.marches._render()
	return true

func _make_ab_fixture(variant: String, fields: bool) -> Dictionary:
	seed(20260930)
	var battle := _make_ab_game(variant, 105)
	var view := _make_ab_game(variant, 102)
	var army_ready: bool = _seed_ab_army(battle, fields)
	var wire_host := make_wire(105)
	var wire_client := make_wire(102)
	var server: RefCounted = load(AB_ROOT + variant + "/war_network_match.gd").new()
	var receiver: RefCounted = load(AB_ROOT + variant + "/war_network_match.gd").new()
	var fixture := {"variant": variant, "host": battle, "replica": view, "authority": server, "client": receiver,
		"host_wire": wire_host, "client_wire": wire_client, "wall": 0.0, "events": [], "replica_events": [],
		"packets": 0, "anchors": 0, "facts": 0, "install_calls": 0, "present_calls": 0,
		"samples": _new_samples(AB_STAGES), "zero_display_steps": 0, "max_pending": 0,
		"validation_codec": Codec.new(), "initialized": false}
	if not army_ready: return fixture
	var initial: Dictionary = fixture.validation_codec.capture(battle, 0)
	var valid_initial: bool = Codec.valid(initial, view)
	check(valid_initial, variant + " fixture produces a schema-valid initial snapshot")
	if not valid_initial:
		var invalid_rows: Array = []
		for group: String in Codec.GROUPS:
			for key: String in initial[group]:
				if not Codec.valid_record(group, initial[group][key], view):
					var diagnostic := {"group": group, "key": key}
					if group == "orders": diagnostic.route_points = initial[group][key][6].size()
					elif invalid_rows.size() < 8: diagnostic.row = initial[group][key]
					invalid_rows.append(diagnostic)
		print("PIPELINE_AB_INITIALIZATION_ERROR ", JSON.stringify({"variant": variant, "stage": "initial_schema", "invalid_rows": invalid_rows}))
		return fixture
	_trace_events(battle, fixture.events)
	_trace_events(view, fixture.replica_events)
	server.setup(battle, wire_host)
	receiver.setup(view, wire_client)
	_flush_ab(fixture)
	receiver.process(0.0)
	check(not receiver._snapshot_loading and not view.is_rule_paused(), variant + " starts with installed active replica")
	check(battle.marches._units.size() == ab_soldiers and view.marches._units.size() == ab_soldiers, variant + " restores the complete background army")
	if receiver._snapshot_loading or view.is_rule_paused() or battle.marches._units.size() != ab_soldiers or view.marches._units.size() != ab_soldiers:
		print("PIPELINE_AB_INITIALIZATION_ERROR ", JSON.stringify({"variant": variant, "stage": "transport_restore", "resync_reasons": receiver.resync_reasons,
			"host_invalid_packets": wire_host.invalid_packets, "client_invalid_packets": wire_client.invalid_packets,
			"remaining_blobs": receiver._blobs.size(), "remaining_outbox": server._outbox.size(), "host_aborted": server._aborted}))
		return fixture
	fixture.initial_resyncs = receiver.resync_count
	fixture.initial_distance = view.marches._units[0].distance
	fixture.initialized = true
	return fixture

func _trace_events(game: Node3D, trace: Array) -> void:
	game.presentation_event.connect(func(kind: String, payload: Dictionary):
		if recording_events: trace.append(["presentation", kind, payload.duplicate(true)]))
	game.marches.departure_queue_changed.connect(func(source: int, faction: int, change: int):
		if recording_events: trace.append(["queue", source, faction, change]))
	game.marches.unit_departed.connect(func(source: int, faction: int):
		if recording_events: trace.append(["departed", source, faction]))
	game.marches.unit_arrived.connect(func(target: int, faction: int, strength: float, bonus: float, origin: bool):
		if recording_events: trace.append(["arrived", target, faction, strength, bonus, origin]))
	game.marches.unit_defeated.connect(func(at: Vector3, heading: Vector3, faction: int, impulse: Vector3, burning: bool):
		if recording_events: trace.append(["defeated", Codec.v3(at), Codec.v3(heading), faction, Codec.v3(impulse), burning]))
	game.marches.combat_death.connect(func(faction: int, target: int, killer: int):
		if recording_events: trace.append(["death", faction, target, killer]))

func _deliver_ab(fixture: Dictionary, to_client: bool) -> void:
	var wire: FakeOnline = fixture.host_wire if to_client else fixture.client_wire
	var target: RefCounted = fixture.client if to_client else fixture.authority
	var outgoing: Array[Dictionary] = wire.sent
	wire.sent = []
	for packet: Dictionary in outgoing:
		if int(packet.target) >= 0 and int(packet.target) != target.online.player_id: continue
		target._on_message(int(packet.sender), str(packet.kind), packet.payload)
		if to_client:
			fixture.packets += 1
			if packet.kind == "anchors": fixture.anchors += 1
			if packet.kind == "events" and packet.payload.has("seq"): fixture.facts += 1

func _flush_ab(fixture: Dictionary) -> void:
	for _index: int in 400:
		fixture.authority._flush_outbox(0.1)
		fixture.authority._flush_anchors(0.1)
		_deliver_ab(fixture, true)
		_deliver_ab(fixture, false)
		if fixture.authority._outbox.is_empty() and fixture.authority._anchor_outbox.is_empty() and fixture.host_wire.sent.is_empty() and fixture.client_wire.sent.is_empty(): break
	fixture.client._apply_view()

func _stage_ab(fixture: Dictionary, frame: int) -> void:
	if frame % 15 == 0:
		fixture.host.by_id[2].population = float(fixture.host.by_id[2].queued_population + 12)
		fixture.client.submit({"type": "dispatch", "source": 2, "target": 8, "percent": 100})
	fixture.wall += PROFILE_STEP
	var stamp := 10000 + roundi(float(fixture.wall) * 1000.0)
	fixture.authority.bench_now_ms = stamp
	fixture.client.bench_now_ms = stamp
	fixture.client.rtt_ms = 0.0
	fixture.client.codec.bench_install_usec = 0
	fixture.client.codec.bench_install_calls = 0
	fixture.client.codec.bench_present_usec = 0
	fixture.client.codec.bench_present_calls = 0

func _advance_ab(fixture: Dictionary, record: bool) -> void:
	var samples: Dictionary = fixture.samples
	var before: float = fixture.replica.elapsed
	var pair_begun := Time.get_ticks_usec()
	var began := Time.get_ticks_usec()
	fixture.authority.process(PROFILE_STEP)
	_sample(samples, "host_process_inclusive", began, record)
	began = Time.get_ticks_usec()
	_deliver_ab(fixture, true)
	_sample(samples, "client_receive_inclusive", began, record)
	began = Time.get_ticks_usec()
	fixture.client.process(PROFILE_STEP)
	_sample(samples, "client_process_inclusive", began, record)
	began = Time.get_ticks_usec()
	_deliver_ab(fixture, false)
	_sample(samples, "host_receive_inclusive", began, record)
	_sample(samples, "pair_inclusive", pair_begun, record)
	if record:
		samples.client_install_inclusive.append(float(fixture.client.codec.bench_install_usec) / 1000.0)
		samples.client_present_inclusive.append(float(fixture.client.codec.bench_present_usec) / 1000.0)
		fixture.install_calls += fixture.client.codec.bench_install_calls
		fixture.present_calls += fixture.client.codec.bench_present_calls
		if fixture.replica.elapsed <= before: fixture.zero_display_steps += 1
	fixture.max_pending = maxi(fixture.max_pending, fixture.client._pending.size())

func _ab_case(round_index: int, fields: bool) -> void:
	recording_events = false
	ab_max_render_error = 0.0
	var pair: Array[Dictionary] = []
	for variant: String in ["reference", "candidate"]:
		var fixture := _make_ab_fixture(variant, fields)
		pair.append(fixture)
		if not fixture.initialized:
			ab_initialization_failed = true
			await _dispose_ab(pair)
			return
	var label := "overlapping_fields" if fields else "ordinary_march"
	_compare_ab(pair, label + " initial")
	for frame: int in VERIFY_FRAMES + ab_warmup + ab_frames:
		recording_events = frame < VERIFY_FRAMES
		for fixture: Dictionary in pair: _stage_ab(fixture, frame)
		var order: Array = [0, 1] if (frame + round_index) % 2 == 0 else [1, 0]
		for index: int in order:
			seed(77119 + frame)
			_advance_ab(pair[index], frame >= VERIFY_FRAMES + ab_warmup)
		if frame < VERIFY_FRAMES: _compare_ab(pair, "%s correctness frame %d" % [label, frame])
	recording_events = false
	_compare_ab(pair, label + " measured final")
	var compared := _fingerprints(pair[0])
	check(not pair[0].events.is_empty(), label + " captures real events in the correctness phase")
	check(pair[0].events.any(func(event: Array): return event[0] == "presentation" and event[1] == "dispatch"), label + " serialized dispatch executes through Host process")
	var stage_results := {}
	var raw := {}
	var evidence := {}
	for fixture: Dictionary in pair:
		var variant: String = fixture.variant
		stage_results[variant] = {}
		for stage: String in AB_STAGES:
			check(fixture.samples[stage].size() == ab_frames, variant + " complete samples " + stage)
			stage_results[variant][stage] = _statistics(fixture.samples[stage])
		raw[variant] = fixture.samples
		evidence[variant] = {"final": _fingerprints(fixture), "rule_tick": fixture.authority._tick,
			"event_sequence": fixture.authority._seq, "sampled_install_calls": fixture.install_calls,
			"sampled_present_calls": fixture.present_calls, "zero_display_steps": fixture.zero_display_steps,
			"delivered_packets": fixture.packets, "delivered_anchors": fixture.anchors, "delivered_facts": fixture.facts,
			"sent_rule_bytes": fixture.authority.sent_rule_bytes, "maximum_pending": fixture.max_pending,
			"host_units": fixture.host.marches._units.size(), "replica_units": fixture.replica.marches._units.size(),
			"correctness_events": fixture.events.size(), "resync_delta": fixture.client.resync_count - fixture.initial_resyncs}
		check(fixture.client.resync_count == fixture.initial_resyncs, variant + " does not replace active work with recovery")
		check(fixture.replica.marches._units[0].distance > fixture.initial_distance, variant + " replica actually marches")
		check(fixture.zero_display_steps < ab_frames and fixture.present_calls == ab_frames, variant + " every sampled client frame presents")
		check(fixture.authority._tick == VERIFY_FRAMES + ab_warmup + ab_frames, variant + " exact fixed tick count")
		check(fixture.host_wire.invalid_packets == 0 and fixture.client_wire.invalid_packets == 0, variant + " valid serialized protocol")
		check(fixture.replica_events.is_empty(), variant + " presentation does not emit gameplay events")
		if VERIFY_FRAMES + ab_warmup + ab_frames >= 17: check(fixture.anchors > 0, variant + " includes paced anchor delivery")
		if ab_frames >= 15: check(fixture.install_calls > 0, variant + " sampled frames include actual client installation")
		_flush_ab(fixture)
		check(Codec.digest(fixture.client._mirror) == Codec.digest(fixture.authority._published), variant + " final reliable facts converge")
	_compare_ab(pair, label + " after drain")
	check(pair[0].install_calls == pair[1].install_calls and pair[0].present_calls == pair[1].present_calls, label + " compares equal install/present workloads")
	var ratios := {}
	for stage: String in AB_STAGES:
		ratios[stage] = float(stage_results.reference[stage].mean_ms) / maxf(0.000001, float(stage_results.candidate[stage].mean_ms))
	print("PIPELINE_AB_RESULT ", JSON.stringify({"round": round_index, "case": label, "map": ab_map,
		"frames": ab_frames, "warmup": ab_warmup, "initial_soldiers": ab_soldiers, "stages": stage_results,
		"mean_speedup": ratios, "raw_samples_ms": raw, "evidence": evidence, "matched_fingerprints": compared,
		"render_position_tolerance": RENDER_TOLERANCE, "maximum_render_position_error": ab_max_render_error}))
	await _dispose_ab(pair)

func _dispose_ab(pair: Array[Dictionary]) -> void:
	for fixture: Dictionary in pair:
		await fixture.host.prepare_shutdown()
		await fixture.replica.prepare_shutdown()
		fixture.host.free()
		fixture.replica.free()
		fixture.host_wire.free()
		fixture.client_wire.free()

func _unit_rows(game: Node3D) -> Dictionary:
	var rows := {}
	var iteration_order: Array = []
	for unit: WarMarches.MarchUnit in game.marches._units:
		iteration_order.append(unit.unit_id)
		rows[str(unit.unit_id)] = [unit.order.order_id, unit.distance, unit.lane, Codec.v3(unit.position),
			Codec.v3(unit.heading), unit.gait, Codec.v3(unit.presentation_offset), unit.presentation_gait_offset,
			unit.spawn_delay, unit.pending_departure, unit.departure_sequence, unit.rush_remaining,
			unit.levitation_remaining, unit.alive, unit.reserved, unit.intercepted_by, unit.cloaked, unit.weakened]
	return {"order": iteration_order, "rows": rows, "elapsed": game.elapsed}

func _fingerprints(fixture: Dictionary) -> Dictionary:
	return {"host_rule": Codec.digest(fixture.validation_codec.capture(fixture.host, fixture.authority._tick)),
		"published_rule": Codec.digest(fixture.authority._published), "mirror": Codec.digest(fixture.client._mirror),
		"view": Codec.digest(fixture.client._view), "host_motion": Codec.digest(_unit_rows(fixture.host)),
		"client_motion": Codec.digest(_unit_rows(fixture.replica)), "events": Codec.digest({"events": fixture.events})}

func _compare_ab(pair: Array[Dictionary], label: String) -> void:
	var a := _fingerprints(pair[0])
	var b := _fingerprints(pair[1])
	for key: String in a: check(a[key] == b[key], label + " exact " + key + " hash")
	check(pair[0].events == pair[1].events, label + " ordered event payloads")
	check(pair[0].authority._seq == pair[1].authority._seq and pair[0].authority.sent_rule_bytes == pair[1].authority.sent_rule_bytes, label + " authoritative event sequence/bytes")
	check(pair[0].client._applied == pair[1].client._applied and pair[0].client.resync_count == pair[1].client.resync_count, label + " client committed sequence/recovery count")
	for side: String in ["host", "replica"]:
		var first: Node3D = pair[0][side].marches
		var second: Node3D = pair[1][side].marches
		for index: int in 2:
			var marches: Node3D = pair[index][side].marches
			check(marches._render_batch_depth == 0 and not marches._render_pending,
				"%s %s %s production batch is closed and clean" % [label, pair[index].variant, side])
		check(first._units.size() == second._units.size(), label + " " + side + " render pool size")
		var valid: bool = first._units.size() == second._units.size()
		var normal := 0
		var cloaked := 0
		for index: int in mini(first._units.size(), second._units.size()):
			var unit: WarMarches.MarchUnit = first._units[index]
			var other: WarMarches.MarchUnit = second._units[index]
			valid = valid and unit.unit_id == other.unit_id and unit.is_exposed() == other.is_exposed()
			if not unit.is_exposed(): continue
			var position_error: float = first._presentation_position(unit).distance_to(second._presentation_position(other))
			ab_max_render_error = maxf(ab_max_render_error, position_error)
			valid = valid and position_error <= RENDER_TOLERANCE
			valid = valid and unit.cloaked == other.cloaked and unit.order.faction == other.order.faction
			valid = valid and unit.heading == other.heading and unit.gait + unit.presentation_gait_offset == other.gait + other.presentation_gait_offset
			if unit.cloaked: cloaked += 1
			else: normal += 1
		check(valid, label + " " + side + " final render inputs within 2e-6")
		check(first._multimesh.visible_instance_count == normal and second._multimesh.visible_instance_count == normal, label + " " + side + " normal visible count")
		check(first._cloaked_mesh.visible_instance_count == cloaked and second._cloaked_mesh.visible_instance_count == cloaked, label + " " + side + " cloak visible count")
