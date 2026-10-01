extends "res://tests/block_war_replication_test.gd"
## Lingering slow survives reliable facts, compact motion anchors and recovery.
var soldier: WarMarches.MarchUnit
var soldier_key: String
const SLOW_SPEED := WarMarches.SPEED * Codec.RULES.BEAR_SLOW_MULTIPLIER

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
	check(absf(displayed.distance - soldier.distance) <= 0.00051, label + " distance respects the compact anchor's millimeter precision")
	near(displayed.slow_remaining, soldier.slow_remaining, label + " slow timer")
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
		for state: RefCounted in world.faction_skills: state.energy = 100.0
		world.sync_environment_bonuses()
	host.elapsed = 10.0
	var route := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	host.marches.send(1, 0, 1, 1, route)
	host.marches.send(2, 0, 2, 1, route)
	soldier = host.marches._units[0]
	soldier_key = str(soldier.unit_id)
	host.marches.create_slow_zone(0, Vector3.ZERO, SLOW_SPEED, 4.0)
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	check(not client._snapshot_loading, "initial snapshot installs the slow state")
	_compare("initial")
	var seq: int = authority._seq
	_advance(0.5)
	check(authority._seq == seq, "continuous contact does not create a reliable update every tick")
	check(client._anchor_state.get("units", {}).has(soldier_key), "compact movement anchor is accepted inside the zone")
	if client._anchor_state.get("units", {}).has(soldier_key):
		var anchor: Array = client._anchor_state.units[soldier_key]
		near(float(anchor[14]) - float(anchor[12]), 5.0, "compact anchors refresh the tail at their own timestamp")
	_compare("inside with compact anchor")
	_advance(0.4)
	check(authority._seq == seq, "continued contact stays on the optional motion channel")
	_compare("inside between anchors")
	_advance(0.6)
	check(authority._seq > seq, "leaving the circle publishes a reliable fixed deadline")
	near(float(client._mirror.units[soldier_key][14]), 16.0, "tail deadline is five seconds after the actual exit at eleven")
	_compare("outside")
	_validate_rows()
	seq = authority._seq
	_advance(0.5)
	check(authority._seq == seq, "ordinary tail countdown causes no reliable traffic")
	_compare("outside with compact anchor")
	_advance(2.0)
	check(replica.marches.slow_zones.is_empty(), "field removal replicates independently of the slow tail")
	near(soldier.slow_remaining, 2.0, "removing a field cannot restart an already departed soldier's tail")
	_compare("after field removal")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	_compare("recovery snapshot during tail")
	_advance(2.1)
	near(soldier.slow_remaining, 0.0, "authority clears the expired tail")
	near(float(client._mirror.units[soldier_key][14]), 0.0, "expiry publishes a reliable cleared state")
	_compare("after tail expiry")
	check(client.resync_count == 1, "slow updates do not trigger invalid-state or checksum resync loops")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "slow updates use valid serialized packets")
	_stale_prediction()
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("BEAR_SLOW_REPLICATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _validate_rows() -> void:
	var state: Dictionary = authority.codec.capture(host, authority._tick)
	check(Codec.valid(state, replica), "full snapshot validates a nonzero tail")
	var row: Array = state.units[soldier_key]
	for bad: float in [-1.0, NAN, INF, float(row[12]) + 5.01]:
		var broken := row.duplicate()
		broken[14] = bad
		check(not Codec.valid_record("units", broken, replica), "invalid tail rejected before install: %s" % bad)
	var old_row := row.duplicate()
	old_row.resize(14)
	check(not Codec.valid_record("units", old_row, replica), "old unit layout is rejected")
	state.schema -= 1
	check(not Codec.valid(state, replica), "old snapshot schema is rejected explicitly")

func _stale_prediction() -> void:
	host.marches.clear()
	host.elapsed = 20.0
	host.marches.send(1, 0, 1, 1, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]))
	soldier = host.marches._units[0]
	host.marches.create_slow_zone(0, Vector3.ZERO, 100.0, 4.0)
	var state: Dictionary = authority.codec.capture(host, 600)
	var reader := Codec.new()
	reader.install(replica, state, 20.75, true)
	near(replica.marches._units[0].slow_remaining, 5.0, "historical snapshot refreshes during its predicted interval")
	near(replica.marches._units[0].distance, SLOW_SPEED * 0.75, "historical snapshot predicts slowed motion")
	reader.present(replica, state, 1.25)
	var capped: float = replica.marches._units[0].distance
	near(capped, SLOW_SPEED, "movement stops at the existing one-second prediction cap")
	near(replica.marches._units[0].slow_remaining, 5.0, "a still-active field refreshes the frozen display")
	reader.present(replica, state, 4.3)
	near(replica.marches._units[0].distance, capped, "aging a tail cannot bypass the prediction cap")
	near(replica.marches._units[0].slow_remaining, 2.7, "tail ages after field expiry beyond the movement cap")
	var late_reader := Codec.new()
	late_reader.install(replica, state, 26.3, true)
	near(replica.marches._units[0].distance, capped, "late installation and incremental display agree on capped motion")
	near(replica.marches._units[0].slow_remaining, 2.7, "late installation and incremental display agree on the tail")
	late_reader.present(replica, state, 3.0)
	near(replica.marches._units[0].slow_remaining, 0.0, "a stale snapshot cannot make the tail permanent")
