extends "res://tests/tutorial_test.gd"
## Extra boundaries beyond the full curriculum gesture test. Native keyboard,
## pointer and window signals exercise interruption and return paths. A fresh
## lesson phase isolates each case without replaying the eleven-course suite.
## Settings are applied in memory; completion writes use a separate test path.

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func open_lesson(id: String) -> void:
	root.get_node("Session").tutorial_lesson_id = id
	game = BATTLE.instantiate()
	game.progress_path = output.path_join("boundary_progress_%d.cfg" % OS.get_process_id())
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	await physics_frame
	for frame: int in 5: await process_frame

func select_phase(index: int) -> void:
	game.phase_index = index - 1
	game._next_phase()
	for frame: int in 3: await process_frame
	click(game.tutor.continue_button)
	await process_frame

func close_lesson() -> void:
	await game.prepare_shutdown()
	game.free()
	game = null
	await process_frame

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600, 900)
	var session: Node = root.get_node("Session")
	var settings: GameSettings = session.settings
	var settings_before := settings.snapshot()
	var quiet := settings.defaults()
	quiet.music_enabled = false
	settings._apply_values(quiet, false)
	var selections := [session.block_war_map_id, session.block_war_commander, session.block_war_opponent_commander, session.online_nickname, session.online.address, session.online.port]

	await open_lesson("basics")
	var elapsed: float = game.elapsed
	key(KEY_ESCAPE)
	await process_frame
	check(game._local_menu and not game.tutor.visible, "lecture Esc opens local menu and hides tutorial chrome")
	game._process(3.0)
	check(game.elapsed == elapsed, "lecture plus menu retains simulation freeze")
	key(KEY_F3)
	await process_frame
	check(not game._local_menu and game.tutor.visible and game.simulation_paused, "F3 closes menu but restores lecture freeze")
	game._process(3.0)
	check(game.elapsed == elapsed, "F3 cannot advance paused lecture time")
	key(KEY_F3)
	await process_frame
	check(game._local_menu, "F3 from lecture opens menu")
	key(KEY_ESCAPE)
	await process_frame
	check(not game._local_menu and game.simulation_paused, "Esc from menu returns to lecture safely")
	await select_phase(2)
	key(KEY_ESCAPE)
	await process_frame
	check(game._local_menu and not game.simulation_paused, "practice Esc uses local menu pause")
	game._process(3.0)
	check(game.elapsed == elapsed, "practice menu freezes ongoing world")
	key(KEY_F3)
	await process_frame
	game._process(0.2)
	check(not game._local_menu and game.elapsed > elapsed, "practice resumes after F3")
	var from: Vector2 = game.camera.unproject_position(game.by_id[0].global_position + Vector3.UP * 1.5)
	var to: Vector2 = game.camera.unproject_position(game.by_id[1].global_position + Vector3.UP * 1.5)
	motion(from)
	mouse(from, true)
	motion(to, to-from, MOUSE_BUTTON_MASK_LEFT)
	check(game.drag_source != null, "native building drag is armed before focus loss")
	root.focus_exited.emit()
	mouse(to, false)
	check(game.drag_source == null and not game.accepted_action and game.by_id[0].queued_population == 0, "focus loss cancels building drag without phantom dispatch")
	mouse(Vector2(960,450), true, MOUSE_BUTTON_MIDDLE)
	check(game.camera_rig.dragging, "middle drag starts")
	root.focus_exited.emit()
	mouse(Vector2(960,450), false, MOUSE_BUTTON_MIDDLE)
	check(not game.camera_rig.dragging, "focus loss clears middle drag")
	await close_lesson()

	await open_lesson("recruit")
	await select_phase(1)
	game._process(0.0)
	from = game.hud.get_node("UI/Skills/Row/Skill0").get_global_rect().get_center()
	to = game.camera.unproject_position(game.by_id[0].global_position + Vector3.UP * 1.5)
	var supply: float = game.energy
	motion(from)
	mouse(from, true)
	check(game.armed_skill == 0, "native skill drag is armed before focus loss")
	root.focus_exited.emit()
	mouse(to, false)
	check(game.armed_skill == -1 and game.energy == supply and not game.accepted_action, "focus loss cancels skill without resource loss or release")
	game._process(10.0)
	check(game.elapsed == 0.0, "focus loss keeps first-time skill aiming patient")
	drag(from, to)
	check(game.accepted_action, "skill can be attempted again after focus loss")
	await close_lesson()

	await open_lesson("morale")
	await select_phase(1)
	var starting_points: float = game.morale.points(0)
	game._process(120.0)
	check(game.elapsed == 0.0 and game.morale.points(0) == starting_points, "thinking before the first morale order cannot decay the teaching setup")
	drag(game.camera.unproject_position(game.by_id[0].global_position + Vector3.UP * 1.5), game.camera.unproject_position(game.by_id[1].global_position + Vector3.UP * 1.5))
	for tick: int in 200:
		if game.phase_index > 1: break
		game._process(0.1)
		await process_frame
	check(game.phase_index == 2 and game.morale.level(0) >= 1, "morale lecture follows a real first star even after a long wait")
	await close_lesson()

	await open_lesson("energy")
	game.by_id[1].faction = 0
	game.by_id[1].refresh_visual()
	game.energy = 35.0
	await select_phase(2)
	var starting_energy: float = game.phase_start_energy
	game._process(2.0)
	check(game.energy > starting_energy and game.phase_index == 2, "energy lesson has partial progress before replay")
	var partial: float = game.energy
	game._replay()
	game._process(5.0)
	check(game.energy == partial, "replay lecture freezes partial energy progress")
	click(game.tutor.continue_button)
	await process_frame
	check(game.phase_start_energy == starting_energy, "replay preserves original energy objective baseline")
	game._process(2.0)
	await process_frame
	check(game.phase_index > 2, "five total energy gained completes even after replay")
	print("ENERGY_REPLAY baseline=", starting_energy, " resumed_baseline=", game.phase_start_energy, " energy=", game.energy, " phase=", game.phase_index)
	game.set_paused(true)
	await game.restart()
	await session.transition.completed
	game = current_scene
	game.set_process(false)
	game.progress_path = output.path_join("boundary_progress_%d.cfg" % OS.get_process_id())
	check(not paused and game.lesson_id == "energy" and game.simulation_paused and not game._local_menu, "restart from menu opens fresh lecture without inherited pause menu")
	check(game.phase_index == 0 and game.camera_rig.dragging == false and game.armed_skill == -1, "restart clears phase and gestures")
	await game.exit_to_lobby()
	await session.transition.completed
	game = null
	check(current_scene.scene_file_path == session.TUTORIAL_MENU_SCENE and not paused, "tutorial exit returns to active lesson menu")
	check(selections == [session.block_war_map_id, session.block_war_commander, session.block_war_opponent_commander, session.online_nickname, session.online.address, session.online.port], "tutorial restart/exit preserve ordinary and online preferences")
	settings._apply_values(settings_before, false)
	print("TUTORIAL_BOUNDARIES_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
