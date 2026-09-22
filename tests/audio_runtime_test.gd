extends SceneTree
## Captures the real Master mix with the Dummy audio driver; never changes system volume.

var game: Node3D
var audio: Node
var capture := AudioEffectCapture.new()
var checks: int = 0
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var events: Dictionary = {}
var capture_slot: int
var settings_file: String

func _initialize() -> void:
	call_deferred("_run")

func _finalize() -> void:
	if not settings_file.is_empty() and FileAccess.file_exists(settings_file):
		DirAccess.remove_absolute(settings_file)

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func _heard(kind: StringName, _at: Vector3, _spatial: bool) -> void:
	events[kind] = int(events.get(kind, 0)) + 1

func _silence() -> void:
	for branch: Node in audio.get_children():
		for voice: Node in branch.get_children():
			voice.stop()
	await create_timer(0.15).timeout
	events.clear()
	audio._next_sound_ms.clear()
	capture.clear_buffer()

func _freeze(unit: Node) -> void:
	unit.set_physics_process(false)
	unit.get_node("AttackWindup").stop()
	unit.navigation_agent.avoidance_enabled = false

func _press_mute_key() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key = InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame

func _measure(label: String) -> Dictionary:
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var energy := 0.0
	var active := 0
	for sample: Vector2 in samples:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		if maxf(absf(sample.x), absf(sample.y)) > 0.000001:
			energy += sample.length_squared()
			active += 1
	var data := {"event": label, "peak_dbfs": linear_to_db(maxf(peak, 0.00000001)), "active_rms_dbfs": linear_to_db(maxf(sqrt(energy / maxf(2.0 * active, 1.0)), 0.00000001)), "active_frames": active}
	measurements.append(data)
	print("AUDIO_MEASURE ", JSON.stringify(data))
	return data

func _run() -> void:
	create_timer(140.0).timeout.connect(func(): push_error("AUDIO_RUNTIME watchdog"); quit(3))
	settings_file = OS.get_environment("TEMP").path_join("block-conquest-audio-runtime-%d.cfg" % OS.get_process_id())
	root.get_node("Session/Settings").settings_path = settings_file
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	game = current_scene
	game.tests_running = true
	game.bots.clear()
	game.camera_rig.edge_scroll = false
	audio = game.get_node("Audio")
	audio.sound_played.connect(_heard)
	await create_timer(0.25).timeout
	for unit: Node in get_nodes_in_group("units"):
		_freeze(unit)
		_check(unit.sound_requested.is_connected(game.play_world_sound), "initial unit audio connected through visible-world dispatch: " + unit.name)
	for building: Node in get_nodes_in_group("buildings"):
		building.set_physics_process(false)
		_check(building.sound_requested.is_connected(game.play_world_sound), "building audio connected through visible-world dispatch: " + building.name)
	game.get_node("IncomeTimer").stop()
	game.get_node("EnemyTimer").stop()
	game.camera_rig.focus_at(Vector3(-12, 0, 18), true)
	audio.set_volume_percent(85.0)
	if audio.muted:
		audio.toggle_mute()
	capture.buffer_length = 8.0
	capture_slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	_check(audio.get_node("UI").get_child_count() == 6 and audio.get_node("Combat").get_child_count() == 24 and audio.get_node("Foley").get_child_count() == 8, "native voice pools have fixed 6/24/8 limits")
	_check(not audio.has_node("Music") and not audio.has_node("Wind"), "scene has no BGM or looping ambience")
	_check(game.get_node("CameraRig/AudioListener3D").is_current(), "low listener replaces distant overhead camera for positional audio")
	_check(AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "Master uses native peak limiter")
	for kind: String in audio.BANK.EVENTS:
		var info: Dictionary = audio.BANK.EVENTS[kind]
		var max_duration := 0.0
		for stream: AudioStreamWAV in info.streams:
			_check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and stream.get_length() > 0.05, "finite imported sample: " + stream.resource_path.get_file())
			max_duration = maxf(max_duration, stream.get_length())
		await _silence()
		if info.bus == &"UI":
			audio.play_ui(kind)
		else:
			audio.play_world(kind, Vector3(-12, 0, 18))
		await create_timer(max_duration / 0.97 + 0.12).timeout
		var result := _measure(kind)
		_check(result.active_frames > 200 and result.active_rms_dbfs > -45.0, kind + " reaches audible Master mix")
		_check(result.peak_dbfs <= -0.9, kind + " stays below peak ceiling")
	_check(capture.get_discarded_frames() == 0, "sample capture never overflowed")
	await _silence()
	for repeat in range(100):
		audio.play_world(&"sword_hit", Vector3(-12, 0, 18))
	_check(events.get(&"sword_hit", 0) == 1, "100 same-frame impacts are limited to one audible event")
	await create_timer(0.2).timeout
	var count_before: int = events.get(&"sword_hit", 0)
	audio.play_world(&"sword_hit", Vector3(200, 0, 200))
	_check(events.get(&"sword_hit", 0) == count_before, "distant inaudible combat does not allocate voices")
	await _silence()
	for step in range(55):
		for kind: String in audio.BANK.EVENTS:
			if audio.BANK.EVENTS[kind].bus != &"UI":
				for soldier in range(160):
					audio.play_world(kind, Vector3(-12 + soldier % 8, 0, 18))
		await create_timer(0.04).timeout
		var active := 0
		for branch: Node in audio.get_children():
			for voice: Node in branch.get_children():
				active += int(voice.playing)
		if active > 38:
			failures.append("voice pool overflow")
	var battle_mix := _measure("160-unit event flood")
	_check(battle_mix.active_frames > 1000 and battle_mix.peak_dbfs <= -0.9, "dense combat mix remains audible and never clips")
	await _silence()
	var visible_effect_at: Vector3 = game.headquarters.global_position + Vector3(4, 0, 4)
	game.camera_rig.focus_at(visible_effect_at, true)
	game.spawn_effect(visible_effect_at, "muzzle")
	var effect: BattleEffect = game.get_node("EffectPool")._active.back()
	_check(not effect.has_node("Sound"), "particle effects no longer own transient audio players")
	game.get_node("EffectPool")._release(effect)
	await create_timer(0.15).timeout
	_check(audio.get_node("Combat").get_children().any(func(voice: Node): return voice.playing), "cannon sound tail survives freeing its visual effect")
	audio.play_world(&"cart_wheel", Vector3(-12, 0, 18))
	await create_timer(0.04).timeout
	game.toggle_pause()
	await create_timer(0.08).timeout
	_check(audio.get_node("Combat").get_children().all(func(voice: Node): return not voice.has_stream_playback() or voice.stream_paused), "pause freezes all active combat voices")
	_check(audio.get_node("Foley").get_children().all(func(voice: Node): return not voice.has_stream_playback() or voice.stream_paused), "pause freezes all active foley voices")
	var world_count: int = events.get(&"cannon_shot", 0)
	audio.play_world(&"cannon_shot", Vector3(-12, 0, 18))
	_check(events.get(&"cannon_shot", 0) == world_count, "paused world cannot start another sound")
	audio.play_ui(&"coin")
	_check(events.has(&"coin"), "UI audio remains available during pause")
	game.hud.get_node("PauseOverlay/Paper/SoundVolume").value = 40.0
	_check(absf(audio.volume_percent() - 40.0) < 0.1, "pause slider controls real Master gain")
	await _press_mute_key()
	_check(AudioServer.is_bus_mute(0) and game.hud.get_node("PauseOverlay/Paper/SoundMute").button_pressed, "M mute updates bus and UI consistently")
	await _press_mute_key()
	game.toggle_pause()
	_check(audio.get_node("Combat").get_children().all(func(voice: Node): return not voice.stream_paused), "resume releases world voices")
	audio.set_volume_percent(85.0)
	await _gameplay_events()
	await game.prepare_shutdown()
	AudioServer.remove_bus_effect(0, capture_slot)
	var file := FileAccess.open(OS.get_environment("TEMP").path_join("block-conquest-audio-runtime.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements, "audio_driver": AudioServer.get_driver_name()}, "  "))
	file.close()
	print("AUDIO_RUNTIME ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _gameplay_events() -> void:
	await _silence()
	game.select_entities([game.headquarters])
	game.gold = 0
	game.recruit("farmer")
	game.command_bus.tick()
	_check(game.headquarters.production.training.is_empty(), "unaffordable recruitment does not queue a unit")
	_check(events.has(&"denied"), "failed recruitment produces UI denial")
	game.gold = 1000
	game.recruit("farmer")
	game.command_bus.tick()
	_check(game.headquarters.production.training.size() == 1, "legal recruitment enters the production queue")
	_check(events.has(&"recruit"), "successful recruitment produces UI acknowledgment")
	var before_recruitment: int = game.unit_container.get_child_count()
	game.headquarters.production._physics_process(BalanceCatalog.unit("farmer").training_seconds)
	_check(game.unit_container.get_child_count() == before_recruitment + 1, "completing the queued training creates a new unit")
	var recruited: Node = game.unit_container.get_child(game.unit_container.get_child_count() - 1)
	_check(recruited.sound_requested.is_connected(game.play_world_sound), "dynamically recruited unit joins visible-world audio dispatch")
	_freeze(recruited)
	for kind: String in ["swordsman", "archer", "knight", "catapult", "cannon"]:
		await _silence()
		var fighter: Node3D = game.spawn_unit(kind, 0, Vector3(-12, 0, 18))
		var target_distance := maxf(2.1, BalanceCatalog.unit(kind).min_range + BalanceCatalog.unit(kind).radius + BalanceCatalog.unit("knight").radius + 0.5)
		var victim: Node3D = game.spawn_unit("knight", 1, fighter.global_position + Vector3.FORWARD * target_distance)
		_freeze(victim)
		victim.hp = 10000.0
		fighter.navigation_agent.avoidance_enabled = false
		game.get_node("FogOfWar").tick(FogOfWar.UPDATE_SECONDS)
		fighter.issue_attack(victim)
		await create_timer(1.65).timeout
		var release: StringName = {"swordsman": &"sword_swing", "knight": &"sword_swing", "archer": &"bow_release", "catapult": &"catapult_release", "cannon": &"cannon_shot"}[kind]
		var impact: StringName = {"swordsman": &"sword_hit", "knight": &"sword_hit", "archer": &"arrow_hit", "catapult": &"stone_hit", "cannon": &"explosion"}[kind]
		_check(events.has(release) and events.has(impact), kind + " real attack emits timed release and impact")
		_freeze(fighter)
		fighter.receive_damage(99999.0, victim)
		_check(events.has(&"death_fall"), kind + " real death emits fall sound")
		fighter.queue_free()
		victim.queue_free()
		await process_frame
	for kind: String in ["swordsman", "knight", "catapult"]:
		await _silence()
		var mover: Node3D = game.spawn_unit(kind, 0, Vector3(-11, 0, 25))
		mover.navigation_agent.avoidance_enabled = false
		mover.issue_move(Vector3(-5, 0, 25))
		await create_timer(2.0).timeout
		var sound: StringName = {"swordsman": &"footstep_dirt", "knight": &"horse_hoof", "catapult": &"cart_wheel"}[kind]
		_check(events.has(sound), kind + " actual travel emits distance-driven foley")
		mover.stop()
		await create_timer(0.2).timeout
		var stopped_count: int = events.get(sound, 0)
		await create_timer(0.45).timeout
		_check(events.get(sound, 0) == stopped_count, kind + " stationary unit emits no footsteps")
		_freeze(mover)
		mover.queue_free()
	await _silence()
	game.end_battle(true)
	_check(events.has(&"victory"), "victory emits finite non-musical UI feedback")
