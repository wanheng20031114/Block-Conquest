extends "res://tests/block_war_snapshot_test.gd"
## Pig facts use absolute clocks; a remote display can never settle the impact.

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	host = current_scene
	host.set_process(false); host.camera_rig.set_process(false); host.ai_enabled = false; host.audio.muted = true
	replica = load("res://scenes/block_war/block_war.tscn").instantiate()
	root.add_child(replica)
	replica.set_process(false); replica.camera_rig.set_process(false); replica.ai_enabled = false; replica.audio.muted = true
	replica.presentation_event.connect(func(_kind: String, _payload: Dictionary): replica_events += 1)
	fresh(host)
	for building: WarBuilding in host.buildings: building.kind = 1
	host.elapsed = 10.0
	host.faction_skills[0].commander = &"pig"
	host.faction_skills[2].commander = &"pig"
	host.pig.ready[2] = Vector3(14.75, 8.5, 1.0)
	host.pig.ready_owners[2] = 2
	host.pig._sync_durations(host)
	host.pig.drops.append({"id": 5, "faction": 0, "at": host.by_id[0].global_position, "age": 0.25, "impacted": false})
	host.pig.next_drop_id = 6
	var route: PackedVector3Array = host.marches.make_flight_route(host.by_id[0].global_position, host.by_id[1].global_position)
	host.marches.queue_departure(0, 1, 0, 6, route, true, true, true, true)
	var state := writer.capture(host, 300)
	check(Snapshot.valid(state, host), "A complete pig snapshot validates with reserved flying troops and an unlanded giant pig")
	check(state.schema == Snapshot.SCHEMA and state.counters.size() == 5 and state.counters[4] == 6, "Current schema contains the independent drop identity counter")
	check(state.pig_ready["2"] == [2, 24.75, 18.5, 11.0], "All three independent armed timers are transmitted as deadlines")
	check(state.pig_drops["5"][2] == 9.75 and not state.pig_drops["5"][3], "The giant pig transmits one start time and an authoritative impact flag")
	var order_key: String = state.orders.keys()[0]
	check(state.orders[order_key].slice(8, 11) == [true, true, true], "Orders retain charge, real flight and density as independent flags")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(state, "", true, true))
	check(Snapshot.valid(decoded, replica) and Snapshot.digest(decoded) == Snapshot.digest(state), "Pig clocks and flags survive the actual JSON wire representation")
	reader.install(replica, decoded)
	var restored := Snapshot.new().capture(replica, 300)
	check(Snapshot.digest(restored) == Snapshot.digest(state), "Installing and recapturing pig state is lossless")
	var soldier: WarMarches.MarchUnit = replica.marches._units[0]
	check(soldier.order.pig_charge and soldier.order.airborne and soldier.order.dense and soldier.order.energy_origin, "Remote soldiers restore all pig flags before their pose and movement are calculated")
	check(replica.pig.ready_owners[2] == 2 and replica.pig.next_drop_id == 6, "Ready ownership and future drop identities survive reconnect")
	var before_population: float = replica.by_id[0].population
	var before_army: int = replica.marches._units.size()
	var before_queue: int = replica.by_id[0].queued_population
	reader.present(replica, decoded, 1.0)
	near(replica.pig.ready[2].x, 13.75, "The remote charge readiness clock advances from its absolute deadline")
	near(replica.pig.ready[2].z, 0.0, "An expired ready icon can disappear without a host packet")
	near(replica.pig.drops[0].age, 1.25, "The giant pig animation advances past its visual impact time")
	check(not replica.pig.drops[0].impacted, "Animation time cannot fabricate an authoritative impact fact")
	check(replica.by_id[0].population == before_population and replica.by_id[0].queued_population == before_queue and replica.marches._units.size() == before_army, "Remote impact animation cannot halve a garrison, cancel reservations or kill soldiers")
	check(replica_events == 0, "Remote pig install and visual advance emit no gameplay events")
	var still: float = replica.pig.drops[0].age
	replica.match_paused = true
	reader.present(replica, decoded, 2.0)
	near(replica.pig.drops[0].age, still, "Global pause freezes pig animations and readiness clocks")
	replica.match_paused = false
	_diff_clocks(state)
	_validation(state)
	_flight_prediction()
	await replica.prepare_shutdown()
	replica.queue_free()
	await host.prepare_shutdown()
	await process_frame
	print("BLOCK_WAR_PIG_SNAPSHOT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _diff_clocks(state: Dictionary) -> void:
	host.elapsed += 0.25
	host.pig.ready[2] -= Vector3.ONE * 0.25
	host.pig.drops[0].age += 0.25
	host.pig._sync_durations(host)
	var later := writer.capture(host, 308)
	var delta := Snapshot.diff(state, later)
	check(not delta.set.has("pig_ready") and not delta.set.has("pig_drops"), "Ordinary pig countdown and falling animation produce no reliable state traffic")
	var drift := later.duplicate(true)
	drift.pig_ready["2"][1] -= 0.0002
	drift.factions["2"][3][0] -= 0.0002
	delta = Snapshot.diff(later, drift)
	check(not delta.set.has("pig_ready") and not delta.set.get("factions", {}).has("2"), "Float32 readiness timer rounding does not spam reliable updates")
	check(Snapshot.same_structure("factions", later.factions["2"], drift.factions["2"]), "Optional anchors accept the same harmless pig timer rounding as reliable facts")
	host.elapsed += 0.2
	host.pig.drops[0].age += 0.2
	host.pig.ready[2] -= Vector3.ONE * 0.2
	host.pig._sync_durations(host)
	host.pig.drops[0].impacted = true
	var impact := writer.capture(host, 309)
	delta = Snapshot.diff(later, impact)
	check(delta.set.get("pig_drops", {}).has("5") and delta.set.pig_drops["5"][3], "The authoritative impact transition is sent as one reliable fact")
	var mirror := later.duplicate(true)
	Snapshot.apply_delta(mirror, delta)
	Snapshot.apply_delta(mirror, delta)
	check(mirror.pig_drops["5"][3] and Snapshot.valid(mirror, host), "Replaying an absolute impact fact remains valid and cannot duplicate damage")
	host.pig.ready.erase(2); host.pig.ready_owners.erase(2)
	host.pig.drops.clear()
	host.pig._sync_durations(host)
	var ended := writer.capture(host, 310)
	delta = Snapshot.diff(impact, ended)
	check(delta.remove.get("pig_ready", []).has("2") and delta.remove.get("pig_drops", []).has("5"), "Consumption or expiry removes the correct ready marker and drop identity")
	Snapshot.apply_delta(mirror, delta)
	reader.install(replica, mirror)
	check(replica.pig.ready.is_empty() and replica.pig.drops.is_empty(), "Authoritative deletion clears old pig state after reconnect or packet delay")

func _validation(state: Dictionary) -> void:
	for index: int in range(8, 11):
		for bad: Variant in [1, "true", null, [], {}]:
			var altered := state.duplicate(true)
			altered.orders[altered.orders.keys()[0]][index] = bad
			check(not Snapshot.valid(altered, host), "Pig order flags require strict booleans at index %d" % index)
	for bad: Variant in [[], [0, 1, 2], [0, 0.0, 0.0, 0.0], [0, -1.0, 2.0, 3.0], [0, NAN, 2.0, 3.0], [6, 1.0, 2.0, 3.0], [0, "15", 2.0, 3.0]]:
		var altered := state.duplicate(true)
		altered.pig_ready["2"] = bad
		check(not Snapshot.valid(altered, host), "Malformed ready clocks are rejected before indexing or installation")
	var wrong_owner := state.duplicate(true)
	wrong_owner.pig_ready["2"][0] = 1
	check(not Snapshot.valid(wrong_owner, host), "Readiness cannot belong to a faction that does not own that building")
	var unknown := state.duplicate(true)
	unknown.pig_ready["99999"] = unknown.pig_ready["2"]
	check(not Snapshot.valid(unknown, host), "Ready markers require a real map building")
	for bad: Variant in [[], [0, [0, 0], 0.0, false], [0, [0, INF, 0], 0.0, false], [0, [0, 0, 0], NAN, false], [0, [0, 0, 0], 0.0, 1], [-1, [0, 0, 0], 0.0, false]]:
		var altered := state.duplicate(true)
		altered.pig_drops["5"] = bad
		check(not Snapshot.valid(altered, host), "Malformed pig drops are rejected before animation or damage processing")
	var reused := state.duplicate(true)
	reused.counters[4] = 5
	check(not Snapshot.valid(reused, host), "Future drop identities must exceed every live drop")
	var old_schema := state.duplicate(true)
	old_schema.schema = 5
	check(not Snapshot.valid(old_schema, host), "An old schema cannot silently discard pig state")
	var old_counters := state.duplicate(true)
	old_counters.counters.resize(4)
	check(not Snapshot.valid(old_counters, host), "Legacy counters cannot reset the drop identity stream")
	var eternal := state.duplicate(true)
	eternal.pig_ready["2"][1] = state.time + 16.0
	check(not Snapshot.valid(eternal, host), "A ready deadline cannot extend past the fifteen-second lifetime")
	var future := state.duplicate(true)
	future.pig_drops["5"][2] = state.time + 0.1
	check(not Snapshot.valid(future, host), "A live drop cannot start in the future")
	var expired := state.duplicate(true)
	expired.pig_drops["5"][2] = state.time - 2.0
	check(Snapshot.valid(expired, host), "A mirror may retain an expired visual while awaiting its reliable deletion")
	var premature := state.duplicate(true)
	premature.pig_drops["5"][3] = true
	check(not Snapshot.valid(premature, host), "A falling pig cannot claim an impact before its fall time")
	for airborne: bool in [true, false]:
		var overcrowded := state.duplicate(true)
		var order_id: String = overcrowded.orders.keys()[0]
		overcrowded.orders[order_id][9] = airborne
		var first: Array = overcrowded.units.values()[0].duplicate(true)
		first[3] = false
		first[1] = 2.0
		overcrowded.units.clear()
		overcrowded.buildings["0"][4] = 0
		var limit: int = 30 if airborne else 60
		for index: int in range(1, limit + 1): overcrowded.units[str(index)] = first.duplicate(true)
		overcrowded.counters[1] = limit + 2
		check(Snapshot.valid(overcrowded, host), "A pig order at its exact flight/density cap validates")
		overcrowded.units[str(limit + 1)] = first.duplicate(true)
		check(not Snapshot.valid(overcrowded, host), "A pig order cannot bypass the thirty/sixty-person cap in snapshots")

func _flight_prediction() -> void:
	fresh(host)
	host.pig.ready.clear(); host.pig.ready_owners.clear(); host.pig.drops.clear()
	host.elapsed = 20.0
	var route: PackedVector3Array = host.marches.make_flight_route(host.by_id[0].global_position, host.by_id[1].global_position)
	host.marches.queue_departure(0, 1, 0, 1, route, false, true, true, true)
	var unit: WarMarches.MarchUnit = host.marches._units[0]
	unit.distance = unit.order.length * 0.5
	host.marches._update_pose(unit)
	var state := writer.capture(host, 600)
	var expected: float = unit.distance + host.marches.movement_distance(unit, 0.25)
	reader.install(replica, state, 20.25)
	var copied: WarMarches.MarchUnit = replica.marches._units[0]
	near(copied.distance, expected, "Late flight anchors integrate the pig speed before drawing their corrected position")
	check(copied.position.y > replica.map.definition.surface_height(Vector2(copied.position.x, copied.position.z)) + 1.0, "Late flight prediction keeps its altitude above the actual terrain")
	var returned: WarMarches.MarchOrder = host.marches.return_order(unit.order)
	host.marches.redirect(unit, returned)
	state = writer.capture(host, 601)
	reader.install(replica, state)
	copied = replica.marches._units[0]
	check(copied.order.returning and copied.order.pig_charge and copied.order.airborne and copied.order.dense, "Recall publishes a new airborne order without losing its modifiers")
