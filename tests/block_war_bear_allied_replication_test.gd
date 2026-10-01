extends "res://tests/block_war_replication_test.gd"
## A remote bear can support teammates through the normal command and snapshot path.

func configuration() -> Dictionary:
	var value := super.configuration()
	value.slots[2].commander = "bear"
	return value

func _cast(index: int, target: int) -> void:
	check(client.submit({"type": "skill_building", "skill": index, "target": target}).accepted, "remote bear submits skill %d" % index)
	deliver(client_wire, authority)
	boundary()
	flush()

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
		world.by_id[2].global_position = world.by_id[0].global_position + Vector3(40, 0, 0)
	host.by_id[0].kind = 0
	host.by_id[0].level = 1
	host.faction_skills[2].energy = 100.0
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	check(not client._snapshot_loading, "allied bear fixture installs its initial snapshot")
	check(replica._valid_skill_target(0, replica.by_id[0]), "client targeting preview accepts an idle ally residence")
	_cast(0, 0)
	check(not host.by_id[0].is_constructing and host.by_id[0].level == 2, "host accepts the remote direct upgrade on a teammate")
	check(not replica.by_id[0].is_constructing and replica.by_id[0].level == 2, "client receives the completed allied upgrade")
	check(is_equal_approx(host.by_id[0].population, 100.0), "direct upgrade leaves allied troops unchanged")
	check(host.by_id[0].faction == 0 and replica.by_id[0].faction == 0, "toolbox never transfers building ownership")
	check(host.faction_skills[2].energy < 81.0 and host.faction_skills[0].energy < 21.0, "remote caster pays while the receiving ally retains its own account")
	check(replica._valid_skill_target(2, replica.by_id[0]) and replica.bear.partner(replica, replica.by_id[0]) == replica.by_id[4], "client preview chooses another teammate as link support")
	_cast(2, 0)
	check(host.bear.links.has(0) and replica.bear.links.has(0), "cross-player link survives authority and replica ticks")
	if host.bear.links.has(0) and replica.bear.links.has(0):
		check(host.bear.links[0].faction == 2 and replica.bear.links[0].support == 4, "link preserves caster and distinct target/support owners")
	host._on_unit_arrived(0, 1, 23.1)
	authority._publish_step(0.0)
	flush()
	check(is_equal_approx(host.by_id[0].population, 90.0) and is_equal_approx(host.by_id[4].population, 89.0), "authoritative cross-player link shares twenty-one damage as ten and eleven")
	check(is_equal_approx(replica.by_id[0].population, 90.0) and is_equal_approx(replica.by_id[4].population, 89.0), "both allied casualty counts replicate exactly")
	host.faction_skills[2].energy = 100.0
	authority._publish_step(0.0)
	flush()
	check(replica._valid_skill_target(3, replica.by_id[4]), "client ward preview accepts an ally")
	_cast(3, 4)
	check(host.bear.wards.has(4) and replica.bear.wards.has(4), "remote ward protects the allied support building")
	check(is_equal_approx(replica.skill_defense_bonus(replica.by_id[4]), 1.2), "client displays the allied building's active defense")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(replica.bear.links.has(0) and replica.bear.wards.has(4), "full recovery snapshot preserves cross-player effects")
	host._on_unit_arrived(4, 1, 300.0)
	authority._publish_step(0.0)
	flush()
	check(not replica.bear.links.has(0) and not replica.bear.wards.has(4), "capture removes both effects from the client")
	check(is_zero_approx(replica.faction_skills[2].durations[2]) and is_zero_approx(replica.faction_skills[2].durations[3]), "capture clears both timers on the casting player's HUD")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "allied support preserves the reliable state checksum")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "allied skills use valid existing network messages")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("BEAR_ALLIED_REPLICATION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
