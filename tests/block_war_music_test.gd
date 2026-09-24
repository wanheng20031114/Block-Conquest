extends SceneTree
## Exercise the shipped scene, native MP3 looping, mixer routing and scene teardown.
var checks := 0
var failures: Array[String] = []
var capture := AudioEffectCapture.new()

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func _rms() -> float:
	var frames := capture.get_buffer(capture.get_frames_available())
	var energy := 0.0
	for frame: Vector2 in frames:
		energy += frame.length_squared()
	return sqrt(energy / maxf(frames.size() * 2.0, 1.0))

func _sample() -> float:
	# Drain the native mixer's previous gain ramp and any short UI acknowledgments.
	await create_timer(0.5).timeout
	capture.clear_buffer()
	await create_timer(0.25).timeout
	return _rms()

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("BLOCK_WAR_MUSIC deadline"); quit(3))
	var settings: GameSettings = root.get_node("Session/Settings")
	var temporary_path := OS.get_environment("TEMP").path_join("block-war-music-%d.cfg" % OS.get_process_id())
	settings.settings_path = temporary_path
	settings._apply_values(settings.defaults(), false)
	root.get_node("Session").block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	var game: Node3D = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	var audio: Node = game.audio
	var music: AudioStreamPlayer = audio.get_node("Music")
	var bgm_bus := AudioServer.get_bus_index(&"BGM")
	_check(music.autoplay and music.playing, "battle scene starts its authored native music player")
	_check(music.stream.resource_path == "res://assets/audio/block_war/music/battle_bgm_01.mp3", "battle uses the approved official BGM1 asset")
	_check(music.stream is AudioStreamMP3 and music.stream.loop and music.stream.loop_offset == 0.0, "looping belongs to the imported MP3 resource")
	_check(music.bus == &"BGM" and AudioServer.get_bus_send(bgm_bus) == &"Master", "music has its own bus directly into Master")
	_check(AudioServer.get_bus_effect_count(bgm_bus) == 0, "music does not inherit combat compression")
	print("BGM1_DURATION_SECONDS ", music.stream.get_length())
	capture.buffer_length = 2.0
	var capture_slot := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	music.seek(12.0)
	_check(await _sample() > 0.001, "approved music produces real PCM in the native Master mix")
	music.seek(music.stream.get_length() - 0.15)
	# AudioStreamPlayer.seek starts a new native playback instance.
	var playback: AudioStreamPlayback = music.get_stream_playback()
	var previous_loops := playback.get_loop_count()
	await create_timer(0.6).timeout
	_check(music.playing and playback.get_loop_count() > previous_loops and music.get_playback_position() < 2.0, "native playback crosses the end and loops without script replay")
	game.set_paused(true)
	paused = true
	var before_pause := music.get_playback_position()
	_check(await _sample() > 0.001 and music.get_playback_position() > before_pause and not music.stream_paused, "background music continues through local menu and SceneTree pause")
	paused = false
	game.set_paused(false)
	settings.open_menu()
	settings.menu.show_page("Audio")
	settings.menu.get_node("%MusicEnabled").button_pressed = false
	settings.menu._apply(false)
	_check(await _sample() < 0.00001 and AudioServer.is_bus_mute(bgm_bus), "applying the music switch silences music in the actual output mix")
	capture.clear_buffer()
	audio.play_ui(&"war_capture")
	await create_timer(0.3).timeout
	_check(_rms() > 0.001 and not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"UI")), "disabling music leaves native UI effects audible")
	# Let the full random-pitch acknowledgment finish before measuring music silence.
	while audio.get_node("UI").get_children().any(func(voice: AudioStreamPlayer): return voice.playing):
		await process_frame
	settings.menu.get_node("%MusicEnabled").button_pressed = true
	settings.menu.get_node("%MusicVolume").value = 0.0
	settings.menu._apply(false)
	_check(await _sample() < 0.00001, "zero music volume is silent with the toggle enabled")
	var position_before_enable := music.get_playback_position()
	settings.menu.get_node("%MusicVolume").value = 50.0
	settings.menu._apply(false)
	_check(await _sample() > 0.001 and music.get_playback_position() > position_before_enable, "restoring volume resumes the continuing music without restarting the intro")
	var music_gain := AudioServer.get_bus_volume_db(bgm_bus)
	settings.set_volume_percent(23.0)
	settings.set_muted(true)
	_check(AudioServer.is_bus_mute(0) and not AudioServer.is_bus_mute(bgm_bus) and is_equal_approx(AudioServer.get_bus_volume_db(bgm_bus), music_gain), "Master mute and gain remain independent from saved music settings")
	settings.set_muted(false)
	settings.close_menu()
	var old_player: WeakRef = weakref(music)
	var old_playback: WeakRef = weakref(playback)
	playback = null
	await game.exit_to_lobby()
	await scene_changed
	await root.get_node("Session/Transition").completed
	_check(old_player.get_ref() == null and old_playback.get_ref() == null, "returning to lobby releases the music player and native playback")
	_check(not current_scene.has_node("Audio/Music") and await _sample() < 0.00001, "lobby has no leftover battle music")
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	music = game.audio.get_node("Music")
	_check(music.playing and music.get_playback_position() < 1.0 and game.audio.get_child_count() == 4, "reentering battle starts exactly one new music player")
	await game.prepare_shutdown()
	AudioServer.remove_bus_effect(0, capture_slot)
	DirAccess.remove_absolute(temporary_path)
	print("BLOCK_WAR_MUSIC ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
