extends "res://tests/block_war_rabbit_integration_test.gd"
## Real input and gameplay events must request the right audible material.
var sounds: Array[Dictionary] = []
var menu_sounds: Array[StringName] = []

func heard(kind: StringName) -> int:
	return sounds.filter(func(item: Dictionary): return item.kind == kind).size()

func clear_sounds() -> void:
	for branch: String in ["UI", "Combat", "Foley"]:
		for voice: Node in game.audio.get_node(branch).get_children():
			voice.stop()
	game.audio._next_sound_ms.clear()
	sounds.clear()

func _record(kind: StringName, at: Vector3, spatial: bool) -> void:
	sounds.append({"kind": kind, "position": at, "spatial": spatial})

func _run() -> void:
	create_timer(70.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	var settings: Node = root.get_node("Session/Settings")
	var settings_path := OS.get_environment("TEMP").path_join("block-war-audio-feedback-%d.cfg" % OS.get_process_id())
	settings.settings_path = settings_path
	var preferences: Dictionary = settings.snapshot()
	preferences.music_enabled = false
	settings.apply_preferences(preferences)
	await reset()
	game.audio.sound_played.connect(_record)
	clear_sounds()
	key(KEY_Q, true)
	check(heard(&"war_drag") == 1, "skill pickup gives immediate soft drag feedback")
	var drop: Vector2 = game.camera.unproject_position(Vector3(-22, 0, 10))
	motion(drop)
	key(KEY_Q, false)
	check(heard(&"war_rabbit_dash") == 1 and heard(&"war_skill_drum") == 0, "rabbit Q release uses its own wind sound")
	refill()
	clear_sounds()
	key(KEY_W, true)
	motion(screen(enemy()))
	key(KEY_W, false)
	check(heard(&"war_rabbit_seal") == 1 and heard(&"war_rebuild") == 0, "rabbit W uses paper seal material on release")
	refill()
	clear_sounds()
	var route: PackedVector3Array = game.map.get_building_route(home(), game.buildings[2])
	game.marches.send(home().building_id, game.buildings[2].building_id, 0, 12, route)
	game.marches.tick(.3)
	check(game.cast_skill(2, home()), "recall has eligible troops")
	check(heard(&"war_rabbit_recall") == 1 and heard(&"war_skill_command") == 0, "rabbit E requests its whistle in the cast frame")
	refill()
	clear_sounds()
	var plan := tunnel_plan()
	check(not plan.is_empty(), "tunnel has a legal source and exit")
	game.audio.play_world(&"war_march", plan.exit)
	check(game.cast_skill(3, plan.target), "rabbit tunnel casts while footsteps are playing")
	check(heard(&"war_rabbit_burrow") == 1, "footstep rate limiting cannot swallow tunnel audio")
	var tunnel: Dictionary = sounds.filter(func(item: Dictionary): return item.kind == &"war_rabbit_burrow")[0]
	check(tunnel.position.distance_to(plan.exit) < .001 and tunnel.spatial, "tunnel sound is at the visible exit rather than the target building")
	refill()
	clear_sounds()
	key(KEY_Q, true)
	mouse(drop, true, MOUSE_BUTTON_RIGHT)
	check(heard(&"war_cancel") == 1 and game.armed_skill == -1, "right-click skill cancellation has one cancel cue")
	clear_sounds()
	key(KEY_Q, true)
	motion(icon(0))
	key(KEY_Q, false)
	check(heard(&"war_cancel") == 1 and heard(&"war_rabbit_dash") == 0, "invalid drop cancels audibly without a cast sound")
	near(game.energy, 100.0, "cancellation spends no energy")
	clear_sounds()
	game.set_paused(true)
	check(heard(&"war_pause") == 1, "pause has one opening cue")
	game.hud._open_help()
	check(heard(&"war_select") == 1 and heard(&"war_pause") == 1, "help inside pause emits feedback without a second pause cue")
	game.hud._close_help()
	check(heard(&"war_cancel") == 1, "return from help to pause is audible")
	game.set_paused(false)
	check(heard(&"war_resume") == 1, "resume emits its closing cue")
	clear_sounds()
	game.faction_skills[0].commander = RULES.COMMANDER_ID
	refill()
	check(game.cast_skill(2, home()) and heard(&"war_skill_shield") == 1, "shield sound starts with the sphere")
	refill()
	check(game.cast_ground_skill(3, Vector3(-22, 0, 10)) and heard(&"war_skill_breach") == 1, "fire sound starts in the ignition frame")
	clear_sounds()
	game.marches.clear()
	var tower: WarBuilding = game.buildings[2]
	tower.kind = 1
	tower.faction = 1
	tower.level = 1
	tower.refresh_visual()
	var origin := tower.global_position + Vector3(3, 0, 0)
	expose(0, 1, origin, origin + Vector3(20, 0, 0), home().building_id)
	game.marches.tick(.01)
	game._fire_tower(tower)
	check(heard(&"cannon_shot") == 1 and heard(&"war_projectile_hit") == 0, "cannon launch does not prematurely emit a hit")
	game._tick_projectiles(.6)
	check(heard(&"war_projectile_hit") == 1 and game.marches.get_units().is_empty(), "projectile collision produces one hit at the actual casualty")
	await game.prepare_shutdown()
	var feedback: Node = root.get_node("Session/UIFeedback")
	feedback.stop_all()
	feedback.sound_played.connect(func(kind: StringName): menu_sounds.append(kind))
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await create_timer(.25).timeout
	check(menu_sounds.is_empty(), "restoring selected map and commander does not make fake click sounds")
	var pick: Button = current_scene.get_node("%PlayerCommander1")
	mouse(pick.get_global_rect().get_center(), true)
	mouse(pick.get_global_rect().get_center(), false)
	check(menu_sounds == [&"select"], "native commander click is audible exactly once")
	check(feedback.get_node("select").stream is AudioStreamRandomizer, "menu variants use a native randomizer")
	check(feedback.get_node("select").max_polyphony == 2, "rapid menu clicks have bounded native polyphony")
	feedback.stop_all()
	menu_sounds.clear()
	settings.open_menu()
	check(menu_sounds.is_empty(), "opening settings and restoring slider values is silent")
	settings.menu.get_node("%Volume").value_changed.emit(45.0)
	settings.menu.get_node("%Volume").value_changed.emit(46.0)
	check(menu_sounds == [&"ratio"], "settings slider provides one rate-limited tactile cue")
	settings.close_menu()
	feedback.stop_all()
	menu_sounds.clear()
	var start: Button = current_scene.get_node("%Start")
	mouse(start.get_global_rect().get_center(), true)
	mouse(start.get_global_rect().get_center(), false)
	check(menu_sounds == [&"order"], "native start button has its own confirmation cue")
	await scene_changed
	check(root.get_node("Session/UIFeedback") == feedback, "menu player persists through scene transition")
	while root.get_node("Session").transition.busy:
		await process_frame
	game = current_scene
	game.set_process(false)
	await game.prepare_shutdown()
	feedback.stop_all()
	await process_frame
	await process_frame
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(settings_path)
	print("BLOCK_WAR_AUDIO_FEEDBACK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
