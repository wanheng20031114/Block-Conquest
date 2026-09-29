extends SceneTree
## Reliable progress and bounded bulk transfers must not look like lost events.
const Coordinator := preload("res://scripts/network/war_network_match.gd")
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
var checks := 0
var failures: Array[String] = []

class StateFixture extends Node:
	const MORALE := preload("res://scripts/block_war/war_morale.gd")
	var buildings: Array = []
	var by_id: Dictionary = {}
	var faction_count := 1
	var initial_human_factions: Array[int] = [0]

class Subject extends "res://scripts/network/war_network_match.gd":
	var requests: Array[String] = []
	func _request_resync(reason: String = "recovery") -> void:
		requests.append(reason)
		_snapshot_loading = true

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	_check_progress()
	_check_no_transfer()
	_check_pinned_deadline()
	_check_unrelated_completion()
	_check_missing_event_completion()
	_check_transfer_selection()
	_check_reset_boundaries()
	print("EVENT_GAP checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _subject() -> Subject:
	var value := Subject.new()
	value.game = StateFixture.new()
	value._snapshot_loading = false
	var counters: Array = []
	counters.resize(Snapshot.COUNTER_SIZE)
	counters.fill(1)
	counters[2] = 0
	value._mirror = {"schema": Snapshot.SCHEMA, "tick": 0, "time": 0.0, "finished": false, "winner": -2,
		"counters": counters, "match_control": {"paused": false, "by": -1, "surrendered": []}}
	for group: String in Snapshot.GROUPS: value._mirror[group] = {}
	value._mirror.factions["0"] = ["squirrel", 0.0, [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], -1,
		0.0, 0.0, 10.0, 0.0, Snapshot.RULES.natural_energy_regen(0.0), [1, 1, 1, 1]]
	check(Snapshot.valid(value._mirror, value.game), "minimal authority fixture satisfies the full current schema")
	return value

func _patch(seq: int) -> Dictionary:
	var counters: Array = []
	counters.resize(Snapshot.COUNTER_SIZE)
	counters.fill(1)
	counters[2] = 0
	return {"seq": seq, "tick": seq, "time": float(seq) / 30.0, "finished": false, "winner": -2,
		"set": {}, "remove": {}, "visuals": [], "counters": counters,
		"match_control": {"paused": false, "by": -1, "surrendered": []}}

func _begin(value: Subject, id: String, seq: int, deadline: int, purpose: String = "events") -> PackedByteArray:
	var raw := JSON.stringify(_patch(seq), "", true, true).to_utf8_buffer()
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	value._receive_blob("snapshot_begin", {"id": id, "purpose": purpose, "size": compressed.size(), "raw_size": raw.size(),
		"parts": ceili(float(compressed.size()) / Coordinator.CHUNK_BYTES), "hash": compressed.hex_encode().sha256_text()})
	# Only the wall-clock coordinate is controlled; metadata/chunks/end use the
	# actual production receiver and ordinary compression/hash validation.
	value._blobs[id].deadline = deadline
	return compressed

func _complete(value: Subject, id: String, compressed: PackedByteArray) -> void:
	for index: int in ceili(float(compressed.size()) / Coordinator.CHUNK_BYTES):
		var chunk := compressed.slice(index * Coordinator.CHUNK_BYTES, mini(compressed.size(), (index + 1) * Coordinator.CHUNK_BYTES))
		value._receive_blob("snapshot_chunk", {"id": id, "index": index, "data": Marshalls.raw_to_base64(chunk)})
	value._receive_blob("snapshot_end", {"id": id, "purpose": "events"})

func _check_progress() -> void:
	var value := _subject()
	value._receive_events(_patch(2))
	for cycle: int in 6:
		value._check_event_gap(0.8, (cycle + 1) * 800)
		check(value.requests.is_empty(), "continuous ordered progress does not exhaust one shared two-second timer")
		# Queue the next gap before resolving this one, so pending never empties.
		value._receive_events(_patch(value._applied + 4))
		value._gap_transfer = {"id": "earlier-gap", "deadline": 100000}
		value._receive_events(_patch(value._applied + 1))
		check(value._applied == (cycle + 1) * 2 and value._pending.size() == 1, "complete transactions advance while the next gap stays queued")
		check(value._gap_age == 0.0 and value._gap_transfer.is_empty(), "each committed sequence clears the prior gap age and transfer allowance")
	value.game.free()

func _check_no_transfer() -> void:
	var value := _subject()
	value._receive_events(_patch(2))
	value._check_event_gap(2.0, 2000)
	check(value.requests.is_empty(), "the original two-second grace remains inclusive")
	value._check_event_gap(0.01, 2010)
	check(value.requests == ["event_gap"], "a stalled gap without a bulk transfer still requests recovery")
	value.game.free()
	value = _subject()
	value._receive_events(_patch(2))
	_begin(value, "snapshot-only", 1, 100000, "snapshot")
	value._check_event_gap(2.1, 2100)
	check(value.requests == ["event_gap"], "an unrelated snapshot does not extend an event gap")
	value.game.free()

func _check_pinned_deadline() -> void:
	var value := _subject()
	value._receive_events(_patch(2))
	_begin(value, "slow-event", 1, 10000)
	value._check_event_gap(2.1, 2100)
	check(value.requests.is_empty() and value._gap_transfer.id == "slow-event", "an active event transfer may outlive the ordinary gap grace")
	check(value._gap_transfer.deadline == 10000, "the gap captures the existing absolute transfer deadline")
	# Neither another transfer nor reusing the same ID can prolong this gap.
	_begin(value, "later-event", 3, 50000)
	_begin(value, "slow-event", 1, 90000)
	value._check_event_gap(7.8, 9900)
	check(value.requests.is_empty() and value._gap_transfer.deadline == 10000, "new or replaced manifests cannot extend the pinned deadline")
	value._check_event_gap(0.1, 10000)
	check(value.requests == ["event_gap"], "the original deadline remains a hard bound even with live replacement blobs")
	value.game.free()

func _check_unrelated_completion() -> void:
	var value := _subject()
	value._receive_events(_patch(3))
	var compressed := _begin(value, "unrelated-event", 2, 10000)
	value._check_event_gap(2.1, 2100)
	_complete(value, "unrelated-event", compressed)
	check(value._applied == 0 and value._pending.size() == 2, "a valid later blob cannot bypass the still-missing first transaction")
	_begin(value, "another-event", 4, 100000)
	value._check_event_gap(0.1, 2200)
	check(value.requests == ["event_gap"], "finishing an unrelated blob cannot roll the gap onto a newer transfer")
	value.game.free()

func _check_missing_event_completion() -> void:
	var value := _subject()
	value._receive_events(_patch(2))
	var compressed := _begin(value, "missing-event", 1, 10000)
	value._check_event_gap(2.1, 2100)
	_complete(value, "missing-event", compressed)
	check(value._applied == 2 and value._pending.is_empty() and value.requests.is_empty(), "the missing compressed event commits before the waiting later fact")
	check(value._gap_age == 0.0 and value._gap_transfer.is_empty(), "successful bulk progress releases the old allowance")
	value._receive_events(_patch(4))
	value._check_event_gap(1.9, 4000)
	check(value.requests.is_empty(), "a new gap receives its own grace after bulk completion")
	value._check_event_gap(0.2, 4200)
	check(value.requests == ["event_gap"], "a later gap cannot reuse the completed blob's deadline")
	value.game.free()

func _check_transfer_selection() -> void:
	var value := _subject()
	value._receive_events(_patch(2))
	_begin(value, "longer", 3, 12000)
	_begin(value, "earlier", 1, 8000)
	_begin(value, "unrelated-snapshot", 1, 3000, "snapshot")
	value._check_event_gap(2.1, 2100)
	check(value.requests.is_empty() and value._gap_transfer.id == "earlier", "multiple active event transfers use the earliest bounded deadline")
	value._blobs.erase("earlier")
	value._check_event_gap(0.1, 2200)
	check(value.requests == ["event_gap"], "retiring the chosen transfer cannot silently switch to a longer one")
	value.game.free()

func _check_reset_boundaries() -> void:
	var value := _subject()
	value._gap_age = 5.0
	value._gap_transfer = {"id": "old", "deadline": 10000}
	value._check_event_gap(1.0, 6000)
	check(value._gap_age == 0.0 and value._gap_transfer.is_empty(), "an empty pending queue clears gap bookkeeping")
	value._receive_events(_patch(2))
	value._snapshot_loading = true
	value._gap_age = 5.0
	value._gap_transfer = {"id": "old", "deadline": 10000}
	value._check_event_gap(10.0, 15000)
	check(value.requests.is_empty() and value._gap_age == 0.0 and value._gap_transfer.is_empty(), "an existing snapshot recovery owns its own deadline without duplicate gap recovery")
	value.game.free()
