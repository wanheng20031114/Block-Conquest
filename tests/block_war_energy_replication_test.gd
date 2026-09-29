extends "res://tests/block_war_replication_test.gd"
## Fractional combat income and the timed energy boundary survive replication.

const ENERGY_RULES := preload("res://scripts/block_war/war_skill_rules.gd")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	check(host.faction_skills[2].energy == 20.0, "all commanders begin with twenty energy")
	host.elapsed = 99.75
	host.faction_skills[2].energy = 2.999
	host.morale.adjust(2, WarMorale.points_for_stars(2.999))
	host.bear.damage_remainders[2] = 0.625
	host.bear.combat_damage_remainders[2] = 0.125
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	check(not client._snapshot_loading, "initial energy snapshot installs")
	check(is_equal_approx(replica.faction_skills[2].energy, 2.999), "private fractional energy survives JSON and installation")
	check(replica.faction_skills[5].energy == 0.0, "other players' private accounts stay redacted")
	check(is_equal_approx(replica.morale.stars(2), 2.999), "fractional morale stars survive account synchronization")
	check(replica.bear.damage_remainders[2] == 0.625 and replica.bear.combat_damage_remainders[2] == 0.125, "mixed damage retains both total and combat shares")
	var initial: Dictionary = authority.codec.capture(host, authority._tick)
	check(Codec.valid(initial, host), "mixed remainder state is valid")
	var malformed: Dictionary = initial.duplicate(true)
	malformed.combat_remainders["2"] = 0.75
	check(not Codec.valid(malformed, host), "combat share cannot exceed total remainder")
	malformed = initial.duplicate(true)
	malformed.remainders.erase("2")
	check(not Codec.valid(malformed, host), "combat share requires the corresponding total remainder")
	var row: Array = initial.factions["2"].duplicate(true)
	check(Codec.valid_account(row, host) and float(row[9]) == 1.0, "pre-boundary account accepts one energy per second")
	check(is_equal_approx(Codec.energy_at(row, 100.25), 3.749), "old anchor integrates both sides of the hundred-second boundary")
	row[9] = 1.5
	check(is_equal_approx(Codec.energy_at(row, 100.25), 3.999), "tower bonus remains additive across the boundary")
	row[8] = 100.0
	row[9] = 2.0
	check(Codec.valid_account(row, host), "post-boundary account accepts two energy per second")
	row[9] = 1.0
	check(not Codec.valid_account(row, host), "post-boundary account rejects the old natural rate")
	row[9] = 2.0 + ENERGY_RULES.energy_tower_bonus(host.buildings.size()) + 0.01
	check(not Codec.valid_account(row, host), "account rejects income above the possible tower budget")
	client.codec.present(replica, client._mirror, 0.5)
	check(is_equal_approx(replica.faction_skills[2].energy, 3.749), "client presentation crosses the boundary without waiting for a packet")
	host.simulate(0.5)
	check(is_equal_approx(host.faction_skills[2].energy, 3.749), "authority agrees with boundary prediction")
	authority._tick += 15
	authority._publish_step(0.5)
	flush()
	check(is_equal_approx(replica.faction_skills[2].energy, host.faction_skills[2].energy), "post-boundary authoritative account agrees with displayed energy")
	# No clock advance: a fractional earned bonus must still produce a fact.
	host.faction_skills[2].energy += 0.075
	authority._tick += 1
	authority._publish_step(0.0)
	flush()
	check(is_equal_approx(replica.faction_skills[2].energy, host.faction_skills[2].energy), "fractional combat income is reliably published without passive time")
	host.bear.damage_remainders.erase(2)
	host.bear.combat_damage_remainders.erase(2)
	authority._publish_step(0.0)
	flush()
	check(not replica.bear.damage_remainders.has(2) and not replica.bear.combat_damage_remainders.has(2), "cleared total and combat remainders are removed together")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "energy changes preserve the exact reliable mirror")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("ENERGY_REPLICATION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
