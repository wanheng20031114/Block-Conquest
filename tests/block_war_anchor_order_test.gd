extends SceneTree
## Optional anchors may overtake reliable facts, but never become those facts.
const Coordinator := preload("res://scripts/network/war_network_match.gd")
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
var checks := 0
var failures: Array[String] = []

class StateFixture extends Node:
	const MORALE := preload("res://scripts/block_war/war_morale.gd")
	var buildings: Array = [0, 1]
	var by_id := {0: true, 1: true}
	var faction_count := 1
	var initial_human_factions: Array[int] = [0]
	var elapsed := 0.0

class Subject extends "res://scripts/network/war_network_match.gd":
	var requests: Array[String] = []
	func _request_resync(reason: String = "recovery") -> void:
		requests.append(reason)
		_snapshot_loading = true
	func _apply_view(_defer_render: bool = false) -> void: pass
	func _try_recovery_ack() -> void: pass
	func _local_slot() -> Dictionary: return {"control_epoch": 1}

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	_check_overtaking()
	_check_new_entity()
	_check_deletion()
	_check_route_change(false)
	_check_route_change(true)
	_check_structure()
	_check_replacement()
	_check_capacity()
	_check_snapshot_reset()
	print("ANCHOR_ORDER checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _subject() -> Subject:
	var value := Subject.new()
	value.game = StateFixture.new()
	value._snapshot_loading = false
	value._mirror = {"schema": Snapshot.SCHEMA, "tick": 0, "time": 0.0, "finished": false, "winner": -2,
		"counters": [10, 100, 0, 1, 1, 1], "match_control": {"paused": false, "by": -1, "surrendered": []}}
	for group: String in Snapshot.GROUPS: value._mirror[group] = {}
	for key: String in ["0", "1"]:
		value._mirror.buildings[key] = [0, 0, 1, 10.0, 0, 0.0, 0, -1, 0.0, 0.0, 0.0, 0.0]
	value._mirror.factions["0"] = ["squirrel", 0.0, [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], -1,
		0.0, 0.0, 10.0, 0.0, Snapshot.RULES.natural_energy_regen(0.0), [1, 1, 1, 1]]
	value._mirror.orders["1"] = [0, 1, 0, 1.0, false, 0.0, [[0.0, 0.0, 0.0], [100.0, 0.0, 0.0]], false, false, false, false, false, false]
	value._mirror.units["1"] = [1, 2.0, 0.0, false, 0, 0.0, 0.0, 0.0, false, false, false, -1, 0.0, 0.0, 0.0]
	check(Snapshot.valid(value._mirror, value.game), "fixture includes fully validated buildings, order and moving soldier")
	return value

func _event(seq: int, at_time: float, writes: Dictionary = {}, removes: Dictionary = {}) -> Dictionary:
	return {"seq": seq, "tick": seq, "time": at_time, "finished": false, "winner": -2,
		"set": writes, "remove": removes, "visuals": [], "counters": [10, 100, 0, 1, 1, 1],
		"match_control": {"paused": false, "by": -1, "surrendered": []}}

func _anchor(base: int, tick: int, at_time: float, distance: float, key: String = "1") -> Dictionary:
	return {"base": base, "tick": tick, "time": at_time, "group": "units", "rows": {key: roundi(distance * 1000.0)}}

func _check_overtaking() -> void:
	var value := _subject()
	var canonical := Snapshot.digest(value._mirror)
	value._receive_anchor(_anchor(1, 20, 1.0, 3.0))
	check(value._pending_anchors.size() == 1 and value._anchor_state.is_empty(), "a future anchor waits without entering presentation")
	check(value._host_tick == -1 and value._host_time == 0.0 and not value._view_dirty, "queueing does not advance authority time or mark an install")
	check(Snapshot.digest(value._mirror) == canonical, "queueing cannot change committed rule state")
	value._receive_events(_event(1, 0.5))
	check(value._pending_anchors.is_empty() and value._anchor_state.units["1"][1] == 3.0, "the reliable base unlocks the overtaking distance correction")
	check(value._anchor_versions["units:1"] == 20 and value._host_tick == 20 and value._host_time == 1.0, "only the validated replay advances anchor version and authority clock")
	check(value._mirror.units["1"][1] == 2.0 and value.requests.is_empty(), "replayed optional data neither changes canonical distance nor requests recovery")
	value.game.free()

func _check_new_entity() -> void:
	var value := _subject()
	value._receive_anchor(_anchor(1, 20, 1.0, 5.0, "2"))
	var row: Array = value._mirror.units["1"].duplicate()
	row[1] = 4.0
	row[12] = 0.5
	value._receive_events(_event(1, 0.5, {"units": {"2": row}}))
	check(value._applied == 1 and value._anchor_state.units["2"][1] == 5.0, "an anchor may wait for its soldier's creation transaction")
	check(value._mirror.units["2"][1] == 4.0 and value._pending_anchors.is_empty(), "new-entity replay still preserves canonical data")
	value.game.free()

func _check_deletion() -> void:
	var value := _subject()
	value._receive_anchor(_anchor(1, 20, 1.0, 3.0))
	value._receive_events(_event(1, 0.5, {}, {"units": ["1"]}))
	check(value._applied == 1 and value._pending_anchors.is_empty(), "a reached base retires a queued row even when the soldier was deleted")
	check(not value._anchor_state.get("units", {}).has("1") and not value._anchor_versions.has("units:1"), "an old anchor cannot recreate a removed soldier")
	check(value._host_tick == 1 and value._host_time == 0.5, "a rejected deleted-entity anchor cannot advance authority time")
	value.game.free()

func _check_route_change(same_time: bool) -> void:
	var value := _subject()
	var changed_at := 1.0 if same_time else 2.0
	value._receive_anchor(_anchor(1, 20, 1.0, 3.0))
	var row: Array = value._mirror.units["1"].duplicate()
	row[0] = 2
	row[1] = 98.0
	row[12] = changed_at
	var order: Array = value._mirror.orders["1"].duplicate(true)
	order[0] = 1
	order[1] = 0
	order[4] = true
	value._receive_events(_event(2, changed_at, {"orders": {"2": order}, "units": {"1": row}}))
	value._receive_events(_event(1, 0.5))
	var label := "same-time route change" if same_time else "later route change"
	check(value._applied == 2 and value._mirror.units["1"][0] == 2, label + " commits the new route before replay")
	check(value._pending_anchors.is_empty() and not value._anchor_state.get("units", {}).has("1"), label + " rejects a compact distance belonging to the earlier route")
	check(value._host_tick == 2 and value._host_time == changed_at, label + " keeps rejected optional time out of the clock")
	value._receive_anchor(_anchor(2, 21, changed_at + 0.1, 98.1))
	check(value._anchor_state.units["1"][0] == 2 and is_equal_approx(value._anchor_state.units["1"][1], 98.1), label + " accepts a fresh correction based on the new route")
	value.game.free()

func _check_structure() -> void:
	var value := _subject()
	var old_row: Array = value._mirror.buildings["0"].duplicate()
	old_row[3] = 12.0
	old_row[11] = 1.0
	value._receive_anchor({"base": 1, "tick": 20, "time": 1.0, "group": "buildings", "rows": {"0": old_row}})
	var new_row: Array = value._mirror.buildings["0"].duplicate()
	new_row[1] = 1
	new_row[11] = 0.5
	value._receive_events(_event(1, 0.5, {"buildings": {"0": new_row}}))
	check(value._applied == 1 and value._mirror.buildings["0"][1] == 1, "the fixture commits a real building conversion")
	check(not value._anchor_state.get("buildings", {}).has("0") and value._host_tick == 1, "matching base alone cannot bypass building structure validation")
	value.game.free()

func _check_replacement() -> void:
	var value := _subject()
	value._receive_anchor(_anchor(1, 20, 1.0, 3.0))
	value._receive_anchor(_anchor(1, 19, 0.9, 2.5))
	var invalid := _anchor(1, 30, 1.5, 9.0)
	invalid.rows["1"] = ["bad compact row"]
	value._receive_anchor(invalid)
	check(value._pending_anchors.size() == 1 and value._pending_anchors["units:1"].tick == 20, "old and malformed future rows cannot replace a valid cached revision")
	value._receive_anchor(_anchor(1, 21, 1.1, 4.0))
	check(value._pending_anchors.size() == 1 and value._pending_anchors["units:1"].tick == 21, "only the newest pending row is retained for a soldier")
	value._receive_events(_event(1, 0.5))
	value._receive_anchor(_anchor(1, 20, 1.0, 3.0))
	value._receive_anchor(_anchor(2, 20, 1.0, 3.0))
	check(value._anchor_versions["units:1"] == 21 and value._anchor_state.units["1"][1] == 4.0, "an old direct or future anchor cannot replace a newer installed revision")
	check(value._pending_anchors.is_empty(), "already superseded rows do not occupy the pending cache")
	value.game.free()

func _check_capacity() -> void:
	var value := _subject()
	for start: int in range(0, 4096, 32):
		var payload := {"base": 1, "tick": 20, "time": 1.0, "group": "units", "rows": {}}
		for index: int in range(start, start + 32): payload.rows[str(index + 1)] = 3000
		value._receive_anchor(payload)
	check(value._pending_anchors.size() == 4096, "a complete ordinary 4096-soldier sweep can overtake reliable traffic without eviction")
	check(value._host_tick == -1 and value._anchor_state.is_empty(), "a whole queued sweep still cannot advance time or presentation")
	value._pending_anchors.clear()
	var filler := _anchor(1, 20, 1.0, 3.0)
	# Fill bookkeeping directly; there is no need to simulate 65536 soldiers.
	for index: int in Coordinator.MAX_PENDING_ANCHOR_ROWS:
		value._pending_anchors["units:old-%d" % index] = filler
	var canonical := Snapshot.digest(value._mirror)
	value._receive_anchor(_anchor(1, 21, 1.1, 4.0))
	check(value._pending_anchors.size() <= Coordinator.MAX_PENDING_ANCHOR_ROWS and value._pending_anchors.has("units:1"), "overflow keeps the newest row within the fixed schema-sized bound")
	check(not value._pending_anchors.has("units:old-0") and value._pending_anchors.has("units:old-%d" % (Coordinator.MAX_PENDING_ANCHOR_ROWS - 1)), "overflow drops the oldest optional rows in a bounded batch")
	check(Snapshot.digest(value._mirror) == canonical and value.requests.is_empty(), "optional cache pressure cannot drop facts or request recovery")
	value.game.free()

func _check_snapshot_reset() -> void:
	var value := _subject()
	value._receive_anchor(_anchor(1, 20, 1.0, 3.0))
	var baseline := value._mirror.duplicate(true)
	value._install_snapshot({"state": baseline, "view": baseline.duplicate(true), "seq": 0, "through": 0,
		"epoch": 1, "account": baseline.factions["0"].duplicate(true), "winner": -2})
	check(value._pending_anchors.is_empty() and value.requests.is_empty(), "a validated recovery baseline clears pre-recovery optional rows")
	check(value._anchor_state.units["1"][1] == 2.0 and value._anchor_versions["units:1"] == 0, "the recovered baseline owns its own distance and version")
	value._snapshot_loading = true
	value._receive_anchor(_anchor(1, 21, 1.1, 4.0))
	check(value._pending_anchors.is_empty(), "no anchors are queued against an unavailable snapshot baseline")
	value.game.free()
