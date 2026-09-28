extends SceneTree
## Lossless facts, atomic reservations, display-only prediction and hostile shapes.
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
var host: Node3D
var replica: Node3D
var writer := Snapshot.new()
var reader := Snapshot.new()
var checks := 0
var failures: Array[String] = []
var replica_events := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.00001, "%s: %s / %s" % [label, actual, expected])

func fresh(game: Node3D) -> void:
	game.marches.clear()
	game.projectiles.clear(); game.fire_states.clear()
	game.bear.links.clear(); game.bear.wards.clear(); game.bear.damage_remainders.clear(); game.bear.shots.clear()
	game.marches.blocked_destinations.clear(); game.shields.clear()
	game.morale.configure(game.faction_count)
	game.elapsed = 0.0; game.finished = false; game._local_menu = false
	for b: WarBuilding in game.buildings:
		b.kind = 0; b.level = 1; b.population = 20.0
		b.faction = b.building_id if b.building_id < 6 else -1
		b.cancel_construction(); b.clear_disruption(); b.clear_burrow()
		game.tower_clocks[b.building_id] = 0.0
	for skill: RefCounted in game.faction_skills:
		skill.energy = 50.0; skill.cooldowns.fill(0.0); skill.durations.fill(0.0); skill.recruit_target_id = -1

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
	host.by_id[0].population = 70.0
	host.issue_order(host.by_id[0], host.by_id[6], 50, 0)
	host.begin_building_construction(host.by_id[1], -1, 1)
	host.by_id[2].begin_disruption(4.0)
	host.by_id[3].begin_burrow(13.0)
	host.shields[0] = 7.0
	host.faction_skills[0].recruit_target_id = 0
	host.faction_skills[0].durations[0] = 3.0
	host.faction_skills[1].commander = &"rabbit"
	host.faction_skills[1].cooldowns[0] = 12.0
	host.faction_skills[2].commander = &"bear"
	host.faction_skills[3].commander = &"frog"
	host.morale.adjust(4, 2371.125)
	host.bear.links[2] = {"target": 2, "support": 4, "faction": 2, "remaining": 5.5, "settled": 21, "pulse": 0.7}
	host.bear.damage_remainders[2] = 0.375
	host.bear.wards[3] = {"faction": 3, "remaining": 2.0, "shot_clock": 0.25, "pulse": 1.0}
	host.marches.blocked_destinations[3] = 3
	var route := PackedVector3Array([Vector3.ZERO, Vector3(30, 0, 0)])
	host.marches.send(4, 1, 4, 1, route, 0.625)
	var troop: WarMarches.MarchUnit = host.marches._units[-1]
	troop.rush_remaining = 0.2; troop.levitation_remaining = 0.1; troop.cloaked = true; troop.weakened = true
	troop.reserved = true; troop.intercepted_by = 1
	host.marches._update_pose(troop)
	host.marches.create_haste_zone(4, Vector3.ZERO, 4.5, 2.0, 1.6)
	host.marches.create_slow_zone(1, Vector3.ZERO, 6.0, 3.0)
	host.marches.apply_frog_field(0, 3, Vector3(8, 0, 8))
	host.projectiles.append({"target": troop, "at": Vector3(2, 2, 0), "position": Vector3(2, 2, 0), "previous": Vector3(2, 2, 0), "to": troop.position + Vector3.UP * 0.65, "tracking": false, "age": 0.125, "duration": 0.4})
	host.bear.shots.append({"target": troop, "origin": Vector3(2, 6, 0), "position": Vector3(2, 6, 0), "previous": Vector3(2, 6, 0), "to": troop.position + Vector3.UP * 0.65, "age": 0.15, "duration": 0.4})
	var fire: RefCounted = host.start_fire(Vector3(12, 0, 9), 4.5, 1)
	fire.age = 0.6; fire.hit_buildings[1] = true
	var state := writer.capture(host, 17)
	check(Snapshot.valid(state, host), "complete authoritative snapshot validates")
	var encoded := JSON.stringify(state, "", true, true)
	var decoded: Dictionary = JSON.parse_string(encoded)
	check(Snapshot.valid(decoded, replica), "JSON roundtrip validates all integral-double identifiers")
	check(Snapshot.digest(decoded) == Snapshot.digest(state), "canonical digest survives the actual JSON wire representation")
	if Snapshot.digest(decoded) != Snapshot.digest(state):
		FileAccess.open("res://.local/multiplayer-core/hash-original.json", FileAccess.WRITE).store_string(JSON.stringify(Snapshot._canonical(state), "", true, true))
		FileAccess.open("res://.local/multiplayer-core/hash-decoded.json", FileAccess.WRITE).store_string(JSON.stringify(Snapshot._canonical(decoded), "", true, true))
	reader.install(replica, decoded)
	var restored := Snapshot.new().capture(replica, 17)
	check(Snapshot.digest(restored) == Snapshot.digest(state), "full state roundtrip preserves every captured rule field")
	if Snapshot.digest(restored) != Snapshot.digest(state):
		FileAccess.open("res://.local/multiplayer-core/hash-restored.json", FileAccess.WRITE).store_string(JSON.stringify(Snapshot._canonical(restored), "", true, true))
	check(replica_events == 0, "install emits no skill damage construction or casualty facts")
	check(replica.by_id[0].queued_population == host.by_id[0].queued_population and replica.by_id[0].population == 70.0, "hidden departure reservations do not pre-deduct displayed garrison")
	check(replica.bear.links[2].settled == 21 and replica.bear.damage_remainders[2] == 0.375, "bear cumulative split and fractional debt survive")
	check(replica.fire_states[0].effect_id == fire.effect_id and replica.fire_states[0].hit_buildings.has(1), "fire identity and per-building hit ledger survive")
	check(replica.projectiles[0].target == replica.bear.shots[0].target and replica.projectiles[0].target.unit_id == troop.unit_id, "both projectile kinds share stable restored soldier references")
	check(reader._objects[str(troop.unit_id)].cloaked and reader._objects[str(troop.unit_id)].weakened, "persistent frog flags survive snapshots")
	var redacted := Snapshot.for_player(state, 1)
	check(redacted.factions["0"][1] == 0.0 and redacted.factions["1"][1] == 50.0 and redacted.factions["1"][2][0] == 12.0, "private energy and cooldowns belong only to receiving faction")
	check(state.factions["0"][1] == 50.0, "privacy filtering never mutates authoritative state")
	_fuzz_records(state)
	_validate_references(state)
	var old_position: Vector3 = replica.projectiles[0].position
	reader._draw_shots(replica, 0.05)
	check(replica.projectiles[0].previous == old_position, "remote projectile trail follows the previous displayed point")
	var shot_target: WarMarches.MarchUnit = replica.projectiles[0].target
	reader._draw_shots(replica, 1.0)
	check(replica.projectiles.is_empty() and replica.bear.shots.is_empty(), "both remote projectile visuals expire without reliable deletion")
	check(shot_target.alive and state.shots.size() == 2 and replica_events == 0, "visual expiry cannot inflict damage or alter the reliable mirror")

	fresh(host)
	var previous := writer.capture(host, 20)
	host.simulate(0.1)
	var continuous := writer.capture(host, 23)
	var delta := Snapshot.diff(previous, continuous)
	check(delta.set.is_empty() and delta.remove.is_empty(), "natural production energy and idle clock do not spam reliable events")
	host._on_unit_arrived(0, 2, 3.0)
	var reinforced := writer.capture(host, 24)
	delta = Snapshot.diff(continuous, reinforced)
	check(delta.set.get("buildings", {}).has("0"), "reinforcement growth sends a reliable garrison fact")
	var mirror := continuous.duplicate(true)
	Snapshot.apply_delta(mirror, delta)
	check(mirror.buildings["0"][3] == reinforced.buildings["0"][3], "reinforcement absolute value applies once")
	Snapshot.apply_delta(mirror, delta)
	check(mirror.buildings["0"][3] == reinforced.buildings["0"][3], "absolute patch replay cannot duplicate reinforced population")
	check(Snapshot.same_structure("buildings", continuous.buildings["0"], reinforced.buildings["0"]), "anchor structure check deliberately ignores continuous population")

	# Expiry must be integrated from the original anchor, not a shortened buff.
	fresh(host)
	host.elapsed = 10.0
	host.marches.send(0, 1, 0, 1, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]))
	troop = host.marches._units[0]
	troop.spawn_delay = 0.1; troop.rush_remaining = 0.2; troop.levitation_remaining = 0.05
	host.marches.create_haste_zone(0, Vector3.ZERO, 50.0, 0.4, 1.6)
	host.marches.create_slow_zone(1, Vector3.ZERO, 50.0, 0.3)
	var expected: float = host.marches.movement_distance(troop, 0.5)
	state = writer.capture(host, 300)
	reader.install(replica, state, 10.5)
	var displayed: WarMarches.MarchUnit = replica.marches._units[0]
	near(displayed.distance, expected, "late anchor handles spawn hold rush and ground-field expiry accurately")
	check(displayed.rush_remaining == 0.0 and displayed.spawn_delay == 0.0 and replica.marches.haste_zones.is_empty(), "expired statuses are visually removed after historical integration")
	var canonical := Snapshot.digest(state)
	reader.present(replica, state, 10.0)
	near(displayed.distance, expected + WarMarches.SPEED * 0.5, "stale unit movement extrapolates at most one second from its anchor")
	check(Snapshot.digest(state) == canonical and replica_events == 0, "presentation cannot mutate canonical mirror or emit gameplay facts")
	var corrected := state.duplicate(true)
	var unit_key: String = corrected.units.keys()[0]
	corrected.time = replica.elapsed
	corrected.units[unit_key][1] = displayed.distance + 0.3
	corrected.units[unit_key][12] = replica.elapsed
	reader.install(replica, corrected, replica.elapsed)
	check(displayed.presentation_offset.length() > 0.2, "small anchor correction creates an independent visual offset")
	reader.present(replica, corrected, 0.5)
	check(displayed.presentation_offset.length() < 0.001, "visual correction settles smoothly without changing rule distance")
	replica.effects.clear()
	replica.effects.append({"life": 0.2})
	replica.effects.append({"life": 0.8})
	reader.present(replica, corrected, 0.3)
	check(replica.effects.size() == 1, "remote capture rings expire without waiting for another gameplay fact")
	near(replica.effects[0].life, 0.5, "remaining presentation effects age by display time")
	replica.effects.clear()
	_recall_and_departure()
	_stress()
	await replica.prepare_shutdown()
	await host.prepare_shutdown()
	print("BLOCK_WAR_SNAPSHOT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _fuzz_records(state: Dictionary) -> void:
	for group: String in Snapshot.GROUPS:
		for malformed: Variant in [null, false, true, "wrong", {}, [], [null], INF, NAN]:
			check(not Snapshot.valid_record(group, malformed, host), "malformed whole record rejected: " + group)
		for row: Variant in state[group].values():
			if not row is Array: continue
			for i: int in row.size():
				var malformed: Array = row.duplicate(true)
				malformed[i] = {"unexpected": [null]}
				check(not Snapshot.valid_record(group, malformed, host), "malformed field rejected: %s/%d" % [group, i])
	for field: int in [2, 3]:
		for index: int in 4:
			var row: Array = state.factions["0"].duplicate(true)
			row[field][index] = "0"
			check(not Snapshot.valid_account(row, host), "nested private-account countdown rejected")

func _validate_references(state: Dictionary) -> void:
	var altered := state.duplicate(true)
	altered.buildings["0"][4] += 1
	check(not Snapshot.valid(altered, host), "snapshot rejects orphaned garrison reservation")
	altered = state.duplicate(true)
	var first: String = altered.units.keys()[0]
	altered.units[first][0] = 999999
	check(not Snapshot.valid(altered, host), "snapshot rejects nonexistent march order")
	altered = state.duplicate(true)
	altered.counters[1] = 1
	check(not Snapshot.valid(altered, host), "snapshot rejects counter that would reuse soldier identity")
	altered = state.duplicate(true)
	altered.orders[altered.orders.keys()[0]][6] = [[0, 0, 0], [0, 0, 0]]
	check(not Snapshot.valid(altered, host), "snapshot rejects zero-length curves before pose evaluation")
	altered = state.duplicate(true)
	altered.finished = true
	check(not Snapshot.valid(altered, host), "finished flag requires an actual winner/draw result")
	altered = state.duplicate(true)
	altered.fires["1"][4] = [999999]
	check(not Snapshot.valid(altered, host), "fire cannot reference a nonexistent building")

func _stress() -> void:
	fresh(host)
	host.marches.send(0, 1, 0, 2000, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]))
	host.marches.tick(0.4)
	var begun := Time.get_ticks_usec()
	var state := writer.capture(host, 1200)
	check(Snapshot.valid(state, host), "two-thousand soldier state validates")
	reader.install(replica, state)
	var first_ms := float(Time.get_ticks_usec() - begun) / 1000.0
	begun = Time.get_ticks_usec()
	for i: int in 8: reader.install(replica, state)
	var repeat_ms := float(Time.get_ticks_usec() - begun) / 8000.0
	check(replica.marches._units.size() == 2000 and reader._orders.size() == 1, "large army reuses one shared baked order")
	print("SNAPSHOT_CPU initial2000_ms=", first_ms, " cached_install_ms=", repeat_ms, " json_bytes=", JSON.stringify(state).length())
	check(first_ms < 1000 and repeat_ms < 100, "snapshot installation fits bounded recovery and cached frame budgets")

func _recall_and_departure() -> void:
	fresh(host)
	host.marches.send(0, 1, 0, 8, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]))
	host.marches.tick(1.0)
	var before := writer.capture(host, 1300)
	reader.install(replica, before)
	var soldier: WarMarches.MarchUnit = host.marches._units[0]
	var key := str(soldier.unit_id)
	var reference: WarMarches.MarchUnit = reader._objects[key]
	var outbound: int = reference.order.order_id
	host.marches.redirect(soldier, host.marches.return_order(soldier.order))
	var after := writer.capture(host, 1301)
	Snapshot.apply_delta(before, Snapshot.diff(before, after))
	check(Snapshot.valid(before, replica), "recall delta atomically installs the new return order")
	reader.install(replica, before)
	check(reader._objects[key] == reference and reference.order.order_id != outbound, "recall keeps restored soldier object and replaces its order identity")
	check(reference.position.distance_to(soldier.position) < 0.0001, "return order reconstructs the same world position")
	host.projectiles.append({"target": soldier, "at": Vector3(3, 3, 0), "position": Vector3(3, 3, 0), "previous": Vector3(3, 3, 0), "to": soldier.position, "tracking": true, "age": 0.1, "duration": 0.4})
	host.marches.hit_target(soldier, Vector3.UP)
	after = writer.capture(host, 1302)
	Snapshot.apply_delta(before, Snapshot.diff(before, after))
	check(Snapshot.valid(before, replica), "in-flight projectile can retain a dead target identity")
	reader.install(replica, before)
	check(not reader._objects.has(key) and not reference.alive, "casualty delta removes soldier without index-based resurrection")
	check(not replica.projectiles[0].target.alive and replica.projectiles[0].target.unit_id == soldier.unit_id, "lost-target projectile keeps an inert identity until its own removal")
	fresh(host)
	host.by_id[0].population = 70.0
	host.marches.queue_tunnel_departure(0, 1, 0, 50, PackedVector3Array([host.by_id[0].position, host.by_id[1].position]), 0.16, 0.7)
	before = writer.capture(host, 1400)
	reader.install(replica, before, 1.5)
	check(replica.by_id[0].population == 70.0 and replica.by_id[0].queued_population == 50, "stale tunnel clock never authorizes local population deduction")
	check(replica.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.pending_departure and not unit.is_exposed()), "expired dig presentation cannot invent unconfirmed departures")
	host.simulate(1.0)
	after = writer.capture(host, 1430)
	Snapshot.apply_delta(before, Snapshot.diff(before, after))
	check(Snapshot.valid(before, replica), "real tunnel departure patch keeps garrison reservations and soldier flags atomic")
	reader.install(replica, before)
	check(replica.by_id[0].population == host.by_id[0].population and replica.by_id[0].queued_population == host.by_id[0].queued_population, "host-confirmed batches synchronize the exact doorway population")
