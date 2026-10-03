extends RefCounted
## Tutorial visits and completion share a file, separate from battle preferences.

const CATALOG := preload("res://scripts/tutorial/tutorial_catalog.gd")
const SAVE_PATH := "user://tutorial_progress.cfg"
const LEGACY_IDS: PackedStringArray = ["basics", "interface"]

static func completed_lessons(save_path: String = SAVE_PATH) -> PackedStringArray:
	var config := ConfigFile.new()
	var error := config.load(save_path)
	if error == ERR_FILE_NOT_FOUND:
		return PackedStringArray()
	if error != OK:
		push_warning("教程进度无法读取：%s" % error_string(error))
		return PackedStringArray()
	return _completed_in(config, false)

static func _completed_in(config: ConfigFile, preserve_legacy: bool) -> PackedStringArray:
	var saved: Variant = config.get_value("tutorial", "completed_lessons", PackedStringArray())
	if not saved is PackedStringArray and not saved is Array:
		return PackedStringArray()
	var completed := PackedStringArray()
	for lesson_id: String in CATALOG.IDS:
		if saved.has(lesson_id):
			completed.append(lesson_id)
	if preserve_legacy:
		for lesson_id: String in LEGACY_IDS:
			if saved.has(lesson_id):
				completed.append(lesson_id)
	return completed

static func is_completed(lesson_id: String, save_path: String = SAVE_PATH) -> bool:
	return completed_lessons(save_path).has(lesson_id)

static func has_started(save_path: String = SAVE_PATH) -> bool:
	var config := ConfigFile.new()
	var error := config.load(save_path)
	if error == ERR_FILE_NOT_FOUND:
		return false
	if error != OK:
		push_warning("教程进度无法读取：%s" % error_string(error))
		return false
	return config.get_value("tutorial", "started", false) == true or not _completed_in(config, true).is_empty()

static func mark_started(save_path: String = SAVE_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(save_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	if config.get_value("tutorial", "started", false) == true:
		return OK
	config.set_value("tutorial", "started", true)
	return config.save(save_path)

static func mark_completed(lesson_id: String, save_path: String = SAVE_PATH) -> Error:
	if not CATALOG.IDS.has(lesson_id):
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	var error := config.load(save_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	var completed := _completed_in(config, true)
	if completed.has(lesson_id):
		return OK
	completed.append(lesson_id)
	config.set_value("tutorial", "started", true)
	config.set_value("tutorial", "completed_lessons", completed)
	return config.save(save_path)

static func next_lesson(save_path: String = SAVE_PATH) -> String:
	var completed := completed_lessons(save_path)
	for lesson_id: String in CATALOG.IDS:
		if not completed.has(lesson_id):
			return lesson_id
	return ""
