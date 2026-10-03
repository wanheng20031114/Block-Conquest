extends Control
## The railway fills the viewport; only its station markers sit above the map.

const MARKER_OFFSET := Vector2(-38, 22)
@onready var session: Node = get_node("/root/Session")
@onready var stops: Array[Button] = [%Stage01, %Stage02, %Stage03, %Stage04, %Stage05, %Stage06]
@onready var diorama: SubViewportContainer = %Landscape
var selected_index := 0
var _dragging := false
var _previous_content_aspect: Window.ContentScaleAspect

func _ready() -> void:
	# The railway expands with the window instead of inheriting menu letterboxing.
	_previous_content_aspect = get_window().content_scale_aspect
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for index: int in stops.size():
		stops[index].disabled = true
		stops[index].pressed.connect(_activate_station.bind(index))
	diorama.intro_finished.connect(_reveal_journey)
	diorama.view_changed.connect(_project_stops)
	%MapInput.gui_input.connect(_map_input)
	%Back.pressed.connect(_back)
	%Settings.pressed.connect(_open_settings)
	%ReturnTrain.pressed.connect(_return_to_train)
	session.get_node("UIFeedback").bind_buttons(%MapActions)
	session.campaign_progress_changed.connect(_refresh_progress)
	session.settings.opened.connect(_sync_ambient)
	session.settings.closed.connect(_sync_ambient)
	session.load_failed.connect(_show_error)
	%LoadError.visibility_changed.connect(_sync_ambient)
	selected_index = clampi(int(session.get_meta("campaign_selected_stage", session.campaign_current_stage())), 0, stops.size() - 1)
	diorama.focus_station(selected_index, false)

func _exit_tree() -> void:
	get_window().content_scale_aspect = _previous_content_aspect

func _reveal_journey() -> void:
	for stop: Button in stops:
		stop.disabled = false
	%Stops.show()
	_refresh_progress()
	_select(selected_index, false, false)
	_project_stops()

func _process(_delta: float) -> void:
	# Camera transforms are flushed after the native viewport has resized.
	if not diorama.intro_running and not session.settings.is_open():
		_project_stops()

func _project_stops() -> void:
	if diorama.intro_running:
		return
	var viewport_rect := Rect2(Vector2.ZERO, %MapViewport.size)
	for index: int in stops.size():
		var point: Vector2 = diorama.stage_position(index)
		stops[index].position = point + MARKER_OFFSET
		stops[index].visible = not diorama.camera.is_position_behind(diorama.anchors[index].global_position) and viewport_rect.has_point(point)

func _select(index: int, animated: bool = true, move_camera: bool = true) -> void:
	if diorama.intro_running or (animated and _navigation_blocked()):
		return
	selected_index = index
	session.set_meta("campaign_selected_stage", index)
	for i: int in stops.size():
		stops[i].set_selected(i == index, animated)
	if move_camera:
		diorama.focus_station(index, animated)

func _activate_station(index: int) -> void:
	if diorama.intro_running or _navigation_blocked():
		return
	var available: bool = session.campaign_stage_unlocked(index)
	_select(index, true, not available)
	if available:
		_start_stage()

func _refresh_progress() -> void:
	var current: int = session.campaign_current_stage()
	diorama.park_train(current)
	for index: int in stops.size():
		stops[index].set_progress(session.campaign_stage_unlocked(index), session.campaign_stage_completed(index), index == current)

func _map_input(event: InputEvent) -> void:
	if diorama.intro_running or _navigation_blocked():
		_end_drag()
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
			%MapInput.mouse_default_cursor_shape = Control.CURSOR_DRAG if _dragging else Control.CURSOR_MOVE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			diorama.zoom_view(-event.factor if event.button_index == MOUSE_BUTTON_WHEEL_UP else event.factor)
	elif event is InputEventMouseMotion and _dragging:
		diorama.pan_view(event.relative)
	%MapInput.accept_event()

func _input(event: InputEvent) -> void:
	# Releasing over a marker must also end a drag that began on the map.
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		_end_drag()

func _end_drag() -> void:
	_dragging = false
	%MapInput.mouse_default_cursor_shape = Control.CURSOR_MOVE

func _start_stage() -> void:
	if diorama.intro_running or _navigation_blocked():
		return
	if not session.campaign_stage_unlocked(selected_index):
		return
	var error: Error = session.start_campaign_stage(selected_index)
	if error != OK:
		_show_error("无法进入关卡，请重试。")

func _step(direction: int) -> void:
	diorama.skip_intro()
	_select(clampi(selected_index + direction, 0, stops.size() - 1))

func _return_to_train() -> void:
	if _navigation_blocked():
		return
	diorama.skip_intro()
	_select(session.campaign_current_stage())

func _open_settings() -> void:
	if not _navigation_blocked():
		session.settings.open_menu()

func _sync_ambient() -> void:
	_end_drag()
	diorama.set_ambient(not session.settings.is_open() and not %LoadError.visible)

func _navigation_blocked() -> bool:
	return session.settings.is_open() or session.transition.busy or %LoadError.visible

func _back() -> void:
	if _navigation_blocked():
		return
	session.set_meta("campaign_return_focus", true)
	session.back_to_lobby()

func _unhandled_key_input(event: InputEvent) -> void:
	if _navigation_blocked() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
	elif event.keycode == KEY_P or event.is_action_pressed("pause"):
		_open_settings()
	elif event.keycode == KEY_HOME:
		_return_to_train()
	elif event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_start_stage()
	elif event.keycode == KEY_SPACE and diorama.intro_running:
		diorama.skip_intro()
	else:
		var index := -1
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			index = event.keycode - KEY_1
		elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_6:
			index = event.keycode - KEY_KP_1
		if index < 0:
			return
		diorama.skip_intro()
		_select(index)
	get_viewport().set_input_as_handled()

func _show_error(message: String) -> void:
	%LoadError.dialog_text = message
	%LoadError.popup_centered()
