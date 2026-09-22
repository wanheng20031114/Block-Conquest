extends SceneTree
## Headless native mixer coverage; temporary preferences never touch the user's file.
const WAR_BANK = preload("res://scripts/block_war/war_sound_bank.gd")
var audio: Node
var capture := AudioEffectCapture.new()
var capture_slot: int
var checks := 0
var failures: Array[String] = []
var heard: Dictionary = {}
var temporary_settings: String

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func _on_sound(kind: StringName, _at: Vector3, _spatial: bool) -> void:
	heard[kind] = int(heard.get(kind, 0)) + 1

func _clear() -> void:
	for branch: Node in audio.get_children():
		for voice: Node in branch.get_children():
			voice.stop()
	await create_timer(0.12).timeout
	heard.clear()
	audio._next_sound_ms.clear()
	capture.clear_buffer()

func _measure() -> Vector2:
	var peak := 0.0
	var energy := 0.0
	var active := 0
	for frame: Vector2 in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		if frame.length_squared() > 0.0000000001:
			energy += frame.length_squared()
			active += 1
	return Vector2(peak, sqrt(energy / maxf(active * 2.0, 1.0)))

func _run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("BLOCK_WAR_AUDIO_MIX deadline"); quit(3))
	temporary_settings = OS.get_environment("TEMP").path_join("block-war-audio-mix-%d.cfg" % OS.get_process_id())
	root.get_node("Session/Settings").settings_path = temporary_settings
	change_scene_to_file("res://tests/block_war_audio_mix_test.tscn")
	await scene_changed
	audio = current_scene.get_node("Audio")
	audio.sound_played.connect(_on_sound)
	audio.set_volume_percent(75.0)
	if audio.muted:
		audio.toggle_mute()
	capture.buffer_length = 4.0
	capture_slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	_check(audio.get_node("UI").get_child_count() == 6 and audio.get_node("Combat").get_child_count() == 24 and audio.get_node("Foley").get_child_count() == 8, "campaign reuses 38 native pooled voices")
	_check(audio.get_node("Combat/Voice00").max_distance == 96.0 and audio.get_node("Foley/Voice00").max_distance == 72.0, "campaign spatial attenuation matches its battlefield scale")
	var sample_count := 0
	for kind: String in WAR_BANK.EVENTS:
		var info: Dictionary = WAR_BANK.EVENTS[kind]
		var duration := 0.0
		var finite := true
		for stream: AudioStreamWAV in info.streams:
			sample_count += 1
			finite = finite and stream.get_length() >= 0.08 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and stream.data.size() > 1000
			duration = maxf(duration, stream.get_length())
		_check(finite, kind + " has finite imported PCM samples")
		await _clear()
		if info.bus == &"UI":
			audio.play_ui(kind)
		else:
			audio.play_world(kind, Vector3(8, 0, 0))
		await create_timer(duration / 0.97 + 0.09).timeout
		var level := _measure()
		_check(level.y > 0.005 and level.x <= db_to_linear(-0.9), "%s reaches the real Master mix (RMS %.1f dBFS, peak %.1f dBFS)" % [kind, linear_to_db(level.y), linear_to_db(level.x)])
	_check(sample_count == 36, "all 36 campaign variants loaded")
	await _clear()
	for request in range(500):
		audio.play_world(&"war_melee", Vector3.ZERO)
	_check(heard.get(&"war_melee", 0) == 1, "500 simultaneous contacts produce one bounded impact")
	await _clear()
	audio.play_world(&"war_march", Vector3(180, 0, 0))
	_check(heard.is_empty(), "out-of-range march consumes no voice or cooldown")
	audio.play_world(&"war_march", Vector3(43, 0, 0))
	await create_timer(0.6).timeout
	_check(heard.get(&"war_march", 0) == 1 and _measure().y > 0.003, "visible edge formation at 43m is audible")
	await _clear()
	var marches: WarMarches = current_scene.get_node("Marches")
	marches.send(0, 1, 0, 300, PackedVector3Array([Vector3(-15, 0, 0), Vector3(15, 0, 0)]))
	marches.send(2, 3, 1, 300, PackedVector3Array([Vector3(15, 0, 4), Vector3(-15, 0, 4)]))
	marches.tick(0.1)
	audio.tick_marches(0.10, marches)
	_check(heard.is_empty(), "march audio skips per-frame soldier polling")
	audio.tick_marches(0.25, marches)
	_check(heard.get(&"war_march", 0) == 1, "600 soldiers request one sampled group")
	await create_timer(0.25).timeout
	audio.tick_marches(0.34, marches)
	_check(heard.get(&"war_march", 0) == 2, "next sample alternates the nearby visible formations")
	await _clear()
	var camera: Camera3D = current_scene.get_node("CameraRig/Camera3D")
	camera.position.x = 200.0
	await process_frame
	audio.tick_marches(0.34, marches)
	_check(heard.is_empty(), "formations outside the camera frustum stay silent")
	camera.position.x = 0.0
	# Same-frame pending 3D play and pause must be silent; UI continues normally.
	audio.play_world(&"war_melee", Vector3.ZERO)
	audio.set_world_paused(true)
	paused = true
	await create_timer(0.13).timeout
	capture.clear_buffer()
	await create_timer(0.15).timeout
	_check(_measure().x < 0.00001, "pause holds pending world sounds before the physics tick")
	audio.play_ui(&"war_pause")
	await create_timer(0.30).timeout
	_check(_measure().y > 0.005, "pause acknowledgement remains audible")
	var before: int = heard.get(&"war_march", 0)
	audio.tick_marches(0.34, marches)
	_check(heard.get(&"war_march", 0) == before, "paused marching emits no steps")
	paused = false
	audio.set_world_paused(false)
	await _clear()
	audio.toggle_mute()
	audio.play_ui(&"war_capture")
	await create_timer(0.96).timeout
	# Capture is a pre-fader bus effect; final output muting happens after it.
	_check(AudioServer.is_bus_mute(0) and audio.muted and audio.settings.muted, "campaign mute updates the shared settings and native Master output")
	audio.toggle_mute()
	# The two virtual lookups leave the original mode's soundbank usable.
	await _clear()
	audio.play_ui(&"select")
	await create_timer(0.4).timeout
	_check(_measure().y > 0.003, "original shared UI event still plays through the inherited director")
	var references: Array[WeakRef] = audio.stop_all()
	await process_frame
	await process_frame
	await create_timer(0.12).timeout
	_check(references.all(func(reference: WeakRef): return reference.get_ref() == null), "shutdown releases every native playback")
	AudioServer.remove_bus_effect(0, capture_slot)
	if FileAccess.file_exists(temporary_settings):
		DirAccess.remove_absolute(temporary_settings)
	print("BLOCK_WAR_AUDIO_MIX ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
