extends "res://tests/block_war_bear_allied_replication_test.gd"
## Cancellation, hostile wards and remote caster cleanup are authoritative facts.

func configuration() -> Dictionary:
	var value := super.configuration()
	value.slots[0].kind = "human"
	value.slots[0].controller = "human"
	value.slots[0].player_id = 100
	return value

func _publish() -> void:
	authority._tick += 1
	authority._publish_step(0.0)
	flush()

func _fund() -> void:
	host.faction_skills[2].energy = 100.0
	host.faction_skills[2].cooldowns.fill(0.0)
	_publish()

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	for world: Node3D in [host, replica]:
		for building: WarBuilding in world.buildings:
			building.kind = 3
			building.population = 100.0
		world.by_id[4].global_position = world.by_id[0].global_position + Vector3(10, 0, 0)
	host.faction_skills[2].energy = 100.0
	check(host.issue_order(host.by_id[1], host.by_id[0], 100, 1) > 0, "fixture queues actual enemy departures")
	var before: float = host.by_id[1].population
	var departed: int = host.marches._units.filter(func(unit: WarMarches.MarchUnit): return not unit.pending_departure).size()
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	check(replica.by_id[1].queued_population > 0, "client starts with the real queued army")
	_cast(1, 1)
	check(host.bear.locks.has(1) and replica.bear.locks.has(1), "remote W installs its persistent lock on both peers")
	check(host.by_id[1].queued_population == 0 and replica.by_id[1].queued_population == 0, "W cancellation releases every queue reservation on both peers")
	check(host.marches._units.size() == departed and replica.marches._units.size() == departed, "W cancellation only deletes the pending soldiers in replication")
	check(is_equal_approx(host.by_id[1].population, before) and is_equal_approx(replica.by_id[1].population, before), "cancelled soldiers remain in the real garrison")
	check(not host.execute_network_command(1, {"type": "dispatch", "source": 1, "target": 0, "percent": 100}).accepted, "authoritative command routing rejects departure while locked")
	var state: Dictionary = authority.codec.capture(host, authority._tick)
	check(Codec.valid(state, replica), "lock state is a valid complete snapshot")
	for row: Variant in [[2], [2, -1.0], [2, INF], [6, 4.0], ["2", 4.0]]:
		check(not Codec.valid_record("locks", row, replica), "malformed lock is rejected before installation: " + str(row))
	var invalid := state.duplicate(true)
	invalid.locks["1"][0] = 1
	check(not Codec.valid(invalid, replica), "allied-owner departure lock is rejected")
	invalid = state.duplicate(true)
	invalid.locks["1"][1] = state.time + host.SKILL_RULES.BEAR_DURATIONS[1] + 0.1
	check(not Codec.valid(invalid, replica), "oversized departure lock is rejected")
	invalid = state.duplicate(true)
	invalid.schema -= 1
	check(not Codec.valid(invalid, replica), "previous schema is rejected explicitly")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(replica.bear.is_locked(1) and replica.by_id[1].queued_population == 0, "recovery snapshot keeps cancellation and remaining lock")
	var previous: Dictionary = authority.codec.capture(host, authority._tick)
	host.simulate(0.5)
	var next: Dictionary = authority.codec.capture(host, authority._tick + 1)
	var delta := Codec.diff(previous, next)
	check(not delta.set.has("locks") and not delta.remove.has("locks"), "lock countdown needs no high-frequency reliable updates")
	_publish()
	_fund()
	_cast(3, 3)
	check(host.bear.wards.has(3) and replica.bear.wards.has(3), "remote enemy R reaches both peers")
	check(host.bear.wards[3].hostile and replica.bear.wards[3].hostile, "hostile mode survives the serialized snapshot")
	check(is_equal_approx(replica.skill_defense_bonus(replica.by_id[3]), -0.3), "client displays the enemy defense penalty")
	check(not replica.shields.has(3), "enemy R does not create a replicated shield")
	state = authority.codec.capture(host, authority._tick)
	check(Codec.valid(state, replica), "hostile ward and lock validate together")
	invalid = state.duplicate(true)
	invalid.wards["3"][4] = false
	check(not Codec.valid(invalid, replica), "protective mode on the caster's enemy is rejected")
	var old_ward: Array = state.wards["3"].duplicate()
	old_ward.resize(4)
	check(not Codec.valid_record("wards", old_ward, replica), "old ward layout cannot silently lose hostile mode")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(replica.bear.wards[3].hostile and replica.bear.wards[3].faction == 2, "recovery preserves the hostile fireball's caster")
	_fund()
	_cast(2, 0)
	check(host.bear.links.has(0) and replica.bear.links.has(0), "surrender fixture includes a link on teammates")
	var result: Dictionary = host.surrender_faction(2)
	check(result.accepted and not result.defeated, "remote bear can surrender while its human teammate remains")
	_publish()
	check(host.bear.locks.is_empty() and host.bear.wards.is_empty() and host.bear.links.is_empty(), "surrender ends all bear effects cast onto buildings owned by others")
	check(replica.bear.locks.is_empty() and replica.bear.wards.is_empty() and replica.bear.links.is_empty(), "remote surrender atomically clears lock, curse and link")
	check(not replica.bear.is_locked(1) and is_zero_approx(replica.skill_defense_bonus(replica.by_id[3])), "client no longer predicts the surrendered bear's penalties")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "reworked bear skills preserve the complete reliable checksum")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "reworked skills retain valid packet routing")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("BEAR_REWORK_REPLICATION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
