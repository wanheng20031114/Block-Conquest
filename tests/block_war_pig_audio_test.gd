extends "res://tests/block_war_replication_test.gd"
## Observe the native sound signal from real gestures and serialized gameplay.
const CUES: Array[StringName] = [
	&"war_pig_charge", &"war_pig_fly", &"war_pig_formation", &"war_pig_drop", &"war_pig_impact",
]
var sounds: Array[Dictionary] = []
var game: Node3D

func configuration() -> Dictionary:
	var value := super.configuration()
	value.slots[2].commander = "pig"
	value.match_id = "pig-audio-test"
	return value

func _record(peer: String, kind: StringName, at: Vector3, spatial: bool) -> void:
	sounds.append({"peer": peer, "kind": kind, "at": at, "spatial": spatial})

func heard(peer: String, kind: StringName) -> int:
	return sounds.filter(func(event: Dictionary): return event.peer == peer and event.kind == kind).size()

func pig_count(peer: String) -> int:
	return sounds.filter(func(event: Dictionary): return event.peer == peer and event.kind in CUES).size()

func _clear_audio(value: Node3D) -> void:
	for branch: String in ["UI", "Combat", "Foley"]:
		for voice: Node in value.audio.get_node(branch).get_children(): voice.stop()
	value.audio._next_sound_ms.clear()

func _mouse(at: Vector2, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
	root.push_input(event, true)

func _refill(value: Node3D, faction: int = 0) -> void:
	value.faction_skills[faction].energy = 100.0
	value.faction_skills[faction].cooldowns.fill(0.0)

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy": quit(2); return
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	var settings: GameSettings = root.get_node("Session/Settings")
	var original := settings.snapshot()
	var preferences := settings.defaults()
	preferences.music_enabled = false
	settings._apply_values(preferences, false)
	await _local_gestures()
	await _network_events()
	settings._apply_values(original, false)
	print("PIG_AUDIO checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _local_gestures() -> void:
	var session: Node = root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"pig"
	session.block_war_opponent_commander = &"squirrel"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.sound_played.connect(func(kind: StringName, at: Vector3, spatial: bool): _record("local", kind, at, spatial))
	for building: WarBuilding in game.buildings:
		building.kind = 3
		building.population = 80.0
		building.refresh_visual()
	_refill(game)
	game.update_hud()
	await physics_frame
	await process_frame
	var home: WarBuilding = game.buildings[0]
	var at: Vector3 = home.global_position
	for index: int in 4:
		_refill(game)
		_clear_audio(game)
		sounds.clear()
		game.select_building(null)
		var icon: Vector2 = game.hud.get_node("UI/Skills/Row/Skill%d" % index).get_global_rect().get_center()
		var aim: Vector2 = game.camera.unproject_position(at if index == 3 else at + Vector3.UP * 1.5)
		_mouse(icon, true)
		check(game.armed_skill == index and pig_count("local") == 0, "Pig %d pickup has no premature success sound" % index)
		_mouse(aim, true, MOUSE_BUTTON_RIGHT)
		_mouse(aim, false)
		check(game.armed_skill == -1 and pig_count("local") == 0 and is_equal_approx(game.energy, 100.0), "Pig %d right-click cancellation cannot later cast or play its cue" % index)
		_clear_audio(game)
		sounds.clear()
		_mouse(icon, true)
		_mouse(aim, false)
		check(game.cooldowns[index] > 0 and heard("local", CUES[index]) == 1 and pig_count("local") == 1, "Pig %d valid native release plays exactly its own cue" % index)
		var events := sounds.filter(func(event: Dictionary): return event.kind == CUES[index])
		if events.size() == 1:
			check(events[0].spatial and events[0].at.distance_to(at) < 0.15, "Pig %d cue is located at the actual effect" % index)
		check(not (game.cast_ground_skill(index, at) if index == 3 else game.cast_skill(index, home)) and pig_count("local") == 1, "Pig %d rejected cooldown cannot repeat its success cue" % index)
	# A retry after cooldown reset still fails if this building is already armed.
	_refill(game)
	for index: int in 3:
		var before := pig_count("local")
		check(not game.cast_skill(index, home) and pig_count("local") == before, "Pig %d duplicate preparation stays silent" % index)
	var enemy: WarBuilding = game.buildings.filter(func(building: WarBuilding): return building.faction == 1)[0]
	for index: int in 3:
		var before := pig_count("local")
		check(not game.cast_skill(index, enemy) and pig_count("local") == before, "Pig %d hostile building rejection stays silent" % index)
	check(heard("local", &"war_pig_impact") == 0, "R release is a falling cue, never an immediate impact")
	game.simulate(0.649)
	check(heard("local", &"war_pig_impact") == 0, "R remains silent until the 0.65 second damage boundary")
	game.set_paused(true)
	game.simulate(3.0)
	check(heard("local", &"war_pig_impact") == 0 and is_equal_approx(game.pig.drops[0].age, 0.649), "Pause freezes R timing and cannot preplay the landing")
	game.set_paused(false)
	game.simulate(0.002)
	check(heard("local", &"war_pig_impact") == 1, "Resuming crosses the real impact boundary and plays once")
	game.simulate(2.0)
	check(heard("local", &"war_pig_impact") == 1 and game.pig.drops.is_empty(), "Pig effect expiry cannot replay its impact sound")
	_march_material(home, enemy)
	await game.prepare_shutdown()
	game.free()
	game = null

func _march_material(home: WarBuilding, enemy: WarBuilding) -> void:
	# Real march records exercise the shared foley grouping, including buffs
	# that can overlap the pig's flight without creating a hidden sound source.
	game.marches.clear()
	_clear_audio(game)
	sounds.clear()
	var origin := Vector3(0, 0, 0)
	game.marches.send(home.building_id, enemy.building_id, 0, 1, PackedVector3Array([origin, origin + Vector3(20, 0, 0)]))
	var unit: WarMarches.MarchUnit = game.marches._units[0]
	unit.distance = 0.0
	unit.spawn_delay = 0.0
	unit.position = origin
	unit.order.airborne = true
	game.audio.tick_marches(0.4, game.marches)
	check(heard("local", &"war_march") == 0, "A pig flying troop cannot emit grounded footsteps")
	unit.order.airborne = false
	unit.levitation_remaining = 2.0
	game.audio.tick_marches(0.4, game.marches)
	check(heard("local", &"war_march") == 0, "Frog levitation on pig troops also suppresses grounded footsteps")
	unit.levitation_remaining = 0.0
	unit.cloaked = true
	game.audio.tick_marches(0.4, game.marches)
	check(heard("local", &"war_march") == 0, "Concealed troops do not reveal their position through footsteps")
	unit.cloaked = false
	game.audio.tick_marches(0.4, game.marches)
	check(heard("local", &"war_march") == 1, "The same exposed ground march retains its ordinary footsteps")

func _grant_network_energy() -> void:
	_refill(host, 2)
	authority._publish_step(0.0)
	flush()

func _client_command(command: Dictionary) -> Array[Dictionary]:
	check(client.submit(command).accepted, "Real pig client accepts %s" % command.type)
	var duplicate: Dictionary = client_wire.sent[-1].duplicate(true)
	client_wire.sent.append(duplicate)
	deliver(client_wire, authority)
	authority.process(Coordinator.STEP)
	var facts: Array[Dictionary] = []
	for packet: Dictionary in host_wire.sent:
		if packet.kind == "events" and packet.payload.has("seq"):
			facts.append(packet.duplicate(true))
	deliver(host_wire, client)
	client.process(Coordinator.STEP)
	flush()
	return facts

func _replay(facts: Array[Dictionary]) -> void:
	# Re-submit actual encoded reliable transactions, not presentation callbacks.
	for packet: Dictionary in facts:
		client._on_message(105, "events", packet.payload)
		client._on_message(105, "events", packet.payload)
	client._apply_view()

func _network_events() -> void:
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	host.audio.muted = false
	replica.audio.muted = false
	host.audio.sound_played.connect(func(kind: StringName, at: Vector3, spatial: bool): _record("host", kind, at, spatial))
	replica.audio.sound_played.connect(func(kind: StringName, at: Vector3, spatial: bool): _record("client", kind, at, spatial))
	for building: WarBuilding in host.buildings:
		building.kind = 3
		building.population = 80.0
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	boundary()
	sounds.clear()
	for index: int in 3:
		_grant_network_energy()
		var facts := _client_command({"type": "skill_building", "skill": index, "target": 2})
		check(heard("host", CUES[index]) == 1 and heard("client", CUES[index]) == 1, "Pig %d host and remote peer each play one dedicated native cue" % index)
		check(not facts.is_empty(), "Pig %d emits a serializable transaction for replay coverage" % index)
		_replay(facts)
		check(heard("host", CUES[index]) == 1 and heard("client", CUES[index]) == 1, "Pig %d duplicated input and repeated event packets cannot replay audio" % index)
	var at: Vector3 = host.by_id[2].global_position
	_grant_network_energy()
	var release := _client_command({"type": "skill_ground", "skill": 3, "x": at.x, "z": at.z})
	check(heard("host", &"war_pig_drop") == 1 and heard("client", &"war_pig_drop") == 1 and heard("client", &"war_pig_impact") == 0, "Network R releases its warning once without premature impact")
	_replay(release)
	check(heard("client", &"war_pig_drop") == 1, "Replayed R release does not restart its sound")
	var before := pig_count("client")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(pig_count("client") == before and replica.pig.drops.size() == 1, "Reconnect during falling R restores its state without replaying warning or preparation audio")
	var impacts: Array[Dictionary] = []
	for frame: int in 25:
		authority.process(Coordinator.STEP)
		for packet: Dictionary in host_wire.sent:
			if packet.kind == "events" and packet.payload.has("seq"):
				impacts.append(packet.duplicate(true))
		deliver(host_wire, client)
		client.process(Coordinator.STEP)
		deliver(client_wire, authority)
	flush()
	check(heard("host", &"war_pig_impact") == 1 and heard("client", &"war_pig_impact") == 1, "Host damage boundary produces one landing cue on each peer after reconnect")
	_replay(impacts)
	check(heard("client", &"war_pig_impact") == 1, "Repeated impact transactions cannot replay landing audio")
	before = pig_count("client")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	check(pig_count("client") == before, "A post-impact full snapshot is silent about past skills and impact")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "Audio remains inside the existing validated match transport")
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free(); replica.free(); host_wire.free(); client_wire.free()
