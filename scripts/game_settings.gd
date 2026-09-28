class_name GameSettings
extends CanvasLayer
## Independent display, sound and camera preferences for 积木战争.
signal changed
signal opened
signal closed

const FPS_OPTIONS: Array[int] = [30, 60, 90, 120, 144, 165, 240, 0]
const DEFAULT_VOLUME_PERCENT := 50.0
const DEFAULT_MUSIC_VOLUME_PERCENT := 50.0
const PAN_ACTIONS := {"war_pan_left": KEY_LEFT, "war_pan_right": KEY_RIGHT,
	"war_pan_up": KEY_UP, "war_pan_down": KEY_DOWN}
var settings_path := "user://settings.cfg"
var edge_scroll_enabled := true
var camera_speed := 1.0
var zoom_speed := 1.0
var volume_percent := DEFAULT_VOLUME_PERCENT
var muted := false
var music_enabled := true
var music_volume_percent := DEFAULT_MUSIC_VOLUME_PERCENT
var window_mode := 0
var resolution := Vector2i(1600, 900)
var vsync := true
var fps_limit := 120
var _display_previous: Dictionary = {}
var _previous_window: Dictionary = {}
var _close_after_confirm := false
var _previous_focus: WeakRef
@onready var menu: Control = $Menu
@onready var display_timer: Timer = $DisplayRevertTimer

func _enter_tree() -> void:
	if settings_path != "user://settings.cfg":
		return
	var current_directory := OS.get_user_data_dir()
	var previous_directory := current_directory.get_base_dir().path_join(UserDataMigration.PREVIOUS_PROJECT_DIRECTORY)
	var error := UserDataMigration.migrate(previous_directory, current_directory)
	if error != OK:
		push_warning("积木战争：旧版通用设置迁移失败，错误码 %d" % error)

func _ready() -> void:
	menu.hide()
	var values := defaults()
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		for key: String in values:
			values[key] = config.get_value("settings", key, values[key])
	for action: String in PAN_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode = PAN_ACTIONS[action]
		InputMap.action_add_event(action, event)
	_apply_values(_sanitize(values), false)
	if DisplayServer.get_name() != "headless" and not _automated_launch():
		_apply_display()
	display_timer.timeout.connect(revert_display)

func _automated_launch() -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	return args.has("--script") or args.has("--position") or args.has("--editor") or args.has("--capture")

func defaults() -> Dictionary:
	return {"edge_scroll_enabled": true, "camera_speed": 1.0, "zoom_speed": 1.0,
		"volume_percent": DEFAULT_VOLUME_PERCENT, "muted": false, "window_mode": 0,
		"music_enabled": true, "music_volume_percent": DEFAULT_MUSIC_VOLUME_PERCENT,
		"resolution": Vector2i(1600, 900), "vsync": true, "fps_limit": 120}

func snapshot() -> Dictionary:
	return {"edge_scroll_enabled": edge_scroll_enabled, "camera_speed": camera_speed, "zoom_speed": zoom_speed,
		"volume_percent": volume_percent, "muted": muted, "window_mode": window_mode,
		"music_enabled": music_enabled, "music_volume_percent": music_volume_percent,
		"resolution": resolution, "vsync": vsync, "fps_limit": fps_limit}

func _sanitize(values: Dictionary) -> Dictionary:
	var result := defaults()
	for key: String in ["edge_scroll_enabled", "muted", "music_enabled", "vsync"]:
		if values.get(key) is bool:
			result[key] = values[key]
	for key: String in ["camera_speed", "zoom_speed", "volume_percent", "music_volume_percent"]:
		var value: Variant = values.get(key)
		if (value is float or value is int) and is_finite(float(value)):
			result[key] = clampf(float(value), 0.25, 3.0) if key.ends_with("speed") else clampf(float(value), 0.0, 100.0)
	if values.get("window_mode") is int and values.window_mode in [0, 1, 2]:
		result.window_mode = values.window_mode
	if values.get("fps_limit") is int and values.fps_limit in FPS_OPTIONS:
		result.fps_limit = values.fps_limit
	if values.get("resolution") is Vector2i:
		var requested: Vector2i = values.resolution
		if requested.x >= 960 and requested.y >= 540 and requested.x <= 7680 and requested.y <= 4320:
			result.resolution = requested
	return result

func _apply_values(values: Dictionary, display: bool) -> void:
	for key: String in values:
		set(key, values[key])
	Engine.max_fps = fps_limit
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume_percent / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, muted)
	var music_bus := AudioServer.get_bus_index(&"BGM")
	AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(music_volume_percent / 100.0, 0.0001)))
	AudioServer.set_bus_mute(music_bus, not music_enabled or music_volume_percent <= 0.0)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		if display:
			_apply_display()
	changed.emit()

func _apply_display() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_size(resolution)
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(usable.position + (usable.size - resolution).max(Vector2i.ZERO) / 2)
	if window_mode == 1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif window_mode == 2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	# Fullscreen windows follow the monitor; this choice controls native 3D render resolution.
	var actual := DisplayServer.window_get_size()
	get_tree().root.scaling_3d_scale = minf(float(resolution.x) / maxf(actual.x, 1), float(resolution.y) / maxf(actual.y, 1)) if window_mode != 0 else 1.0

func open_menu() -> void:
	if is_open():
		return
	var focused := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focused) if focused != null else null
	menu.refresh(snapshot())
	menu.show()
	menu.open_motion()
	menu.get_node("%Close").grab_focus(true)
	opened.emit()

func close_menu() -> void:
	if not is_open(): return
	if not _display_previous.is_empty(): revert_display()
	menu.hide()
	closed.emit()
	# The caller may have left its scene while the shared settings layer was up.
	var previous: Control = _previous_focus.get_ref() if _previous_focus != null else null
	_previous_focus = null
	if is_instance_valid(previous) and previous.is_visible_in_tree() and previous.get_focus_mode_with_override() != Control.FOCUS_NONE:
		if not previous is BaseButton or not previous.disabled:
			previous.grab_focus(true)

func is_open() -> bool:
	return menu.visible

func apply_preferences(values: Dictionary, close_after: bool = false) -> void:
	if not _display_previous.is_empty(): return
	var candidate := _sanitize(values)
	var display_changed: bool = candidate.window_mode != window_mode or candidate.resolution != resolution
	_close_after_confirm = close_after
	if display_changed:
		_display_previous = snapshot()
		_previous_window = {"position": DisplayServer.window_get_position(), "size": DisplayServer.window_get_size(), "scale": get_tree().root.scaling_3d_scale}
	_apply_values(candidate, display_changed)
	if display_changed:
		display_timer.start(15.0)
		menu.show_display_confirmation()
	else:
		var error := _save()
		menu.refresh(snapshot())
		menu.set_status("设置已保存。" if error == OK else "设置保存失败，请检查目录写入权限。")
		if close_after and error == OK: close_menu()

func confirm_display() -> void:
	if _display_previous.is_empty(): return
	display_timer.stop()
	_display_previous.clear()
	_previous_window.clear()
	var error := _save()
	menu.hide_display_confirmation()
	menu.refresh(snapshot())
	if error != OK: menu.set_status("设置保存失败，请检查目录写入权限。")
	if _close_after_confirm and error == OK: close_menu()

func revert_display() -> void:
	if _display_previous.is_empty(): return
	display_timer.stop()
	_apply_values(_display_previous, true)
	if DisplayServer.get_name() != "headless" and window_mode == 0:
		DisplayServer.window_set_size(_previous_window.size)
		DisplayServer.window_set_position(_previous_window.position)
		get_tree().root.scaling_3d_scale = _previous_window.scale
	_display_previous.clear()
	_previous_window.clear()
	menu.hide_display_confirmation()
	menu.refresh(snapshot())
	menu.set_status("已恢复先前设置。")

func _save() -> Error:
	var config := ConfigFile.new()
	for key: String in snapshot():
		config.set_value("settings", key, get(key))
	var error := config.save(settings_path)
	if error != OK:
		menu.set_status("设置保存失败，请检查目录写入权限。")
	return error

func set_volume_percent(value: float) -> void:
	volume_percent = clampf(value, 0, 100)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume_percent / 100.0, 0.0001)))
	_save()
	changed.emit()

func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, value)
	_save()
	changed.emit()

func toggle_fullscreen() -> void:
	# A deliberate hotkey toggles the remembered mode through the same native
	# display application as the settings page, keeping the two interfaces in sync.
	window_mode = 1 if window_mode == 0 else 0
	if DisplayServer.get_name() != "headless":
		_apply_display()
	_save()
	changed.emit()
