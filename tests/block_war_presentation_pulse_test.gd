extends SceneTree
## Reinstalling facts never restarts an already displayed bear attack pulse.
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
const BATTLE := preload("res://scenes/block_war/block_war.tscn")
const COMMANDERS: Array[String] = ["bear", "bear", "squirrel", "rabbit", "frog", "fox"]

var host: Node3D
var replica: Node3D
var checks := 0
var failures: Array[String] = []
var gameplay_events := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL PRESENTATION_PULSE ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.00001, "%s: %s / %s" % [label, actual, expected])

func pulses(link: float, ward: float, label: String) -> void:
	near(float(replica.bear.links[0].pulse), link, label + " link")
	near(float(replica.bear.wards[1].pulse), ward, label + " ward")

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = _make_game(105)
	current_scene = host
	replica = _make_game(102)
	replica.presentation_event.connect(func(_kind: String, _payload: Dictionary): gameplay_events += 1)
	replica.marches.departure_queue_changed.connect(func(_source: int, _faction: int, _change: int): gameplay_events += 1)
	host.elapsed = 10.0
	for building: WarBuilding in host.buildings:
		building.kind = 0
		building.level = 1
		building.population = 100.0
		building.faction = building.building_id if building.building_id < 6 else -1
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
	host.by_id[2].faction = 0
	host.bear.links[0] = {"target": 0, "support": 2, "faction": 0, "remaining": 8.0, "settled": 1, "pulse": 1.0}
	host.bear.wards[1] = {"faction": 1, "remaining": 5.0, "shot_clock": 0.5, "pulse": 1.0, "hostile": false}
	var state: Dictionary = Snapshot.new().capture(host, 300)
	var digest: String = Snapshot.digest(state)
	check(Snapshot.valid(state, replica), "pulse fixture is a valid complete authority snapshot")
	var reader := Snapshot.new()
	reader.install(replica, state, 10.0, true)
	pulses(1.0, 1.0, "first attack appears")
	reader.present(replica, state, 0.1)
	pulses(0.7, 0.5, "local animation decays")
	reader.install(replica, state, replica.elapsed, true)
	pulses(0.7, 0.5, "same row identity preserves decay")
	reader.install(replica, state.duplicate(true), replica.elapsed, true)
	pulses(0.7, 0.5, "equal decoded rows preserve decay")

	# Later metadata and a building fact must not date this old pulse anew.
	var unrelated := state.duplicate(true)
	unrelated.time = replica.elapsed
	unrelated.tick = 303
	unrelated.buildings["3"][3] = 90.0
	unrelated.buildings["3"][11] = replica.elapsed
	reader.install(replica, unrelated, replica.elapsed, true)
	pulses(0.7, 0.5, "unrelated reliable fact preserves decay")
	reader.present(replica, unrelated, 0.3)
	pulses(0.0, 0.0, "both flashes expire")
	for index: int in 12:
		reader.present(replica, unrelated, 0.02)
		unrelated.time = replica.elapsed
		unrelated.tick = 313 + index
		reader.install(replica, unrelated, replica.elapsed, true)
		pulses(0.0, 0.0, "unrelated anchor %d cannot revive a flash" % index)
	check(Snapshot.digest(state) == digest, "presentation never modifies the original pulse rows")

	# A real new attack can have exactly the same pulse value as the old one;
	# settled and shot_clock distinguish it from an unrelated reinstall.
	var next_attack := unrelated.duplicate(true)
	next_attack.time = replica.elapsed
	next_attack.tick = 330
	next_attack.links["0"][4] = 3
	next_attack.wards["1"][2] = replica.elapsed + host.SKILL_RULES.BEAR_ORB_INTERVAL
	reader.install(replica, next_attack, replica.elapsed, true)
	pulses(1.0, 1.0, "next settled hit and orb shot replay once")
	reader.present(replica, next_attack, 0.1)
	pulses(0.7, 0.5, "next attack decays normally")
	var sampled_again := next_attack.duplicate(true)
	sampled_again.time = replica.elapsed
	sampled_again.tick = 333
	sampled_again.links["0"][5] = 0.7
	sampled_again.wards["1"][3] = 0.5
	reader.install(replica, sampled_again, replica.elapsed, true)
	pulses(0.7, 0.5, "fresh full snapshot preserves the sampled pulse age")
	reader.present(replica, sampled_again, 0.1)
	pulses(0.4, 0.0, "fresh snapshot does not extend pulse lifetime")

	var quiet := sampled_again.duplicate(true)
	quiet.time = replica.elapsed
	quiet.tick = 336
	quiet.links["0"][4] = 4
	quiet.links["0"][5] = 0.0
	quiet.wards["1"][2] = replica.elapsed + host.SKILL_RULES.BEAR_ORB_INTERVAL
	quiet.wards["1"][3] = 0.0
	reader.install(replica, quiet, replica.elapsed, true)
	pulses(0.0, 0.0, "settlement without shared damage and empty shot attempt stay dark")

	var removed := quiet.duplicate(true)
	removed.links.clear()
	removed.wards.clear()
	reader.install(replica, removed, replica.elapsed, true)
	check(replica.bear.links.is_empty() and replica.bear.wards.is_empty(), "removed effects disappear")
	check(reader._link_pulses.is_empty() and reader._ward_pulses.is_empty(), "removed effect pulse caches are retired")
	var reused := state.duplicate(true)
	reused.time = replica.elapsed
	reused.tick = 340
	reader.install(replica, reused, replica.elapsed, true)
	pulses(1.0, 1.0, "recreated effect at the same building can flash again")

	var late_reader := Snapshot.new()
	late_reader.install(replica, state, 10.1, true)
	pulses(0.7, 0.5, "late first install ages pulses from fact time")
	late_reader.install(replica, state, 10.5, true)
	pulses(0.0, 0.0, "late repeat install cannot revive expired pulses")
	var expired_reader := Snapshot.new()
	expired_reader.install(replica, state, 10.5, true)
	pulses(0.0, 0.0, "old first snapshot has no already expired flash")
	var buffered_reader := Snapshot.new()
	buffered_reader.install(replica, state, 9.9, true)
	pulses(1.0, 1.0, "fact ahead of buffered display appears once")
	buffered_reader.present(replica, state, 0.05)
	buffered_reader.install(replica, state, replica.elapsed, true)
	pulses(0.85, 0.75, "buffered display still decays before fact clock catches up")

	var paused := state.duplicate(true)
	paused.match_control.paused = true
	paused.match_control.by = 0
	var pause_reader := Snapshot.new()
	pause_reader.install(replica, paused, 10.0, true)
	pause_reader.present(replica, paused, 0.5)
	near(replica.elapsed, 10.0, "pause freezes display time")
	pause_reader.install(replica, paused, replica.elapsed, true)
	pulses(1.0, 1.0, "paused reinstall preserves the frozen pulse")
	pause_reader.install(replica, state, replica.elapsed, true)
	pause_reader.present(replica, state, 0.1)
	pulses(0.7, 0.5, "resume continues the same pulse")
	check(gameplay_events == 0, "pulse presentation emits no damage or departure facts")
	await replica.prepare_shutdown()
	await host.prepare_shutdown()
	replica.free()
	host.free()
	print("PRESENTATION_PULSE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

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
