extends SceneTree
## Exact presentation equivalence against the former per-soldier field clock.
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
const BATTLE := preload("res://scenes/block_war/block_war.tscn")
const COMMANDERS: Array[String] = ["squirrel", "rabbit", "bear", "frog", "fox", "squirrel"]

class ReferenceCodec:
	extends "res://scripts/network/war_snapshot.gd"
	func _move_visual_unit(game: Node, unit: WarMarches.MarchUnit, seconds: float, at_time: float) -> void:
		# Restore precisely the removed operation and its old early-return guard.
		if not unit.pending_departure and seconds > 0.0:
			_set_field_clock(game, _last_state, at_time, false)
		super._move_visual_unit(game, unit, seconds, at_time)

var host: Node3D
var optimized: Node3D
var reference: Node3D
var writer := Snapshot.new()
var reader := Snapshot.new()
var old_reader := ReferenceCodec.new()
var state: Dictionary = {}
var state_digest := ""
var checks := 0
var failures: Array[String] = []
var gameplay_events := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL PRESENTATION_EQUIVALENCE ", label)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = _make_game(105)
	current_scene = host
	optimized = _make_game(102)
	reference = _make_game(102)
	for game: Node3D in [optimized, reference]:
		game.presentation_event.connect(func(_kind: String, _payload: Dictionary): gameplay_events += 1)
		game.marches.departure_queue_changed.connect(func(_source: int, _faction: int, _change: int): gameplay_events += 1)
	_seed_host()
	var early := writer.capture(host, 300)
	check(early.units.size() == 90, "fixture has 72 moving and 18 reserved soldiers")
	if not _install_pair(early, float(early.time), "initial live fields"):
		await _finish()
		return
	for game: Node3D in [optimized, reference]:
		game.effects.append({"life": 0.15})
		game.effects.append({"life": 0.65})
	for delta: float in [0.0, -0.01, 0.01, 0.025, 0.045, 0.04]:
		_advance(delta, "initial field/status boundary")

	# This is the same mixture produced when optional anchors for different units
	# arrive at different ticks. Rows come from real captures, including deadlines.
	host.simulate(0.12)
	var middle := writer.capture(host, 304)
	host.simulate(0.16)
	var latest := writer.capture(host, 309)
	var mixed := latest.duplicate(true)
	var bases: Dictionary = {}
	for key: String in mixed.units:
		if mixed.units[key][3] or early.units[key][3]: continue
		var sample: Dictionary = [early, middle, latest][int(key) % 3]
		mixed.units[key] = sample.units[key].duplicate(true)
		bases[float(mixed.units[key][12])] = true
	# Historical views retain expired field deadlines until older rows integrate.
	mixed.fields = early.fields.duplicate(true)
	check(bases.size() == 3, "historical unit rows retain three distinct anchor times")
	check(mixed.fields.values().any(func(row: Array): return row[0] != "shield" and float(row[4]) < float(mixed.time)), "history includes a field expired before the newest anchor")
	if not _install_pair(mixed, float(latest.time) + 0.09, "mixed historical anchors"):
		await _finish()
		return
	# The preceding install intentionally reused displayed units: unchanged rows
	# keep their already-presented distance. Compare traversal orders with fresh
	# codecs on BOTH sides, so every row integrates from its historical anchor.
	reader = Snapshot.new()
	old_reader = ReferenceCodec.new()
	if not _install_pair(mixed, float(latest.time) + 0.09, "fresh forward mixed historical anchors"):
		await _finish()
		return
	var ordered_distances := _distances(optimized)
	var reversed := mixed.duplicate(true)
	var keys: Array = reversed.units.keys()
	keys.reverse()
	reversed.units = {}
	for key: String in keys: reversed.units[key] = mixed.units[key].duplicate(true)
	# Fresh codecs force historical integration again, avoiding the unchanged-row
	# fast path when testing a different last anchor in the dictionary traversal.
	reader = Snapshot.new()
	old_reader = ReferenceCodec.new()
	if not _install_pair(reversed, float(latest.time) + 0.09, "reversed mixed historical anchors"):
		await _finish()
		return
	check(_distances(optimized) == ordered_distances, "historical integration is independent of unit dictionary order")
	var pending_before := _pending_positions(optimized)
	check(not pending_before.is_empty(), "historical install retains native departure reservations")
	for delta: float in [0.015, 0.035, 0.08, 0.12, 0.22, 0.35, 0.9, 1.2]:
		_advance(delta, "mixed anchor expiry and extrapolation")
	check(_pending_positions(optimized) == pending_before, "presentation never releases or advances reserved soldiers")
	check(optimized.marches.haste_zones.is_empty() and optimized.marches.slow_zones.is_empty() and optimized.marches.weak_zones.is_empty(), "all overlapping field kinds expire")
	check(optimized.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.rush_remaining == 0.0 and unit.levitation_remaining == 0.0 and unit.spawn_delay == 0.0), "rush levitation and spawn clocks expire")
	check(optimized.projectiles.is_empty() and optimized.bear.shots.is_empty(), "tower and orb visuals expire without casualty facts")
	var capped := _distances(optimized)
	_advance(0.4, "beyond every historical extrapolation cap")
	check(_distances(optimized) == capped, "all movement stops at each row's extrapolation cap")

	# A later real authority sample changes a building owner, recalls a squad and
	# removes a whole order. Existing small corrections must retain smooth offsets.
	host.simulate(1.1)
	host.by_id[6].faction = 2
	host.by_id[6].population = 21.0
	var recalled: Array[WarMarches.MarchUnit] = []
	for unit: WarMarches.MarchUnit in host.marches._units:
		if unit.order.faction == 0 and unit.is_exposed() and recalled.size() < 3:
			recalled.append(unit)
	check(recalled.size() == 3, "authority has exposed soldiers for a real recall")
	if not recalled.is_empty():
		var returning: WarMarches.MarchOrder = host.marches.return_order(recalled[0].order)
		for unit: WarMarches.MarchUnit in recalled: host.marches.redirect(unit, returning)
	var removed: Array[String] = []
	var removed_order := ""
	for index: int in range(host.marches._units.size() - 1, -1, -1):
		var unit: WarMarches.MarchUnit = host.marches._units[index]
		if unit.order.faction == 1:
			removed.append(str(unit.unit_id))
			removed_order = str(unit.order.order_id)
			host.marches._remove_unit(index)
	host.sync_environment_bonuses()
	var corrected := writer.capture(host, 342)
	if not _install_pair(corrected, float(corrected.time), "capture recall and unit removal"):
		await _finish()
		return
	check(optimized.by_id[6].faction == 2, "captured building ownership reaches both displays")
	check(not removed.is_empty() and removed.all(func(key: String): return not reader._objects.has(key)) and not reader._orders.has(removed_order), "removed soldiers and their obsolete order are retired")
	check(optimized.marches._units.any(func(unit: WarMarches.MarchUnit): return unit.order.returning), "recalled soldiers retain their new return order")
	check(optimized.marches._units.any(func(unit: WarMarches.MarchUnit): return unit.presentation_offset.length_squared() > 0.000001), "small authoritative corrections exercise presentation smoothing")
	_advance(0.05, "first correction smoothing frame")
	_advance(0.12, "second correction smoothing frame")

	# Pause arrives behind the already extrapolated display and reinstalls rows at
	# the control boundary. No presentation clock may run until authority resumes.
	host.simulate(0.08)
	host.match_paused = true
	host.pause_faction = 2
	var paused := writer.capture(host, 345)
	if not _install_pair(paused, float(paused.time), "pause behind display clock"):
		await _finish()
		return
	var frozen := _units(optimized)
	var paused_time: float = optimized.elapsed
	_advance(0.7, "authoritative pause")
	check(optimized.elapsed == paused_time and _units(optimized) == frozen, "pause freezes distance gait statuses and offsets exactly")
	host.match_paused = false
	host.pause_faction = -1
	host.marches.create_haste_zone(2, Vector3(-3, 0, 0), 10.0, 0.31, 1.6)
	host.marches.create_slow_zone(1, Vector3(2, 0, 0), 14.0, 0.19)
	var resumed := writer.capture(host, 346)
	if not _install_pair(resumed, float(resumed.time), "resume with changed field geometry"):
		await _finish()
		return
	for delta: float in [0.03, 0.16, 0.12, 0.3, 0.6]:
		_advance(delta, "resumed field crossings")
	for game: Node3D in [optimized, reference]: game.simulation_paused = true
	frozen = _units(optimized)
	paused_time = optimized.elapsed
	_advance(0.4, "transport pause")
	check(optimized.elapsed == paused_time and _units(optimized) == frozen, "transport pause also freezes presentation")
	for game: Node3D in [optimized, reference]: game.simulation_paused = false

	# No active units is a separate boundary for moving the shared clock outside
	# the unit loop; fields and buildings must still present identically.
	host.marches.clear()
	for building: WarBuilding in host.buildings: building.queued_population = 0
	host.projectiles.clear()
	host.bear.shots.clear()
	host.marches.create_haste_zone(0, Vector3.ZERO, 7.0, 0.2, 1.6)
	var empty := writer.capture(host, 347)
	if _install_pair(empty, float(empty.time), "empty army with live field"):
		_advance(0.1, "empty army before field expiry")
		_advance(0.2, "empty army after field expiry")
		check(optimized.marches.haste_zones.is_empty(), "empty army does not prevent field expiry")
	check(gameplay_events == 0, "install and presentation emit no gameplay or departure facts")
	await _finish()

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

func _seed_host() -> void:
	host.elapsed = 10.0
	for building: WarBuilding in host.buildings:
		building.kind = 0
		building.level = 1
		building.population = 100.0
		building.faction = building.building_id if building.building_id < 6 else -1
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
	for faction: int in host.faction_count:
		var skill: RefCounted = host.faction_skills[faction]
		skill.energy = host.ENERGY_MAX * 0.4
		skill.cooldowns[0] = 0.45
		skill.durations[1] = 0.65
		var z := float(faction - 3) * 1.3
		host.marches.send(faction, faction + 6, faction, 12, PackedVector3Array([Vector3(-14, 0, z), Vector3(4, 0, z + 2), Vector3(28, 0, z)]))
	for index: int in host.marches._units.size():
		var unit: WarMarches.MarchUnit = host.marches._units[index]
		unit.distance = 0.4 + float(index % 12) * 0.72
		unit.spawn_delay = [0.0, 0.06, 0.23][index % 3]
		unit.rush_remaining = [0.0, 0.18, 0.52, 0.8][index % 4]
		unit.levitation_remaining = [0.0, 0.0, 0.11, 0.41][index % 4]
		unit.cloaked = index % 7 == 0
		unit.weakened = index % 5 == 0
		host.marches._update_pose(unit)
	host.marches.queue_departure(4, 10, 4, 12, PackedVector3Array([Vector3(-10, 0, 8), Vector3(35, 0, 8)]))
	host.marches.queue_tunnel_departure(5, 11, 5, 6, PackedVector3Array([Vector3(-10, 0, -8), Vector3(35, 0, -8)]), 0.12, 0.75)
	host.marches.create_haste_zone(0, Vector3(-8, 0, -2), 6.0, 0.55, 1.6)
	host.marches.create_haste_zone(2, Vector3(-9, 0, 0), 4.5, 0.08, 1.6)
	host.marches.create_haste_zone(4, Vector3(-8, 0, 3), 8.0, 0.8, 1.4)
	host.marches.create_slow_zone(1, Vector3(-7, 0, 0), 8.0, 0.25)
	host.marches.create_slow_zone(3, Vector3(-6, 0, 1), 6.0, 0.4)
	host.marches.apply_frog_field(0, 1, Vector3(-8, 0, 0))
	host.marches.weak_zones[1].remaining = 0.65
	host.marches.apply_frog_field(0, 2, Vector3(-5, 0, 2))
	host.marches.weak_zones[2].remaining = 0.3
	host.by_id[2].begin_disruption(0.4)
	host.by_id[3].begin_burrow(0.6)
	host.begin_building_construction(host.by_id[1], -1, 1)
	host.shields[0] = 0.55
	host.morale.adjust(0, 500.0)
	host.bear.links[2] = {"target": 2, "support": 4, "faction": 2, "remaining": 0.7, "settled": 3, "pulse": 0.8}
	host.bear.locks[1] = {"faction": 2, "remaining": 0.21}
	host.bear.wards[3] = {"faction": 3, "remaining": 0.36, "shot_clock": 0.5, "pulse": 0.5, "hostile": false}
	host.bear.wards[1] = {"faction": 2, "remaining": 0.36, "shot_clock": 0.5, "pulse": 0.5, "hostile": true}
	var target: WarMarches.MarchUnit = host.marches._units[4]
	target.reserved = true
	target.intercepted_by = 1
	var origin := target.position + Vector3(2, 3, 0)
	host.projectiles.append({"target": target, "at": origin, "position": origin, "previous": origin, "to": target.position + Vector3.UP * 0.65, "tracking": true, "age": 0.02, "duration": 0.8})
	host.bear.shots.append({"target": target, "origin": origin, "position": origin, "previous": origin, "to": target.position + Vector3.UP * 0.65, "tracking": false, "age": 0.04, "duration": 0.9})
	host.start_fire(Vector3(25, 0, 20), 2.0, 1)
	host.sync_environment_bonuses()

func _install_pair(next: Dictionary, at_time: float, label: String) -> bool:
	var valid := Snapshot.valid(next, optimized)
	check(valid, label + ": fixture passes snapshot validation")
	if not valid: return false
	state = next
	state_digest = Snapshot.digest(state)
	# Independent trees and independent dictionaries prevent cross-contamination.
	reader.install(optimized, state, at_time)
	old_reader.install(reference, state.duplicate(true), at_time)
	_compare(label)
	return true

func _advance(delta: float, label: String) -> void:
	reader.present(optimized, state, delta)
	old_reader.present(reference, old_reader._last_state, delta)
	_compare("%s delta=%s" % [label, delta])

func _compare(label: String) -> void:
	check(_units(optimized) == _units(reference), label + ": exact unit distance gait pose status and offset")
	var actual := Snapshot.new().capture(optimized, 1)
	var expected := Snapshot.new().capture(reference, 1)
	for group: String in Snapshot.GROUPS:
		check(actual[group] == expected[group], label + ": exact " + group)
	check(actual == expected and Snapshot.digest(actual) == Snapshot.digest(expected), label + ": full capture and digest")
	check(Snapshot.digest(state) == state_digest and Snapshot.digest(old_reader._last_state) == state_digest, label + ": canonical input remains unchanged")
	check(_fields(optimized) == _fields(reference), label + ": live field clocks and skill defense state")
	check(_shots(optimized) == _shots(reference), label + ": projectile trails tracking and references")
	check(optimized.effects == reference.effects, label + ": presentation effect lifetimes")
	check(_meshes(optimized.marches, ["Militia", "CloakedMilitia"]) == _meshes(reference.marches, ["Militia", "CloakedMilitia"]), label + ": rendered soldier transforms and shader data")
	var effect_paths: Array[String] = ["Frog/Mist", "Frog/Bubbles", "Bear/LockGrounds", "Bear/LockChains", "Bear/LockSeals", "Bear/LockShackles", "Bear/HostileGrounds", "Bear/Fractures", "Bear/UpgradeSweeps", "Bear/Chains", "Bear/Wards", "Bear/Bolts"]
	check(_meshes(optimized.world_effects, effect_paths) == _meshes(reference.world_effects, effect_paths), label + ": native field and projectile mesh output")

func _units(game: Node3D) -> Dictionary:
	var rows := {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		rows[unit.unit_id] = [unit.order.order_id, unit.distance, unit.gait, unit.position, unit.heading, unit.presentation_offset, unit.lane, unit.spawn_delay, unit.rush_remaining, unit.levitation_remaining, unit.pending_departure, unit.departure_sequence, unit.alive, unit.cloaked, unit.weakened, unit.reserved, unit.intercepted_by]
	return rows

func _pending_positions(game: Node3D) -> Dictionary:
	var rows := {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.pending_departure: rows[unit.unit_id] = [unit.distance, unit.gait]
	return rows

func _distances(game: Node3D) -> Dictionary:
	var rows := {}
	for unit: WarMarches.MarchUnit in game.marches._units: rows[unit.unit_id] = unit.distance
	return rows

func _fields(game: Node3D) -> Array:
	return [game.marches.haste_zones, game.marches.slow_zones, game.marches.weak_zones, game.shields, game.bear.locks, game.bear.wards, game.marches.environment_speed]

func _shots(game: Node3D) -> Array:
	var rows: Array = []
	for shots: Array in [game.projectiles, game.bear.shots]:
		for shot: Dictionary in shots:
			rows.append([shot.network_id, shot.target.unit_id, shot.target.alive, shot.position, shot.previous, shot.to, shot.age, shot.duration, shot.tracking])
	return rows

func _meshes(branch: Node, paths: Array[String]) -> Dictionary:
	var result := {}
	for path: String in paths:
		var mesh: MultiMesh = branch.get_node(path).multimesh
		var rows: Array = []
		for index: int in mesh.visible_instance_count:
			var row: Array = [mesh.get_instance_transform(index)]
			if mesh.use_custom_data: row.append(mesh.get_instance_custom_data(index))
			if mesh.use_colors: row.append(mesh.get_instance_color(index))
			rows.append(row)
		result[path] = rows
	return result

func _finish() -> void:
	await optimized.prepare_shutdown()
	await reference.prepare_shutdown()
	await host.prepare_shutdown()
	optimized.free()
	reference.free()
	host.free()
	print("PRESENTATION_EQUIVALENCE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
