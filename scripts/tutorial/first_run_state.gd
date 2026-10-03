extends RefCounted
## Snapshot first-run eligibility before the Settings child migrates old preferences.

const LEGACY_FILES: PackedStringArray = ["settings.cfg", "campaign.cfg", "tutorial_progress.cfg"]
var pending := false
var _save_path: String

func _init(directory: String = "user://") -> void:
	_save_path = directory.path_join("onboarding.cfg")
	var config := ConfigFile.new()
	var error := config.load(_save_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("首次引导记录无法读取：%s" % error_string(error))
		return
	if error == OK and config.get_value("onboarding", "tutorial_prompt_shown", false) == true:
		return
	for filename: String in LEGACY_FILES:
		if FileAccess.file_exists(directory.path_join(filename)):
			return
	pending = true

func mark_shown() -> Error:
	if not pending:
		return OK
	# A failed disk write must not repeat the prompt after returning to this menu.
	pending = false
	var config := ConfigFile.new()
	config.set_value("onboarding", "tutorial_prompt_shown", true)
	return config.save(_save_path)
