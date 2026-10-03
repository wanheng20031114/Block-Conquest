extends "res://tests/block_war_replication_test.gd"
## The three-second drum tail survives reliable facts, compact anchors and recovery.
var soldier: WarMarches.MarchUnit
var soldier_key: String
const HASTE_SPEED := WarMarches.SPEED * 1.6

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %s / %s" % [label, actual, expected])

func _advance(seconds: float) -> void:
	host.marches.tick(seconds)
	host.elapsed += seconds
	authority._tick += roundi(seconds * 30.0)
	authority._publish_step(seconds)
	flush()
	client.codec.present(replica, client._view, host.elapsed - replica.elapsed)

func _compare(label: String) -> void:
	var displayed: WarMarches.MarchUnit = client.codec._objects[soldier_key]
	check(absf(displayed.distance - soldier.distance) <= 0.00051, label + " compact anchor keeps millimeter precision")
	near(displayed.haste_remaining, soldier.haste_remaining, label + " haste timer")
	near(displayed.haste_bonus, soldier.haste_bonus, label + " haste bonus")
	near(replica.marches.speed_multiplier(displayed), host.marches.speed_multiplier(soldier), label + " speed")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), label + " reliable checksum")

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	for world: Node3D in [host, replica]:
		for building: WarBuilding in world.buildings:
			building.kind = 3
			building.population = 100.0
		for skill: RefCounted in world.faction_skills: skill.energy = 100.0
		world.sync_environment_bonuses()
	host.elapsed = 10.0
	var route := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	host.marches.send(0, 1, 0, 1, route)
	host.marches.send(1, 0, 1, 1, route)
	soldier = host.marches._units[0]
	soldier_key = str(soldier.unit_id)
	host.marches.create_haste_zone(0, Vector3.ZERO, HASTE_SPEED, 2.5, 1.6)
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	check(not client._snapshot_loading, "initial snapshot installs the haste state")
	_compare("initial")
	var seq: int = authority._seq
	_advance(0.5)
	check(authority._seq == seq, "continuous contact creates no reliable update per tick")
	check(client._anchor_state.get("units", {}).has(soldier_key), "compact movement anchor is accepted inside the zone")
	if client._anchor_state.get("units", {}).has(soldier_key):
		var anchor: Array = client._anchor_state.units[soldier_key]
		near(float(anchor[15]) - float(anchor[12]), 3.0, "compact anchor renews tail at its own timestamp")
	_compare("inside with compact anchor")
	_advance(0.4)
	check(authority._seq == seq, "continued contact stays on optional motion channel")
	_compare("inside between anchors")
	_advance(0.6)
	check(authority._seq > seq, "circle exit publishes a reliable fixed deadline")
	near(float(client._mirror.units[soldier_key][15]), 14.0, "deadline is three seconds after actual exit at eleven")
	_compare("outside")
	_validate_rows()
	seq = authority._seq
	_advance(0.5)
	check(authority._seq == seq, "ordinary tail countdown creates no reliable traffic")
	_compare("outside with compact anchor")
	_advance(0.5)
	check(replica.marches.haste_zones.is_empty(), "field removal replicates independently of tail")
	near(soldier.haste_remaining, 1.5, "field removal cannot restart a departed soldier's tail")
	_compare("after field removal")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	_compare("recovery snapshot during tail")
	_advance(1.6)
	near(soldier.haste_remaining, 0.0, "authority clears expired tail")
	near(float(client._mirror.units[soldier_key][15]), 0.0, "expiry publishes zero deadline")
	near(float(client._mirror.units[soldier_key][16]), 0.0, "expiry publishes zero bonus")
	_compare("after tail expiry")
	check(client.resync_count == 1, "haste causes no invalid-state or checksum resync loops")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "haste uses valid serialized packets")
	_stale_prediction()
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("SQUIRREL_HASTE_REPLICATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _validate_rows() -> void:
	var state: Dictionary = authority.codec.capture(host, authority._tick)
	check(Codec.valid(state, replica), "full snapshot validates nonzero tail")
	var row: Array = state.units[soldier_key]
	for bad: float in [-1.0, NAN, INF, float(row[12]) + 3.01]:
		var broken := row.duplicate()
		broken[15] = bad
		check(not Codec.valid_record("units", broken, replica), "invalid haste deadline rejected: %s" % bad)
	for bad: float in [-1.0, NAN, INF, 100.0, 0.0]:
		var broken := row.duplicate()
		broken[16] = bad
		check(not Codec.valid_record("units", broken, replica), "invalid or unmatched haste bonus rejected: %s" % bad)
	var missing_deadline := row.duplicate()
	missing_deadline[15] = 0.0
	check(not Codec.valid_record("units", missing_deadline, replica), "bonus without a deadline is rejected")
	var old_row := row.duplicate()
	old_row.resize(15)
	check(not Codec.valid_record("units", old_row, replica), "old unit layout is rejected")
	state.schema -= 1
	check(not Codec.valid(state, replica), "old snapshot schema is rejected explicitly")

func _stale_prediction() -> void:
	host.marches.clear()
	host.elapsed = 20.0
	host.marches.send(0, 1, 0, 1, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]))
	soldier = host.marches._units[0]
	host.marches.create_haste_zone(0, Vector3.ZERO, 100.0, 4.0, 1.75)
	var state: Dictionary = authority.codec.capture(host, 600)
	var reader := Codec.new()
	reader.install(replica, state, 20.75, true)
	near(replica.marches._units[0].haste_remaining, 3.0, "historical snapshot renews during prediction")
	near(replica.marches._units[0].haste_bonus, 0.75, "wire preserves actual field strength")
	near(replica.marches._units[0].distance, WarMarches.SPEED * 1.75 * 0.75, "historical snapshot predicts hasted motion")
	reader.present(replica, state, 1.25)
	var capped: float = replica.marches._units[0].distance
	near(capped, WarMarches.SPEED * 1.75, "movement retains one-second prediction cap")
	near(replica.marches._units[0].haste_remaining, 3.0, "active field renews frozen display")
	reader.present(replica, state, 3.3)
	near(replica.marches._units[0].distance, capped, "aging tail cannot bypass prediction cap")
	near(replica.marches._units[0].haste_remaining, 1.7, "tail ages after field expiry beyond movement cap")
	var late_reader := Codec.new()
	late_reader.install(replica, state, 25.3, true)
	near(replica.marches._units[0].distance, capped, "late install agrees on capped motion")
	near(replica.marches._units[0].haste_remaining, 1.7, "late install agrees on tail")
	near(replica.marches._units[0].haste_bonus, 0.75, "late install retains sampled strength after field ends")
	late_reader.present(replica, state, 2.0)
	near(replica.marches._units[0].haste_remaining, 0.0, "stale snapshot cannot make haste permanent")
	near(replica.marches._units[0].haste_bonus, 0.0, "expired display also clears cached bonus")
