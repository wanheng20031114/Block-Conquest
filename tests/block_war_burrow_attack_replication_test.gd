extends "res://tests/block_war_replication_test.gd"
## Tunnel provenance survives immutable order replacements and real wire recovery.

var passengers: Array[int] = []
var waiting: Array[int] = []

func configuration() -> Dictionary:
	var value := super.configuration()
	value.match_id = "burrow-attack-replication"
	for faction: int in [0, 3]:
		value.slots[faction].kind = "human"
		value.slots[faction].controller = "human"
		value.slots[faction].player_id = 100 + faction
	return value

func _publish() -> void:
	authority._tick += 1
	authority._publish_step(0.0)
	flush()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "reliable tunnel facts have identical digests")

func _unit(game: Node3D, id: int) -> WarMarches.MarchUnit:
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.unit_id == id: return unit
	return null

func _compare(ids: Array[int], faction: int, bonus: float, label: String) -> void:
	for id: int in ids:
		var original := _unit(host, id)
		var displayed := _unit(replica, id)
		check(original != null and displayed != null, "%s preserves soldier identity %d" % [label, id])
		if original == null or displayed == null: continue
		check(original.order.rabbit_burrow and displayed.order.rabbit_burrow, label + " retains the tunnel marker")
		check(original.order.faction == faction and displayed.order.faction == faction, label + " has the current owner")
		check(original.order.strength == 1.0 and displayed.order.strength == 1.0, label + " keeps one actual soldier")
		check(is_equal_approx(host.marches.projected_attack_bonus(original), bonus) and is_equal_approx(replica.marches.projected_attack_bonus(displayed), bonus), label + " calculates the same skill attack")
		check(client._mirror.orders[str(original.order.order_id)][12] == true, label + " publishes the marker as an order fact")
	check(Codec.valid(client._mirror, replica), label + " passes full snapshot validation")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	for building: WarBuilding in host.buildings:
		building.kind = 0
		building.population = 100.0
	var route := PackedVector3Array([Vector3(-20, 0, 0), Vector3(20, 0, 0)])
	host.marches.send_tunnel(2, 1, 2, 2, route, 0.16)
	for unit: WarMarches.MarchUnit in host.marches._units:
		unit.distance = 12.0
		host.marches._update_pose(unit)
		passengers.append(unit.unit_id)
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	check(not client._snapshot_loading, "initial tunnel snapshot installs")
	_compare(passengers, 2, 0.5, "initial snapshot")
	_validate_orders()

	# Pending tunnel ranks belong to the garrison until they really depart.
	host.marches.queue_tunnel_departure(2, 1, 2, 7, route, 0.16, 1.0)
	for unit: WarMarches.MarchUnit in host.marches._units:
		if unit.pending_departure: waiting.append(unit.unit_id)
	host.marches.send(2, 1, 2, 1, PackedVector3Array([Vector3(-20, 0, 15), Vector3(20, 0, 15)]))
	var ordinary: WarMarches.MarchUnit = host.marches._units[-1]
	_publish()
	_compare(waiting, 2, 0.5, "incremental pending departure")
	check(host.by_id[2].queued_population == 7 and replica.by_id[2].queued_population == 7, "attack bonus does not change reserved population")
	check(not _unit(replica, ordinary.unit_id).order.rabbit_burrow and replica.marches.projected_attack_bonus(_unit(replica, ordinary.unit_id)) == 0.0, "ordinary new departures do not inherit another order's bonus")
	check(host.marches._units.size() == 10 and replica.marches._units.size() == 10, "two exposed, seven reserved and one ordinary soldier remain ten objects")

	var first := _unit(host, passengers[0])
	check(host.marches.apply_rush(2, first.position, 4.0, 8.0) == 2, "rush selects the two exposed tunnel passengers")
	_publish()
	_compare(passengers, 2, 1.0, "Q and tunnel additive attack")
	check(host.RABBIT_SKILLS.recall(host, first.position, 2) == 2, "real whistle recalls the exposed passengers only")
	_publish()
	_compare(passengers, 2, 1.0, "recall replacement")
	check(_unit(replica, passengers[0]).order.returning, "returning route is installed with its attack provenance")
	check(host.FOX_SKILLS.convert(host, first.position, 5) == 2, "real fox conversion changes both recalled passengers")
	_publish()
	_compare(passengers, 5, 1.0, "conversion replacement")
	for id: int in passengers: _unit(host, id).rush_remaining = 0.0
	_publish()
	_compare(passengers, 5, 0.5, "rush expiry leaves persistent tunnel attack")

	check(host.surrender_faction(5).accepted, "the converted army's owner surrenders to its human teammate")
	_publish()
	_compare(passengers, 3, 0.5, "exposed surrender transfer")
	check(host.surrender_faction(2).accepted, "the pending tunnel's owner surrenders to its human teammate")
	_publish()
	_compare(waiting, 0, 0.5, "reserved surrender transfer")
	check(host.by_id[2].population == 60.0 and replica.by_id[2].population == 60.0 and host.by_id[2].queued_population == 7, "surrender applies only its normal garrison penalty and retains all seven funded reservations")
	check(host.marches._units.size() == 10 and replica.marches._units.size() == 10, "recall, conversion and surrender never multiply the population")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	_compare(passengers, 3, 0.5, "recovery of converted and surrendered army")
	_compare(waiting, 0, 0.5, "recovery of transferred reservations")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "extended orders retain bounded primitive packet contracts")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("BURROW_ATTACK_REPLICATION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _validate_orders() -> void:
	var state: Dictionary = authority.codec.capture(host, authority._tick)
	var key: String = state.orders.keys()[0]
	check(state.schema == Codec.SCHEMA and state.orders[key].size() == 13, "current schema explicitly carries the thirteenth order field")
	for bad: Variant in [0, 1, 0.5, "true", null, {}, []]:
		var row: Array = state.orders[key].duplicate(true)
		row[12] = bad
		check(not Codec.valid_record("orders", row, host), "tunnel provenance rejects non-boolean " + str(bad))
	var old: Dictionary = state.duplicate(true)
	old.schema = 10
	check(not Codec.valid(old, host), "schema ten cannot silently discard tunnel attack")
	old = state.duplicate(true)
	old.orders[key].pop_back()
	check(not Codec.valid(old, host), "truncated old-format order is rejected in a new-format snapshot")
