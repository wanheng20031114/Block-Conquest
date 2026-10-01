extends "res://tests/block_war_replication_test.gd"
## Building mist defense is derived from the already replicated field facts.

func configuration() -> Dictionary:
	var value := super.configuration()
	value.slots[0].commander = "frog"
	value.slots[2].commander = "frog"
	return value

func _publish() -> void:
	authority._tick += 1
	authority._publish_step(0.0)
	flush()

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %.6f / %.6f" % [label, actual, expected])

func _same_bonus(id: int, expected: float, label: String) -> void:
	near(host.skill_defense_bonus(host.by_id[id]), expected, label + " on host")
	near(replica.skill_defense_bonus(replica.by_id[id]), expected, label + " on client")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	for building: WarBuilding in host.buildings:
		building.kind = 0
		building.level = 1
		building.population = 100.0
	for faction: int in host.faction_count:
		host.faction_skills[faction].energy = 100.0
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	var target: WarBuilding = host.by_id[1]
	var center: Vector3 = target.global_position
	check(host.marches._units.is_empty(), "remote building-only cast starts without marching troops")
	check(client.submit({"type": "skill_ground", "skill": 0, "x": center.x, "z": center.z}).accepted, "remote frog submits mist through the real command route")
	deliver(client_wire, authority)
	boundary()
	flush()
	_same_bonus(1, -0.25, "remote mist weakens the covered enemy building")
	check(host.faction_skills[2].energy < 80.1 and replica.faction_skills[2].energy < 80.1, "host and private client account both charge the mist cost")
	var before: Dictionary = authority.codec.capture(host, authority._tick)
	check(Codec.valid(before, replica) and before.fields.has("weak:2"), "building-only mist uses the existing valid field snapshot")
	host.simulate(0.25)
	var after: Dictionary = authority.codec.capture(host, authority._tick + 1)
	var delta := Codec.diff(before, after)
	check(not delta.set.has("fields") and not delta.remove.has("fields"), "field countdown does not require frequent reliable defense updates")
	_publish()
	_same_bonus(1, -0.25, "the client derives the same defense between field events")
	check(host.cast_ground_skill(0, center, 0), "a second allied frog casts an overlapping cloud")
	check(host.cast_skill(3, target, 4), "allied bear curses the same enemy building")
	_publish()
	_same_bonus(1, -0.55, "overlapping fog applies once and adds to hostile bear R")
	host._on_unit_arrived(1, 0, 9.0)
	_publish()
	near(target.population, 80.0, "authoritative real combat uses the combined skill defense")
	near(replica.by_id[1].population, target.population, "client receives the exact combined-defense casualties")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	_same_bonus(1, -0.55, "recovery snapshot restores both spells without cast replay")
	check(replica.marches.weak_zones.size() == 2 and replica.bear.wards[1].hostile, "recovery keeps both independent fog casters and hostile ward mode")
	host.shields[1] = 8.0
	_publish()
	_same_bonus(1, -0.30, "replicated squirrel shield offsets mist and curse")
	host._on_unit_arrived(1, 0, 200.0)
	_publish()
	check(target.faction == 0 and replica.by_id[1].faction == 0, "capture updates ownership on both peers")
	_same_bonus(1, 0.0, "capture clears ward and shield and rechecks mist allegiance")
	host._on_unit_arrived(1, 1, 400.0)
	_publish()
	check(target.faction == 1 and replica.by_id[1].faction == 1, "opposing recapture remains an authoritative fact")
	_same_bonus(1, -0.25, "still-active fog applies to the recaptured hostile building")
	# Client presentation ages the same deadline even without another reliable
	# update; a later recovery must not resurrect the expired building penalty.
	var reader := Codec.new()
	var state: Dictionary = authority.codec.capture(host, authority._tick)
	reader.install(replica, state)
	reader.present(replica, state, 3.1)
	near(replica.skill_defense_bonus(replica.by_id[1]), 0.0, "client presentation removes the building penalty at the field deadline")
	host.simulate(3.1)
	_publish()
	_same_bonus(1, 0.0, "host and event client agree after the final mist expires")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	_same_bonus(1, 0.0, "post-expiry recovery cannot resurrect a stale building debuff")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "mist combat and ownership changes preserve the reliable checksum")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "all mist commands and snapshots retain the existing packet contract")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("FROG_MIST_REPLICATION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
