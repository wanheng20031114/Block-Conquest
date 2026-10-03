extends SceneTree
## New visits, completion and legacy saves are checked without loading a battle.

const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	var directory := ProjectSettings.globalize_path("res://.local/tutorial-progress-%d" % OS.get_process_id())
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create isolated fixture directory")
	var save_path := directory.path_join("progress.cfg")
	check(not PROGRESS.has_started(save_path), "new player has not played a tutorial")
	check(PROGRESS.completed_lessons(save_path).is_empty(), "new player has no completed chapters")
	check(PROGRESS.next_lesson(save_path) == "core_command", "new curriculum begins with command chapter")
	check(PROGRESS.mark_completed("invalid", save_path) == ERR_INVALID_PARAMETER, "unknown completion is rejected")
	check(not FileAccess.file_exists(save_path), "read and rejected completion create no file")
	check(PROGRESS.mark_started(save_path) == OK, "ready tutorial records a visit")
	check(PROGRESS.has_started(save_path), "visit survives reloading")
	check(PROGRESS.completed_lessons(save_path).is_empty(), "a visit never completes a chapter")
	check(PROGRESS.mark_started(save_path) == OK, "repeat visit is idempotent")
	check(PROGRESS.mark_completed("house", save_path) == OK, "advanced exercises can complete independently")
	check(PROGRESS.mark_completed("core_command", save_path) == OK, "core chapter completion saves")
	check(PROGRESS.mark_completed("core_command", save_path) == OK, "completed chapters can be replayed")
	check(PROGRESS.completed_lessons(save_path) == PackedStringArray(["core_command", "house"]), "completion is unique and follows curriculum order")
	check(PROGRESS.next_lesson(save_path) == "core_buildings", "continuation prioritizes the second core chapter")
	var before := FileAccess.get_file_as_bytes(save_path)
	check(PROGRESS.mark_started(save_path) == OK and FileAccess.get_file_as_bytes(save_path) == before, "visit tracking preserves existing completion bytes")
	var config := ConfigFile.new()
	check(config.load(save_path) == OK, "save is a native ConfigFile")
	check(config.get_sections() == PackedStringArray(["tutorial"]), "tutorial owns only its own section")

	for legacy_id: String in ["basics", "interface", "house", "morale", "tower", "forge", "energy", "recruit", "drum", "shield", "fire"]:
		config.clear()
		config.set_value("tutorial", "completed_lessons", PackedStringArray([legacy_id]))
		check(config.save(save_path) == OK, "save legacy completion fixture")
		check(PROGRESS.has_started(save_path), "legacy completion counts as prior play: " + legacy_id)
		check(not PROGRESS.is_completed("core_command", save_path) and not PROGRESS.is_completed("core_buildings", save_path), "legacy completion never unlocks new core completion")
		check(PROGRESS.mark_started(save_path) == OK, "legacy visit upgrades save")
		config.load(save_path)
		check(config.get_value("tutorial", "completed_lessons") == PackedStringArray([legacy_id]), "mark_started preserves legacy completion")
		check(PROGRESS.mark_completed("core_command", save_path) == OK, "new core can complete alongside old records")
		config.load(save_path)
		check(config.get_value("tutorial", "completed_lessons").has(legacy_id), "new completion preserves previous legitimate records")

	config.clear()
	config.set_value("tutorial", "completed_lessons", ["house", "unknown", "house", 25, "fire"])
	config.save(save_path)
	check(PROGRESS.completed_lessons(save_path) == PackedStringArray(["house", "fire"]), "unknown, duplicate and non-string completions are filtered")
	config.set_value("tutorial", "completed_lessons", 47)
	config.save(save_path)
	check(PROGRESS.completed_lessons(save_path).is_empty() and not PROGRESS.has_started(save_path), "malformed completion is not a played tutorial")
	check(PROGRESS.mark_started(directory.path_join("missing/progress.cfg")) != OK, "visit save failure is returned to the caller")
	check(PROGRESS.mark_completed("core_command", directory.path_join("missing/progress.cfg")) != OK, "completion save failure is returned to the caller")
	check(DirAccess.remove_absolute(save_path) == OK, "isolated progress file is removed")
	check(DirAccess.remove_absolute(directory) == OK, "isolated fixture directory is removed")
	print("TUTORIAL_PROGRESS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
