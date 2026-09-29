extends SceneTree
## Six native DTLS humans plus a second room; bounded realistic correction traffic.
const Relay := preload("res://server/war_relay_server.gd")
const Online := preload("res://scripts/network/war_online.gd")
const P := preload("res://scripts/network/war_protocol.gd")
const TLSFixture := preload("res://tests/network_tls_fixture.gd")
var tls := TLSFixture.new()
var server: Node
var clients: Array[Node] = []
var events: Dictionary = {}
var anchors: Dictionary = {}
var chunks: Dictionary = {}
var cursors: Dictionary = {}
var errors: Array[String] = []
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(passed: bool, text: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(text)

func until(predicate: Callable, description: String, timeout: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	var passed: bool = predicate.call()
	check(passed, description)
	return passed

func client(index: int, port: int) -> Node:
	var value := Online.new()
	value.certificate_path = tls.certificate_path
	value.content_hash = "load-fixture"
	root.add_child(value)
	value.match_message.connect(func(_sender: int, kind: String, _payload: Dictionary):
		if kind == "events": events[index] = int(events.get(index, 0)) + 1
		if kind == "anchors": anchors[index] = int(anchors.get(index, 0)) + 1
		if kind == "snapshot_chunk": chunks[index] = int(chunks.get(index, 0)) + 1)
	value.cursor_received.connect(func(_sender: int, _payload: Dictionary): cursors[index] = int(cursors.get(index, 0)) + 1)
	value.error_received.connect(func(message: String): errors.append(message))
	clients.append(value)
	value.connect_relay("127.0.0.1", port)
	return value

func _run() -> void:
	create_timer(60, true, false, true).timeout.connect(func(): _finish(3))
	var certificate_error := tls.create("load")
	check(certificate_error == OK, "load test creates its own local DTLS identity")
	if certificate_error != OK: return _finish()
	server = Relay.new()
	server.model.content_hash = "load-fixture"
	root.add_child(server)
	var start_error: Error = server.start("127.0.0.1", 0, tls.key_path, tls.certificate_path)
	check(start_error == OK, "six-player relay starts with validated trust")
	if start_error != OK: return _finish()
	var port: int = server.connection.get_local_port()
	for index: int in 7: client(index, port)
	if not await until(func(): return clients.all(func(value: Node): return value.connection_state == "connected"), "seven independent encrypted connections complete handshake"): return _finish()
	var host: Node = clients[0]
	host.create_room("islands", "六人房主")
	if not await until(func(): return not host.room.is_empty(), "six-seat room created"): return _finish()
	host.move_to_slot(5)
	await until(func(): return host.local_faction == 5, "six-player Host moves to slot five")
	for index: int in range(1, 6):
		clients[index].join_room(host.room.code, "玩家%d" % index)
		if not await until(func(): return clients[index].local_faction == index - 1, "joining player preserves fixed slot %d" % (index - 1)): return _finish()
	clients[6].create_room("rift", "另一房间")
	await until(func(): return not clients[6].room.is_empty(), "independent second room coexists")
	for index: int in 6: clients[index].choose_commander(P.COMMANDERS[index % 4])
	await until(func(): return host.room.slots[0].commander == "rabbit" and host.room.slots[1].commander == "bear" and host.room.slots[2].commander == "frog", "mixed commanders remain per-seat in six-human room")
	for index: int in 6: clients[index].set_ready(true)
	await until(func(): return host.room.slots.all(func(slot: Dictionary): return slot.ready), "six humans prepare together")
	host.start_match()
	await until(func(): return clients.slice(0, 6).all(func(value: Node): return value.connection_state == "loading" and not value.match_config.is_empty()), "six manifests precede start barrier")
	for index: int in 6: clients[index].loaded()
	if not await until(func(): return clients.slice(0, 6).all(func(value: Node): return value.connection_state == "match"), "six-human match starts"): return _finish()
	host.send_match("events", {"scope": "foreign"}, clients[6].player_id)
	await create_timer(0.1).timeout
	check(not events.has(6), "Host cannot route private facts into another room")
	clients[2].send_cursor({"cursor_seq": 1, "presence_epoch": 1, "world_x": 13, "world_z": 9, "visible": true, "pressed": false})
	await until(func(): return int(cursors.get(0, 0)) == 1 and int(cursors.get(4, 0)) == 1, "six-player cursor goes to exactly two allied humans")
	check(not cursors.has(1) and not cursors.has(3) and not cursors.has(5) and not cursors.has(6), "all three enemies and other room receive no cursor")
	# 8192 troops at 2 Hz / 32 troop anchors per packet = 512 correction packets/s.
	# Add 30 reliable event batches/s and a concurrent recovery stream. The loop
	# follows wall time rather than frame rate and reports achieved counts.
	var began := Time.get_ticks_msec()
	var sent_anchors := 0
	var sent_events := 0
	var sent_chunks := 0
	var duration := 4.0
	var bytes_before: int = host.sent_bytes
	while float(Time.get_ticks_msec() - began) / 1000.0 < duration:
		var elapsed := minf(duration, float(Time.get_ticks_msec() - began) / 1000.0)
		var desired := int(elapsed * 512.0)
		while sent_anchors < desired:
			var rows: Array = []
			for unit: int in 32: rows.append([sent_anchors * 32 + unit, 12500])
			host.send_match("anchors", {"tick": sent_anchors, "units": rows}, -1, 4, false)
			sent_anchors += 1
		while sent_events < int(elapsed * 30.0):
			host.send_match("events", {"seq": sent_events, "transactions": [{"kind": "depart", "population": 49.5}]})
			sent_events += 1
		while sent_chunks < int(elapsed * 160.0):
			var destination := sent_chunks % 5 + 1
			host.send_match("snapshot_chunk", {"index": sent_chunks, "data": "x".repeat(1024)}, clients[destination].player_id, 5, true)
			sent_chunks += 1
		await process_frame
	var elapsed_ms := Time.get_ticks_msec() - began
	await until(func(): return events.values().reduce(func(total: int, value: Variant): return total + int(value), 0) >= sent_events * 5, "all reliable battle batches survive full six-player correction load")
	await until(func(): return chunks.values().reduce(func(total: int, value: Variant): return total + int(value), 0) == sent_chunks, "concurrent recovery chunks drain completely without silent loss")
	for index: int in range(1, 6):
		check(int(events.get(index, 0)) == sent_events, "each mirror receives every event exactly once")
		check(int(anchors.get(index, 0)) > sent_anchors / 2, "each mirror keeps receiving disposable corrections under load")
	check(clients.slice(0, 6).all(func(value: Node): return value.connection_state == "match"), "healthy six-player traffic does not trip relay protection")
	check(errors.is_empty(), "no rate-limit, queue or protocol errors at 8192-unit anchor-equivalent load")
	print("BLOCK_WAR_NETWORK_LOAD_METRICS " + JSON.stringify({"duration_ms": elapsed_ms, "sent_anchors": sent_anchors, "sent_events": sent_events, "sent_chunks": sent_chunks, "host_bytes": host.sent_bytes - bytes_before, "received_anchors": anchors, "received_events": events, "received_chunks": chunks}))
	_finish()

func _finish(code: int = -1) -> void:
	for value: Node in clients:
		value.disconnect_relay()
		value.free()
	clients.clear()
	if server != null:
		server.stop()
		server.free()
		server = null
	check(tls.cleanup() == OK, "load test removes its local TLS files after shutdown")
	print("BLOCK_WAR_NETWORK_LOAD checks=%d failures=%d" % [checks, failures])
	quit(code if code >= 0 else (0 if failures == 0 else 1))
