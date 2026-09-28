extends SceneTree
## Silent native mix capture for the menu click; no windows or saved preferences.
var capture := AudioEffectCapture.new()
var checks := 0
var failures: Array[String] = []
var clicks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func peak(frames: PackedVector2Array) -> float:
	var value := 0.0
	for frame: Vector2 in frames:
		value = maxf(value, maxf(absf(frame.x), absf(frame.y)))
	return value

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy" or OS.get_cmdline_user_args().is_empty():
		printerr("Use --headless --audio-driver Dummy --script res://tests/ui_click_capture.gd -- <output>")
		quit(2)
		return
	create_timer(12.0, true, false, true).timeout.connect(func(): quit(3))
	var output := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var settings: GameSettings = root.get_node("Session/Settings")
	var original := settings.snapshot()
	settings._apply_values(settings.defaults(), false)
	var feedback: Node = root.get_node("Session/UIFeedback")
	var voice: AudioStreamPlayer = feedback.get_node("select")
	var sample: AudioStreamWAV = voice.stream.get_stream(0)
	check(sample.resource_path == "res://assets/audio/ui/soft_click.wav", "runtime points to the new click")
	check(sample.format == AudioStreamWAV.FORMAT_16_BITS and sample.mix_rate == 48000, "native importer preserves PCM16 at 48 kHz")
	check(is_equal_approx(sample.get_length(), 0.048) and sample.loop_mode == AudioStreamWAV.LOOP_DISABLED, "click stays short and never loops")
	check(voice.bus == &"UI" and is_equal_approx(voice.volume_db, -8.0), "click keeps the calibrated UI route and gain")
	check(voice.max_polyphony == 2, "rapid clicks retain bounded native polyphony")
	feedback.sound_played.connect(func(kind: StringName):
		if kind == &"select": clicks += 1)
	capture.buffer_length = 5.0
	var slot := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	await create_timer(0.15).timeout
	capture.clear_buffer()
	await create_timer(0.15).timeout
	for index: int in 3:
		feedback.play(&"select")
		await create_timer(0.6).timeout
	for index: int in 6:
		feedback.play(&"select")
		await create_timer(0.1).timeout
	await create_timer(0.2).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	check(clicks == 9, "three singles and six quick clicks all reach the event entry")
	check(peak(frames) > 0.005 and peak(frames) < 0.25, "native mix is audible with ample headroom")
	check(capture.get_discarded_frames() == 0, "native audition has no buffer overrun")
	check(not voice.playing, "short click has no lingering playback")
	var recording := FileAccess.open(output.path_join("clicks.f32"), FileAccess.WRITE)
	recording.store_buffer(frames.to_byte_array())
	recording.close()
	var report := {"mix_rate": AudioServer.get_mix_rate(), "master_db": AudioServer.get_bus_volume_db(0),
		"player_db": voice.volume_db, "frames": frames.size(), "clicks": clicks, "peak_before_master": peak(frames)}
	feedback.stop_all()
	clicks = 0
	for index: int in 200:
		feedback.play(&"select")
	check(clicks == 1, "same-frame request flood yields one click")
	await create_timer(0.15).timeout
	var ui := AudioServer.get_bus_index(&"UI")
	AudioServer.set_bus_mute(ui, true)
	capture.clear_buffer()
	feedback.play(&"select")
	await create_timer(0.15).timeout
	check(peak(capture.get_buffer(capture.get_frames_available())) < 0.00001, "UI bus mute suppresses the new click")
	AudioServer.set_bus_mute(ui, false)
	feedback.stop_all()
	AudioServer.remove_bus_effect(0, slot)
	settings._apply_values(original, false)
	report["checks"] = checks
	report["failures"] = failures
	var report_file := FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t") + "\n")
	report_file.close()
	print("UI_CLICK_CAPTURE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
