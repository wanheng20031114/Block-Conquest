extends SceneTree
## End-to-end pointer/keyboard navigation, with all writes isolated from user progress.

const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")
var checks := 0
var failures: Array[String] = []
var output := ""
var progress_path := ""
var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func frames(count: int = 12) -> void:
	for frame: int in count:
		await process_frame

func settle() -> void:
	await frames()
	while root.get_node("Session").transition.busy:
		await process_frame
	await frames(4)

func motion(at: Vector2, relative: Vector2 = Vector2.ZERO, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = mask
	root.push_input(event, true)

func mouse(at: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.pressed = pressed
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	root.push_input(event, true)

func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	motion(at)
	mouse(at, true)
	mouse(at, false)

func key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)

func drag(from: Vector2, to: Vector2) -> void:
	motion(from)
	mouse(from, true)
	motion(from.lerp(to, 0.5), (to - from) * 0.5, MOUSE_BUTTON_MASK_LEFT)
	motion(to, (to - from) * 0.5, MOUSE_BUTTON_MASK_LEFT)
	mouse(to, false)

func expect_scene(path: String, previous_instance: int = 0) -> bool:
	for frame: int in 420:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path and current_scene.get_instance_id() != previous_instance and not root.get_node("Session").transition.busy:
			await frames(6)
			return true
	check(false, "navigation reaches " + path)
	return false

func _isolate_progress() -> void:
	if current_scene != null and current_scene.scene_file_path == "res://scenes/tutorial/tutorial_battle.tscn":
		current_scene.progress_path = progress_path

func capture(label: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)
	print("TUTORIAL_NAV_CAPTURE ", label, " window=", root.size, " viewport=", root.get_visible_rect().size)

func _check_menu_size(size: Vector2i, label: String) -> void:
	root.size = size
	await settle()
	var menu := current_scene
	menu.get_node("%Continue").grab_focus()
	var last: Button = menu.get_node("%LessonFire")
	for press: int in 20:
		if last.has_focus(): break
		key(KEY_TAB)
		await process_frame
	await frames(4)
	var scroll: ScrollContainer = menu.get_node("%LessonScroll")
	check(last.has_focus(), label + " Tab reaches final lesson")
	check(scroll.get_global_rect().encloses(last.get_global_rect()), label + " focused final lesson is fully visible")
	check(not last.disabled and last.is_visible_in_tree(), label + " final lesson remains interactive")
	for card: Button in menu.cards:
		var column: Control = card.get_node("Margin/Column")
		check(column.size.y >= column.get_combined_minimum_size().y and card.size.x >= column.get_combined_minimum_size().x + 32.0, label + " card content fits " + str(card.get_meta("lesson_id")))
	# This curriculum fits in the default letterboxed viewport. If a native
	# vertical scrollbar is needed, focus-follow must still reach its last row.
	var bar := scroll.get_v_scroll_bar()
	check(not bar.visible or scroll.scroll_vertical + bar.page >= last.position.y, label + " scroll preserves final-row reachability")
	await capture(label + "_last_lesson_keyboard")

func _paused_snapshot() -> Array:
	return [game.elapsed, game.by_id[0].population, game.energy, game.phase_index]

func _run() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func(): quit(3))
	output = ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(output)
	progress_path = output.path_join("navigation_progress_%d.cfg" % OS.get_process_id())
	var user_existed := FileAccess.file_exists(PROGRESS.SAVE_PATH)
	var user_bytes := FileAccess.get_file_as_bytes(PROGRESS.SAVE_PATH) if user_existed else PackedByteArray()
	scene_changed.connect(_isolate_progress)
	var session: Node = root.get_node("Session")
	# Keep navigation fixtures independent of a player's first-run invitation.
	session.first_run.pending = false
	var original_preferences: Array = [session.block_war_map_id, session.block_war_commander, session.block_war_opponent_commander]
	root.size = Vector2i(1600, 900)
	check(change_scene_to_file(session.LOBBY_SCENE) == OK, "lobby loads")
	await scene_changed
	await settle()
	click(current_scene.get_node("%Tutorial"))
	if not await expect_scene(session.TUTORIAL_MENU_SCENE): quit(1); return
	check(current_scene.cards.size() == 11, "native lobby click opens eleven lessons")
	await _check_menu_size(Vector2i(1280, 720), "menu_1280x720")
	await _check_menu_size(Vector2i(1024, 768), "menu_1024x768")
	root.size = Vector2i(1600, 900)
	await settle()
	click(current_scene.get_node("%LessonBasics"))
	if not await expect_scene(session.TUTORIAL_BATTLE_SCENE): quit(1); return
	game = current_scene
	check(game.lesson_id == "basics" and game.tutorial_ready and game.simulation_paused, "card opens intended tutorial with frozen introduction")
	check(game.progress_path == progress_path and game.network_match == null and session.online.room.is_empty(), "battle progress is isolated and tutorial stays offline")
	var introduction := _paused_snapshot()
	key(KEY_ESCAPE)
	await settle()
	check(game._local_menu and game.hud.get_node("%PauseOverlay").visible and not game.tutor.visible, "Esc opens native menu above lecture")
	check(_paused_snapshot() == introduction, "opening menu preserves lecture time and supplies")
	key(KEY_ESCAPE)
	await settle()
	check(not game._local_menu and game.tutor.visible and game.tutor.is_instruction_visible(), "Esc closes menu and restores lecture")
	check(_paused_snapshot() == introduction, "closing menu cannot resume a lecture")
	key(KEY_F3)
	await settle()
	check(game._local_menu and not game.tutor.visible, "F3 opens menu from lecture")
	key(KEY_F3)
	await settle()
	check(not game._local_menu and game.tutor.visible and game.simulation_paused, "F3 closes menu but keeps teaching pause")
	check(_paused_snapshot() == introduction, "F3 never advances lecture simulation")
	await capture("battle_lecture_after_pause")
	key(KEY_ESCAPE)
	await settle()
	click(game.hud.get_node("%PauseExit"))
	if not await expect_scene(session.TUTORIAL_MENU_SCENE): quit(1); return
	game = null
	check(PROGRESS.completed_lessons(progress_path).is_empty(), "leaving an unfinished lesson does not mark completion")
	click(current_scene.get_node("%LessonBasics"))
	if not await expect_scene(session.TUTORIAL_BATTLE_SCENE): quit(1); return
	game = current_scene
	check(game.phase_index == 0 and game.lesson_id == "basics" and not game.lesson_complete, "repeat entry resets the same lesson")
	click(game.tutor.get_node("%Exit"))
	if not await expect_scene(session.TUTORIAL_MENU_SCENE): quit(1); return
	game = null
	click(current_scene.get_node("%Back"))
	if not await expect_scene(session.LOBBY_SCENE): quit(1); return
	check(current_scene.get_node("%Tutorial").has_focus(), "native Back restores main-menu focus")
	check([session.block_war_map_id, session.block_war_commander, session.block_war_opponent_commander] == original_preferences, "navigation preserves ordinary battle selections")
	click(current_scene.get_node("%Tutorial"))
	if not await expect_scene(session.TUTORIAL_MENU_SCENE): quit(1); return
	click(current_scene.get_node("%LessonBasics"))
	if not await expect_scene(session.TUTORIAL_BATTLE_SCENE): quit(1); return
	game = current_scene
	# Complete the actual first lesson, using native drag and battle rules.
	game.set_process(false)
	var steps := 0
	while not game.lesson_complete and steps < 8:
		var phase_index: int = game.phase_index
		var action: String = game.phase.action
		if action == "capture":
			check(game.simulation_paused and game.tutor.is_instruction_visible() and not game.tutor.continue_button.visible, "capture explanation accepts a direct gesture without a start button")
			drag(game.camera.unproject_position(game.by_id[0].global_position + Vector3.UP * 1.5), game.camera.unproject_position(game.by_id[1].global_position + Vector3.UP * 1.5))
			check(game.accepted_action and game.practicing and not game.simulation_paused and not game.tutor.is_instruction_visible(), "native building drag starts capture and dismisses its explanation")
			for tick: int in 400:
				if game.phase_index != phase_index: break
				game._process(0.1)
				await process_frame
		else:
			click(game.tutor.continue_button)
			await process_frame
		check(game.phase_index > phase_index or game.lesson_complete, "first lesson advances from " + action)
		if game.phase_index == phase_index and not game.lesson_complete: break
		steps += 1
	check(game.lesson_complete and game.by_id[1].faction == 0, "real capture completes first lesson")
	check(PROGRESS.completed_lessons(progress_path) == PackedStringArray(["basics"]), "first completion saves only in the isolated path")
	await capture("basics_completion_navigation")
	var completed_instance := game.get_instance_id()
	click(game.tutor.next_button)
	if not await expect_scene(session.TUTORIAL_BATTLE_SCENE, completed_instance): quit(1); return
	game = current_scene
	check(game.lesson_id == "interface" and game.phase_index == 0 and game.simulation_paused, "completion Next enters the next authored lesson")
	check(game.progress_path == progress_path, "next lesson also uses isolated test storage")
	click(game.tutor.get_node("%Exit"))
	if not await expect_scene(session.TUTORIAL_MENU_SCENE): quit(1); return
	game = null
	key(KEY_ESCAPE)
	if not await expect_scene(session.LOBBY_SCENE): quit(1); return
	check(FileAccess.file_exists(PROGRESS.SAVE_PATH) == user_existed and (not user_existed or FileAccess.get_file_as_bytes(PROGRESS.SAVE_PATH) == user_bytes), "real tutorial progress is unchanged")
	check(DirAccess.remove_absolute(progress_path) == OK, "isolated test progress is removed")
	print("TUTORIAL_NAVIGATION_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
