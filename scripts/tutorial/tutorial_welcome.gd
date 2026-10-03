extends CanvasLayer
## A scene-authored invitation pointing at the real main-menu tutorial button.
signal dismissed

const FOCUS_LINKS: Array[StringName] = [&"focus_next", &"focus_previous",
	&"focus_neighbor_left", &"focus_neighbor_right", &"focus_neighbor_top", &"focus_neighbor_bottom"]
const FRAME_PADDING := 7.0
const CARD_GAP := 40.0
var active := false
var _target: Button
var _focus_links: Dictionary = {}
@onready var ui: Control = $UI
@onready var dimmer: ColorRect = $UI/Dimmer
@onready var card: PanelContainer = $UI/Card
@onready var skip: Button = %Dismiss

func _ready() -> void:
	hide()
	set_process(false)
	set_process_input(false)
	skip.pressed.connect(dismiss)

func present(target: Button) -> void:
	_target = target
	# Native focus links keep Tab, arrows and gamepad navigation on the two
	# available choices without changing the menu's appearance or button state.
	for property: StringName in FOCUS_LINKS:
		_focus_links[property] = target.get(property)
		target.set(property, target.get_path_to(skip))
		skip.set(property, skip.get_path_to(target))
	active = true
	show()
	_update_layout()
	set_process(true)
	set_process_input(true)
	target.grab_focus(true)

func dismiss() -> void:
	if not active:
		return
	active = false
	hide()
	set_process(false)
	set_process_input(false)
	for property: StringName in FOCUS_LINKS:
		_target.set(property, _focus_links[property])
	_focus_links.clear()
	_target.grab_focus(true)
	dismissed.emit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismiss()

func _process(_delta: float) -> void:
	_update_layout()

func _update_layout() -> void:
	# The first Container pass measures wrapped text before its width settles.
	# Let this free-standing panel shrink to its final native minimum size.
	card.reset_size()
	# Convert through the actual canvas transforms, including the button's
	# focus/hover scale, so the visible frame and click-through area stay aligned.
	var transform := ui.get_global_transform_with_canvas().affine_inverse() * _target.get_global_transform_with_canvas()
	var target_rect: Rect2 = transform * Rect2(Vector2.ZERO, _target.size)
	var frame := target_rect.grow(FRAME_PADDING)
	dimmer.interaction_regions.assign([target_rect])
	var spotlights: Array[Vector4] = []
	spotlights.resize(8)
	spotlights[0] = Vector4(frame.position.x, frame.position.y, frame.size.x, frame.size.y)
	dimmer.material.set_shader_parameter("viewport_size", ui.size)
	dimmer.material.set_shader_parameter("spotlight_count", 1)
	dimmer.material.set_shader_parameter("spotlights", spotlights)
	card.position = Vector2(frame.end.x + CARD_GAP,
		clampf(target_rect.get_center().y - card.size.y * 0.5, 24.0, ui.size.y - card.size.y - 24.0))
