extends "res://tests/block_war_replication_test.gd"
## Authored cannon poses over the real coordinator and serialized fake transport.

var volleys: Array[Dictionary] = []

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	for world: Node3D in [host, replica]:
		for building: WarBuilding in world.buildings:
			building.kind = 3
			building.level = 1
			building.population = 100.0
			building.cancel_construction()
			building.clear_disruption()
			building.clear_burrow()
			building.refresh_visual()
		for id: int in [2, 5]:
			world.by_id[id].kind = 1
			world.by_id[id].faction = id
			world.by_id[id].refresh_visual()
	host.presentation_event.connect(func(kind: String, payload: Dictionary):
		if kind.begins_with("tower_"): volleys.append({"kind": kind, "payload": payload.duplicate(true)}))
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	check(not client._snapshot_loading and not client._recovery_waiting, "initial serialized baseline unlocks client")
	check(host.local_faction == 5 and replica.local_faction == 2, "host and guest use nonzero seats five and two")
	for id: int in [2, 5]:
		for direction: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
			_fire(id, [direction * 5.0])
			_publish()
			flush()
			_assert_pose(id, "seat %d direction %s" % [id, direction])
			check(_forward(host.by_id[id]).dot(direction) > 0.999, "authority selects the intended cardinal target")
			check(volleys.size() == 1, "one-target shot emits one volley presentation")
			check(replica.by_id[id]._recoil_tween != null, "guest cannon starts its authored recoil")
			check(replica.projectiles.size() == 1, "guest installs the independently replicated cannonball")
			if not replica.projectiles.is_empty():
				check(replica.projectiles[0].at.distance_to(host.projectiles[0].at) < 0.001, "host and guest share the exact projectile origin")
	_multi_target_volley()
	_reordered_volleys()
	_snapshot_without_projectiles()
	_validate_yaw_rows()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "presentation leaves the reliable checksum identical")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "all cannon traffic uses valid serialized protocol channels")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	print("TOWER_REPLICATION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _fire(id: int, offsets: Array) -> void:
	host.projectiles.clear()
	host.marches.clear()
	volleys.clear()
	var tower: WarBuilding = host.by_id[id]
	var enemy := 5 if tower.faction == 2 else 2
	for offset: Vector3 in offsets:
		var start := tower.global_position + offset
		host.marches.send(enemy, id, enemy, 1, PackedVector3Array([start, start + offset.normalized() * 20.0]))
	host._fire_tower(tower)
	check(host.projectiles.size() == mini(tower.level, offsets.size()), "authority fires the expected number of physical balls")

func _publish(advance_clock := true) -> void:
	if advance_clock: host.elapsed += Coordinator.STEP
	authority._tick += 1
	authority._publish_step(0.0)

func _forward(building: WarBuilding) -> Vector3:
	var direction: Vector3 = -building.get_node("Visual/Tower/Gun").global_basis.z
	direction.y = 0.0
	return direction.normalized()

func _assert_pose(id: int, label: String) -> void:
	var original: WarBuilding = host.by_id[id]
	var copy: WarBuilding = replica.by_id[id]
	check(_forward(original).dot(_forward(copy)) > 0.99999, label + ": replica barrel matches authoritative aim")
	check(copy.muzzle_position().distance_to(original.muzzle_position()) < 0.001, label + ": both authored muzzle transforms agree")

func _multi_target_volley() -> void:
	var id := 2
	host.by_id[id].level = 4
	host.by_id[id].refresh_visual()
	var host_flash: int = host.world_effects._next_hit
	var guest_flash: int = replica.world_effects._next_hit
	_fire(id, [Vector3(4, 0, 0), Vector3(0, 0, 5), Vector3(-6, 0, 0), Vector3(0, 0, -7)])
	_publish()
	flush()
	check(volleys.size() == 1 and volleys[0].kind == "tower_volley", "four-target salvo publishes one building volley rather than four per-ball effects")
	_assert_pose(id, "four-target salvo")
	check(_forward(host.by_id[id]).dot(Vector3.RIGHT) > 0.999, "salvo barrel keeps the nearest first target rather than the last ball's target")
	check(replica.projectiles.size() == 4, "all four differently aimed projectiles reach the guest")
	var slots: int = host.world_effects.get_node("Hits").get_child_count()
	check((host.world_effects._next_hit - host_flash + slots) % slots == 1, "host flashes its muzzle once per salvo")
	check((replica.world_effects._next_hit - guest_flash + slots) % slots == 1, "guest flashes its muzzle once per salvo")
	check(replica.by_id[id]._recoil_tween != null, "guest starts the shared authored salvo recoil")
	var recoil: Tween = replica.by_id[id]._recoil_tween
	host.by_id[7].population -= 1.0
	_publish()
	flush()
	check(replica.by_id[id]._recoil_tween == recoil, "unrelated fact installation does not restart recoil")
	_assert_pose(id, "unrelated reliable fact")

func _take_packets() -> Array[Dictionary]:
	for index: int in 100:
		authority._flush_outbox(0.1)
		if authority._outbox.is_empty(): break
	var packets: Array[Dictionary] = host_wire.sent
	host_wire.sent = []
	return packets

func _receive(packets: Array[Dictionary]) -> void:
	for packet: Dictionary in packets:
		if packet.target >= 0 and packet.target != client.online.player_id: continue
		client._on_message(int(packet.sender), str(packet.kind), packet.payload)

func _reordered_volleys() -> void:
	var id := 2
	host.by_id[id].level = 1
	host.by_id[id].refresh_visual()
	_fire(id, [Vector3(0, 0, 5)])
	_publish()
	var earlier := _take_packets()
	var old_row: Array = authority._published.buildings[str(id)].duplicate(true)
	var old_time: float = host.elapsed
	var old_tick: int = authority._tick
	var old_seq: int = authority._seq
	_fire(id, [Vector3(-5, 0, 0)])
	# Equal-time facts deliberately test the yaw's structural identity: time
	# alone must not allow an older anchor to erase a newer cannon turn.
	_publish(false)
	var later := _take_packets()
	var applied: int = client._applied
	_receive(later)
	check(client._applied == applied, "later volley waits behind the missing earlier reliable fact")
	_receive(earlier)
	client._apply_view()
	_assert_pose(id, "out-of-order volleys settle in sequence")
	var recoil: Tween = replica.by_id[id]._recoil_tween
	var flash: int = replica.world_effects._next_hit
	_receive(earlier)
	_receive(later)
	client._apply_view()
	check(replica.by_id[id]._recoil_tween == recoil and replica.world_effects._next_hit == flash, "duplicate volleys cannot repeat recoil or muzzle flash")
	_assert_pose(id, "duplicate packets preserve latest aim")
	var anchor: Dictionary = JSON.parse_string(JSON.stringify({"group": "buildings", "rows": {str(id): old_row}, "time": old_time, "tick": old_tick, "base": old_seq}))
	client._on_message(105, "anchors", anchor)
	client._apply_view()
	_assert_pose(id, "old pre-turn anchor cannot rewind the cannon")
	check(replica.by_id[id]._recoil_tween == recoil, "old anchor cannot replay recoil")
	flush()

func _snapshot_without_projectiles() -> void:
	var id := 2
	# Resolve actual shots before recovery, so no live projectile can supply aim.
	host._tick_projectiles(1.0)
	_publish()
	flush()
	check(host.projectiles.is_empty() and replica.projectiles.is_empty(), "all cannonballs have landed before recovery")
	var copy: WarBuilding = replica.by_id[id]
	copy.get_node("Visual/Tower/Gun").rotation.y = 0.37
	var recoil: Tween = copy._recoil_tween
	var flash: int = replica.world_effects._next_hit
	client._on_connection("reconnecting")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(not client._snapshot_loading and not client._recovery_waiting, "recovery finishes with the real chunked snapshot protocol")
	_assert_pose(id, "recovery restores retained aim without any live projectile")
	check(copy._recoil_tween == recoil and replica.world_effects._next_hit == flash, "restoring a cannon pose does not replay a historical volley")
	var row: Array = client._mirror.buildings[str(id)]
	check(row.size() == 13, "building snapshot explicitly retains the cannon yaw")
	if row.size() == 13:
		check(absf(angle_difference(float(row[12]), host.by_id[id].get_node("Visual/Tower/Gun").rotation.y)) < 0.00001, "snapshot yaw is the authoritative authored gun yaw")
	check(host.set_match_paused(true, 5).accepted, "host can pause the recovered cannon fixture")
	_publish(false)
	flush()
	copy.get_node("Visual/Tower/Gun").rotation.y = -0.42
	recoil = copy._recoil_tween
	flash = replica.world_effects._next_hit
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	_assert_pose(id, "paused recovery restores the same retained aim")
	check(replica.match_paused and copy._visual_paused, "recovery preserves paused match and cannon animation")
	check(copy._recoil_tween == recoil and replica.world_effects._next_hit == flash, "paused recovery does not start a new recoil or muzzle flash")
	check(recoil != null and not recoil.is_running(), "the existing recoil remains frozen after paused recovery")

func _validate_yaw_rows() -> void:
	var row: Array = client._mirror.buildings["2"].duplicate(true)
	check(not Codec.valid_record("buildings", row.slice(0, 12), replica), "legacy building rows without cannon yaw are rejected")
	for angle: float in [-PI, PI]:
		row[12] = angle
		check(Codec.valid_record("buildings", row, replica), "canonical positive and negative half turns are accepted")
	for angle: Variant in [NAN, INF, -PI - 0.01, PI + 0.01, "0"]:
		row[12] = angle
		check(not Codec.valid_record("buildings", row, replica), "nonfinite, out-of-range or nonnumeric cannon yaw is rejected")
