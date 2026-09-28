class_name UserDataMigration
extends RefCounted
## The standalone game inherits common preferences once, never another game's
## room identity, first-person options, input bindings, or saved progress.
const PREVIOUS_PROJECT_DIRECTORY := "积木争霸"
const SETTINGS_KEYS: PackedStringArray = ["edge_scroll_enabled", "camera_speed", "zoom_speed",
	"volume_percent", "muted", "music_enabled", "music_volume_percent", "window_mode",
	"resolution", "vsync", "fps_limit"]

static func migrate(previous_directory: String, current_directory: String) -> Error:
	var source := previous_directory.path_join("settings.cfg")
	var destination := current_directory.path_join("settings.cfg")
	if FileAccess.file_exists(destination) or not FileAccess.file_exists(source):
		return OK
	var previous := ConfigFile.new()
	var error := previous.load(source)
	if error != OK:
		return error
	var current := ConfigFile.new()
	for key: String in SETTINGS_KEYS:
		if previous.has_section_key("settings", key):
			current.set_value("settings", key, previous.get_value("settings", key))
	return current.save(destination)
