extends "res://tests/block_war_loudness_capture.gd"
## Scope the existing silent native capture harness to the eight new releases.
const NEW_CUES: Array[StringName] = [
	&"war_bear_toolbox", &"war_bear_stomp", &"war_bear_link", &"war_bear_ward",
	&"war_frog_mist", &"war_frog_float", &"war_frog_cloak", &"war_frog_strike",
]

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if output.is_empty() or AudioServer.get_driver_name() != "Dummy":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(50.0, true, false, true).timeout.connect(func(): quit(3))
	var settings: GameSettings = root.get_node("Session/Settings")
	var original := settings.snapshot()
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
	for kind: StringName in NEW_CUES:
		await _isolated(kind, 0)
	# Existing approved cues are the level references, through the same mix.
	for kind: StringName in [&"war_skill_command", &"war_skill_shield", &"war_rabbit_seal", &"war_projectile_hit"]:
		await _isolated(kind, 0)
	await _isolated(&"war_frog_cloak", 0, Vector3(43, 0, 0), "_edge")
	for stress: bool in [false, true]:
		await _clear()
		seed(1809)
		AudioServer.set_bus_volume_db(0, 0.0 if stress else linear_to_db(0.5))
		music.stream = load("res://assets/audio/block_war/music/battle_bgm_01.mp3")
		music.play(45.0)
		for step: int in 80:
			if step % 2 == 0:
				_world(&"war_melee", step / 2)
			if step % 4 == 0:
				_world(&"war_march", step / 4)
			if step % 7 == 0:
				_world(&"cannon_shot", step / 7)
			if step % 7 == 3:
				_world(&"war_projectile_hit", step / 7)
			if step < 72 and step % 9 == 4:
				_world(NEW_CUES[step / 9], 0)
			if stress and step == 30:
				for faction: int in 6:
					audio.play_world(&"war_bear_ward", Vector3(faction * 3 - 8, 0, 0))
			await create_timer(0.1).timeout
		_save("maximum_overlap" if stress else "battle_default", {"type": "mix", "stress": stress})
	var file := FileAccess.open(output.path_join("captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"mix_rate": AudioServer.get_mix_rate(), "captures": report,
		"tap": "pre/post Master limiter, before Master fader", "discarded_frames": [pre.get_discarded_frames(), post.get_discarded_frames()]}, "\t"))
	file.close()
	recording = false
	var references: Array[WeakRef] = audio.stop_all()
	await create_timer(0.2).timeout
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	AudioServer.remove_bus_effect(0, 0)
	settings._apply_values(original, false)
	var released := references.all(func(ref: WeakRef): return ref.get_ref() == null)
	print("COMMANDER_AUDIO_CAPTURE recordings=", report.size(), " playback_released=", released)
	quit(0 if released else 1)
