extends SceneTree
## Real loopback ENet/DTLS verifies sampling validity without contacting Tokyo.

const Relay := preload("res://server/war_relay_server.gd")
const Online := preload("res://scripts/network/war_online.gd")
const TLSFixture := preload("res://tests/network_tls_fixture.gd")
var tls := TLSFixture.new()
var relay: Node
var online: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func until(predicate: Callable, description: String, seconds: float = 4.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = predicate.call()
	check(passed, description)
	return passed

func unavailable(description: String) -> void:
	var sample: Dictionary = online.transport_diagnostics()
	check(not sample.connected, description + " is not a connected relay")
	check(sample.relay_rtt_ms == -1.0 and sample.relay_jitter_ms == -1.0 and sample.loss_percent == -1.0,
		description + " exposes unavailable measurements instead of zero/default RTT")
	check(sample.last_received_age_ms == -1, description + " has no current receive age")

func _run() -> void:
	create_timer(25.0).timeout.connect(func():
		check(false, "diagnostics test deadline")
		_finish())
	var error := tls.create("diagnostics")
	check(error == OK, "local disposable DTLS identity")
	if error != OK: return _finish()
	relay = Relay.new()
	relay.model.content_hash = "transport-diagnostics-test"
	root.add_child(relay)
	error = relay.start("127.0.0.1", 0, tls.key_path, tls.certificate_path)
	check(error == OK, "local relay binds an ephemeral UDP port")
	if error != OK: return _finish()
	online = Online.new()
	online.content_hash = relay.model.content_hash
	online.certificate_path = tls.certificate_path
	root.add_child(online)
	unavailable("never connected")
	var port: int = relay.connection.get_local_port()
	check(online.connect_relay("127.0.0.1", port) == OK, "begin local DTLS connection")
	unavailable("initial handshake")
	if not await until(func(): return online.transport_diagnostics().connected, "application handshake completes"): return _finish()
	check(online.transport_diagnostics().loss_percent == -1.0, "new peer waits for the first actual loss window")
	if not await until(func(): return online.transport_diagnostics().relay_rtt_ms > 0.0, "native reliable ACK supplies measured RTT"): return _finish()
	var sample: Dictionary = online.transport_diagnostics()
	check(sample.relay_rtt_ms == online._peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), "RTT uses the native millisecond statistic")
	check(sample.relay_jitter_ms == online._peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE), "jitter uses native millisecond deviation")
	check(sample.last_received_age_ms >= 0 and sample.last_received_age_ms < 2000, "receive age belongs to this connected peer")
	check(sample.sent_bytes > 0 and sample.received_bytes > 0, "existing handshake traffic supplies payload counters")
	# No frame/service runs during the following reads. Flush already queued
	# work first so a getter that queues an extra ping cannot hide behind it.
	online._connection.flush()
	online._connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var sent_before: int = online.sent_bytes
	var received_before: int = online.received_bytes
	var queue_before: int = online._bulk_bytes
	var heartbeat_before: int = online._heartbeat_at
	for index: int in 100:
		online.transport_diagnostics()
	online._connection.flush()
	check(online._connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS) == 0.0, "diagnostic reads neither send nor queue native packets")
	check(online.sent_bytes == sent_before and online.received_bytes == received_before and online._bulk_bytes == queue_before,
		"diagnostic reads leave payload counters and bulk queue unchanged")
	check(online._heartbeat_at == heartbeat_before, "diagnostic reads do not reschedule the existing heartbeat")
	if not await until(func(): return online.transport_diagnostics().loss_percent >= 0.0, "native ten-second loss window becomes available", 13.0): return _finish()
	sample = online.transport_diagnostics()
	check(sample.loss_percent == online._peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) * 100.0 / ENetPacketPeer.PACKET_LOSS_SCALE,
		"loss percentage uses ENet's reliable-packet ratio and scale")
	online.disconnect_relay()
	unavailable("disconnected")
	check(online.connect_relay("127.0.0.1", port) == OK, "new transport can reconnect")
	unavailable("reconnecting handshake")
	if not await until(func(): return online.transport_diagnostics().connected, "second native handshake completes"): return _finish()
	check(online.transport_diagnostics().loss_percent == -1.0, "reconnected peer does not reuse the preceding loss sample")
	_finish()

func _finish() -> void:
	if online != null:
		online.free()
		online = null
	if relay != null:
		relay.free()
		relay = null
	check(tls.cleanup() == OK, "owned certificate files removed")
	print("TRANSPORT DIAGNOSTICS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
