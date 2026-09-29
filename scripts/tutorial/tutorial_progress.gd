extends RefCounted
## Tutorial completion is separate from battle preferences and multiplayer data.

const CATALOG := preload("res://scripts/tutorial/tutorial_catalog.gd")
const SAVE_PATH := "user://tutorial_progress.cfg"

static func completed_lessons(save_path: String = SAVE_PATH) -> PackedStringArray:
	var config := ConfigFile.new()
	var error := config.load(save_path)
	if error == ERR_FILE_NOT_FOUND:
		return PackedStringArray()
	if error != OK:
		push_warning("教程进度无法读取：%s" % error_string(error))
		return PackedStringArray()
	var saved: Variant = config.get_value("tutorial", "completed_lessons", PackedStringArray())
	if not saved is PackedStringArray and not saved is Array:
		return PackedStringArray()
	var completed := PackedStringArray()
	for lesson_id: String in CATALOG.IDS:
		if saved.has(lesson_id):
			completed.append(lesson_id)
	return completed

static func is_completed(lesson_id: String) -> bool:
	return completed_lessons().has(lesson_id)

static func mark_completed(lesson_id: String, save_path: String = SAVE_PATH) -> Error:
	if not CATALOG.IDS.has(lesson_id):
		return ERR_INVALID_PARAMETER
	var completed := completed_lessons(save_path)
	if completed.has(lesson_id):
		return OK
	completed.append(lesson_id)
	var config := ConfigFile.new()
	config.set_value("tutorial", "completed_lessons", completed)
	return config.save(save_path)

static func next_lesson() -> String:
	var completed := completed_lessons()
	for lesson_id: String in CATALOG.IDS:
		if not completed.has(lesson_id):
			return lesson_id
	return ""
