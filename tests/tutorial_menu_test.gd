extends SceneTree
## Isolated progress persistence and native menu navigation; never edits user progress.

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
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	var output := ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	var save_path := output.path_join("isolated_progress_%d.cfg" % OS.get_process_id())
	_check(PROGRESS.completed_lessons(save_path).is_empty(), "new player has no completed lessons")
	_check(PROGRESS.mark_completed("invalid", save_path) == ERR_INVALID_PARAMETER, "unknown lessons are rejected")
	_check(not FileAccess.file_exists(save_path), "invalid completion creates no file")
	_check(PROGRESS.mark_completed("house", save_path) == OK, "individual out-of-order lesson can complete")
	_check(PROGRESS.mark_completed("basics", save_path) == OK, "completion saves successfully")
	_check(PROGRESS.mark_completed("basics", save_path) == OK, "replaying a completed lesson is idempotent")
	_check(PROGRESS.completed_lessons(save_path) == PackedStringArray(["basics", "house"]), "saved progress loads uniquely in course order")
	var config := ConfigFile.new()
	_check(config.load(save_path) == OK, "completion is a native ConfigFile")
	_check(config.get_sections() == PackedStringArray(["tutorial"]), "save contains only tutorial completion")
	_check(config.get_section_keys("tutorial") == PackedStringArray(["completed_lessons"]), "save contains no battle or settings state")
	config.set_value("tutorial", "completed_lessons", ["house", "unknown", "house", 25, "fire"])
	config.save(save_path)
	_check(PROGRESS.completed_lessons(save_path) == PackedStringArray(["house", "fire"]), "unknown, duplicate and non-string data is filtered")
	config.set_value("tutorial", "completed_lessons", 47)
	config.save(save_path)
	_check(PROGRESS.completed_lessons(save_path).is_empty(), "malformed completion values do not block the tutorial")
	_check(DirAccess.remove_absolute(save_path) == OK, "isolated save is cleaned up")
	var session: Node = root.get_node("Session")
	var map_id: String = session.block_war_map_id
	var commander: StringName = session.block_war_commander
	var opponent: StringName = session.block_war_opponent_commander
	paused = true
	_check(session.start_tutorial("invalid") == ERR_INVALID_PARAMETER, "invalid lesson cannot start")
	_check(paused, "invalid start does not disturb paused state")
	paused = false
	session.transition.busy = true
	_check(session.start_tutorial() == ERR_BUSY, "transition blocks duplicate start requests")
	session.transition.busy = false
	_check(change_scene_to_file("res://scenes/lobby.tscn") == OK, "lobby loads")
	await scene_changed
	_check(current_scene.get_node("%Tutorial").text == "入门教程    →", "main menu has tutorial entry")
	_check(session.start_tutorial() == OK, "native transition enters lesson menu")
	await session.transition.completed
	_check(current_scene.scene_file_path == session.TUTORIAL_MENU_SCENE, "lesson menu is the current scene")
	_check(current_scene.cards.size() == CATALOG.IDS.size(), "all eleven authored cards exist")
	var found: Array[String] = []
	for card: Button in current_scene.cards:
		var lesson_id: String = card.get_meta("lesson_id")
		found.append(lesson_id)
		_check(not card.disabled and card.focus_mode == Control.FOCUS_ALL, lesson_id + " remains selectable by pointer and keyboard")
		_check(card.get_node("Margin/Column/Headline/Title").text == CATALOG.title(lesson_id), lesson_id + " title comes from curriculum")
	found.sort()
	var expected: Array[String] = CATALOG.IDS.duplicate()
	expected.sort()
	_check(found == expected, "menu has each curriculum lesson exactly once")
	_check(session.block_war_map_id == map_id and session.block_war_commander == commander and session.block_war_opponent_commander == opponent, "tutorial preserves normal battle selections")
	_check(session.online.room.is_empty(), "tutorial has no online room membership")
	current_scene._back()
	await session.transition.completed
	_check(current_scene.scene_file_path == session.LOBBY_SCENE, "back returns via native transition")
	_check(current_scene.get_node("%Tutorial").has_focus(), "return restores focus to tutorial entry")
	print("TUTORIAL_MENU_TEST checks=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)
