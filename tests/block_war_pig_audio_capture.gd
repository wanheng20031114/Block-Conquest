extends "res://tests/block_war_loudness_capture.gd"
## Run with --real-time: native bus taps retain the actual 0.65 s pig landing.
const PIG_CUES: Array[StringName] = [
	&"war_pig_charge", &"war_pig_fly", &"war_pig_formation", &"war_pig_drop", &"war_pig_impact",
]
var game: Node3D
var drive_game := false
var actual_timeline: Array[Dictionary] = []
var actual_start_ms := 0
var last_simulation_us := 0
var capture_discard_start := Vector2i.ZERO

func _process(delta: float) -> bool:
	if drive_game:
		# The first frame delta also contains fixture setup before the cast.
		# Drive from the cast's own real clock so capture cannot pre-age R.
		var now := Time.get_ticks_usec()
		game.simulate((now - last_simulation_us) / 1000000.0)
		last_simulation_us = now
	return super._process(delta)

func _clear() -> void:
	await super._clear()
	capture_discard_start = Vector2i(pre.get_discarded_frames(), post.get_discarded_frames())

func _save(name: String, details: Dictionary) -> void:
	details["discarded_frames"] = [pre.get_discarded_frames() - capture_discard_start.x, post.get_discarded_frames() - capture_discard_start.y]
	super._save(name, details)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty() or AudioServer.get_driver_name() != "Dummy":
		push_error("Pig audio capture requires --audio-driver Dummy and -- --output=<directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(70.0, true, false, true).timeout.connect(func(): quit(3))
	var settings: GameSettings = root.get_node("Session/Settings")
	var original := settings.snapshot()
	settings._apply_values(settings.defaults(), false)
	change_scene_to_file("res://tests/block_war_audio_mix_test.tscn")
	await scene_changed
	audio = current_scene.get_node("Audio")
	music = audio.get_node("Music")
	audio.sound_played.connect(_heard)
	pre.buffer_length = 2.0
	post.buffer_length = 2.0
	AudioServer.add_bus_effect(0, pre, 0)
	AudioServer.add_bus_effect(0, post)
	await create_timer(0.12).timeout
	for kind: StringName in PIG_CUES:
		await _isolated(kind, 0)
	# A far-field sample checks that the pig identity is not lost at map edges.
	await _isolated(&"war_pig_charge", 0, Vector3(43, 0, 0), "_edge")
	for stress: bool in [false, true]:
		await _clear()
		seed(3090)
		AudioServer.set_bus_volume_db(0, 0.0 if stress else linear_to_db(0.5))
		music.stream = load("res://assets/audio/block_war/music/battle_bgm_01.mp3")
		music.play(45.0)
		var timeline: Array[Dictionary] = []
		for step: int in 80:
			if step % 2 == 0: _world(&"war_melee", step / 2)
			if step % 4 == 0: _world(&"war_march", step / 4)
			if step % 7 == 0: _world(&"cannon_shot", step / 7)
			if step % 7 == 3: _world(&"war_projectile_hit", step / 7)
			if step in [6, 22, 38, 54, 61]:
				var kind: StringName = PIG_CUES[[6, 22, 38, 54, 61].find(step)]
				_world(kind, 0)
				timeline.append({"seconds": step * 0.1, "kind": kind})
			if stress and step == 30:
				for faction: int in 6:
					audio.play_world(&"war_pig_impact", Vector3(faction * 3 - 8, 0, 0))
			await create_timer(0.1).timeout
		_save("pig_maximum_overlap" if stress else "pig_battle_default", {"type": "mix", "stress": stress, "timeline": timeline})
	await _clear()
	recording = false
	var references: Array[WeakRef] = audio.stop_all()
	await create_timer(0.2).timeout
	var fixture_released := references.all(func(ref: WeakRef): return ref.get_ref() == null)
	var preferences := settings.defaults()
	preferences.music_enabled = false
	settings._apply_values(preferences, false)
	AudioServer.set_bus_volume_db(0, linear_to_db(0.5))
	var session: Node = root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"pig"
	session.block_war_opponent_commander = &"squirrel"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.camera_rig.set_process(false)
	for building: WarBuilding in game.buildings:
		building.kind = 3
		building.population = 80.0
	audio = game.audio
	music = audio.get_node("Music")
	audio.sound_played.connect(_heard)
	await _clear()
	game.energy = 100.0
	actual_start_ms = Time.get_ticks_msec()
	var start_time: float = game.elapsed
	audio.sound_played.connect(func(kind: StringName, _at: Vector3, _spatial: bool):
		if kind in PIG_CUES:
			actual_timeline.append({"kind": kind, "wall_seconds": (Time.get_ticks_msec() - actual_start_ms) / 1000.0, "simulation_seconds": game.elapsed - start_time})
	)
	var cast: bool = game.cast_ground_skill(3, Vector3(8, 0, 0))
	last_simulation_us = Time.get_ticks_usec()
	drive_game = true
	await create_timer(3.0).timeout
	drive_game = false
	_save("pig_drop_actual_timing", {"type": "actual_gameplay", "cast_accepted": cast, "timeline": actual_timeline, "expected_impact_seconds": 0.65, "position": Vector3(8, 0, 0)})
	var capture_discarded := Vector2i.ZERO
	for entry: Dictionary in report:
		capture_discarded += Vector2i(entry.discarded_frames[0], entry.discarded_frames[1])
	var file := FileAccess.open(output.path_join("captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"mix_rate": AudioServer.get_mix_rate(), "captures": report,
		"tap": "pre/post Master limiter, before Master fader", "discarded_frames": [capture_discarded.x, capture_discarded.y],
		"idle_discarded_frames": [pre.get_discarded_frames() - capture_discarded.x, post.get_discarded_frames() - capture_discarded.y]}, "\t"))
	file.close()
	recording = false
	await game.prepare_shutdown()
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	AudioServer.remove_bus_effect(0, 0)
	settings._apply_values(original, false)
	var correct_timeline: bool = actual_timeline.size() == 2 and actual_timeline[0].kind == &"war_pig_drop" and actual_timeline[1].kind == &"war_pig_impact"
	if correct_timeline:
		correct_timeline = absf(float(actual_timeline[1].simulation_seconds) - 0.65) < 0.002
	print("PIG_AUDIO_CAPTURE recordings=%d fixture_playback_released=%s actual_timeline=%s" % [report.size(), fixture_released, actual_timeline])
	quit(0 if cast and fixture_released and correct_timeline and capture_discarded == Vector2i.ZERO else 1)

func _heard(kind: StringName, _at: Vector3, _spatial: bool) -> void:
	heard[kind] = heard.get(kind, 0) + 1
