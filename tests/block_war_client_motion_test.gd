extends "res://tests/block_war_replication_test.gd"
## Sixty Hz client process and render inputs; real renderers also check MultiMesh.
const FRAME := 1.0 / 60.0
const FRAMES := 480
const WARMUP := 120
const SOLDIERS := 96
var virtual_time := 0.0
var clock_received_at := 0.0
var impaired := false
var packets: Array[Dictionary] = []
var channel_deadlines := {}
var packet_serial := 0
var anchor_packets := 0
var dropped_anchors := 0
var tracked: Array[int] = []
var variant := "current"
var coordinator_script: GDScript = Coordinator
var readback_enabled := false
var readback_samples := 0
var readback_errors := 0
var sampled_visible_count := 0

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	if "--baseline" in OS.get_cmdline_user_args():
		variant = "baseline"
		coordinator_script = load("res://.local/client-smoothness/reference/war_network_match.gd")
	readback_enabled = DisplayServer.get_name() != "headless"
	print("CLIENT_MOTION_MODE ", "render_inputs_and_multimesh_readback" if readback_enabled else "headless_render_inputs_only_no_gpu_acceptance")
	root.get_node("Session").block_war_map_id = "highland"
	for scenario: String in ["clean", "frequent_facts", "jitter_and_loss"]:
		await _case(scenario)
	print("CLIENT_MOTION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _case(label: String) -> void:
	virtual_time = 0.0; clock_received_at = 0.0
	impaired = label == "jitter_and_loss"
	packets.clear(); channel_deadlines.clear(); tracked.clear()
	packet_serial = 0; anchor_packets = 0; dropped_anchors = 0
	readback_samples = 0; readback_errors = 0
	host = make_game(105)
	replica = make_game(102)
	# No combat, arrivals, concealment, terrain turns, or legitimate speed changes.
	for building: WarBuilding in host.buildings:
		building.kind = 0
		building.level = 1
		building.population = building.capacity
	host.marches.send(0, 1, 0, SOLDIERS, PackedVector3Array([Vector3(-20, 0, 0), Vector3(480, 0, 0)]))
	for index: int in SOLDIERS:
		var unit: WarMarches.MarchUnit = host.marches._units[index]
		unit.distance = 8.0 + float(index) * 0.12
		host.marches._update_pose(unit)
		if index in [0, 31, 32, 63, 64, 95]: tracked.append(unit.unit_id)
	host.marches._render()
	host_wire = make_wire(105); client_wire = make_wire(102)
	authority = coordinator_script.new(); client = coordinator_script.new()
	authority.setup(host, host_wire); client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	if readback_enabled: await RenderingServer.frame_post_draw
	check(not client._snapshot_loading and replica.marches._units.size() == SOLDIERS, label + " starts with complete visible army")
	var previous := _sample()
	var trace: Array = []
	var steps: Array[float] = []
	var phases: Array[float] = []
	var stalls := 0
	var backwards := 0
	var gait_rewinds := 0
	var visibility_errors := 0
	var cpu_ms: Array[float] = []
	for frame: int in FRAMES:
		var began := Time.get_ticks_usec()
		_step(frame, label != "clean")
		var cpu_elapsed := float(Time.get_ticks_usec() - began) / 1000.0
		if readback_enabled: await RenderingServer.frame_post_draw
		var current := _sample()
		if current.size() != tracked.size() or replica.marches._units.size() != SOLDIERS or sampled_visible_count != SOLDIERS:
			visibility_errors += 1
		if frame >= WARMUP:
			cpu_ms.append(cpu_elapsed)
			for id: int in tracked:
				if not current.has(id) or not previous.has(id): continue
				var dx: float = current[id][0] - previous[id][0]
				var phase: float = current[id][1] - previous[id][1]
				steps.append(dx); phases.append(phase)
				if absf(dx) < WarMarches.SPEED * FRAME * 0.05: stalls += 1
				if dx < -0.001: backwards += 1
				if phase < -0.01: gait_rewinds += 1
				trace.append([frame, id, virtual_time, host.elapsed, replica.elapsed, client._host_time, current[id][0], current[id][1], dx, phase, client._applied])
		previous = current
	var expected := WarMarches.SPEED * FRAME
	var ratio := _mean(steps) / expected if not steps.is_empty() else 0.0
	var stall_ratio := float(stalls) / maxi(1, steps.size())
	var mode := "rendered" if readback_enabled else "headless_inputs"
	var metrics := {"variant": variant, "case": label, "mode": mode, "display_server": DisplayServer.get_name(),
		"multimesh_readback_samples": readback_samples, "multimesh_readback_errors": readback_errors,
		"frames": FRAMES - WARMUP, "samples": steps.size(), "stalls": stalls, "stall_ratio": stall_ratio,
		"backward_steps": backwards, "gait_rewinds": gait_rewinds, "mean_speed_ratio": ratio, "step_p95": _percentile(steps, 0.95),
		"step_max": _percentile(steps, 1.0), "gait_delta_max": _percentile(phases, 1.0), "visibility_errors": visibility_errors,
		"pair_cpu_p95_ms": _percentile(cpu_ms, 0.95), "dropped_anchors": dropped_anchors}
	check(steps.size() == (FRAMES - WARMUP) * tracked.size(), label + " samples every tracked soldier every frame")
	check(visibility_errors == 0, label + " no false deaths or missing visible render inputs")
	if readback_enabled: check(readback_samples > 0 and readback_errors == 0, label + " real MultiMesh positions and shader gait match every render input")
	check(backwards == 0, label + " ordinary forward march never moves backward")
	check(gait_rewinds == 0, label + " walking animation phase never rewinds")
	check(stall_ratio < (0.08 if impaired else 0.02), label + " ordinary march does not periodically stop")
	check(ratio > 0.85 and ratio < 1.15, label + " rendered travel retains ordinary speed")
	check(_percentile(steps, 1.0) < expected * (6.0 if impaired else 4.0), label + " rendered position has no multi-frame correction jump")
	check(_percentile(phases, 1.0) < 1.5, label + " no abrupt walking-pose phase jump")
	if impaired: check(dropped_anchors > 0, "impaired case actually drops optional anchors")
	_drain_network()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), label + " public facts converge without resync")
	check(client.resync_count == 1, label + " continuous motion does not require recovery")
	metrics["host_rule_hash"] = Codec.digest(authority.codec.capture(host, authority._tick))
	metrics["public_rule_hash"] = Codec.digest(authority._published)
	metrics["mirror_hash"] = Codec.digest(client._mirror)
	metrics["raw_rule_bytes"] = authority.sent_rule_bytes
	metrics["event_sequence"] = authority._seq
	metrics["rule_tick"] = authority._tick
	metrics["units"] = host.marches._units.size()
	print("CLIENT_MOTION_METRICS ", JSON.stringify(metrics))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/client-motion"))
	FileAccess.open("res://.local/client-motion/%s-%s-%s.json" % [variant, mode, label], FileAccess.WRITE).store_string(JSON.stringify({"metrics": metrics,
		"columns": ["frame", "unit_id", "wall_time", "host_time", "client_time", "clock_sample", "render_input_x", "render_input_gait", "dx", "dphase", "event_seq"], "trace": trace}))
	if label == "clean": await _ward_arrival()
	if impaired: _pause_and_recover()
	await host.prepare_shutdown(); await replica.prepare_shutdown()
	host.free(); replica.free(); host_wire.free(); client_wire.free()

func _step(frame: int, frequent_facts: bool) -> void:
	virtual_time += FRAME
	if frequent_facts:
		# A distinct unrelated building fact every 30 Hz authority step.
		host.by_id[5].population = 40.0 + float(floori(float(frame) / 2.0) % 2)
	authority.process(FRAME)
	_enqueue(host_wire, false)
	_deliver_due()
	# Keep the real process() clock path deterministic despite test CPU speed.
	client._host_received_ms = Time.get_ticks_msec() - roundi((virtual_time - clock_received_at) * 1000.0)
	client.rtt_ms = 160.0 if impaired else 0.0
	client.process(FRAME)
	_enqueue(client_wire, true)
	_deliver_due()

func _enqueue(wire: FakeOnline, to_host: bool) -> void:
	var outgoing := wire.sent
	wire.sent = []
	for packet: Dictionary in outgoing:
		var recipient: int = 105 if to_host else 102
		if int(packet.target) >= 0 and int(packet.target) != recipient: continue
		packet_serial += 1
		if packet.kind == "anchors":
			anchor_packets += 1
			if impaired and anchor_packets % 17 == 0:
				dropped_anchors += 1
				continue
		var delay: float = [0.025, 0.11, 0.06, 0.14, 0.065][packet_serial % 5] if impaired else 0.0
		var due := virtual_time + delay
		if int(packet.channel) != 4:
			# ENet preserves reliable ordering within each directional channel.
			var channel := "%s:%d" % [to_host, int(packet.channel)]
			due = maxf(due, float(channel_deadlines.get(channel, 0.0)))
			channel_deadlines[channel] = due
		packets.append({"due": due, "serial": packet_serial, "to_host": to_host, "packet": packet})

func _deliver_due() -> void:
	packets.sort_custom(func(a: Dictionary, b: Dictionary): return a.due < b.due or (a.due == b.due and a.serial < b.serial))
	while not packets.is_empty() and float(packets[0].due) <= virtual_time + 0.000001:
		var delivery: Dictionary = packets.pop_front()
		var packet: Dictionary = delivery.packet
		var target: RefCounted = authority if delivery.to_host else client
		var old_received: int = client._host_received_ms
		# Detect accepted clock writes from time, facts, anchors, and snapshots;
		# also retain the former codec's same-tick time-packet behavior in A/B.
		if not delivery.to_host: client._host_received_ms = -1
		target._on_message(int(packet.sender), str(packet.kind), packet.payload)
		if not delivery.to_host:
			if client._host_received_ms >= 0: clock_received_at = virtual_time
			else: client._host_received_ms = old_received

func _sample() -> Dictionary:
	var result := {}
	var mesh: MultiMesh = replica.marches._multimesh
	var slot := 0
	for unit: WarMarches.MarchUnit in replica.marches._units:
		if not unit.is_exposed() or unit.cloaked: continue
		if unit.unit_id in tracked:
			var position: Vector3 = replica.marches._presentation_position(unit)
			var gait: float = unit.gait + unit.presentation_gait_offset
			result[unit.unit_id] = [position.x, gait]
			# Dummy RenderingServer readback returns defaults, not the values set.
			if readback_enabled:
				readback_samples += 1
				if slot >= mesh.visible_instance_count:
					readback_errors += 1
				else:
					var encoded := mesh.get_instance_custom_data(slot).a
					var mesh_gait := -encoded - 1.0 if encoded < 0.0 else encoded
					if mesh.get_instance_transform(slot).origin.distance_to(position) > 0.0001 or absf(mesh_gait - gait) > 0.0001:
						readback_errors += 1
		slot += 1
	sampled_visible_count = slot
	if readback_enabled and mesh.visible_instance_count != slot: readback_errors += 1
	return result

func _ward_arrival() -> void:
	# The defense ward permits normal entry. Presentation approaches the doorway,
	# then waits only for the authoritative arrival fact to consume the soldier.
	host.marches.clear()
	host.morale.configure(host.faction_count)
	host.shields.clear()
	host.by_id[1].population = 100.0
	host.marches.send(0, 1, 0, 1, host.map.get_building_route(host.by_id[0], host.by_id[1]))
	var soldier: WarMarches.MarchUnit = host.marches._units[0]
	soldier.distance = soldier.order.length - 0.12
	soldier.gait = 42.0
	host.marches._update_pose(soldier)
	host.bear.wards[1] = {"faction": 1, "remaining": 2.0, "shot_clock": 3.0, "pulse": 0.0}
	tracked.assign([soldier.unit_id])
	authority._publish_step(0.0); flush()
	client.process(0.0)
	if readback_enabled: await RenderingServer.frame_post_draw
	var displayed: WarMarches.MarchUnit = client.codec._objects[str(soldier.unit_id)]
	# Installation may already extrapolate the new anchor toward the doorway.
	var distance := soldier.distance
	var gait := soldier.gait
	var errors_before := readback_errors
	# A newly published sample can be ahead of the buffered display clock.
	# Let the replica reach that anchor before measuring its forward prediction.
	var frames_to_arrival := ceili(maxf(0.1, host.elapsed - replica.elapsed + 0.1) / FRAME)
	for _frame: int in frames_to_arrival:
		client.codec.present(replica, client._view, FRAME)
		if readback_enabled: await RenderingServer.frame_post_draw
		_sample()
	check(replica.bear.wards.has(1) and displayed.alive and sampled_visible_count == 1, "ward prediction preserves the soldier until an authoritative arrival")
	check(displayed.distance > distance + 0.10 and displayed.gait + displayed.presentation_gait_offset > gait, "defense ward advances through the old gate limit: distance %.6f -> %.6f, gait %.6f -> %.6f" % [distance, displayed.distance, gait, displayed.gait + displayed.presentation_gait_offset])
	check(is_equal_approx(replica.skill_defense_bonus(replica.by_id[1]), 1.0), "client mirrors the active defense bonus")
	if readback_enabled: check(readback_errors == errors_before, "advancing doorway pose and gait reach the real MultiMesh unchanged")
	host.simulate(0.1)
	check(not soldier.alive and host.marches._units.is_empty(), "authority settles entry during the defense ward")
	check(is_equal_approx(host.by_id[1].population, 99.5), "ward halves ordinary arrival damage instead of rejecting it")
	authority._publish_step(0.0); flush()
	client.process(0.0)
	check(replica.marches._units.is_empty() and not client.codec._objects.has(str(soldier.unit_id)), "arrival fact removes the displayed soldier exactly once")
	check(is_equal_approx(replica.by_id[1].population, host.by_id[1].population), "authoritative ward damage reaches the replica")
	print("CLIENT_MOTION_WARD_ARRIVAL ", JSON.stringify({"variant": variant, "readback": readback_enabled, "host_population": host.by_id[1].population, "replica_population": replica.by_id[1].population}))

func _drain_network() -> void:
	for _round: int in 200:
		virtual_time += 0.05
		authority._flush_outbox(0.05); authority._flush_anchors(0.05)
		_enqueue(host_wire, false); _enqueue(client_wire, true)
		_deliver_due()
		if packets.is_empty() and host_wire.sent.is_empty() and client_wire.sent.is_empty() and authority._outbox.is_empty() and authority._anchor_outbox.is_empty(): break
	client._apply_view()

func _pause_and_recover() -> void:
	check(host.set_match_paused(true, 2).accepted, "motion fixture accepts multiplayer pause")
	authority._publish_step(0.0); flush()
	client.process(0.0)
	var frozen := _sample()
	var frozen_time: float = replica.elapsed
	for _frame: int in 30: client.process(FRAME)
	check(replica.elapsed == frozen_time and _sample() == frozen, "pause freezes positions and shader animation")
	client._last_resync_ms = -10000
	client._request_resync("motion_recovery")
	client.process(FRAME)
	check(client._snapshot_loading and _sample() == frozen, "recovery wait retains frozen visible soldiers")
	authority._snapshot_sent_at.clear()
	flush(); client.process(0.0)
	check(replica.match_paused and not client._snapshot_loading and not client._recovery_waiting, "recovery preserves the paused match")
	check(replica.marches._units.size() == SOLDIERS and _sample().size() == tracked.size(), "recovery keeps every stable soldier identity visible")
	check(host.set_match_paused(false, 2).accepted, "motion fixture resumes multiplayer pause")
	authority._publish_step(0.0); flush()
	client._on_message(105, "time", {"time": host.elapsed, "tick": authority._tick, "seq": authority._seq})
	clock_received_at = virtual_time
	var resumed := _sample()
	for frame: int in 60: _step(frame, true)
	var after := _sample()
	check(after.has(tracked[0]) and float(after[tracked[0]][0]) > float(resumed[tracked[0]][0]) + 0.5, "ordinary visible movement resumes after recovery")
	_drain_network()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "pause and recovery preserve the canonical rule mirror")

func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value: float in values: total += value
	return total / maxi(1, values.size())

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty(): return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * fraction) - 1, 0, ordered.size() - 1)]
