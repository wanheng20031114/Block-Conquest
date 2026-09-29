extends Control
## Saved native controls edit a draft. Apply is atomic; display changes require an in-game countdown.
var draft: Dictionary = {}
var _refreshing := false
var _resolutions: Array[Vector2i] = []
var _display_previous_focus: Control
@onready var settings: GameSettings = get_parent()
@onready var pages: Control = %Pages

func _ready() -> void:
	UIMotion.bind_buttons(self, true)
	get_node("/root/Session/UIFeedback").bind_buttons(self)
	%WindowMode.add_item("窗口", 0)
	%WindowMode.add_item("无边框全屏", 1)
	%WindowMode.add_item("独占全屏", 2)
	for limit: int in GameSettings.FPS_OPTIONS:
		%FrameLimit.add_item("不限帧数" if limit == 0 else "%d FPS" % limit, limit)
	for tab: Button in %Categories.get_children():
		tab.pressed.connect(show_page.bind(String(tab.name)))
	%WindowMode.item_selected.connect(_option_changed.bind("window_mode"))
	%Resolution.item_selected.connect(_resolution_changed)
	%FrameLimit.item_selected.connect(_fps_changed)
	%Vsync.toggled.connect(_toggle_changed.bind("vsync"))
	%Mute.toggled.connect(_sound_enabled_changed)
	%MusicEnabled.toggled.connect(_toggle_changed.bind("music_enabled"))
	%EdgeScroll.toggled.connect(_toggle_changed.bind("edge_scroll_enabled"))
	%Volume.value_changed.connect(_slider_changed.bind("volume_percent"))
	%MusicVolume.value_changed.connect(_slider_changed.bind("music_volume_percent"))
	%CameraSpeed.value_changed.connect(_slider_changed.bind("camera_speed"))
	%ZoomSpeed.value_changed.connect(_slider_changed.bind("zoom_speed"))
	%RestoreDefaults.pressed.connect(_restore_defaults)
	%Cancel.pressed.connect(settings.close_menu)
	%Close.pressed.connect(settings.close_menu)
	%Apply.pressed.connect(_apply.bind(false))
	%Done.pressed.connect(_apply.bind(true))
	%KeepDisplay.pressed.connect(settings.confirm_display)
	%RevertDisplay.pressed.connect(settings.revert_display)
	show_page("Graphics")

func refresh(values: Dictionary) -> void:
	_refreshing = true
	%DebugShortcut.text = "未绑定"
	for event: InputEvent in InputMap.action_get_events("debug"):
		if event is InputEventKey:
			%DebugShortcut.text = OS.get_keycode_string(event.get_physical_keycode_with_modifiers() if event.physical_keycode != 0 else event.get_keycode_with_modifiers())
			break
	draft = values.duplicate(true)
	%WindowMode.select(int(draft.window_mode))
	_resolutions = [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440)]
	var current := DisplayServer.window_get_size()
	if current.x >= 960 and current.y >= 540 and current not in _resolutions: _resolutions.append(current)
	if draft.resolution not in _resolutions: _resolutions.append(draft.resolution)
	_resolutions.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x if a.x != b.x else a.y < b.y)
	%Resolution.clear()
	for value: Vector2i in _resolutions: %Resolution.add_item("%d × %d" % [value.x, value.y])
	%Resolution.select(_resolutions.find(draft.resolution))
	%FrameLimit.select(GameSettings.FPS_OPTIONS.find(int(draft.fps_limit)))
	%Vsync.set_pressed_no_signal(draft.vsync)
	%Mute.set_pressed_no_signal(not draft.muted)
	%MusicEnabled.set_pressed_no_signal(draft.music_enabled)
	%EdgeScroll.set_pressed_no_signal(draft.edge_scroll_enabled)
	%Volume.set_value_no_signal(draft.volume_percent)
	%MusicVolume.set_value_no_signal(draft.music_volume_percent)
	%CameraSpeed.set_value_no_signal(draft.camera_speed)
	%ZoomSpeed.set_value_no_signal(draft.zoom_speed)
	_update_labels()
	%Status.text = "Esc 返回上层 · 点击「应用」保存设置"
	_refreshing = false

func _uses_menu_motion() -> bool:
	var scene: Node = get_tree().current_scene
	return scene != null and scene.is_in_group("animated_menu")

func open_motion() -> void:
	# The persistent settings layer is shared with battles. Only menu scenes
	# opt into the longer, staggered entrance; battle settings keep their motion.
	if not _uses_menu_motion():
		UIMotion.reveal($Center/Panel)
		return
	UIMotion.reveal_menu($Center/Panel)
	UIMotion.reveal_menu($Center/Panel/Layout/Heading, Vector2.ZERO, 0.025)
	UIMotion.reveal_menu($Center/Panel/Layout/Body/Sidebar, Vector2.ZERO, 0.055)
	UIMotion.reveal_menu($Center/Panel/Layout/Body/Content, Vector2.ZERO, 0.085)
	UIMotion.reveal_menu($Center/Panel/Layout/Actions, Vector2.ZERO, 0.115)

func _update_labels() -> void:
	%Vsync.text = "开启" if draft.vsync else "关闭"
	%Mute.text = "关闭" if draft.muted else "开启"
	%MusicEnabled.text = "开启" if draft.music_enabled else "关闭"
	%EdgeScroll.text = "开启" if draft.edge_scroll_enabled else "关闭"
	%VolumeValue.text = "%d%%" % int(draft.volume_percent)
	%MusicVolumeValue.text = "%d%%" % int(draft.music_volume_percent)
	%CameraValue.text = "%.2f ×" % float(draft.camera_speed)
	%ZoomValue.text = "%.2f ×" % float(draft.zoom_speed)

func _option_changed(index: int, key: String) -> void:
	if not _refreshing: draft[key] = index

func _resolution_changed(index: int) -> void:
	if not _refreshing: draft.resolution = _resolutions[index]

func _fps_changed(index: int) -> void:
	if not _refreshing: draft.fps_limit = GameSettings.FPS_OPTIONS[index]

func _toggle_changed(value: bool, key: String) -> void:
	if _refreshing: return
	draft[key] = value
	_update_labels()

func _sound_enabled_changed(enabled: bool) -> void:
	# The visible switch describes sound being on; persistence stores mute.
	_toggle_changed(not enabled, "muted")

func _slider_changed(value: float, key: String) -> void:
	if _refreshing: return
	draft[key] = value
	get_node("/root/Session/UIFeedback").play(&"ratio")
	_update_labels()

func show_page(page: String) -> void:
	var changed_page: bool = not pages.get_node(page).visible
	for child: Control in pages.get_children():
		child.visible = String(child.name) == page
	for category: Button in %Categories.get_children():
		category.set_pressed_no_signal(String(category.name) == page)
	if visible and changed_page:
		if _uses_menu_motion():
			UIMotion.reveal_menu(%SectionTitle)
			UIMotion.reveal_menu(%SectionHint, Vector2.ZERO, 0.025)
			UIMotion.reveal_menu(pages.get_node(page), Vector2(0, 8), 0.05)
		else:
			UIMotion.reveal(pages.get_node(page), Vector2(0, 8))
	%SectionTitle.text = {"Graphics":"显示", "Audio":"声音", "Controls":"镜头", "Hotkeys":"操作速查"}[page]
	%SectionHint.text = {"Graphics":"显示变更需确认，15 秒后可自动恢复。", "Audio":"总音量与背景音乐可独立调节。", "Controls":"调整镜头的移动、缩放与边缘滚动。", "Hotkeys":"积木战争的键盘与鼠标操作。"}[page]

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if code == KEY_ESCAPE:
		if %DisplayConfirm.visible:
			settings.revert_display()
		else:
			settings.close_menu()
		get_viewport().set_input_as_handled()

func _restore_defaults() -> void:
	refresh(settings.defaults())
	set_status("默认设置已填入，应用后生效。")

func _apply(close_after: bool) -> void:
	settings.apply_preferences(draft, close_after)

func set_status(message: String) -> void:
	%Status.text = message

func show_display_confirmation() -> void:
	_display_previous_focus = get_viewport().gui_get_focus_owner()
	%DisplayConfirm.show()
	if _uses_menu_motion():
		UIMotion.reveal_menu(%DisplayConfirm.get_node("Center/Panel"))
	%KeepDisplay.grab_focus()

func hide_display_confirmation() -> void:
	%DisplayConfirm.hide()
	if is_instance_valid(_display_previous_focus) and _display_previous_focus.is_visible_in_tree():
		_display_previous_focus.grab_focus(true)
	_display_previous_focus = null

func _process(_delta: float) -> void:
	if %DisplayConfirm.visible:
		%DisplayCountdown.text = "是否保留当前显示设置？\n%d 秒后自动恢复。" % ceili(settings.display_timer.time_left)
