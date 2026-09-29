extends "res://tests/block_war_audio_feedback_test.gd"
## Actual release gestures and paid AI decisions, using native pooled players.
const RELEASES := {
	&"squirrel": [&"war_skill_command", &"war_skill_drum", &"war_skill_shield", &"war_skill_breach"],
	&"rabbit": [&"war_rabbit_dash", &"war_rabbit_seal", &"war_rabbit_recall", &"war_rabbit_burrow"],
	&"bear": [&"war_bear_toolbox", &"war_bear_stomp", &"war_bear_link", &"war_bear_ward"],
	&"frog": [&"war_frog_mist", &"war_frog_float", &"war_frog_cloak", &"war_frog_strike"],
	&"fox": [&"war_fox_bomb", &"war_fox_steal", &"war_fox_convert", &"war_fox_panic"],
}
const CENTER := Vector3(-22, 0, 10)

func setup(commander: StringName) -> void:
	await reset()
	game.faction_skills[0].commander = commander
	game.faction_skills[1].commander = commander
	game.audio.sound_played.connect(_record)
	game.select_building(null)
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
		building.population = 100.0
		building.refresh_visual()
	game.update_hud()
	await physics_frame
	await process_frame
	clear_sounds()

func release_count() -> int:
	var count := 0
	for event: Array in RELEASES.values():
		for kind: StringName in event:
			count += heard(kind)
	return count

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy":
		quit(2)
		return
	create_timer(65.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	var settings: GameSettings = root.get_node("Session/Settings")
	var original := settings.snapshot()
	var preferences := settings.defaults()
	preferences.music_enabled = false
	settings._apply_values(preferences, false)
	for commander: StringName in RELEASES:
		for index: int in 4:
			await setup(commander)
			var target: WarBuilding = enemy() if (commander in [&"frog", &"fox"] or (commander == &"rabbit" and index == 1)) else home()
			if commander == &"fox":
				game.morale.adjust(target.faction, 1000)
				game.buildings[3].faction = target.faction
			if commander == &"bear":
				if index == 0:
					target.begin_construction(-1, 10)
				elif index == 2:
					var support: WarBuilding = game.buildings[2]
					support.faction = 0
					support.global_position = target.global_position + Vector3(8, 0, 0)
			if game.skill_is_ground(index):
				expose(0, 6, CENTER, CENTER + Vector3(30, 0, 0), enemy().building_id)
				expose(1, 6, CENTER, CENTER + Vector3(30, 0, 0), home().building_id)
				game.marches.tick(0.3)
			var aim: Vector2 = game.camera.unproject_position(CENTER) if game.skill_is_ground(index) else screen(target)
			var code: int = [KEY_Q, KEY_W, KEY_E, KEY_R][index]
			var expected: StringName = RELEASES[commander][index]
			key(code, true)
			motion(aim)
			check(release_count() == 0, "%s held gesture has no premature spell" % expected)
			mouse(aim, true, MOUSE_BUTTON_RIGHT)
			key(code, false)
			check(release_count() == 0 and is_equal_approx(game.energy, 100), "%s canceled gesture has no cast cue or payment" % expected)
			clear_sounds()
			key(code, true)
			motion(aim)
			key(code, false)
			check(game.cooldowns[index] > 0 and heard(expected) == 1 and release_count() == 1, "%s native release plays exactly once in its cast frame" % expected)
			if heard(expected) == 1:
				var event: Dictionary = sounds.filter(func(item: Dictionary): return item.kind == expected)[0]
				var at: Vector3 = CENTER if game.skill_is_ground(index) else target.global_position
				check(event.spatial and event.position.distance_to(at) < 0.12, "%s is spatial at the effect" % expected)
			key(code, true)
			key(code, false)
			check(heard(expected) == 1, "%s cooldown rejection cannot duplicate the release" % expected)
	# Exercise the actual AI decision code, with only the requested skill ready.
	for commander: StringName in [&"bear", &"frog"]:
		for index: int in 4:
			await setup(commander)
			var target := enemy()
			game.faction_skills[1].cooldowns.fill(100.0)
			game.faction_skills[1].cooldowns[index] = 0.0
			if commander == &"bear":
				var support: WarBuilding = game.buildings[2]
				support.faction = 1
				support.global_position = target.global_position + Vector3(8, 0, 0)
				if index == 0:
					target.begin_construction(2, 20)
				else:
					target.population = 10.0
					expose(0, 30, target.global_position + Vector3(7, 0, 0), target.global_position + Vector3(2.5, 0, 0), target.building_id)
			elif index in [0, 1]:
				expose(0, 12, target.global_position + Vector3(5, 0, 0), target.global_position + Vector3(2.5, 0, 0), target.building_id)
			elif index == 2:
				expose(1, 12, CENTER, CENTER + Vector3(30, 0, 0), home().building_id)
			game.elapsed = 20.0
			TACTICS.new(1).take_turn(game)
			var expected: StringName = RELEASES[commander][index]
			check(game.faction_skills[1].cooldowns[index] > 0 and heard(expected) == 1 and release_count() == 1, "%s AI pays and emits its own release exactly once" % expected)
	await setup(&"frog")
	check(not game.cast_ground_skill(1, CENTER) and not game.cast_ground_skill(2, CENTER) and release_count() == 0, "empty float/cloak have no success sound")
	game.bear.wards[enemy().building_id] = {"remaining": 5.0, "faction": 1}
	check(not game.cast_skill(3, enemy()) and release_count() == 0, "invulnerable target rejects lethal strike without success audio")
	await setup(&"bear")
	check(not game.cast_skill(0, home()) and release_count() == 0, "idle building rejects toolbox without success audio")
	# Shared event gates must not swallow a second faction's legal simultaneous cast.
	for commander: StringName in RELEASES:
		for kind: StringName in RELEASES[commander]:
			clear_sounds()
			for faction: int in 6:
				game.audio.play_world(kind, CENTER + Vector3(faction, 0, 0))
			check(heard(kind) == 6, "%s allows six simultaneous faction releases" % kind)
			for duplicate: int in 100:
				game.audio.play_world(kind, CENTER)
			check(heard(kind) == 6, "%s remains bounded under excess requests" % kind)
	await game.prepare_shutdown()
	settings._apply_values(original, false)
	print("COMMANDER_AUDIO checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
