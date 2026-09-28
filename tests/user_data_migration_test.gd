extends SceneTree
## Copy only common preferences into the independent product's user directory.
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	var directory := ProjectSettings.globalize_path("res://.local/war-migration-%d" % OS.get_process_id())
	var previous := directory.path_join("previous")
	var current := directory.path_join("current")
	assert(DirAccess.make_dir_recursive_absolute(previous) == OK)
	assert(DirAccess.make_dir_recursive_absolute(current) == OK)
	var old := ConfigFile.new()
	old.set_value("settings", "volume_percent", 37.0)
	old.set_value("settings", "music_enabled", false)
	old.set_value("settings", "camera_speed", 1.45)
	old.set_value("settings", "resolution", Vector2i(1920, 1080))
	old.set_value("settings", "fp_sensitivity", 2.8)
	old.set_value("hotkeys", "rts_select_army", [KEY_J])
	check(old.save(previous.path_join("settings.cfg")) == OK, "legacy preference fixture saves")
	var identity := ConfigFile.new()
	identity.set_value("lobby", "nickname", "旧指挥官")
	check(identity.save(previous.path_join("lobby_preferences.cfg")) == OK, "legacy lobby fixture saves")
	check(UserDataMigration.migrate(previous, current) == OK, "initial standalone migration succeeds")
	var migrated := ConfigFile.new()
	check(migrated.load(current.path_join("settings.cfg")) == OK, "independent settings file is created")
	check(migrated.get_value("settings", "volume_percent") == 37.0 and not migrated.get_value("settings", "music_enabled"), "audio preferences migrate unchanged")
	check(migrated.get_value("settings", "camera_speed") == 1.45 and migrated.get_value("settings", "resolution") == Vector2i(1920, 1080), "camera and typed display preferences migrate unchanged")
	check(not migrated.has_section_key("settings", "fp_sensitivity") and not migrated.has_section("hotkeys"), "other product's first-person and RTS key settings are excluded")
	check(not FileAccess.file_exists(current.path_join("lobby_preferences.cfg")), "lobby identity is not copied")
	migrated.set_value("settings", "volume_percent", 64.0)
	check(migrated.save(current.path_join("settings.cfg")) == OK, "independent preference fixture saves")
	check(UserDataMigration.migrate(previous, current) == OK, "repeat startup succeeds")
	migrated.load(current.path_join("settings.cfg"))
	check(migrated.get_value("settings", "volume_percent") == 64.0, "existing independent settings win")
	old.load(previous.path_join("settings.cfg"))
	check(old.get_value("settings", "volume_percent") == 37.0 and old.has_section("hotkeys"), "migration leaves the original product's preferences intact")
	check(UserDataMigration.migrate(directory.path_join("missing"), current) == OK, "fresh install does not require the previous product")
	# Only the exact two flat fixture directories created by this test are removed.
	for folder: String in [previous, current]:
		for filename: String in DirAccess.get_files_at(folder):
			check(DirAccess.remove_absolute(folder.path_join(filename)) == OK, "test file cleanup")
		check(DirAccess.remove_absolute(folder) == OK, "test directory cleanup")
	check(DirAccess.remove_absolute(directory) == OK, "test root cleanup")
	print("USER_DATA_MIGRATION_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
