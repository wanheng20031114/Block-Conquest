extends Button
## Scene-authored native button; only its transparent outline is animated.
## HUD uses set_pressed_no_signal(), so native redraw observes both keyboard
## updates and ButtonGroup mouse changes without adding a frame polling loop.

const FILL_DURATION := 0.22
const RELEASE_DURATION := 0.065

@export_range(1, 4) var shortcut_number: int = 2

@onready var outline: ColorRect = $Outline
@onready var key_hint: Label = $Shortcut

var _selected := false
var _transition: Tween
var _phase := 1.0:
	set(value):
		_phase = value
		outline.set_instance_shader_parameter(&"phase", value)
var _selection := 0.0:
	set(value):
		_selection = value
		outline.set_instance_shader_parameter(&"selection", value)


func _ready() -> void:
	key_hint.text = "[%d]" % shortcut_number
	_selected = button_pressed
	_selection = 1.0 if _selected else 0.0
	_phase = 1.0
	resized.connect(_resize_outline)
	visibility_changed.connect(_visibility_changed)
	tree_exiting.connect(_stop_transition)
	_resize_outline()


func _draw() -> void:
	if not is_node_ready():
		return
	outline.set_instance_shader_parameter(&"hover_amount", 1.0 if is_hovered() and not disabled else 0.0)
	outline.set_instance_shader_parameter(&"focus_amount", 1.0 if has_focus(true) else 0.0)
	outline.set_instance_shader_parameter(&"availability", 0.42 if disabled else 1.0)
	if disabled:
		_settle()
	elif button_pressed != _selected:
		_selected = button_pressed
		_stop_transition()
		_transition = create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		if _selected:
			_selection = 1.0
			_phase = 0.0
			_transition.tween_property(self, "_phase", 1.0, FILL_DURATION)
		else:
			_transition.tween_property(self, "_selection", 0.0, RELEASE_DURATION)
			_transition.tween_callback(func(): _phase = 1.0)


func _resize_outline() -> void:
	outline.set_instance_shader_parameter(&"frame_size", size)


func _visibility_changed() -> void:
	if is_node_ready() and not is_visible_in_tree():
		_settle()


func _settle() -> void:
	_stop_transition()
	_selected = button_pressed
	_selection = 1.0 if _selected else 0.0
	_phase = 1.0


func _stop_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null
