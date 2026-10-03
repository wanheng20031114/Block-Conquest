extends SceneTree
## First-entry routing, chapter selection and persistence use isolated progress.

const CATALOG := preload("res://scripts/tutorial/tutorial_catalog.gd")
const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error("TUTORIAL_MENU_TEST " + message)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	var output := ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	var save_path := output.path_join("isolated_progress_%d.cfg" % OS.get_process_id())
	var session: Node = root.get_node("Session")
	var original_path: String = session.tutorial_progress_path
	session.tutorial_progress_path = save_path
	session.first_run.pending = false
	var map_id: String = session.block_war_map_id
	var commander: StringName = session.block_war_commander
	var opponent: StringName = session.block_war_opponent_commander
	paused = true
	_check(session.start_tutorial("invalid") == ERR_INVALID_PARAMETER, "invalid lesson cannot start")
	_check(paused, "invalid start does not disturb paused state")
	_check(not PROGRESS.has_started(save_path), "invalid start does not record a visit")
	paused = false
	session.transition.busy = true
	_check(session.start_tutorial() == ERR_BUSY, "transition blocks duplicate start requests")
	_check(session.show_tutorial_menu() == ERR_BUSY, "course list also respects an active transition")
	session.transition.busy = false
	_check(change_scene_to_file("res://scenes/lobby.tscn") == OK, "lobby loads")
	await scene_changed
	_check(current_scene.get_node("%Tutorial").text == "入门教程    →", "main menu has tutorial entry")
	_check(session.start_tutorial() == OK, "first tutorial entry starts native transition")
	_check(not PROGRESS.has_started(save_path), "requesting a transition does not record a visit before readiness")
	await session.transition.completed
	_check(current_scene.scene_file_path == session.TUTORIAL_BATTLE_SCENE, "first visit opens a teaching scene directly")
	_check(session.tutorial_lesson_id == "core_command" and current_scene.tutorial_ready, "first visit starts the ready core command chapter")
	_check(PROGRESS.has_started(save_path), "ready tutorial records its first visit in the isolated save")
	_check(PROGRESS.completed_lessons(save_path).is_empty(), "entering a chapter does not complete it")
	current_scene.exit_to_lobby()
	await session.transition.completed
	_check(current_scene.scene_file_path == session.TUTORIAL_MENU_SCENE, "battle course action returns to the chapter list")
	_check(current_scene.cards.size() == CATALOG.IDS.size(), "all eleven authored chapter cards exist")
	_check(current_scene.get_node("%CoreCards").get_child_count() == 2, "core teaching has exactly two chapters")
	_check(current_scene.get_node("%AdvancedCards").get_child_count() == 9, "advanced teaching has exactly nine exercises")
	var found: Array[String] = []
	for card: Button in current_scene.cards:
		var lesson_id: String = card.get_meta("lesson_id")
		found.append(lesson_id)
		_check(not card.disabled and card.focus_mode == Control.FOCUS_ALL, lesson_id + " remains selectable by pointer and keyboard")
		_check(card.get_node("Margin/Column/Headline/Title").text == CATALOG.title(lesson_id), lesson_id + " title comes from curriculum")
	_check(found == CATALOG.IDS, "chapter cards follow core then advanced curriculum order")
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = resolution
		await create_timer(0.65, true, false, true).timeout
		var menu: Control = current_scene
		_check(menu.get_global_rect().encloses(menu.get_node("%Continue").get_global_rect()), "continue action fits at " + str(resolution))
		for card: Button in menu.cards:
			for child_path: String in ["Margin/Column/Headline", "Margin/Column/Summary", "Margin/Column/Meta"]:
				_check(card.get_global_rect().grow(1.0).encloses(card.get_node(child_path).get_global_rect()), "%s contents fit at %s" % [card.name, resolution])
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("tutorial-chapters-%dx%d.png" % [resolution.x, resolution.y]))
	_check(session.block_war_map_id == map_id and session.block_war_commander == commander and session.block_war_opponent_commander == opponent, "tutorial preserves normal battle selections")
	_check(session.online.room.is_empty(), "tutorial has no online room membership")
	current_scene._back()
	await session.transition.completed
	_check(current_scene.scene_file_path == session.LOBBY_SCENE, "back returns via native transition")
	_check(current_scene.get_node("%Tutorial").has_focus(), "return restores focus to tutorial entry")
	_check(session.start_tutorial() == OK, "repeat entry starts native transition")
	await session.transition.completed
	_check(current_scene.scene_file_path == session.TUTORIAL_MENU_SCENE, "repeat tutorial entry opens the chapter list")
	_check(session.start_tutorial("core_buildings") == OK, "an explicit core chapter can be replayed")
	await session.transition.completed
	_check(current_scene.scene_file_path == session.TUTORIAL_BATTLE_SCENE and current_scene.lesson_id == "core_buildings", "chapter selection starts the requested chapter")
	current_scene.exit_to_lobby()
	await session.transition.completed
	session.tutorial_progress_path = original_path
	_check(DirAccess.remove_absolute(save_path) == OK, "isolated tutorial save is removed")
	print("TUTORIAL_MENU_TEST checks=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)
