extends SceneTree
## Real sandbox shots, finite smoke tails and captured native mix at 50% volume.
const OUTPUT := "res://.local/musketeer-feedback-20260915/"
var game: Node3D
var checks: int = 0
var failures: Array[String] = []
var capture := AudioEffectCapture.new()
var slot: int
var heard: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func spawn(kind: String, owner: int, at: Vector3) -> BattleUnit:
	var unit: BattleUnit = game.spawn_unit(kind, owner, at)
	unit.stop()
	unit.set_physics_process(false)
	unit.navigation_agent.avoidance_enabled = false
	return unit

func measure(label: String, save_audio: bool = false) -> Dictionary:
	var samples: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	var peak: float = 0
	var energy: float = 0
	var active: int = 0
	var pcm := PackedByteArray()
	if save_audio: pcm.resize(samples.size() * 4)
	for index: int in samples.size():
		var sample: Vector2 = samples[index]
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		if sample.length_squared() > .0000000001:
			energy += sample.length_squared()
			active += 1
		if save_audio:
			pcm.encode_s16(index * 4, int(clampf(sample.x, -1, 1) * 32767))
			pcm.encode_s16(index * 4 + 2, int(clampf(sample.y, -1, 1) * 32767))
	if save_audio:
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.stereo = true
		wav.mix_rate = int(AudioServer.get_mix_rate())
		wav.data = pcm
		check(wav.save_to_wav(OUTPUT + label + ".wav") == OK, "native mix written: " + label)
	return {"peak_dbfs": linear_to_db(maxf(peak, .00000001)), "rms_dbfs": linear_to_db(maxf(sqrt(energy / maxf(2.0 * active, 1.0)), .00000001)), "active_frames": active}

func _run() -> void:
	create_timer(55, true, false, true).timeout.connect(func(): quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	root.gui_disable_input = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	game.hud.hide()
	game.camera_rig.set_process(false)
	game.camera_rig.camera.position = Vector3(5, 10, 13)
	game.camera_rig.camera.look_at(Vector3(0, .6, -.7), Vector3.UP)
	game.camera_rig.camera.size = 15
	var audio: Node = game.get_node("Audio")
	audio.sound_played.connect(func(kind: StringName, _at: Vector3, _spatial: bool): heard[kind] = int(heard.get(kind, 0)) + 1)
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, linear_to_db(.5))
	capture.buffer_length = 8
	slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	var shooter := spawn("musketeer", 0, Vector3(-2, 0, 2))
	var target := spawn("shield_guard", 1, Vector3(1, 0, -3))
	var neighbor := spawn("swordsman", 1, Vector3(3, 0, -3))
	game.select_entities([shooter])
	game.set_running(true)
	await create_timer(.4).timeout
	capture.clear_buffer()
	shooter.issue_attack(target)
	shooter.set_physics_process(true)
	var atlas := Image.create(5120, 1080, false, Image.FORMAT_RGB8)
	var captured_hit := false
	var frames: Array[Dictionary] = []
	for index: int in 24:
		await create_timer(.035).timeout
		await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		frame.convert(Image.FORMAT_RGB8)
		frame.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
		frames.append({"time": game.elapsed, "hp": target.hp, "effects": game.get_node("EffectPool").active_count()})
		# 24 half-size frames keep the motion record compact and reproducible.
		if not captured_hit and target.hp < 145 and index > 0 and frames[index-1].hp < 145:
			check(frame.save_png(OUTPUT + "hit.png") == OK, "real hit frame captured")
			captured_hit = true
		if index == 7: frame.save_png(OUTPUT + "aim.png")
		frame.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(frame, Rect2i(0, 0, 640, 360), Vector2i(index % 8, index / 8) * Vector2i(640, 360))
	check(atlas.save_png(OUTPUT + "shot-atlas.png") == OK, "shot sequence captured")
	shooter.stop()
	shooter.set_physics_process(false)
	check(captured_hit and target.hp == 127 and neighbor.hp == 110, "actual single-target eighteen damage with untouched neighbor")
	check(heard.get(&"musket_shot", 0) == 1, "one attack dispatches one dedicated gunshot")
	await create_timer(.35).timeout
	var single := measure("shot", true)
	check(single.active_frames > 200 and single.peak_dbfs > -28 and single.peak_dbfs < -.9, "musket is audible at default 50 percent without clipping")
	var pool: BattleProjectilePool = game.get_node("ProjectilePool")
	check(pool.active_count() == 0 and pool.visual_count() == 0, "real smoke afterimage finishes and returns its scene")
	# Cosmetic network flights share the smoke path and cannot deal damage.
	var visual := pool.launch_visual(Vector3(-2, 1.2, 2), Vector3(1, 1, -3), "bullet", .1, 0, target)
	pool._physics_process(.1)
	check(visual.visual.get_node("MusketSmoke").visible and target.hp == 127, "replica smoke follows flight without a second hit")
	pool.reset_all()
	check(pool.visual_count() == 0 and pool.get_children().all(func(node: BattleProjectile): return not node.get_node("MusketSmoke").visible), "reset clears even an unfinished replica afterimage")
	# Dense calls use the real fixed voice pool and native limiter, not a synthetic mix.
	capture.clear_buffer()
	heard.clear()
	for burst: int in 6:
		for index: int in 250: audio.play_world(&"musket_shot", shooter.global_position)
		await create_timer(.12).timeout
	var gun_voices: int = audio.get_node("Combat").get_children().filter(func(voice: AudioStreamPlayer3D): return voice.playing and voice.get_meta("kind", &"") == &"musket_shot").size()
	check(gun_voices <= 3 and heard.get(&"musket_shot", 0) <= 6, "1500 requests retain bounded voices and dispatch rate")
	await create_timer(.8).timeout
	var volley := measure("volley", true)
	check(volley.active_frames > 200 and volley.peak_dbfs < -.9, "dense gunshots remain audible without clipping")
	check(capture.get_discarded_frames() == 0, "mix capture did not overflow")
	AudioServer.remove_bus_effect(0, slot)
	FileAccess.open(OUTPUT + "feedback-results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "single": single, "volley": volley, "frames": frames, "volume_percent": 50, "listening": "Native mixer capture and technical measurements; no claim of perceptual listening."}, "\t"))
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	print("MUSKETEER_FEEDBACK ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
