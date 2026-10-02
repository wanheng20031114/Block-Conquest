extends Control
## Six stops projected from an authored block-built 3D landscape.

const DESIGN_SIZE := Vector2(1600, 900)
@onready var session: Node = get_node("/root/Session")
@onready var stops: Array[Button] = [%Stage01, %Stage02, %Stage03, %Stage04, %Stage05, %Stage06]
@onready var diorama: SubViewportContainer = %Landscape
var route: Curve2D
var stage_positions: PackedVector2Array
var selected_index := 0
var _travel: Tween

func _ready() -> void:
	%MapViewport.resized.connect(_fit_atlas)
	_fit_atlas()
	route = diorama.projected_route()
	%Journey.curve = route
	%RouteShadow.points = route.get_baked_points()
	%Route.points = route.get_baked_points()
	for index: int in stops.size():
		var stop := stops[index]
		stage_positions.append(diorama.stage_position(index))
		stop.position = stage_positions[index] - Vector2(38, 66)
		stop.pressed.connect(_select.bind(index))
		stop.focus_entered.connect(_focus_stop.bind(index))
	%Back.pressed.connect(_back)
	%Settings.pressed.connect(session.settings.open_menu)
	%Previous.pressed.connect(_step.bind(-1))
	%Next.pressed.connect(_step.bind(1))
	session.settings.opened.connect(_set_ambient.bind(false))
	session.settings.closed.connect(_set_ambient.bind(true))
	session.load_failed.connect(_show_error)
	UIMotion.bind_menu_buttons(%Navigation)
	UIMotion.bind_menu_buttons(%Pager)
	session.get_node("UIFeedback").bind_buttons(%Navigation)
	session.get_node("UIFeedback").bind_buttons(%Pager)
	_select(clampi(int(session.get_meta("campaign_selected_stage", 0)), 0, stops.size() - 1), false)
	stops[selected_index].grab_focus(true)

func _fit_atlas() -> void:
	%Atlas.scale = %MapViewport.size / DESIGN_SIZE

func _focus_stop(index: int) -> void:
	if stops[index].has_focus(true) and not session.settings.is_open():
		_select(index)

func _select(index: int, animated: bool = true) -> void:
	if session.settings.is_open() or session.transition.busy:
		# Initial setup also runs beneath the shared scene transition.
		if animated:
			return
	selected_index = index
	session.set_meta("campaign_selected_stage", index)
	var stage: CampaignStage = stops[index].stage
	for i: int in stops.size():
		stops[i].set_selected(i == index, animated)
	%StageNumber.text = "%02d" % stage.number
	%StageTitle.text = stage.title
	%Region.text = stage.region
	%Description.text = stage.description
	%PageNumber.text = "%02d / 06" % stage.number
	%Previous.disabled = index == 0
	%Next.disabled = index == stops.size() - 1
	var destination := route.get_closest_offset(stage_positions[index])
	if _travel and _travel.is_valid():
		_travel.kill()
	if animated:
		_travel = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_travel.tween_property(%Traveler, "progress", destination, 0.38)
		UIMotion.reveal_menu(%Details, Vector2(0, 6))
	else:
		%Traveler.progress = destination

func _step(direction: int) -> void:
	var index := clampi(selected_index + direction, 0, stops.size() - 1)
	_select(index)
	stops[index].grab_focus(true)

func _set_ambient(active: bool) -> void:
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
		var index := -1
		if key >= KEY_1 and key <= KEY_6:
			index = key - KEY_1
		elif key >= KEY_KP_1 and key <= KEY_KP_6:
			index = key - KEY_KP_1
		if index >= 0:
			_select(index)
			stops[index].grab_focus(true)
			get_viewport().set_input_as_handled()

func _show_error(message: String) -> void:
	%Status.text = message
