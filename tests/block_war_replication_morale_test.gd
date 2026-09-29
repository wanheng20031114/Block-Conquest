extends "res://tests/block_war_replication_test.gd"
## Combat inside one morale star must not republish an unrelated whole army.

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
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
	host.marches.send(0, 1, 0, 4096, PackedVector3Array([Vector3.ZERO, Vector3(500, 0, 0)]))
	authority._publish_step(0.0)
	flush()
	host_wire.sent.clear()
	var sent_before: int = authority.sent_rule_bytes
	var max_backlog := 0
	var whole_army_updates := 0
	var started := Time.get_ticks_usec()
	# One actual combat arrival per tick awards the defender ten points without
	# crossing the first 500-point movement threshold during this sample.
	for frame: int in 30:
		var previous: Dictionary = authority._previous
		host._on_unit_arrived(1, 0, 1.0)
		host.elapsed += Coordinator.STEP
		authority._tick += 1
		var current := Codec.for_player(authority.codec.capture(host, authority._tick), -1)
		var patch := Codec.diff(previous, current)
		whole_army_updates += int(patch.set.get("units", {}).size() == 4096)
		authority._publish_step(Coordinator.STEP)
		authority._flush_outbox(Coordinator.STEP)
		authority._flush_anchors(Coordinator.STEP)
		max_backlog = maxi(max_backlog, authority._outbox_bytes)
		deliver(host_wire, client)
		deliver(client_wire, authority)
	check(host.morale.points(1) == 300.0 and host.morale.level(1) == 0, "real defending kills award points without changing movement speed")
	check(whole_army_updates == 0, "within-star combat does not reliably republish every soldier")
	check(max_backlog == 0, "within-star combat fits normal reliable traffic without bulk backlog")
	flush()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "combat still commits population and morale to the exact client mirror")
	print("REPLICATION_MORALE_LOAD soldiers=4096 combat_ticks=30 whole_army_updates=", whole_army_updates,
		" raw_rule_bytes=", authority.sent_rule_bytes - sent_before, " max_backlog_bytes=", max_backlog,
		" cpu_ms=", float(Time.get_ticks_usec() - started) / 1000.0)
	# Speed changes still need a reliable shared boundary, in both directions.
	for values: Vector2 in [Vector2(499, 500), Vector2(500, 499), Vector2(999, 1000), Vector2(1000, 999), Vector2(7999, 8000), Vector2(8000, 7999)]:
		host.morale.adjust(0, values.x - host.morale.points(0))
		var previous := Codec.for_player(authority.codec.capture(host, authority._tick), -1)
		host.morale.adjust(0, values.y - host.morale.points(0))
		var current := Codec.for_player(authority.codec.capture(host, authority._tick), -1)
		var patch := Codec.diff(previous, current)
		check(patch.set.get("units", {}).size() == 4096, "crossing %s to %s morale anchors the moving army" % [values.x, values.y])
	var before_field := Codec.for_player(authority.codec.capture(host, authority._tick), -1)
	host.marches.haste_zones[0] = {"at": Vector3.ZERO, "radius": 6.0, "remaining": 5.0, "duration": 5.0, "multiplier": 1.5}
	var during_field := Codec.for_player(authority.codec.capture(host, authority._tick), -1)
	check(Codec.diff(before_field, during_field).set.get("units", {}).size() == 4096, "a newly active movement field still anchors the army")
	host.marches.haste_zones.clear()
	var after_field := Codec.for_player(authority.codec.capture(host, authority._tick), -1)
	check(Codec.diff(during_field, after_field).set.get("units", {}).size() == 4096, "an expired movement field still anchors the army")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("REPLICATION_MORALE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
