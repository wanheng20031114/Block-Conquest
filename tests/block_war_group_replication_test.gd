extends "res://tests/block_war_replication_test.gd"
## One authenticated batch commits all source queues at the same authority tick.

var confirmations: Array[Dictionary] = []
var client_sounds: Array[StringName] = []

func configuration() -> Dictionary:
	var value := super.configuration()
	value.slots[2].commander = "pig"
	return value

func reset_sources() -> void:
	host.marches.clear()
	for index: int in 3:
		var source: WarBuilding = host.by_id[[2, 8, 14][index]]
		source.faction = 2
		source.population = [20.0, 31.0, 50.0][index]
		host.pig.clear_building(host, source.building_id)
	authority._publish_step(0.0)
	flush()
	confirmations.clear()
	client_sounds.clear()
	replica.effects.clear()
	for voice: Node in replica.audio.get_node("UI").get_children(): voice.stop()
	replica.audio._next_sound_ms.clear()

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	for building: WarBuilding in host.buildings:
		building.kind = 3
		building.population = 100.0
	for id: int in [2, 8, 14]: host.by_id[id].faction = 2
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	host.presentation_event.connect(func(kind: String, payload: Dictionary):
		if kind == "dispatch": confirmations.append(payload)
	)
	replica.audio.sound_played.connect(func(kind: StringName, _at: Vector3, _spatial: bool): client_sounds.append(kind))
	reset_sources()
	var selection: Array[Node3D] = [replica.by_id[2], replica.by_id[8], replica.by_id[14]]
	replica.select_buildings(selection)
	check(client.submit({"type": "dispatch_group", "sources": [14, 2, 8], "target": 5, "percent": 50}).accepted, "remote batch enters normal command transport")
	var replay: Dictionary = client_wire.sent[-1].duplicate(true)
	client_wire.sent.append(replay.duplicate(true))
	deliver(client_wire, authority)
	check(host.marches._units.is_empty() and authority._commands.size() == 1, "duplicated batch waits once for the next simulation boundary")
	boundary()
	flush()
	check(host.marches._units.size() == 50 and replica.marches._units.size() == 50, "host and remote contain exactly fifty soldiers")
	check(host.by_id[2].available_population == 10 and host.by_id[8].available_population == 16 and host.by_id[14].available_population == 25, "authoritative per-source rounding and reservations match the preview")
	var orders: Dictionary = {}
	for unit: WarMarches.MarchUnit in host.marches._units: orders[unit.order.source_id] = unit.order.order_id
	check(orders.size() == 3 and orders.values().size() == 3, "each building keeps its own real march order")
	check(confirmations.size() == 1 and confirmations[0].count == 50 and confirmations[0].sources == [2, 8, 14], "one canonical group presentation carries the total")
	check(client_sounds == [&"war_order"] and replica.effects.size() == 1, "remote group plays one confirmation and one target marker")
	check(replica.selected_buildings.size() == 3, "network updates preserve local group selection")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "group order produces the same reliable checksum")
	client_wire.sent.append(replay)
	deliver(client_wire, authority)
	boundary()
	flush()
	check(host.marches._units.size() == 50 and confirmations.size() == 1 and client_sounds == [&"war_order"], "acknowledged replay cannot duplicate soldiers or sound")
	var invalid_sources: Array = [[], "2,8", [2, 2], [2, 8, 999999], [2, true], [2, "8"], [2, null], [2, 8.25], [2, INF], [2, NAN], [2, 2147483648.0]]
	var oversized: Array = []
	oversized.resize(host.buildings.size() + 1)
	oversized.fill(2)
	invalid_sources.append(oversized)
	for values: Variant in invalid_sources:
		var result: Dictionary = host.execute_network_command(2, {"type": "dispatch_group", "sources": values, "target": 5, "percent": 50})
		check(not result.accepted and host.marches._units.size() == 50, "malformed source list is rejected atomically: %s" % str(values))
	for change: Dictionary in [{"percent": 51}, {"percent": true}, {"target": "5"}, {"target": -1}, {"target": 999999}]:
		var command := {"type": "dispatch_group", "sources": [2, 8, 14], "target": 5, "percent": 50}
		command.merge(change, true)
		check(not host.execute_network_command(2, command).accepted and host.marches._units.size() == 50, "invalid target or ratio cannot partially reserve troops: %s" % str(change))
	reset_sources()
	# A capture between submission and execution removes only that source.
	check(client.submit({"type": "dispatch_group", "sources": [2, 8, 14, 0, 5], "target": 5, "percent": 50}).accepted, "partial-validity batch submits")
	deliver(client_wire, authority)
	host.by_id[8].faction = 1
	boundary()
	flush()
	check(host.marches._units.size() == 35 and host.by_id[8].queued_population == 0 and host.by_id[0].queued_population == 0 and host.by_id[5].queued_population == 0, "captured, teammate and enemy buildings never spend troops; valid members dispatch")
	check(confirmations.size() == 1 and confirmations[0].sources == [2, 14], "confirmation lists only successful sources")
	replica.update_hud()
	check(replica.selected_buildings.size() == 2 and replica.by_id[8] not in replica.selected_buildings, "replicated capture removes only the lost selected member")
	reset_sources()
	var allied_before: float = host.by_id[0].population
	check(not host.execute_network_command(2, {"type": "dispatch_group", "sources": [0, 5], "target": 8, "percent": 100}).accepted and host.by_id[0].population == allied_before and host.marches._units.is_empty(), "an all-foreign batch has no effect")
	check(host.execute_network_command(2, {"type": "dispatch_group", "sources": [2.0, 8.0, 14.0], "target": 8.0, "percent": 50.0}).count == 35, "JSON integral doubles work and selected target is excluded")
	check(host.by_id[8].queued_population == 0, "group reinforcement never spends destination's garrison")
	reset_sources()
	for id: int in [2, 8, 14]: host.by_id[id].population = 120.0
	host.pig.arm(host, 0, host.by_id[2], 2)
	host.pig.arm(host, 1, host.by_id[2], 2)
	host.pig.arm(host, 1, host.by_id[8], 2)
	authority._publish_step(0.0)
	flush()
	check(client.submit({"type": "dispatch_group", "sources": [2, 8, 14], "target": 5, "percent": 100}).accepted, "mixed pig preparations submit as one group")
	deliver(client_wire, authority)
	boundary()
	flush()
	var counts := {2: 0, 8: 0, 14: 0}
	var modifiers_correct := true
	for unit: WarMarches.MarchUnit in replica.marches._units:
		counts[unit.order.source_id] += 1
		match unit.order.source_id:
			2: modifiers_correct = modifiers_correct and unit.order.pig_charge and unit.order.airborne and not unit.order.dense
			8: modifiers_correct = modifiers_correct and not unit.order.pig_charge and unit.order.airborne and not unit.order.dense
			14: modifiers_correct = modifiers_correct and not unit.order.pig_charge and not unit.order.airborne and not unit.order.dense
	check(counts == {2: 20, 8: 60, 14: 120} and modifiers_correct, "replica preserves each building's distinct cap, flight and charge")
	check(host.pig.ready.is_empty() and replica.pig.ready.is_empty(), "only successful source preparations are consumed and replicated")
	check(confirmations.size() == 1 and confirmations[0].count == 200, "mixed preparations retain one group confirmation")
	for step: int in 18: boundary(Coordinator.STEP, true)
	flush()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "lost motion anchors do not corrupt group orders")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published) and replica.marches._units.size() == host.marches._units.size(), "recovery snapshot retains complete mixed group marches")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "all batch traffic obeys the existing wire protocol")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("BLOCK_WAR_GROUP_REPLICATION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
