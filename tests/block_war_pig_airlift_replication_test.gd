extends "res://tests/block_war_pig_replication_test.gd"
## Airlift batches remain authoritative across capture, pause, recovery and surrender.

func configuration() -> Dictionary:
	var value := super.configuration()
	value.slots[0].kind = "human"
	value.slots[0].controller = "human"
	value.slots[0].player_id = 100
	value.match_id = "pig-airlift-replication"
	return value

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %.6f / %.6f" % [label, actual, expected])

func publish() -> void:
	authority._tick += 1
	authority._publish_step(0.0)
	flush()

func wait_for_batch(landed: int) -> void:
	for _frame: int in 65:
		if host.pig.airlifts.is_empty() or host.pig.airlifts[0].landed >= landed: break
		boundary(Coordinator.STEP, true)
	flush()
	check(not host.pig.airlifts.is_empty() and host.pig.airlifts[0].landed == landed, "host reaches the exact %d-person batch boundary" % landed)
	check(not replica.pig.airlifts.is_empty() and replica.pig.airlifts[0].landed == landed, "client receives the exact %d-person batch fact despite lost movement anchors" % landed)

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	for building: WarBuilding in host.buildings:
		building.kind = 3
		building.level = 1
		building.population = 80.0
	var target: WarBuilding = host.by_id[1]
	target.population = 3.0
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	boundary()
	grant_energy()
	var army_before: int = host.total_for(2)
	send_client({"type": "skill_building", "skill": 2, "target": 1}, true)
	check(host.pig.airlifts.size() == 1 and replica.pig.airlifts.size() == 1, "duplicate remote E creates exactly one authoritative airlift")
	var identity: int = host.pig.airlifts[0].id
	check(host.pig.airlifts[0].landed == 0 and target.population == 3.0, "casting schedules the first batch instead of applying forty troops instantly")
	check(host.pig.pending_for(2) == 40 and replica.pig.pending_for(2) == 40, "host and client retain all forty not-yet-landed soldiers")
	check(host.total_for(2) == army_before + 40 and replica.total_for(2) == host.total_for(2), "public army totals include pending reinforcements exactly once")
	check(host.pig.ready.is_empty() and replica.pig.ready.is_empty(), "new E never installs the removed formation preparation")
	check(host.faction_skills[2].energy < 35.5 and replica.faction_skills[2].energy < 35.5, "remote caster pays the new E cost once")
	wait_for_batch(8)
	check(target.faction == 2 and replica.by_id[1].faction == 2, "first real eight-person batch captures the three-person enemy building")
	near(target.population, 5.0, "survivors from the capture batch become the new garrison")
	near(replica.by_id[1].population, 5.0, "the client receives exactly those capture survivors")
	check(host.pig.pending_for(2) == 32 and replica.pig.pending_for(2) == 32, "only the landed batch leaves the pending total")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(replica.pig.airlifts[0].id == identity and replica.pig.airlifts[0].landed == 8, "recovery resumes the same partially landed wave")
	near(replica.by_id[1].population, 5.0, "recovery cannot replay the first landing or capture")
	var age: float = host.pig.airlifts[0].age
	send_client({"type": "pause", "paused": true})
	for _frame: int in 5: boundary(0.1, true)
	near(host.pig.airlifts[0].age, age, "global pause freezes authoritative airlift progress")
	near(replica.pig.airlifts[0].age, age, "global pause freezes the same client animation clock")
	check(host.pig.airlifts[0].landed == 8 and target.population == 5.0, "paused time generates no extra batches")
	send_client({"type": "pause", "paused": false})
	# A recapture does not cancel, redirect or duplicate the committed wave.
	host._on_unit_arrived(1, 1, 20.0)
	publish()
	check(target.faction == 1 and replica.by_id[1].faction == 1, "opponents can recapture between landing batches")
	check(host.pig.airlifts[0].target == 1 and host.pig.airlifts[0].landed == 8, "recapture preserves the wave's destination and settled count")
	wait_for_batch(16)
	check(target.faction == 1 and target.population < 15.0, "the next batch fights the building's new hostile owner")
	near(replica.by_id[1].population, target.population, "hostile landing casualties replicate exactly")
	# The paid airborne soldiers are an army: only already landed garrisons
	# receive the surrender loss; the remaining twenty-four transfer intact.
	var before_transfer: float = host.by_id[2].population
	var surrender: Dictionary = host.surrender_faction(2)
	check(surrender.accepted and not surrender.defeated, "pig player surrenders while a human teammate remains")
	publish()
	check(host.pig.airlifts[0].faction == 0 and replica.pig.airlifts[0].faction == 0, "pending wave transfers to the remaining human on both peers")
	check(host.pig.airlifts[0].id == identity and host.pig.airlifts[0].target == 1 and host.pig.airlifts[0].landed == 16, "surrender preserves wave identity, destination and already landed batches")
	check(host.pig.pending_for(2) == 0 and host.pig.pending_for(0) == 24 and replica.pig.pending_for(0) == 24, "all twenty-four pending soldiers transfer without the garrison penalty")
	check(surrender.transfer.soldiers == 24, "surrender accounting includes the transferred airborne army")
	near(host.by_id[2].population, before_transfer * 0.6, "already existing garrison still loses forty percent on surrender")
	near(host.faction_skills[0].durations[2], 0.0, "receiving the wave does not activate the squirrel teammate's third skill")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(replica.pig.airlifts[0].faction == 0 and replica.pig.airlifts[0].landed == 16, "post-surrender recovery keeps the new owner and remaining batches")
	wait_for_batch(40)
	check(target.faction == 0 and replica.by_id[1].faction == 0, "the transferred wave ultimately captures for its receiving teammate")
	near(replica.by_id[1].population, target.population, "all five batches end with one exact authoritative garrison")
	check(host.pig.pending_for(0) == 0 and replica.pig.pending_for(0) == 0, "finished wave contributes no extra soldiers during its landing visual tail")
	var final_population: float = target.population
	for _frame: int in 10: boundary(Coordinator.STEP, true)
	flush()
	check(host.pig.airlifts.is_empty() and replica.pig.airlifts.is_empty(), "visual tail expires and its identity is reliably removed")
	near(target.population, final_population, "visual retirement cannot settle a sixth landing batch")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "airlift pause, capture, surrender and recovery preserve the canonical checksum")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "airlift facts use valid existing message channels")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free(); replica.free(); host_wire.free(); client_wire.free()
	print("PIG_AIRLIFT_REPLICATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
