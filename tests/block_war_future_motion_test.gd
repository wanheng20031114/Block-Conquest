extends SceneTree
## Future motion samples interpolate until their timestamp, then predict once.
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
const BATTLE := preload("res://scenes/block_war/block_war.tscn")
const COMMANDERS: Array[String] = ["squirrel", "rabbit", "bear", "frog", "fox", "pig"]
const EPSILON := 0.00002

var host: Node3D
var coarse: Node3D
var fine: Node3D
var writer := Snapshot.new()
var checks := 0
var failures: Array[String] = []
var gameplay_events := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL FUTURE_MOTION ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < EPSILON, "%s: %s / %s" % [label, actual, expected])

func near_vector(actual: Vector3, expected: Vector3, label: String) -> void:
	check(actual.distance_to(expected) < EPSILON, "%s: %s / %s" % [label, actual, expected])

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = _make_game(105)
	current_scene = host
	coarse = _make_game(102)
	fine = _make_game(102)
	for game: Node3D in [coarse, fine]:
		game.presentation_event.connect(func(_kind: String, _payload: Dictionary): gameplay_events += 1)
		game.marches.departure_queue_changed.connect(func(_source: int, _faction: int, _change: int): gameplay_events += 1)
	_simple_future()
	_mixed_fields()
	check(gameplay_events == 0, "display installation and prediction emit no gameplay facts")
	for game: Node3D in [fine, coarse, host]:
		await game.prepare_shutdown()
		game.free()
	print("FUTURE_MOTION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _simple_future() -> void:
	_seed(9.9, 1)
	var soldier: WarMarches.MarchUnit = host.marches._units[0]
	soldier.distance = 20.0 - WarMarches.SPEED * 0.1
	soldier.gait = 3.0
	host.marches._update_pose(soldier)
	var past := writer.capture(host, 297)
	host.simulate(0.1)
	host.elapsed = 10.0
	var future := writer.capture(host, 300)
	var key: String = future.units.keys()[0]
	var endpoint: Vector3 = soldier.position
	var endpoint_gait: float = soldier.gait
	near(soldier.distance, 20.0, "authority fixture reaches distance twenty at time ten")
	check(Snapshot.valid(past, coarse) and Snapshot.valid(future, coarse), "both real authority samples validate")
	var digest := Snapshot.digest(future)
	var a := Snapshot.new()
	var b := Snapshot.new()
	a.install(coarse, past, 9.9, true)
	b.install(fine, past.duplicate(true), 9.9, true)
	var previous: Vector3 = coarse.marches._units[0].position
	var previous_gait: float = coarse.marches._units[0].gait
	a.install(coarse, future, 9.9, true, true)
	b.install(fine, future.duplicate(true), 9.9, true, true)
	var displayed: WarMarches.MarchUnit = coarse.marches._units[0]
	near(displayed.distance, 20.0, "future sample becomes an endpoint without forward prediction")
	near_vector(displayed.position + displayed.presentation_offset, previous, "install preserves the previously displayed position")
	near(displayed.gait + displayed.presentation_gait_offset, previous_gait, "install preserves the previously displayed gait")
	check(displayed.presentation_offset.length() > 0.1, "fixture exercises a nonzero future position correction")
	a.present(coarse, future, 0.0)
	check(not a._render_pending, "zero-time frame flushes the deferred endpoint render")
	near(displayed.distance, 20.0, "zero-time render cannot advance a future sample")
	a.present(coarse, future, 0.05)
	for index: int in 5: b.present(fine, future, 0.01)
	near(displayed.distance, 20.0, "display time 9.95 does not move the time-ten sample early")
	near(displayed.gait, endpoint_gait, "future gait is not advanced early")
	near_vector(displayed.position + displayed.presentation_offset, previous.lerp(endpoint, 0.5), "future position reaches the interpolation midpoint")
	near(displayed.gait + displayed.presentation_gait_offset, lerpf(previous_gait, endpoint_gait, 0.5), "future gait reaches the interpolation midpoint")
	_compare_games(coarse, fine, "five small frames equal the first half interpolation")
	a.present(coarse, future, 0.1)
	for index: int in 10: b.present(fine, future, 0.01)
	near(coarse.elapsed, 10.05, "straddling frame advances the display clock normally")
	near(displayed.distance, 20.0 + WarMarches.SPEED * 0.05, "straddling frame integrates only time ten through 10.05")
	near(displayed.gait, endpoint_gait + WarMarches.SPEED * 0.05 * 7.0, "gait advances only for the post-sample distance")
	near_vector(displayed.presentation_offset, Vector3.ZERO, "future position correction reaches zero at its timestamp")
	near(displayed.presentation_gait_offset, 0.0, "future gait correction reaches zero at its timestamp")
	_compare_games(coarse, fine, "straddling and split frames agree after the sample")
	check(Snapshot.digest(future) == digest, "interpolation leaves authoritative future rows immutable")

func _mixed_fields() -> void:
	_seed(9.8, 6)
	# Absolute deadlines deliberately fall on both sides of different row bases.
	# Rush can expire while a unit is still hidden or held in the air.
	var spawn_ends := [0.0, 10.03, 10.03, 0.0, 10.015, 0.0]
	var rush_ends := [0.0, 10.10, 10.07, 10.02, 10.11, 0.0]
	var float_ends := [0.0, 10.06, 0.0, 10.025, 10.01, 0.0]
	for index: int in host.marches._units.size():
		var unit: WarMarches.MarchUnit = host.marches._units[index]
		unit.spawn_delay = maxf(0.0, spawn_ends[index] - host.elapsed)
		unit.rush_remaining = maxf(0.0, rush_ends[index] - host.elapsed)
		unit.levitation_remaining = maxf(0.0, float_ends[index] - host.elapsed)
		host.marches._update_pose(unit)
	host.marches.create_haste_zone(0, Vector3.ZERO, 100.0, 0.265, 1.6)
	host.marches.create_slow_zone(1, Vector3.ZERO, 100.0, 0.24)
	var samples: Dictionary = {"9.8": writer.capture(host, 294)}
	for boundary: Array in [[9.85, "9.85", 296], [9.9, "9.9", 297], [10.0, "10", 300], [10.05, "10.05", 302], [10.08, "10.08", 303]]:
		host.simulate(float(boundary[0]) - host.elapsed)
		host.elapsed = float(boundary[0])
		samples[boundary[1]] = writer.capture(host, int(boundary[2]))
	var mixed: Dictionary = samples["10.08"].duplicate(true)
	var keys: Array = mixed.units.keys()
	var bases := ["10.05", "9.8", "10", "9.9", "10.08", "9.85"]
	for index: int in keys.size():
		mixed.units[keys[index]] = samples[bases[index]].units[keys[index]].duplicate(true)
	# The display at 9.9 still needs the expired fields' historical deadlines.
	mixed.fields = samples["9.8"].fields.duplicate(true)
	check(Snapshot.valid(mixed, coarse), "mixed historical and future authority rows validate")
	check(mixed.units[keys[0]][12] > 9.9 and mixed.units[keys[1]][12] < 9.9, "a future unit precedes a historical unit in iteration order")
	check(float(mixed.fields["slow:1"][4]) < float(mixed.units[keys[0]][12]) and float(mixed.fields["haste:0"][4]) > float(mixed.units[keys[0]][12]), "first future sample lies between slow and haste expiry")
	var digest := Snapshot.digest(mixed)
	var a := Snapshot.new()
	var b := Snapshot.new()
	a.install(coarse, mixed, 9.9, true)
	b.install(fine, mixed.duplicate(true), 9.9, true)
	for key: String in keys:
		var row: Array = mixed.units[key]
		var unit: WarMarches.MarchUnit = a._objects[key]
		var expected: float = float(row[1]) if float(row[12]) > 9.9 else float(samples["9.9"].units[key][1])
		near(unit.distance, expected, "mixed initial sample %s advances only its historical portion" % key)
	b.present(fine, mixed, 0.02)
	for key: String in keys:
		var row: Array = mixed.units[key]
		if float(row[12]) <= fine.elapsed: continue
		var unit: WarMarches.MarchUnit = b._objects[key]
		near(unit.distance, float(row[1]), "future mixed unit %s stays at its endpoint before its sample" % key)
		near(unit.gait, float(row[13]), "future mixed gait %s stays at its endpoint before its sample" % key)
	a.present(coarse, mixed, 0.23)
	for index: int in 21: b.present(fine, mixed, 0.01)
	near(coarse.elapsed, 10.13, "long mixed frame crosses every sample and effect deadline")
	_compare_games(coarse, fine, "mixed future and historical rows are frame partition independent")
	host.simulate(10.13 - host.elapsed)
	host.elapsed = 10.13
	_compare_authority(coarse, "single frame")
	_compare_authority(fine, "split frames")
	check(coarse.marches.haste_zones.is_empty() and coarse.marches.slow_zones.is_empty(), "both fields retire after their exact historical expiry")
	for unit: WarMarches.MarchUnit in coarse.marches._units:
		check(unit.spawn_delay == 0.0 and unit.rush_remaining == 0.0 and unit.levitation_remaining == 0.0, "all unit timers expire without a second wait for unit %d" % unit.unit_id)

	# Reversing the mixed dictionary catches a leaked per-unit field clock.
	var reversed := mixed.duplicate(true)
	reversed.units.clear()
	keys.reverse()
	for key: String in keys: reversed.units[key] = mixed.units[key].duplicate(true)
	var reverse_reader := Snapshot.new()
	reverse_reader.install(coarse, reversed, 9.9, true)
	reverse_reader.present(coarse, reversed, 0.23)
	_compare_games(coarse, fine, "reversed future/history traversal keeps identical results")
	_compare_authority(coarse, "reversed traversal")
	check(Snapshot.digest(mixed) == digest, "mixed presentation preserves every input row and field deadline")

func _compare_games(actual: Node3D, expected: Node3D, label: String) -> void:
	near(actual.elapsed, expected.elapsed, label + " elapsed")
	var reference := {}
	for unit: WarMarches.MarchUnit in expected.marches._units: reference[unit.unit_id] = unit
	check(actual.marches._units.size() == reference.size(), label + " unit count")
	for unit: WarMarches.MarchUnit in actual.marches._units:
		var other: WarMarches.MarchUnit = reference[unit.unit_id]
		var prefix := "%s unit %d" % [label, unit.unit_id]
		near(unit.distance, other.distance, prefix + " distance")
		near(unit.gait, other.gait, prefix + " gait")
		near_vector(unit.position + unit.presentation_offset, other.position + other.presentation_offset, prefix + " displayed position")
		near(unit.gait + unit.presentation_gait_offset, other.gait + other.presentation_gait_offset, prefix + " displayed gait")
		near(unit.spawn_delay, other.spawn_delay, prefix + " spawn")
		near(unit.rush_remaining, other.rush_remaining, prefix + " rush")
		near(unit.levitation_remaining, other.levitation_remaining, prefix + " levitation")
		near(unit.slow_remaining, other.slow_remaining, prefix + " lingering slow")

func _compare_authority(game: Node3D, label: String) -> void:
	var reference := {}
	for unit: WarMarches.MarchUnit in host.marches._units: reference[unit.unit_id] = unit
	for unit: WarMarches.MarchUnit in game.marches._units:
		var authority: WarMarches.MarchUnit = reference[unit.unit_id]
		near(unit.distance, authority.distance, "%s agrees with authority distance for %d" % [label, unit.unit_id])
		near(unit.gait, authority.gait, "%s agrees with authority gait for %d" % [label, unit.unit_id])
		near(unit.slow_remaining, authority.slow_remaining, "%s agrees with authority lingering slow for %d" % [label, unit.unit_id])

func _seed(at_time: float, count: int) -> void:
	host.marches.clear()
	host.projectiles.clear()
	host.fire_states.clear()
	host.bear.links.clear()
	host.bear.wards.clear()
	host.bear.shots.clear()
	host.shields.clear()
	host.morale.configure(host.faction_count)
	host.elapsed = at_time
	for building: WarBuilding in host.buildings:
		building.kind = 0
		building.level = 1
		building.population = 100.0
		building.faction = building.building_id if building.building_id < 6 else -1
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
	for skill: RefCounted in host.faction_skills:
		skill.cooldowns.fill(0.0)
		skill.durations.fill(0.0)
		skill.recruit_target_id = -1
	host.sync_environment_bonuses()
	for index: int in count:
		var z := float(index) * 2.0
		host.marches.send(0, 6, 0, 1, PackedVector3Array([Vector3(-40, 0, z), Vector3(60, 0, z)]))
		var unit: WarMarches.MarchUnit = host.marches._units[-1]
		unit.distance = 20.0 + index
		unit.gait = 0.25 * index
		host.marches._update_pose(unit)

func _make_game(player: int) -> Node3D:
	var game: Node3D = BATTLE.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.simulation_paused = false
	var config := {"host_player_id": 105, "slots": []}
	for faction: int in 6:
		config.slots.append({"faction_id": faction, "team_id": faction % 2, "player_id": 100 + faction, "kind": "human", "controller": "human", "commander": COMMANDERS[faction], "name": "Seat %d" % faction})
	game.configure_match(config, player)
	return game
