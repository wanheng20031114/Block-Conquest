extends "res://tests/tutorial_test.gd"
## Result-driven lesson regressions: a committed input is not a finished effect.
## Use the real battle rules, with process disabled so the fixture owns world time.
var progress_file := ""

func open_lesson(id: String, action: String) -> void:
	root.get_node("Session").tutorial_lesson_id = id
	game = BATTLE.instantiate()
	game.progress_path = progress_file
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	await physics_frame
	for frame: int in 4: await process_frame
	var target := -1
	for index: int in game.lesson_steps.size():
		if game.lesson_steps[index].action == action:
			target = index
			break
	check(target >= 0, id + " defines " + action)
	game.phase_index = target - 1
	game._next_phase()
	for frame: int in 4: await process_frame

func close_lesson() -> void:
	await game.prepare_shutdown()
	game.free()
	game = null
	await process_frame

func cast_building(skill: int, target: int) -> Dictionary:
	return game.submit_player_command({"type": "skill_building", "skill": skill, "target": target})

func cast_ground(skill: int, at: Vector3) -> Dictionary:
	return game.submit_player_command({"type": "skill_ground", "skill": skill, "x": at.x, "z": at.z})

func dispatch(percent: int = 50) -> Dictionary:
	return game.submit_player_command({"type": "dispatch", "source": 0, "target": 1, "percent": percent})

func check_running(index: int, label: String) -> void:
	check(game.phase_index == index and game.practicing and not game.simulation_paused and not game.tutor.is_instruction_visible(), label)

func reach_result(label: String, max_seconds: float = 45.0) -> void:
	var index: int = game.phase_index
	var ticks := 0
	while not game._objective_met() and game.phase_index == index and not game.advance_queued and ticks < ceili(max_seconds / 0.05):
		game._process(0.05)
		ticks += 1
	check(game._objective_met(), label + " reaches its real battle result")
	check_running(index, label + " keeps the result visible before advancing")

func finish_result(index: int, label: String, review: bool = false) -> void:
	# No fixed skill timer is used here: the actual result has already been reached.
	game._process(0.35)
	await process_frame
	check_running(index, label + " remains visible during the result hold")
	if review:
		var elapsed: float = game.elapsed
		game._replay()
		game._process(15.0)
		for frame: int in 6: await process_frame
		check(game.elapsed == elapsed and game.phase_index == index, label + " review cannot consume the result hold")
		click(game.tutor.continue_button)
		await process_frame
	game._process(0.3)
	await process_frame
	check_running(index, label + " does not skip the final fraction of the result hold")
	# Native particle tails may outlive the minimum hold, and building pulses use
	# real rendered frames. Allow both clocks to finish without forcing their state.
	for frame: int in 40:
		if game.phase_index > index: break
		game._process(0.05)
		await process_frame
	check(game.phase_index > index and game.simulation_paused, label + " advances only after the visible result hold")

func test_recruit() -> void:
	await open_lesson("recruit", "cast_building")
	var index: int = game.phase_index
	var start: float = game.by_id[0].population
	check(cast_building(0, 0).accepted, "recruit starts from the teaching card")
	game._process(0.1)
	check_running(index, "recruit does not stop on successful placement")
	var energy: float = game.energy
	var duration: float = game.faction_skills[0].durations[0]
	check(not cast_building(0, 0).accepted and game.energy == energy and game.faction_skills[0].durations[0] == duration, "a repeated recruit input cannot spend resources or restart the effect")
	game._process(3.9)
	check(game.by_id[0].population >= start + 16.0 and not game._objective_met(), "the old 46-person threshold no longer truncates recruitment")
	check_running(index, "recruit remains in the cast objective at four seconds")
	await capture("recruit_mid_effect")
	var elapsed: float = game.elapsed
	game.set_paused(true)
	game._process(20.0)
	check(game.elapsed == elapsed and game.faction_skills[0].durations[0] > 1.9, "menu pause preserves the unfinished recruit effect")
	game.set_paused(false)
	game._replay()
	game._process(20.0)
	check(game.elapsed == elapsed and game.phase_index == index, "review pauses the ongoing effect without starting the next phase")
	for frame: int in 6: await process_frame
	click(game.tutor.continue_button)
	await process_frame
	check_running(index, "continuing the recruit review resumes the same effect")
	game._process(1.8)
	check(not game._objective_met() and game.faction_skills[0].recruit_target_id == 0, "recruit remains active just before its six-second duration")
	reach_result("recruit")
	check(game.by_id[0].population >= start + 24.0 - 0.001 and game.faction_skills[0].recruit_target_id == -1, "recruit visibly delivers the full 24 soldiers")
	game.faction_skills[0].cooldowns[0] = 0.0
	game.energy = 100.0
	check(not cast_building(0, 0).accepted and game.energy == 100.0, "completed recruitment cannot be recast during observation even when ordinary skill rules permit it")
	await finish_result(index, "recruit", true)
	check(game.phase.action == "read", "recruit result summary needs no second observation start")
	await close_lesson()

func test_shield() -> void:
	await open_lesson("shield", "cast_building")
	var index: int = game.phase_index
	check(cast_building(2, 1).accepted, "shield placement is accepted")
	check(game.wave_started and game.marches.total_for(1) > 0, "shield placement starts the enemy wave immediately")
	game._process(0.1)
	check_running(index, "shield remains visible after placement")
	await capture("shield_enemy_approaches")
	# One slow frame crosses the whole approach and shielded combat. An end-of-frame
	# population comparison after the shield expires must not lose the evidence.
	game._process(8.0)
	check(game.shield_damage_seen, "long simulation ticks still witness damage during the shield's lifetime")
	check(not game.shields.has(1), "the full eight-second shield has ended")
	reach_result("shield")
	check(game.marches.total_for(1) == 0 and game.by_id[1].faction == 0, "shield waits for the complete enemy wave and surviving outpost")
	await finish_result(index, "shield")
	await close_lesson()

func test_drum() -> void:
	await open_lesson("drum", "dispatch")
	check(dispatch().accepted, "drum lesson sends the real reinforcement column")
	# A stalled frame must still stop at the intermediate teaching checkpoint,
	# rather than consume the whole march before the player can aim the drum.
	game._process(20.0)
	await process_frame
	check(game.phase.action == "cast_ground", "drum pauses the departing column for aiming instruction")
	check(game._army_exposed(0) >= 6 and game.simulation_paused and game.marches.incoming_for(1, 0) > 0, "a long departure frame retains a frozen aimable reinforcement column")
	var index: int = game.phase_index
	check(cast_ground(1, game._army_center(0)).accepted, "drum accepts placement over the column")
	var energy: float = game.energy
	check(not cast_ground(1, game._army_center(0)).accepted and game.energy == energy, "repeated drum input cannot refresh the zone")
	await capture("drum_cast")
	game._process(8.05)
	check(game.haste_seen, "one long simulation tick still records soldiers crossing the haste zone")
	check(not game.marches.haste_zones.has(0), "drum completes its entire eight-second zone")
	if game.marches.total_for(0) > 0:
		check(not game._objective_met(), "drum also waits for the final reinforcement")
	reach_result("drum")
	check(game.haste_arrived and game.marches.incoming_for(1, 0) == 0, "drum waits until the complete reinforcement column arrives")
	await finish_result(index, "drum")
	await close_lesson()

func test_fire() -> void:
	await open_lesson("fire", "fire_hit")
	var index: int = game.phase_index
	check(cast_ground(3, game._army_center(1)).accepted, "fire placement is accepted")
	game._process(0.4)
	check(game.burned_enemies >= 3, "the authored fire target gives at least three visible hits")
	check(not game._objective_met(), "three early kills cannot complete an ongoing fire effect")
	check_running(index, "fire keeps expanding after reaching the kill target")
	await capture("fire_expanding")
	game._process(2.5)
	check(not game.fire_states.is_empty() and not game._objective_met(), "fire observes the visual tail after its damage window closes")
	reach_result("fire")
	check(game.fire_states.is_empty(), "fire completion waits for the full three-second visual lifetime")
	await finish_result(index, "fire")
	await close_lesson()

func test_capture() -> void:
	await open_lesson("core_command", "capture")
	var index: int = game.phase_index
	check(dispatch(100).accepted, "capture sends a full multi-row column")
	for tick: int in 600:
		if game.by_id[1].faction == 0: break
		game._process(0.05)
	check(game.by_id[1].faction == 0 and game.marches.incoming_for(1, 0) > 0, "capture fixture has later rows still approaching after the flag changes")
	check(not game._objective_met(), "changing the flag alone does not cut off arriving reinforcements")
	check_running(index, "capture remains running while the column enters the building")
	var incoming: int = game.marches.incoming_for(1, 0)
	check(not dispatch().accepted and game.marches.incoming_for(1, 0) == incoming, "duplicate capture input cannot add an unintended second wave")
	reach_result("capture")
	check(game.marches.incoming_for(1, 0) == 0, "all dispatched soldiers finish entering before capture completes")
	await finish_result(index, "capture")
	await close_lesson()

func test_capture_recovery() -> void:
	await open_lesson("core_command", "capture")
	# A stronger neutral building isolates a legitimate under-strength first order.
	game.by_id[1].population = 18.0
	check(dispatch(25).accepted, "an under-strength opening order is accepted")
	for tick: int in 800:
		if game.marches.total_for(0) == 0: break
		game._process(0.05)
	game._process(0.05)
	check(game.by_id[1].faction == -1 and not game._objective_met(), "failed first capture does not falsely complete the goal")
	check(dispatch(100).accepted, "a spent insufficient wave allows a corrective reinforcement order")
	reach_result("corrected capture")
	check(game.by_id[1].faction == 0, "the corrective order can finish the original objective")
	await close_lesson()

func has_capture_ring(target: int) -> bool:
	for effect: Dictionary in game.effects:
		if effect.kind == "capture" and effect.at == game.by_id[target].global_position:
			return true
	return false

func test_short_capture_effect() -> void:
	await open_lesson("core_command", "capture")
	var index: int = game.phase_index
	# Five soldiers exactly resolve four defenders and occupy the neutral house.
	# No long queue can incidentally give the 1.1-second capture ring time to fade.
	game.by_id[0].population = 20.0
	check(dispatch(25).accepted, "short capture sends only the required five soldiers")
	reach_result("short capture")
	check(has_capture_ring(1), "the capture ring still exists when the final soldier enters")
	for frame: int in 20: await process_frame
	check(not game.by_id[1]._capture_tween.is_running(), "the native building pulse finishes before checking the remaining ring")
	game._process(0.8)
	await process_frame
	check(has_capture_ring(1), "the authored ring outlives the generic result hold")
	check_running(index, "capture does not freeze its remaining ring after the minimum hold")
	for frame: int in 24:
		if game.phase_index > index: break
		game._process(0.05)
		await process_frame
	check(game.phase_index > index and not has_capture_ring(1), "short capture advances only after its complete ring fades")
	await close_lesson()

func test_tower_and_upgrade() -> void:
	await open_lesson("tower", "reinforce_tower")
	var index: int = game.phase_index
	check(dispatch().accepted, "tower accepts reinforcement")
	game._process(0.1)
	check_running(index, "tower does not pause immediately after the order")
	reach_result("tower")
	check(game.tower_shots > 0 and game.marches.total_for(1) == 0 and game.marches.incoming_for(1, 0) == 0 and game.by_id[1].faction == 0, "tower observes automatic fire, all reinforcements, and the whole enemy wave")
	await finish_result(index, "tower")
	await close_lesson()
	await open_lesson("house", "upgrade")
	index = game.phase_index
	check(game.submit_player_command({"type": "upgrade", "building": 0}).accepted, "upgrade starts real construction")
	game._process(4.8)
	check(game.by_id[0].is_constructing and not game._objective_met(), "upgrade cannot complete before actual construction finishes")
	reach_result("upgrade")
	check(game.by_id[0].level == 2 and not game.by_id[0].is_constructing, "upgrade observes the real second-level model")
	game.by_id[0].population = 120.0
	check(not game.submit_player_command({"type": "upgrade", "building": 0}).accepted, "the result hold cannot accept an accidental third-level upgrade")
	for frame: int in 20: await process_frame
	game._process(1.8)
	await process_frame
	check_running(index, "upgrade keeps the final construction dust alive after its building pulse finishes")
	var particle_tail := 0.0
	for particles: GPUParticles3D in game.by_id[0]._construction_particles:
		particle_tail = maxf(particle_tail, particles.lifetime)
	game._process(maxf(0.0, particle_tail - 1.8) + 0.1)
	await process_frame
	check(game.phase_index > index and game.simulation_paused, "upgrade advances after its authored construction particle lifetime")
	await close_lesson()

func test_unsuccessful_fire_retry() -> void:
	await open_lesson("fire", "fire_hit")
	var index: int = game.phase_index
	# A depleted approaching wave makes the three-kill objective impossible. Keep
	# the same native fire placement/rules to test the recovery path, not a timer.
	game.marches.clear()
	game.marches.send(2, 1, 1, 2, PackedVector3Array([Vector3(3, 0, -5), Vector3(-9, 0, -5)]))
	check(cast_ground(3, game._army_center(1)).accepted, "a cast against a depleted wave is still a real valid placement")
	game._process(6.0)
	await process_frame
	check(game.fire_states.is_empty() and game.burned_enemies < 3 and game.phase_index == index and not game.lesson_complete, "an expired effect that missed its objective does not award completion")
	check(not game.tutor.get_node("%Retry").disabled, "the player can retry an unsuccessful practice")
	click(game.tutor.get_node("%Retry"))
	await root.get_node("Session").transition.completed
	game = current_scene
	game.set_process(false)
	game.progress_path = progress_file
	check(game.lesson_id == "fire" and game.phase_index == 0 and game.simulation_paused and game.burned_enemies == 0 and not game.accepted_action, "retry restores a fresh fire lesson and its supplies")
	await close_lesson()

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600, 900)
	progress_file = output.path_join("effect_progress_%d.cfg" % OS.get_process_id())
	# Native retry recreates the battle through Session, before this fixture can
	# assign its instance fields. Isolate that initial mark_started write too.
	var session: Node = root.get_node("Session")
	var previous_progress: String = session.tutorial_progress_path
	session.tutorial_progress_path = progress_file
	var settings: GameSettings = root.get_node("Session").settings
	var settings_before := settings.snapshot()
	var quiet := settings.defaults()
	quiet.music_enabled = false
	settings._apply_values(quiet, false)
	await test_recruit()
	await test_shield()
	await test_drum()
	await test_fire()
	await test_capture()
	await test_capture_recovery()
	await test_short_capture_effect()
	await test_tower_and_upgrade()
	await test_unsuccessful_fire_retry()
	settings._apply_values(settings_before, false)
	session.tutorial_progress_path = previous_progress
	if FileAccess.file_exists(progress_file): DirAccess.remove_absolute(progress_file)
	print("TUTORIAL_EFFECT_COMPLETION_TEST checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
