extends SceneTree
## Compare the optimized sender with its prior implementation at wire boundaries.
const Coordinator := preload("res://scripts/network/war_network_match.gd")
var checks := 0
var failures: Array[String] = []

class CapturedOnline extends Node:
	var connection_state := "match"
	var sent: Array[Dictionary] = []
	var abort_reason := ""
	func send_match(kind: String, payload: Dictionary, target: int = -1, channel: int = 2, reliable: bool = true) -> void:
		sent.append({"kind": kind, "payload": payload.duplicate(true), "target": target, "channel": channel, "reliable": reliable})
	func abort_connection(reason: String) -> void:
		abort_reason = reason
		connection_state = "disconnected"

class CapturedGame extends Node:
	var simulation_paused := false

class LegacyCoordinator extends "res://scripts/network/war_network_match.gd":
	# Preserve both old entry points: large events used to serialize twice.
	func _send_payload(kind: String, payload: Dictionary, target: int = -1) -> void:
		var bytes := JSON.stringify(payload, "", true, true).to_utf8_buffer()
		sent_rule_bytes += bytes.size()
		if bytes.size() <= 12000: online.send_match(kind, payload, target)
		else: _send_blob(kind, payload, target)

	func _send_blob(purpose: String, payload: Dictionary, target: int) -> void:
		var raw := JSON.stringify(payload, "", true, true).to_utf8_buffer()
		if raw.size() > MAX_BLOB_BYTES:
			_abort_sync("对局同步数据超过容量上限，房间已结束"); return
		var bytes := raw.compress(FileAccess.COMPRESSION_ZSTD)
		if _outbox_bytes + bytes.size() * 2 + 2048 > MAX_OUTBOX_BYTES:
			_abort_sync("网络同步持续积压，房间已结束，请检查房主上行网络"); return
		_blob_serial += 1
		var id := "%d:%d" % [_tick, _blob_serial]
		if purpose == "snapshot": _snapshot_transfers[target] = {"id": id, "started": false}
		var parts := ceili(float(bytes.size()) / CHUNK_BYTES)
		_queue("snapshot_begin", {"id": id, "purpose": purpose, "size": bytes.size(), "raw_size": raw.size(), "parts": parts, "hash": bytes.hex_encode().sha256_text()}, target)
		for index: int in parts:
			_queue("snapshot_chunk", {"id": id, "index": index, "data": Marshalls.raw_to_base64(bytes.slice(index * CHUNK_BYTES, mini(bytes.size(), (index + 1) * CHUNK_BYTES)))}, target)
		_queue("snapshot_end", {"id": id, "purpose": purpose}, target)

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	_compare("small Unicode event", {"text": "城堡与士气 🏰", "seq": 7, "rows": [null, true, -0.0, 0.125, {"z": 2, "a": 1}]})
	_compare("12000-byte direct event", _sized_payload(12000))
	_compare("12001-byte bulk event", _sized_payload(12001))
	var army := {"seq": 7, "set": {"units": {}}, "remove": {}, "visuals": []}
	for index: int in 4096:
		army.set.units[str(index + 1)] = [1, index * 0.125, index % 4, false, index, 0.0, 0.0, 0.0, false, false, false, -1, 2.5, index * 0.75]
	_compare("multi-chunk army event", army)
	_compare("snapshot envelope", {"state": army, "view": army, "seq": 7, "epoch": 4, "account": ["熊", 37.25], "winner": -2}, true)
	# Simulate exhausted accounting without allocating a 48 MiB queue.
	_compare("event queue capacity", army, false, true)
	_compare("snapshot queue capacity", army, true, true)
	# These highly compressible inputs exercise the actual 8 MiB boundary while
	# keeping queued and captured wire data small. Each case releases its input.
	_compare("raw limit accepted", _sized_payload(Coordinator.MAX_BLOB_BYTES))
	_compare("raw limit event rejected", _sized_payload(Coordinator.MAX_BLOB_BYTES + 1))
	_compare("raw limit snapshot rejected", _sized_payload(Coordinator.MAX_BLOB_BYTES + 1), true)
	_check_record_times()
	print("BLOB_EQUIVALENCE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _sized_payload(byte_count: int) -> Dictionary:
	var overhead := JSON.stringify({"text": ""}, "", true, true).to_utf8_buffer().size()
	return {"text": "x".repeat(byte_count - overhead)}

func _compare(label: String, payload: Dictionary, snapshot: bool = false, exhausted: bool = false) -> void:
	var reference := LegacyCoordinator.new()
	var candidate := Coordinator.new()
	var raw_size := JSON.stringify(payload, "", true, true).to_utf8_buffer().size()
	var oversized := raw_size > Coordinator.MAX_BLOB_BYTES
	var expect_abort := exhausted or oversized
	var bulk := snapshot or raw_size > 12000
	for sender: RefCounted in [reference, candidate]:
		sender.online = CapturedOnline.new()
		sender.game = CapturedGame.new()
		sender._tick = 47
		sender._seq = 17
		sender._blob_serial = 3
		sender._recovery_baselines[23] = {"seq": 7, "epoch": 4}
		# Keep an earlier queued chunk so ordering and failure cleanup are visible.
		sender._queue("snapshot_chunk", {"id": "older:1", "index": 0, "data": "AA=="}, 18)
		if exhausted: sender._outbox_bytes = Coordinator.MAX_OUTBOX_BYTES
		if snapshot: sender._send_blob("snapshot", payload, 23)
		else: sender._send_payload("events", payload, 23)
	check(_encoded(_sender_state(reference)) == _encoded(_sender_state(candidate)), label + " preserves queue, metadata, accounting, serial and abort state")
	check(candidate.sent_rule_bytes == (0 if snapshot else raw_size), label + " preserves raw event metering")
	check(candidate._aborted == expect_abort and candidate.game.simulation_paused == expect_abort, label + " preserves capacity decisions")
	if expect_abort:
		var reason := "对局同步数据超过容量上限，房间已结束" if oversized else "网络同步持续积压，房间已结束，请检查房主上行网络"
		check(candidate.online.abort_reason == reason and candidate.online.connection_state == "disconnected", label + " preserves the failure reason and disconnect")
		check(candidate._outbox.is_empty() and candidate._outbox_bytes == 0 and candidate._blob_serial == 3, label + " clears queued data without consuming a blob ID")
	elif bulk:
		_check_blob(label, candidate, payload, snapshot)
	else:
		check(candidate._outbox.size() == 1 and candidate.online.sent.size() == 1, label + " keeps the direct event outside the bulk queue")
		check(candidate.online.sent[0].kind == "events" and candidate.online.sent[0].target == 23, label + " preserves direct event routing")
	# Flush in multiple bounded token-budget steps through the real shared method.
	for sender: RefCounted in [reference, candidate]:
		for _step: int in 1024:
			if sender._outbox.is_empty(): break
			sender._flush_outbox(0.05)
	check(reference._outbox.is_empty() and candidate._outbox.is_empty(), label + " drains the finite fixture")
	check(_encoded(_sender_state(reference)) == _encoded(_sender_state(candidate)), label + " preserves every flushed packet and final bookkeeping")
	var channels_valid := true
	for packet: Dictionary in candidate.online.sent:
		channels_valid = channels_valid and packet.reliable and int(packet.channel) == (2 if packet.kind == "events" else 5)
	check(channels_valid, label + " retains reliable event and bulk channels")
	if snapshot and not expect_abort:
		check(candidate.online.sent[-1].payload.through == 17 and candidate._recovery_baselines[23].seq == 17 and candidate._snapshot_transfers.is_empty(), label + " retains recovery completion bookkeeping")
	for sender: RefCounted in [reference, candidate]:
		sender.online.free()
		sender.game.free()

func _check_blob(label: String, sender: RefCounted, payload: Dictionary, snapshot: bool) -> void:
	var entries: Array = sender._outbox
	var meta: Dictionary = entries[1].payload
	check(entries[0].payload.id == "older:1" and entries[1].kind == "snapshot_begin" and entries[-1].kind == "snapshot_end", label + " preserves manifest and end ordering behind existing traffic")
	check(meta.id == "47:4" and meta.purpose == ("snapshot" if snapshot else "events") and int(meta.parts) == entries.size() - 3, label + " retains blob identity, purpose and chunk count")
	var compressed := PackedByteArray()
	var chunks_valid := true
	for index: int in int(meta.parts):
		var entry: Dictionary = entries[index + 2]
		var chunk := Marshalls.base64_to_raw(entry.payload.data)
		chunks_valid = chunks_valid and entry.kind == "snapshot_chunk" and entry.target == 23 and entry.payload.id == meta.id and int(entry.payload.index) == index and chunk.size() <= Coordinator.CHUNK_BYTES
		compressed.append_array(chunk)
	check(chunks_valid and compressed.size() == int(meta.size) and compressed.hex_encode().sha256_text() == meta.hash, label + " preserves chunk order and compressed-byte hash")
	check(compressed.decompress(int(meta.raw_size), FileAccess.COMPRESSION_ZSTD) == _encoded(payload), label + " restores the exact canonical JSON bytes")
	var counted_bytes := 0
	for entry: Dictionary in entries:
		counted_bytes += _encoded(entry.payload).size() + 160
	check(counted_bytes == sender._outbox_bytes, label + " retains exact queue byte accounting")

func _sender_state(sender: RefCounted) -> Dictionary:
	return {"queue": sender._outbox, "queue_bytes": sender._outbox_bytes, "raw_bytes": sender.sent_rule_bytes,
		"serial": sender._blob_serial, "transfers": sender._snapshot_transfers, "recovery": sender._recovery_baselines,
		"tokens": sender._bulk_tokens, "sent": sender.online.sent, "aborted": sender._aborted,
		"paused": sender.game.simulation_paused, "reason": sender.online.abort_reason, "connection": sender.online.connection_state}

func _encoded(value: Dictionary) -> PackedByteArray:
	return JSON.stringify(value, "", true, true).to_utf8_buffer()

func _check_record_times() -> void:
	var sender := Coordinator.new()
	for group: String in ["buildings", "factions", "units"]:
		var index: int = {"buildings": 11, "factions": 8, "units": 12}[group]
		var row: Array = []
		row.resize(index + 1)
		for value: Variant in [0, 12.5, -1.0, "12.5", null, INF, NAN]:
			row[index] = value
			var expected := float(value) if Coordinator.Snapshot._number(value) else -1.0
			check(sender._record_time(group, row) == expected, group + " preserves record-time type and finite-number handling")
		check(sender._record_time(group, []) == -1.0 and sender._record_time(group, null) == -1.0, group + " preserves absent record-time handling")
