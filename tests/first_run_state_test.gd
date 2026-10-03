extends SceneTree
## First-run persistence uses isolated fixtures and never writes player progress.

const FIRST_RUN_STATE := preload("res://scripts/tutorial/first_run_state.gd")
var checks := 0
var failures: Array[String] = []
var _directories: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _fixture(directory: String) -> String:
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create isolated fixture")
	_directories.append(directory)
	return directory

func _run() -> void:
	var directory := _fixture(ProjectSettings.globalize_path("res://.local/first-run-state-%d" % OS.get_process_id()))
	var fresh_directory := _fixture(directory.path_join("fresh"))
	var fresh := FIRST_RUN_STATE.new(fresh_directory)
	check(fresh.pending, "a new player is eligible for the tutorial recommendation")
	check(not FileAccess.file_exists(fresh_directory.path_join("onboarding.cfg")), "checking eligibility writes no file")
	check(FIRST_RUN_STATE.new(fresh_directory).pending, "unshown recommendation remains eligible on the next launch")
	check(fresh.mark_shown() == OK and not fresh.pending, "actual presentation consumes and saves eligibility")
	var config := ConfigFile.new()
	check(config.load(fresh_directory.path_join("onboarding.cfg")) == OK, "presentation creates a native ConfigFile")
	check(config.get_value("onboarding", "tutorial_prompt_shown", false) == true, "saved marker records presentation")
	check(not FIRST_RUN_STATE.new(fresh_directory).pending, "a later launch does not repeat the recommendation")
	check(fresh.mark_shown() == OK and not fresh.pending, "repeat acknowledgement is harmless")

	for filename: String in FIRST_RUN_STATE.LEGACY_FILES:
		var existing_directory := _fixture(directory.path_join(filename.get_basename()))
		var existing := ConfigFile.new()
		existing.set_value("fixture", "sentinel", filename)
		var existing_path := existing_directory.path_join(filename)
		check(existing.save(existing_path) == OK, "create previous-player fixture: " + filename)
		var before := FileAccess.get_file_as_bytes(existing_path)
		var previous_player := FIRST_RUN_STATE.new(existing_directory)
		check(not previous_player.pending, "existing player is recognized by " + filename)
		check(previous_player.mark_shown() == OK, "ineligible player acknowledgement is harmless")
		check(not FileAccess.file_exists(existing_directory.path_join("onboarding.cfg")), "existing player eligibility creates no marker")
		check(FileAccess.get_file_as_bytes(existing_path) == before, "previous player data is untouched")

	var migration_source := _fixture(directory.path_join("previous_product"))
	var migration_target := _fixture(directory.path_join("new_product"))
	var preferences := ConfigFile.new()
	preferences.set_value("settings", "volume_percent", 37.0)
	check(preferences.save(migration_source.path_join("settings.cfg")) == OK, "create other-product settings fixture")
	var before_migration := FIRST_RUN_STATE.new(migration_target)
	check(UserDataMigration.migrate(migration_source, migration_target) == OK, "settings migration succeeds after eligibility snapshot")
	check(before_migration.pending, "new product retains eligibility after settings migration")
	check(before_migration.mark_shown() == OK, "migrated preferences do not prevent first presentation")
	check(preferences.load(migration_target.path_join("settings.cfg")) == OK and preferences.get_value("settings", "volume_percent") == 37.0, "presentation preserves migrated preferences")

	var unavailable_directory := directory.path_join("missing/child")
	var unavailable := FIRST_RUN_STATE.new(unavailable_directory)
	check(unavailable.pending, "unwritten state begins eligible")
	check(unavailable.mark_shown() != OK, "unwritable save location returns its error")
	check(not unavailable.pending, "save failure still consumes this process's recommendation")
	check(not FileAccess.file_exists(unavailable_directory.path_join("onboarding.cfg")), "save failure creates no success marker")
	check(unavailable.mark_shown() == OK and not unavailable.pending, "save failure never rearms the same instance")
	check(FIRST_RUN_STATE.new(unavailable_directory).pending, "a future launch can retry the unsaved recommendation")
	check(root.get_node("Session").first_run != null, "Session initializes first-run state before menus load")

	# Remove only the exact flat fixture directories created above, children first.
	_directories.reverse()
	for fixture_directory: String in _directories:
		for filename: String in DirAccess.get_files_at(fixture_directory):
			check(DirAccess.remove_absolute(fixture_directory.path_join(filename)) == OK, "remove isolated fixture file")
		check(DirAccess.remove_absolute(fixture_directory) == OK, "remove isolated fixture directory")
	print("FIRST_RUN_STATE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
