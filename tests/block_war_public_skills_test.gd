extends "res://tests/block_war_replication_test.gd"
## Public readiness is a reliable three-state fact; exact accounts stay private.

func configuration() -> Dictionary:
	var value := super.configuration()
	value.match_id = "public-skills"
	value.slots[0].commander = "fox"
	return value

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105); replica = make_game(102)
	host_wire = make_wire(105); client_wire = make_wire(102)
	host.faction_skills[0].energy = 40.0
	host.faction_skills[0].cooldowns.assign([0.0, 5.0, 0.0, 0.0])
	host.faction_skills[5].energy = 100.0
	host.faction_skills[5].cooldowns[0] = 1.0
	check(host.public_skill_statuses_for(0) == [2, 0, 1, 1], "authority distinguishes cooling, ready but unaffordable, and affordable")
	authority = Coordinator.new(); client = Coordinator.new()
	authority.setup(host, host_wire); client.setup(replica, client_wire)
	flush()
	check(not client._snapshot_loading, "initial snapshot installs the new schema")
	check(replica.public_skill_statuses_for(0) == [2, 0, 1, 1], "other faction's three states survive a serialized full snapshot")
	check(replica.public_skill_statuses_for(5) == [0, 2, 2, 2], "host player is public like every other remote faction")
	check(replica.faction_skills[0].commander == &"fox", "public states remain paired with each faction's commander")
	_check_private()
	check(replica.public_skill_statuses_for(2) == [2, 1, 2, 1], "local readiness uses the private account at the exact cost boundary")
	replica.faction_skills[2].energy = 19.99
	check(replica.public_skill_statuses_for(2) == [1, 1, 1, 1], "local readiness can respond before the next public status packet")
	client._apply_account()
	# Natural regeneration is quiet until it actually changes a visible state.
	host.faction_skills[0].energy = 59.9
	host.faction_skills[0].cooldowns[0] = 0.1
	_publish()
	var before: Dictionary = authority._published.duplicate(true)
	check(replica.public_skill_statuses_for(0) == [0, 0, 1, 1], "reliable delta installs a new cooldown with insufficient energy for E")
	host.simulate(0.2)
	_publish()
	check(replica.public_skill_statuses_for(0) == [2, 0, 2, 1], "cooldown expiry and natural energy threshold publish without movement anchors")
	check(not Codec.same_structure("factions", before.factions["0"], authority._published.factions["0"]), "readiness transition prevents old anchors from overriding the reliable state")
	var stale: Array = before.factions["0"].duplicate(true)
	stale[8] = host.elapsed
	client._receive_anchor({"group": "factions", "rows": {"0": stale}, "base": client._applied, "time": host.elapsed, "tick": authority._tick + 100})
	client._apply_view()
	check(replica.public_skill_statuses_for(0) == [2, 0, 2, 1], "a later delivered old status anchor cannot rewind readiness")
	var continuous: Dictionary = Codec.for_player(authority.codec.capture(host, authority._tick), -1)
	host.simulate(0.1)
	var later: Dictionary = Codec.for_player(authority.codec.capture(host, authority._tick + 3), -1)
	check(Codec.diff(continuous, later).set.is_empty(), "ordinary cooldown and energy progress emit no public countdown updates")
	# Spending shared energy can remove several glows in the same transaction.
	host.faction_skills[0].energy = 0.0
	host.faction_skills[0].cooldowns.assign([30.0, 0.0, 0.0, 0.0])
	_publish()
	check(replica.public_skill_statuses_for(0) == [0, 1, 1, 1], "energy spending dims all newly unaffordable skills while retaining their complete icons")
	host.faction_skills[0].energy = 100.0
	_publish()
	check(replica.public_skill_statuses_for(0) == [0, 2, 2, 2], "instant combat or capture income lights ready skills without exposing energy")
	_check_private()
	var published: Dictionary = authority._published.duplicate(true)
	client.codec.present(replica, client._view, 0.5)
	check(replica.public_skill_statuses_for(0) == [0, 2, 2, 2], "client presentation never invents remote countdown or energy changes")
	check(Codec.digest(published) == Codec.digest(authority._published), "presentation cannot modify committed public facts")
	# Reconnection restores the three states through the ordinary chunked path.
	replica.faction_skills[0].public_statuses.fill(1)
	authority._snapshot_sent_at.clear(); authority._send_snapshot(102); flush()
	check(replica.public_skill_statuses_for(0) == [0, 2, 2, 2], "recovery baseline restores public readiness")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "public states retain the common digest after reconnection")
	_check_private()
	check(host.execute_network_command(5, {"type": "pause", "paused": true}).accepted, "authority accepts pause for the public-state fixture")
	_publish()
	var paused_time: float = host.elapsed
	host.simulate(3.0)
	client.codec.present(replica, client._view, 3.0)
	check(replica.match_paused and host.elapsed == paused_time and replica.elapsed == paused_time, "pause freezes authority and replica clocks at the same boundary")
	check(replica.public_skill_statuses_for(0) == [0, 2, 2, 2], "paused display preserves status without inventing cooldown expiry")
	authority._snapshot_sent_at.clear(); authority._send_snapshot(102); flush()
	check(replica.match_paused and replica.public_skill_statuses_for(0) == [0, 2, 2, 2], "reconnection during pause preserves public states")
	check(host.execute_network_command(5, {"type": "pause", "paused": false}).accepted, "authority resumes the public-state fixture")
	_publish()
	check(not replica.match_paused and replica.public_skill_statuses_for(0) == [0, 2, 2, 2], "resume does not consume cooldown or energy while paused")
	_validate_states(authority.codec.capture(host, authority._tick))
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "public readiness uses existing valid packet channels")
	await replica.prepare_shutdown()
	await host.prepare_shutdown()
	print("BLOCK_WAR_PUBLIC_SKILLS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _publish() -> void:
	authority._tick += 1
	authority._publish_step(0.0)
	deliver(host_wire, client, false, true)
	client._apply_view()

func _check_private() -> void:
	for faction: int in host.faction_count:
		if faction == replica.local_faction: continue
		var row: Array = client._mirror.factions[str(faction)]
		check(row[1] == 0.0 and row[2] == [0.0, 0.0, 0.0, 0.0], "wire keeps faction %d energy and exact cooldowns private" % faction)
		check(replica.faction_skills[faction].energy == 0.0 and replica.faction_skills[faction].cooldowns == [0.0, 0.0, 0.0, 0.0], "remote account %d contains only redacted private fields" % faction)

func _validate_states(state: Dictionary) -> void:
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(state))
	for bad: Variant in [[], [0, 1, 2], [0, 1, 2, 0, 1], null, true, {}, "ready"]:
		var row: Array = decoded.factions["0"].duplicate(true)
		row[10] = bad
		check(not Codec.valid_account(row, host), "malformed public skill array is rejected: %s" % str(bad))
	for bad: Variant in [-1, 3, 1.5, true, "2", INF, NAN, null, []]:
		var row: Array = decoded.factions["0"].duplicate(true)
		row[10][0] = bad
		check(not Codec.valid_account(row, host), "invalid public skill state is rejected: %s" % str(bad))
	var old: Dictionary = state.duplicate(true)
	old.schema = 4
	check(not Codec.valid(old, host), "old schema cannot silently omit public skill states")
