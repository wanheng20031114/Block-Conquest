extends SceneTree
## Real battle replicas over serialized, reordered and selectively lost packets.
const Coordinator := preload("res://scripts/network/war_network_match.gd")
const Codec := preload("res://scripts/network/war_snapshot.gd")
const Protocol := preload("res://scripts/network/war_protocol.gd")
var checks := 0
var failures: Array[String] = []
var host: Node3D
var replica: Node3D
var authority: RefCounted
var client: RefCounted
var host_wire: FakeOnline
var client_wire: FakeOnline

class FakeOnline extends Node:
	signal match_started(config: Dictionary)
	signal match_message(sender: int, kind: String, payload: Dictionary)
	signal room_changed(room: Dictionary)
	signal state_changed(state: String)
	signal cursor_received(sender: int, payload: Dictionary)
	signal recovery_requested(player: int)
	var room: Dictionary
	var match_config: Dictionary
	var player_id: int
	var local_faction: int
	var is_host: bool
	var connection_state := "match"
	var sent: Array[Dictionary] = []
	var recovered: Array[int] = []
	var surrender_confirmations: Array[int] = []
	var invalid_packets := 0
	func abort_connection(_reason: String) -> void: connection_state = "disconnected"
	func loaded() -> void: pass
	func send_cursor(_payload: Dictionary) -> void: pass
	func complete_recovery(player: int, _epoch: int) -> void: recovered.append(player)
	func confirm_surrender(player: int) -> void: surrender_confirmations.append(player)
	func send_command(payload: Dictionary) -> void:
		send_match("command", payload, -1, 1, true)
	func send_match(kind: String, payload: Dictionary, target: int = -1, channel: int = 2, reliable: bool = true) -> void:
		if kind != "command" and not Protocol.valid_match_channel(kind, channel, reliable): invalid_packets += 1
		var bytes := Protocol.encode({"sender": player_id, "kind": kind, "payload": payload, "target": target, "channel": channel})
		if bytes.is_empty(): invalid_packets += 1; return
		sent.append(Protocol.decode(bytes))

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ", label)

func configuration() -> Dictionary:
	var value := {"map_id": "highland", "host_player_id": 105, "match_id": "replication-test", "code": "TESTAB", "revision": 1, "phase": "match", "slots": []}
	for f: int in 6:
		var human := f in [2, 5]
		value.slots.append({"slot_id": f, "faction_id": f, "team_id": f % 2, "kind": "human" if human else "bot", "commander": ["squirrel", "rabbit", "rabbit", "frog", "bear", "bear"][f], "player_id": 100 + f if human else -1, "name": "Player %d" % f, "ready": true, "connected": true, "controller": "human" if human else "bot", "control_epoch": 1, "surrendered": false})
	return value

func make_game(player: int) -> Node3D:
	var value: Node3D = load("res://scenes/block_war/block_war.tscn").instantiate()
	root.add_child(value)
	value.set_process(false)
	value.camera_rig.set_process(false)
	value.ai_enabled = false
	value.audio.muted = true
	value.configure_match(configuration(), player)
	return value

func make_wire(player: int) -> FakeOnline:
	var wire := FakeOnline.new()
	wire.room = configuration()
	wire.match_config = configuration()
	wire.player_id = player
	wire.local_faction = player - 100
	wire.is_host = player == 105
	root.add_child(wire)
	return wire

func deliver(wire: FakeOnline, target: RefCounted, reverse: bool = false, drop_anchors: bool = false) -> void:
	var packets := wire.sent
	wire.sent = []
	if reverse: packets.reverse()
	for packet: Dictionary in packets:
		if drop_anchors and packet.kind == "anchors": continue
		if packet.target >= 0 and packet.target != target.online.player_id: continue
		target._on_message(int(packet.sender), str(packet.kind), packet.payload)

func flush() -> void:
	for _round: int in 200:
		authority._flush_outbox(0.1)
		authority._flush_anchors(0.1)
		deliver(host_wire, client)
		deliver(client_wire, authority)
		if authority._outbox.is_empty() and authority._anchor_outbox.is_empty() and host_wire.sent.is_empty() and client_wire.sent.is_empty(): break
	client._apply_view()

func boundary(delta: float = Coordinator.STEP, loss: bool = false) -> void:
	authority.process(delta)
	deliver(host_wire, client, false, loss)
	client.process(delta)
	deliver(client_wire, authority)

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	check(not client._snapshot_loading, "initial chunked snapshot unlocks replica")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "JSON roundtrip preserves initial canonical checksum")
	if Codec.digest(client._mirror) != Codec.digest(authority._published):
		var a := JSON.stringify(authority._published, "", true, true)
		var b := JSON.stringify(client._mirror, "", true, true)
		for index: int in mini(a.length(), b.length()):
			if a[index] != b[index]:
				print("FIRST_DIFF ", index, " HOST ", a.substr(maxi(0,index-60),160), " CLIENT ", b.substr(maxi(0,index-60),160)); break
	check(replica.local_faction == 2 and host.local_faction == 5, "arbitrary host and client seats retained")
	check(replica.faction_skills[2].energy == 30.0 and replica.faction_skills[5].energy == 0.0, "only local private account restored")
	check(host_wire.recovered.has(102), "completed snapshot acknowledged on command channel")

	var source: WarBuilding = host.by_id[2]
	var target: WarBuilding = host.by_id[8]
	var original: float = source.population
	var command := {"seq": 1, "epoch": 1, "command": {"type": "dispatch", "source": 2, "target": 8, "percent": 50}}
	authority._receive_command(102, command)
	authority._receive_command(102, command)
	boundary()
	check(source.queued_population > 0 and source.population > original * 0.5, "command reserves troops without debiting the entire queue")
	print("DEPARTURE initial=", original, " remaining=", source.population, " queued=", source.queued_population, " units=",host.marches._units.size())
	check(authority._commands.is_empty(), "duplicate queued command only executes once")
	var first_units: int = host.marches._units.size()
	authority._receive_command(102, command)
	boundary()
	check(host.marches._units.size() == first_units, "replayed acknowledged command does not create another army")
	for i: int in 90:
		boundary(Coordinator.STEP, true)
		if i % 15 == 0:
			check(replica.by_id[2].queued_population == source.queued_population, "gradual queue departure is a reliable fact at %d" % i)
			check(Codec.digest(client._mirror) == Codec.digest(authority._published), "lossy movement does not corrupt facts at %d" % i)
			if i == 0:
				FileAccess.open("res://.local/replication-host.json", FileAccess.WRITE).store_string(JSON.stringify(authority._published, "", true, true))
				FileAccess.open("res://.local/replication-client.json", FileAccess.WRITE).store_string(JSON.stringify(client._mirror, "", true, true))
	check(source.queued_population == 0, "departure eventually completes")
	check(client.resync_count == 1, "normal snapshots and lossy anchors do not produce resync loops")

	# Reliable events may arrive on the bulk stream after later small events.
	var base: int = client._applied
	var event_list: Array[Dictionary] = []
	for i: int in 3:
		source.population -= 1.0
		authority._tick += 1
		host.elapsed += Coordinator.STEP
		authority._publish_step(Coordinator.STEP)
		for packet: Dictionary in host_wire.sent:
			if packet.kind == "events" and packet.payload.has("seq"): event_list.append(packet)
		host_wire.sent.clear()
	check(event_list.size() == 3, "three independent damage transactions published")
	for i: int in [2, 0, 0, 1]:
		var packet: Dictionary = event_list[i]
		client._on_message(105, "events", packet.payload)
	client._apply_view()
	check(client._applied == base + 3 and client._pending.is_empty(), "out of order and duplicate transactions apply once in order")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "reordered event mirror equals Host")

	# Fresh continuous snapshot data cannot change the hash baseline.
	host.simulate(0.2)
	authority._tick += 6
	authority._publish_step(0.2)
	deliver(host_wire, client)
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "fresh view and stale committed anchors have one consistent snapshot hash")
	var recovery_applied: int = client._applied
	var stale := {"state": client._mirror.duplicate(true), "view": client._view.duplicate(true), "seq": maxi(0, recovery_applied - 1), "through": recovery_applied, "epoch": 1, "account": client._account, "winner": -2}
	client._install_snapshot(stale)
	check(client._applied == recovery_applied, "old snapshot cannot rewind reliable state")

	# A baseline arriving ahead of the final bulk transaction must not return
	# control early, and pre-recovery presentation is deliberately discarded.
	client_wire.sent.clear()
	client._queued_visuals.append({"kind": "dispatch", "payload": {"faction": 2}})
	var catching_up := {"state": client._mirror.duplicate(true), "view": Codec.for_player(authority.codec.capture(host, authority._tick), -1), "seq": client._applied, "through": client._applied + 1, "epoch": 1, "account": client._account, "winner": -2}
	client._install_snapshot(catching_up)
	check(client._recovery_waiting and client._queued_visuals.is_empty(), "recovery discards old visuals and waits for its through boundary")
	check(not client_wire.sent.any(func(packet: Dictionary): return packet.kind == "ack"), "no recovered acknowledgement before later facts arrive")
	check(not client.submit({"type": "upgrade", "building": 2}).accepted, "input remains blocked while catching up")
	source.population -= 1.0
	host.elapsed += Coordinator.STEP
	authority._tick += 1
	authority._publish_step(Coordinator.STEP)
	deliver(host_wire, client)
	client._apply_view()
	check(not client._recovery_waiting and client_wire.sent.any(func(packet: Dictionary): return packet.kind == "ack"), "later transaction releases recovery acknowledgement")
	deliver(client_wire, authority)
	var large_size := 8 * 1024 * 1024
	client._receive_blob("snapshot_begin", {"id": "large-timeout", "purpose": "snapshot", "size": large_size, "raw_size": large_size, "parts": ceili(float(large_size) / Coordinator.CHUNK_BYTES), "hash": "a".repeat(64)})
	check(int(client._blobs["large-timeout"].deadline) - Time.get_ticks_msec() > 120000, "large valid transfer has a size-aware deadline")
	client._blobs.erase("large-timeout")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	var scheduled_size: int = authority._outbox_bytes
	authority._send_snapshot(102)
	check(authority._outbox_bytes == scheduled_size and authority._snapshot_transfers.has(102), "rapid resync does not cancel its only scheduled snapshot")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	check(authority._outbox_bytes <= scheduled_size + 64, "not-yet-started snapshots coalesce by recipient")
	flush()

	# One corrupt optional row cannot poison the revision of a valid replacement.
	var unit_key: String = client._mirror.units.keys()[0]
	var tick: int = authority._tick + 10
	var bad_anchor := {"group": "units", "rows": {unit_key: ["invalid"]}, "base": client._applied, "time": host.elapsed, "tick": tick}
	client._receive_anchor(bad_anchor)
	check(int(client._anchor_versions.get("units:" + unit_key, -1)) < tick, "invalid anchor does not consume its revision")
	var anchor_row: Array = client._mirror.units[unit_key].duplicate(true)
	anchor_row[1] += 0.1
	anchor_row[12] = host.elapsed
	bad_anchor.rows[unit_key] = roundi(float(anchor_row[1]) * 1000.0)
	client._receive_anchor(bad_anchor)
	check(client._anchor_versions.get("units:" + unit_key) == tick, "valid replacement of rejected anchor is accepted")
	client._apply_view()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "display corrections never mutate canonical checksum")

	# A pending command loses authority if the seat changes before the next tick.
	var queued_before: int = source.queued_population
	authority._receive_command(102, {"seq": 2, "epoch": 1, "command": {"type": "dispatch", "source": 2, "target": 8, "percent": 50}})
	host_wire.room.slots[2].controller = "bot"
	host_wire.room.slots[2].control_epoch = 2
	boundary()
	check(source.queued_population == queued_before, "expired control epoch blocks commands already in flight")
	host_wire.room.slots[2].controller = "human"
	authority._receive_command(102, {"seq": 3, "epoch": 1, "command": {"type": "upgrade", "building": 2}})
	check(authority._commands.is_empty(), "old epoch remains rejected after human resumes")

	var paused_at: float = host.elapsed
	host_wire.connection_state = "reconnecting"
	authority.process(5.0)
	check(host.elapsed == paused_at, "Host disconnect pauses rule time")
	host_wire.connection_state = "match"
	authority.process(Coordinator.STEP)
	check(host.elapsed - paused_at < 0.04, "resume never catches up five seconds of paused time")
	flush()

	# Final result can overtake a chunked final state but cannot freeze it early.
	client._on_message(105, "finished", {"winner": 1, "seq": authority._seq + 1})
	client._maybe_finish()
	check(not replica.finished, "result waits for final authoritative transaction")
	host._finish_match(1)
	authority._publish_step(0.0)
	flush()
	client._maybe_finish()
	check(replica.finished and replica.winner_team == 1, "result appears after final state installation")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "every message fits primitive and channel contracts")
	authority._outbox_bytes = Coordinator.MAX_OUTBOX_BYTES
	authority._send_blob("events", {"small": true}, -1)
	check(authority._aborted and host_wire.connection_state == "disconnected" and authority._outbox_bytes == 0, "exhausted transfer budget explicitly closes instead of silently dropping facts")
	print("REPLICATION checks=", checks, " failures=", failures.size(), " reliable_bytes=", authority.sent_rule_bytes, " resyncs=", client.resync_count)
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	quit(0 if failures.is_empty() else 1)
