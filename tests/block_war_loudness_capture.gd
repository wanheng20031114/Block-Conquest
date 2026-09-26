extends SceneTree
## Silent, deterministic native mixer captures. Run with --audio-driver Dummy.
## PCM is taken before the Master fader; the report records that fader separately.
const BANK = preload("res://scripts/block_war/war_sound_bank.gd")
var audio: Node
var music: AudioStreamPlayer
var pre := AudioEffectCapture.new()
var post := AudioEffectCapture.new()
var pre_frames := PackedVector2Array()
var post_frames := PackedVector2Array()
var recording := false
var output: String
var report: Array[Dictionary] = []
var heard: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if recording:
		_drain()
	return false

func _drain() -> void:
	pre_frames.append_array(pre.get_buffer(pre.get_frames_available()))
	post_frames.append_array(post.get_buffer(post.get_frames_available()))

func _clear() -> void:
	recording = false
	for branch: String in ["UI", "Combat", "Foley"]:
		for voice: Node in audio.get_node(branch).get_children():
			voice.stop()
	for voice: AudioStreamPlayer in root.get_node("Session/UIFeedback").get_children():
		voice.stop()
	music.stop()
	await create_timer(0.20).timeout
	audio._next_sound_ms.clear()
	heard.clear()
	pre.clear_buffer()
	post.clear_buffer()
	pre_frames.clear()
	post_frames.clear()
	recording = true

func _save(name: String, details: Dictionary) -> void:
	_drain()
	recording = false
	for tap: String in ["pre", "post"]:
		var frames: PackedVector2Array = pre_frames if tap == "pre" else post_frames
		var file := FileAccess.open(output.path_join(name + "_" + tap + ".f32"), FileAccess.WRITE)
		file.store_buffer(frames.to_byte_array())
	details.merge({"name": name, "master_db": AudioServer.get_bus_volume_db(0),
		"music_bus_db": AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"BGM")),
		"events_played": heard.duplicate(), "frames": post_frames.size()})
	report.append(details)
	print("CAPTURE ", name, " frames=", post_frames.size())

func _isolated(kind: StringName, index: int, at := Vector3(8, 0, 0), suffix := "") -> void:
	await _clear()
	var info: Dictionary = audio._event_info(kind)
	var voice: Node = audio._pools[info.bus][0]
	voice.stream = info.streams[index]
	voice.volume_db = info.gain_db
	voice.pitch_scale = 1.0
	voice.set_meta("kind", kind)
	voice.set_meta("priority", info.priority)
	voice.set_meta("started", Time.get_ticks_msec())
	if info.bus != &"UI":
		voice.global_position = at
	voice.play()
	await create_timer(voice.stream.get_length() + 0.16).timeout
	_save("%s_%02d%s" % [kind, index + 1, suffix], {"type": "isolated", "kind": kind,
		"variant": index, "gain_db": info.gain_db, "bus": info.bus, "position": at,
		"sample": voice.stream.resource_path})

func _world(kind: StringName, n: int) -> void:
	var positions := [Vector3(8, 0, 0), Vector3(-18, 0, -8), Vector3(29, 0, 12), Vector3(-36, 0, 8)]
	audio.play_world(kind, positions[n % positions.size()])

func _scene_mix(name: String, track: int, music_at: float, stress := false) -> void:
	await _clear()
	seed(1208)
	music.stream = load("res://assets/audio/block_war/music/battle_bgm_%02d.mp3" % track)
	music.play(music_at)
	var timeline: Array[Dictionary] = []
	var skills := [&"war_skill_command", &"war_skill_drum", &"war_skill_shield", &"war_skill_breach",
		&"war_rabbit_dash", &"war_rabbit_seal", &"war_rabbit_recall", &"war_rabbit_burrow"]
	for step in range(100):
		if step % 2 == 0:
			_world(&"war_melee", step / 2)
		if step % 4 == 0:
			_world(&"war_march", step / 4)
		if step % 5 == 0:
			_world(&"cannon_shot", step / 5)
		if step % 5 == 2:
			_world(&"war_projectile_hit", step / 5)
		if step % 12 == 3:
			_world(&"war_reinforce", step / 12)
		if step in [10, 52]:
			_world(&"war_rebuild" if step == 10 else &"war_upgrade", 0)
		if step >= 15 and step <= 85 and (step - 15) % 10 == 0:
			var skill: StringName = skills[(step - 15) / 10]
			_world(skill, 0)
			timeline.append({"seconds": step * 0.1, "kind": skill})
		if step % 17 == 0:
			audio.play_ui(&"war_order")
		if step in [24, 68]:
			audio.play_ui(&"war_capture" if step == 24 else &"war_lost")
		if stress and step in [30, 60]:
			# Legal overlapping event types plus a flood of identical contacts.
			for skill: StringName in skills:
				audio.play_world(skill, Vector3.ZERO)
			for request in range(500):
				audio.play_world(&"war_melee", Vector3.ZERO)
		await create_timer(0.1).timeout
	audio.play_ui(&"war_victory")
	await create_timer(2.8).timeout
	_save(name, {"type": "mix", "track": track, "music_start": music_at,
		"stress": stress, "timeline": timeline, "music_player_db": music.volume_db})

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if output.is_empty() or AudioServer.get_driver_name() != "Dummy":
		push_error("Use --audio-driver Dummy and -- --output=<temporary directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(160.0).timeout.connect(func(): push_error("LOUDNESS_CAPTURE deadline"); quit(3))
	var settings: GameSettings = root.get_node("Session/Settings")
	settings.settings_path = output.path_join("settings.cfg")
	settings._apply_values(settings.defaults(), false)
	change_scene_to_file("res://tests/block_war_audio_mix_test.tscn")
	await scene_changed
	audio = current_scene.get_node("Audio")
	music = audio.get_node("Music")
	audio.sound_played.connect(func(kind: StringName, _at: Vector3, _spatial: bool): heard[kind] = heard.get(kind, 0) + 1)
	pre.buffer_length = 2.0
	post.buffer_length = 2.0
	AudioServer.add_bus_effect(0, pre, 0)
	AudioServer.add_bus_effect(0, post)
	await create_timer(0.12).timeout
	if OS.get_cmdline_user_args().has("--scenes-only"):
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("captures.json")))
		for entry: Dictionary in previous.captures:
			if entry.type not in ["mix", "music"]:
				report.append(entry)
	else:
		for kind: String in BANK.EVENTS:
			for index in BANK.EVENTS[kind].streams.size():
				await _isolated(kind, index)
		for index in 2:
			await _isolated(&"cannon_shot", index)
		for kind: String in ["select", "order", "cancel", "ratio"]:
			await _clear()
			var voice: AudioStreamPlayer = root.get_node("Session/UIFeedback").get_node(kind)
			voice.play()
			await create_timer(0.7).timeout
			_save("menu_" + kind, {"type": "menu", "kind": kind, "gain_db": voice.volume_db})
		for kind: StringName in [&"war_march", &"war_skill_breach"]:
			await _isolated(kind, 0, Vector3(43, 0, 0), "_edge")
	# Both music choices, quiet baseline and deliberately busy combat.
	for track in [1, 2]:
		await _clear()
		music.stream = load("res://assets/audio/block_war/music/battle_bgm_%02d.mp3" % track)
		music.play(45.0)
		await create_timer(4.0).timeout
		_save("music_%02d" % track, {"type": "music", "track": track, "music_player_db": music.volume_db})
		await _scene_mix("battle_%02d" % track, track, 45.0)
	AudioServer.set_bus_volume_db(0, 0.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"BGM"), 0.0)
	await _scene_mix("maximum_stress", 2, 45.0, true)
	var file := FileAccess.open(output.path_join("captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"mix_rate": AudioServer.get_mix_rate(), "captures": report,
		"tap": "pre/post native Master limiter, both before Master volume", "discarded_frames": [pre.get_discarded_frames(), post.get_discarded_frames()]}, "\t"))
	recording = false
	var references: Array[WeakRef] = audio.stop_all()
	await create_timer(0.2).timeout
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	AudioServer.remove_bus_effect(0, 0)
	print("LOUDNESS_CAPTURE ", report.size(), " recordings; playback released=", references.all(func(ref: WeakRef): return ref.get_ref() == null))
	quit()
