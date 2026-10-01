extends "res://tests/block_war_replication_test.gd"
## Real client pig commands, lossy motion, reordered facts and falling-pig recovery.

var impacts := 0

func configuration() -> Dictionary:
	var value := super.configuration()
	value.slots[2].commander = "pig"
	value.match_id = "pig-replication-test"
	return value

func send_client(command: Dictionary, duplicate: bool = false) -> void:
	check(client.submit(command).accepted, "Pig player submits %s through the real client command channel" % command.type)
	if duplicate:
		var replay: Dictionary = client_wire.sent[-1].duplicate(true)
		client_wire.sent.append(replay)
	deliver(client_wire, authority)
	boundary()
	flush()

func grant_energy() -> void:
	host.faction_skills[2].energy = 100.0
	authority._publish_step(0.0)
	flush()

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
	# The native frame loop releases transport pause after recovery; flush()
	# drains packets only, so let both real coordinators run their first frame.
	boundary()
	check(not client._snapshot_loading and replica.faction_skills[2].commander == &"pig", "Room configuration and initial snapshots recognize the sixth hero in a nonzero client seat")
	host.presentation_event.connect(func(kind: String, _payload: Dictionary):
		if kind == "pig_impact": impacts += 1
	)
	# Stable, nonproducing structures isolate exact population effects and avoid
	# unrelated cannon casualties while commands cross the simulated transport.
	for building: WarBuilding in host.buildings:
		building.kind = 3; building.level = 1; building.population = 80.0
	var source: WarBuilding = host.by_id[2]
	source.population = 70.0
	grant_energy()
	for skill: int in 2:
		send_client({"type": "skill_building", "skill": skill, "target": 2}, skill == 1)
		check(host.pig.flags_for(2)[skill] > 14.0 and replica.pig.flags_for(2)[skill] > 14.0, "Pig skill %d arms once on host and remote building" % skill)
	check(host.pig.ready_owners[2] == 2 and replica.pig.ready_owners[2] == 2, "Stacked preparations retain their owning player through replication")
	send_client({"type": "dispatch", "source": 2, "target": 8, "percent": 100}, true)
	check(host.marches._units.size() == 20 and source.available_population == 50.0, "Q plus W caps the client command at twenty and leaves fifty soldiers uncommitted")
	check(host.pig.ready.is_empty() and replica.pig.ready.is_empty(), "Successful dispatch consumes both preparations on both peers")
	for unit: WarMarches.MarchUnit in replica.marches._units:
		check(unit.order.pig_charge and unit.order.airborne and not unit.order.dense, "Every replicated soldier carries charge and flight without the removed formation skill")
	for frame: int in 45: boundary(Coordinator.STEP, true)
	flush()
	check(source.queued_population == 0 and source.population == 50.0 and replica.by_id[2].population == 50.0, "Lossy motion anchors never change the exact twenty-person gradual departure")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "Pig flight leaves host and replica reliable state identical")
	source.population = 100.0
	host.faction_skills[2].cooldowns[1] = 0.0
	grant_energy()
	send_client({"type": "skill_building", "skill": 1, "target": 2})
	send_client({"type": "dispatch", "source": 2, "target": 8, "percent": 100})
	check(source.available_population == 40.0, "Flight-only client order caps at sixty and keeps the remaining forty")
	var flight_count := 0
	for unit: WarMarches.MarchUnit in host.marches._units:
		if unit.order.airborne and not unit.order.pig_charge: flight_count += 1
	check(flight_count == 60, "The host actually creates sixty flying soldiers rather than only changing a UI count")
	var impact_target: WarBuilding = host.by_id[10]
	impact_target.population = 80.0
	var center: Vector3 = impact_target.global_position
	var victims: Array[WarMarches.MarchUnit] = []
	for faction: int in [0, 1, 2]:
		host.marches.send(faction, 10, faction, 1, PackedVector3Array([center, center + Vector3(20, 0, 0)]))
		var soldier: WarMarches.MarchUnit = host.marches._units[-1]
		# This already-paid fixture is exposed at the impact point, independent
		# of the real sixty-person departure queue at the same source building.
		soldier.distance = 0.0
		soldier.levitation_remaining = 2.0
		host.marches._update_pose(soldier)
		victims.append(soldier)
	grant_energy()
	send_client({"type": "skill_ground", "skill": 3, "x": center.x, "z": center.z}, true)
	check(host.pig.drops.size() == 1 and replica.pig.drops.size() == 1 and impacts == 0, "Duplicated R input creates one falling pig and no immediate damage")
	for frame: int in 22: boundary(Coordinator.STEP, true)
	flush()
	check(impacts == 1 and impact_target.population == 40.0 and replica.by_id[10].population == 40.0, "Only the authority settles one impact and synchronizes the exact halved garrison")
	for victim: WarMarches.MarchUnit in victims: check(not victim.alive, "Giant pig removes friendly, allied and hostile exposed troops regardless of frog levitation")
	for frame: int in 30: boundary(Coordinator.STEP, true)
	flush()
	check(impacts == 1 and impact_target.population == 40.0 and host.pig.drops.is_empty() and replica.pig.drops.is_empty(), "Visual expiry cannot repeat impact or leave a stale giant pig in the mirror")
	_reorder_damage(impact_target)
	# Recover while a second pig is still falling. Install must retain its age
	# and identity without restarting the animation or settling local damage.
	host.faction_skills[2].cooldowns[3] = 0.0
	grant_energy()
	send_client({"type": "skill_ground", "skill": 3, "x": center.x, "z": center.z})
	var drop_id: int = host.pig.drops[0].id
	var before: float = impact_target.population
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(replica.pig.drops.size() == 1 and replica.pig.drops[0].id == drop_id and replica.pig.next_drop_id == host.pig.next_drop_id, "Reconnect installs the existing falling pig and preserves future identities")
	check(impacts == 1 and replica.by_id[10].population == before, "Installing a falling pig snapshot does not replay its impact")
	for frame: int in 24: boundary(Coordinator.STEP, true)
	flush()
	check(impacts == 2 and impact_target.population == before * 0.5 and replica.by_id[10].population == before * 0.5, "The recovered falling pig lands once at the host and both peers agree")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "Recovery and repeated pig commands end with identical canonical mirrors")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "All pig commands and state fit the primitive channel contract")
	print("PIG_REPLICATION checks=%d failures=%d impacts=%d" % [checks, failures.size(), impacts])
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free(); replica.free(); host_wire.free(); client_wire.free()
	quit(0 if failures.is_empty() else 1)

func _reorder_damage(target: WarBuilding) -> void:
	var events: Array[Dictionary] = []
	var base: int = client._applied
	for index: int in 3:
		target.population -= 1.0
		host.elapsed += Coordinator.STEP
		authority._tick += 1
		authority._publish_step(Coordinator.STEP)
		for packet: Dictionary in host_wire.sent:
			# Private account updates share the event channel but have no
			# transaction sequence and do not enter the canonical fact stream.
			if packet.kind == "events" and packet.payload.has("seq"): events.append(packet)
		host_wire.sent.clear()
	check(events.size() == 3, "Three separate post-impact population facts are serialized (got %d)" % events.size())
	if events.size() != 3: return
	for index: int in [2, 0, 0, 1, 2]:
		client._on_message(105, "events", events[index].payload)
	client._apply_view()
	check(client._applied == base + 3 and client._pending.is_empty(), "Reordered and replayed facts apply exactly once after pig impact")
	check(replica.by_id[target.building_id].population == target.population and Codec.digest(client._mirror) == Codec.digest(authority._published), "Out-of-order recovery preserves the exact damaged garrison")
