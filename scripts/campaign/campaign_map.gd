extends Control
## Six railway stations; camera browsing never moves the progress train.

const DESIGN_SIZE := Vector2(1600, 900)
const MARKER_OFFSET := Vector2(-38, 22)
const MARKER_BOUNDS := Rect2(88, 166, 1424, 446)
@onready var session: Node = get_node("/root/Session")
@onready var stops: Array[Button] = [%Stage01, %Stage02, %Stage03, %Stage04, %Stage05, %Stage06]
@onready var station_shortcuts: Array[Button] = [%Stop01, %Stop02, %Stop03, %Stop04, %Stop05, %Stop06]
@onready var diorama: SubViewportContainer = %Landscape
var route: Curve2D
var stage_positions: PackedVector2Array
var selected_index := 0
var _dragging := false

func _ready() -> void:
	%MapViewport.resized.connect(_fit_atlas)
	_fit_atlas()
	for index: int in stops.size():
		stops[index].disabled = true
		stops[index].pressed.connect(_select.bind(index))
		station_shortcuts[index].pressed.connect(_select.bind(index))
		station_shortcuts[index].focus_entered.connect(_focus_shortcut.bind(index))
	diorama.intro_finished.connect(_reveal_journey)
	diorama.view_changed.connect(_project_stops)
	%MapInput.gui_input.connect(_map_input)
	%Overview.pressed.connect(func(): diorama.show_overview())
	%ReturnTrain.pressed.connect(_return_to_train)
	%Back.pressed.connect(_back)
	%Settings.pressed.connect(session.settings.open_menu)
	%Previous.pressed.connect(_step.bind(-1))
	%Next.pressed.connect(_step.bind(1))
	%Start.pressed.connect(_start_stage)
	session.campaign_progress_changed.connect(_refresh_progress)
	session.settings.opened.connect(_set_ambient.bind(false))
	session.settings.closed.connect(_set_ambient.bind(true))
	session.load_failed.connect(_show_error)
	for section: Control in [%Navigation, %Pager, %Actions, %CameraControls, %StationShortcuts]:
		UIMotion.bind_menu_buttons(section)
		session.get_node("UIFeedback").bind_buttons(section)
	selected_index = clampi(int(session.get_meta("campaign_selected_stage", session.campaign_current_stage())), 0, stops.size() - 1)

func _reveal_journey() -> void:
	for stop: Button in stops:
		stop.disabled = false
	%IntroHint.hide()
	%Stops.show()
	%Details.show()
	%Footer.show()
	%StationShortcuts.show()
	%CameraControls.show()
	%ExploreHint.show()
	_refresh_progress()
	_select(selected_index, false, false)
	_project_stops()
	UIMotion.reveal_menu(%Details, Vector2(0, 8), 0.08)
	UIMotion.reveal_menu(%Footer, Vector2(0, 8), 0.12)
	station_shortcuts[selected_index].grab_focus(true)

func _process(_delta: float) -> void:
	# Keep GUI projection current after the scene tree flushes camera transforms.
	if not diorama.intro_running and not session.settings.is_open():
		_project_stops()

func _project_stops() -> void:
	if diorama.intro_running:
		return
	route = diorama.projected_route()
	stage_positions.clear()
	for index: int in stops.size():
		var point: Vector2 = diorama.stage_position(index)
		stage_positions.append(point)
		stops[index].position = point + MARKER_OFFSET
		stops[index].visible = not diorama.camera.is_position_behind(diorama.anchors[index].global_position) and MARKER_BOUNDS.has_point(point)
	%Overview.button_pressed = diorama.overview

func _fit_atlas() -> void:
	%Atlas.scale = %MapViewport.size / DESIGN_SIZE

func _focus_shortcut(index: int) -> void:
	if station_shortcuts[index].has_focus(true) and not session.settings.is_open():
		_select(index)

func _select(index: int, animated: bool = true, move_camera: bool = true) -> void:
	if diorama.intro_running:
		return
	if animated and (session.settings.is_open() or session.transition.busy):
		return
	selected_index = index
	session.set_meta("campaign_selected_stage", index)
	var stage: CampaignStage = stops[index].stage
	for i: int in stops.size():
		stops[i].set_selected(i == index, animated)
		station_shortcuts[i].button_pressed = i == index
	%StageNumber.text = "%02d" % stage.number
	%StageTitle.text = stage.title
	%Region.text = stage.region
	%Description.text = stage.description
	%PageNumber.text = "%02d / 06" % stage.number
	%Previous.disabled = index == 0
	%Next.disabled = index == stops.size() - 1
	_refresh_departure()
	if move_camera:
		diorama.focus_station(index, animated)
	if animated:
		UIMotion.reveal_menu(%Details, Vector2(0, 6))

func _refresh_progress() -> void:
	var current: int = session.campaign_current_stage()
	diorama.park_train(current)
	for index: int in stops.size():
		var available: bool = session.campaign_stage_unlocked(index)
		var cleared: bool = session.campaign_stage_completed(index)
		stops[index].set_progress(available, cleared, index == current)
		var indicator := " · 列车" if index == current else (" · 已过" if cleared else (" · 可玩" if available else " · 未达"))
		station_shortcuts[index].text = "%02d%s" % [index + 1, indicator]
		station_shortcuts[index].tooltip_text = stops[index].tooltip_text
	%Progress.text = "已通过 %02d / 06 站" % session.campaign_completed_count
	%TrainLocation.text = "列车停靠 · " + stops[current].stage.title
	_refresh_departure()

func _refresh_departure() -> void:
	var unlocked: bool = session.campaign_stage_unlocked(selected_index)
	var completed: bool = session.campaign_stage_completed(selected_index)
	%Start.disabled = not unlocked
	%Start.text = "再次挑战  →" if completed else ("进入关卡  →" if unlocked else "尚未抵达")
	if not unlocked:
		%Status.text = "通过第 %02d 站后解锁" % selected_index
	elif completed:
		%Status.text = "已通关 · 可自由重玩，列车保留进度"
	else:
		%Status.text = "当前关卡 · 胜利后前往下一站" if selected_index < 5 else "终点关卡 · 完成最后一战"

func _map_input(event: InputEvent) -> void:
	if diorama.intro_running or session.settings.is_open() or session.transition.busy:
		_dragging = false
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

func _return_to_train() -> void:
	_select(session.campaign_current_stage())

func _start_stage() -> void:
	if diorama.intro_running or session.settings.is_open() or session.transition.busy:
		return
	if not session.campaign_stage_unlocked(selected_index):
		return
	var error: Error = session.start_campaign_stage(selected_index)
	if error != OK:
		_show_error("无法进入关卡，请重试。")

func _step(direction: int) -> void:
	if diorama.intro_running:
		return
	var index := clampi(selected_index + direction, 0, stops.size() - 1)
	_select(index)
	station_shortcuts[index].grab_focus(true)

func _set_ambient(active: bool) -> void:
	_dragging = false
	diorama.set_ambient(active)
	%Snow.speed_scale = 1.0 if active else 0.0
	%Pollen.speed_scale = 1.0 if active else 0.0

func _back() -> void:
	if session.transition.busy or session.settings.is_open():
		return
	session.set_meta("campaign_return_focus", true)
	session.back_to_lobby()

func _unhandled_key_input(event: InputEvent) -> void:
	if session.settings.is_open() or session.transition.busy:
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		if key == KEY_SPACE and diorama.intro_running:
			diorama.skip_intro()
			get_viewport().set_input_as_handled()
			return
		var index := -1
		if key >= KEY_1 and key <= KEY_6:
			index = key - KEY_1
		elif key >= KEY_KP_1 and key <= KEY_KP_6:
			index = key - KEY_KP_1
		if index >= 0:
			diorama.skip_intro()
			_select(index)
			station_shortcuts[index].grab_focus(true)
			get_viewport().set_input_as_handled()

func _show_error(message: String) -> void:
	%Status.text = message
