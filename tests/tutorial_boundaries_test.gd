extends "res://tests/tutorial_test.gd"
## Extra boundaries beyond the full curriculum gesture test. Native keyboard,
## pointer and window signals exercise interruption and return paths. A fresh
## lesson phase isolates each case without replaying the eleven-course suite.
## Settings are applied in memory; completion writes use a separate test path.
var keyboard_viewport: SubViewport

func key(code: Key) -> void:
	key_event(code, true)
	key_event(code, false)

func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	game.get_viewport().push_input(event, true)

func open_lesson(id: String, native_pointer: bool = false) -> void:
	root.get_node("Session").tutorial_lesson_id = id
	game = BATTLE.instantiate()
	game.progress_path = output.path_join("boundary_progress_%d.cfg" % OS.get_process_id())
	if native_pointer:
		# Window.get_mouse_position queries the OS cursor, which push_input does
		# not move on a private desktop. A native SubViewport owns mouse position
		# from its injected events, so keyboard release uses the real aim code.
		keyboard_viewport = SubViewport.new()
		keyboard_viewport.size = root.size
		keyboard_viewport.own_world_3d = true
		keyboard_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(keyboard_viewport)
		keyboard_viewport.add_child(game)
	else:
		root.add_child(game)
	current_scene = keyboard_viewport if native_pointer else game
	game.set_process(false)
	await physics_frame
	for frame: int in 5: await process_frame

func select_phase(index: int) -> void:
	game.phase_index = index - 1
	game._next_phase()
	for frame: int in 6: await process_frame
	if game.tutor.continue_button.visible:
		click(game.tutor.continue_button)
		await process_frame

func close_lesson() -> void:
	await game.prepare_shutdown()
	game.free()
	game = null
	if keyboard_viewport != null:
		keyboard_viewport.free()
		keyboard_viewport = null
	await process_frame

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600, 900)
	var session: Node = root.get_node("Session")
	session.tutorial_progress_path = output.path_join("boundary_progress_%d.cfg" % OS.get_process_id())
	var settings: GameSettings = session.settings
	var settings_before := settings.snapshot()
	var quiet := settings.defaults()
	quiet.music_enabled = false
	settings._apply_values(quiet, false)
	var selections := [session.block_war_map_id, session.block_war_commander, session.block_war_opponent_commander, session.online_nickname, session.online.address, session.online.port]

	await open_lesson("core_command")
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
	await select_phase(3)
	check(game.simulation_paused and not game.practicing and not game.tutor.continue_button.visible, "direct capture opens frozen with no start gate")
	key(KEY_ESCAPE)
	await process_frame
	check(game._local_menu and game.simulation_paused, "direct teaching Esc opens local menu")
	game._process(3.0)
	check(game.elapsed == elapsed, "direct teaching menu keeps world frozen")
	key(KEY_F3)
	await process_frame
	game._process(0.2)
	check(not game._local_menu and game.simulation_paused and game.elapsed == elapsed, "F3 restores direct teaching without starting the world")
	var from: Vector2 = game.camera.unproject_position(game.by_id[0].global_position + Vector3.UP * 1.5)
	var to: Vector2 = game.camera.unproject_position(game.by_id[1].global_position + Vector3.UP * 1.5)
	motion(from)
	mouse(from, true)
	motion(to, to-from, MOUSE_BUTTON_MASK_LEFT)
	check(game.drag_source != null, "native building drag is armed before focus loss")
	root.focus_exited.emit()
	mouse(to, false)
	check(game.drag_source == null and not game.accepted_action and game.by_id[0].queued_population == 0 and game.simulation_paused, "focus loss cancels teaching drag without phantom dispatch or resume")
	motion(from)
	mouse(from, true)
	motion(to, to - from, MOUSE_BUTTON_MASK_LEFT)
	mouse(game.tutor.instruction.get_global_rect().get_center(), true, MOUSE_BUTTON_RIGHT)
	mouse(to, false)
	game._process(3.0)
	check(game.drag_source == null and not game.accepted_action and game.by_id[0].queued_population == 0 and game.elapsed == elapsed, "right-click over the instruction cancels a building drag and keeps time frozen")
	drag(from, game.tutor.instruction.get_global_rect().get_center())
	check(not game.accepted_action and game.simulation_paused and game.by_id[0].queued_population == 0, "building release over explanation cannot issue an order behind it")
	var rejected: Dictionary = game.submit_player_command({"type": "dispatch", "source": 1, "target": 0, "percent": 50})
	check(not rejected.accepted and game.simulation_paused and not game.practicing, "wrong source and target cannot start teaching simulation")
	drag(from, to)
	check(game.accepted_action and game.practicing and not game.simulation_paused, "valid direct teaching drag enters practice")
	key(KEY_ESCAPE)
	await process_frame
	check(game._local_menu and not game.simulation_paused, "practice Esc uses local menu pause after the real order")
	game._process(3.0)
	check(game.elapsed == elapsed, "practice menu freezes dispatched troops")
	key(KEY_F3)
	await process_frame
	game._process(0.2)
	check(not game._local_menu and game.elapsed > elapsed, "F3 resumes the real practice")
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
	mouse(from, true)
	mouse(game.tutor.instruction.get_global_rect().get_center(), true, MOUSE_BUTTON_RIGHT)
	mouse(to, false)
	game._process(10.0)
	check(game.armed_skill == -1 and game.energy == supply and game.simulation_paused and not game.accepted_action and game.elapsed == 0.0, "right-click cancels direct skill aim outside the spotlight without consuming time or supplies")
	drag(from, game.camera.unproject_position(game.by_id[1].global_position + Vector3.UP * 1.5))
	check(game.energy == supply and not game.accepted_action and game.simulation_paused, "recruiting onto a neutral building is rejected while the explanation stays paused")
	drag(from, game.tutor.instruction.get_global_rect().get_center())
	check(game.energy == supply and not game.accepted_action and game.armed_skill == -1 and game.simulation_paused, "skill release on the explanation does not cast or resume")
	await close_lesson()

	await open_lesson("recruit", true)
	await select_phase(1)
	supply = game.energy
	to = game.camera.unproject_position(game.by_id[0].global_position + Vector3.UP * 1.5)
	var aim_motion := InputEventMouseMotion.new()
	aim_motion.position = to
	aim_motion.global_position = to
	keyboard_viewport.push_input(aim_motion, true)
	check(keyboard_viewport.get_mouse_position().is_equal_approx(to), "keyboard fixture uses a native viewport with the injected pointer position")
	key_event(KEY_Q, true)
	check(game.armed_skill == 0 and game.simulation_paused and game.tutor.is_instruction_visible(), "Q directly arms the taught skill while retaining the paused explanation")
	game._process(5.0)
	check(game.elapsed == 0.0 and game.energy == supply, "holding a skill shortcut preserves tutorial thinking time")
	key_event(KEY_Q, false)
	check(game.accepted_action and game.energy < supply and game.practicing and not game.simulation_paused, "releasing Q over the valid target commits and begins practice")
	await close_lesson()

	await open_lesson("fire", true)
	await select_phase(1)
	supply = game.energy
	var aiming_time: float = game.elapsed
	var army_before: int = game.marches.total_for(1)
	to = game.camera.unproject_position(game._aim_position())
	aim_motion.position = to
	aim_motion.global_position = to
	keyboard_viewport.push_input(aim_motion, true)
	key_event(KEY_R, true)
	check(game.armed_skill == 3 and game.ground_skill_target.is_finite() and game.can_cast_skill(3), "valid fire aim remains available during the paused explanation")
	check(not game.can_cast_skill(1) and not game.can_cast_skill(3, 1), "teaching availability cannot enable unrelated skills or another faction")
	game._process(20.0)
	check(game.simulation_paused and game.elapsed == aiming_time and game.energy == supply and game.marches.total_for(1) == army_before, "availability queries and aiming leave troops, time and supplies frozen")
	for frame: int in 6: await process_frame
	await RenderingServer.frame_post_draw
	check(keyboard_viewport.get_texture().get_image().save_png(output.path_join("fire_frozen_aim.png")) == OK, "capture valid ground targeting while the explanation freezes time")
	game.energy = 0.0
	check(not game.can_cast_skill(3), "teaching preview retains native energy validation")
	game.energy = supply
	game.cooldowns[3] = 1.0
	check(not game.can_cast_skill(3), "teaching preview retains native cooldown validation")
	game.cooldowns[3] = 0.0
	var fire_center: Vector3 = game._army_center(1)
	var paused_command: Dictionary = game.execute_network_command(0, {"type": "skill_ground", "skill": 3, "x": fire_center.x, "z": fire_center.z})
	check(not paused_command.accepted and not game.cast_ground_skill(3, fire_center) and game.energy == supply, "read-only preview availability cannot bypass the native paused execution gate")
	game.set_paused(true)
	check(not game.can_cast_skill(3), "local menu still blocks ground skill availability")
	game.set_paused(false)
	check(game.can_cast_skill(3) and game.simulation_paused, "closing the menu restores the valid teaching preview without resuming time")
	key_event(KEY_R, false)
	check(not game.accepted_action and game.energy == supply, "menu cancellation prevents a held shortcut from releasing a phantom skill")
	await close_lesson()

	await open_lesson("house")
	await select_phase(1)
	var population_before: float = game.by_id[0].population
	check(game.selected == game.by_id[0] and game.simulation_paused, "upgrade is selected and ready in its paused explanation")
	click(game.hud.get_node("UI/Selection/BuildingActions/Upgrade"))
	check(game.accepted_action and game.by_id[0].is_constructing and game.by_id[0].population < population_before and not game.simulation_paused, "native upgrade button works directly and starts actual construction")
	game._replay()
	var construction_before: float = game.by_id[0].construction_remaining
	game._process(5.0)
	check(game.by_id[0].construction_remaining == construction_before and game.tutor.continue_button.visible, "review after accepted upgrade freezes construction and offers resume")
	for frame: int in 6: await process_frame
	click(game.tutor.continue_button)
	game._process(0.5)
	check(game.by_id[0].construction_remaining < construction_before, "resume after review continues existing construction")
	await close_lesson()

	await open_lesson("core_command")
	await select_phase(6)
	key(KEY_2)
	check(not game.accepted_action and game.simulation_paused and game.phase_index == 6, "unchanged ratio does not complete the adjustment objective")
	key(KEY_1)
	check(game.percentage == 25 and game.accepted_action and not game.simulation_paused, "number 1 selects 25 percent directly from the explanation")
	game._process(0.0)
	await process_frame
	check(game.phase_index == 7 and game.simulation_paused, "ratio shortcut advances once into the frozen skill explanation")
	await select_phase(0)
	for frame: int in 6: await process_frame
	var view_start: Vector2 = game.tutor.gesture._from
	mouse(view_start, true, MOUSE_BUTTON_WHEEL_UP)
	game.camera_rig._process(0.2)
	game._process(0.0)
	await process_frame
	check(game.phase_index == 1 and game.simulation_paused and game.elapsed == 0.0, "direct wheel zoom completes without starting world time")
	for frame: int in 6: await process_frame
	view_start = game.tutor.gesture._from
	mouse(view_start, true, MOUSE_BUTTON_MIDDLE)
	check(game.camera_rig.dragging, "direct pan explanation accepts middle button")
	root.focus_exited.emit()
	mouse(view_start, false, MOUSE_BUTTON_MIDDLE)
	check(not game.camera_rig.dragging and game.simulation_paused and not game.accepted_action, "losing focus cancels a direct camera drag without completing an unmoved view")
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
