class_name LobbyOutpost
extends Node3D
## Presentation-only buildings: fixed native pick boxes, independent visual motion.
signal touched(outpost: LobbyOutpost)
signal hover_changed(outpost: LobbyOutpost, hovered: bool)
@export var accent := Color("597e65")
var hovered := false
var interactive := true
var reaction := 0.0
var _hover_motion: Tween
var _tap_motion: Tween
var _last_tap := -1.0
@onready var visual: Node3D = $Lift
@onready var flag: MeshInstance3D = $Lift/Model/Flag

func _ready() -> void:
	$Pick.mouse_entered.connect(set_hovered.bind(true))
	$Pick.mouse_exited.connect(set_hovered.bind(false))
	$Pick.input_event.connect(_on_input)
	flag.set_instance_shader_parameter("cloth_color", accent)
	$Lift/Model/Roof.set_instance_shader_parameter("team_tint", accent)

func set_hovered(value: bool) -> void:
	value = value and interactive
	if value == hovered:
		return
	hovered = value
	if _hover_motion != null:
		_hover_motion.kill()
	_hover_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_motion.tween_property(visual, "position:y", 0.16 if value else 0.0, 0.18)
	hover_changed.emit(self, value)

func set_interactive(value: bool) -> void:
	interactive = value
	$Pick.input_ray_pickable = value
	if not value:
		set_hovered(false)

func _on_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if interactive and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tap()

func tap() -> void:
	var now := Time.get_ticks_msec() * 0.001
	if not interactive or now - _last_tap < 0.22:
		return
	_last_tap = now
	if _tap_motion != null:
		_tap_motion.kill()
	# A small nod anchored at ground level, never cumulative squash or rotation.
	_tap_motion = create_tween()
	_tap_motion.tween_property($Lift/Model, "rotation:z", -0.045, 0.065).set_trans(Tween.TRANS_SINE)
	_tap_motion.tween_property($Lift/Model, "rotation:z", 0.018, 0.12).set_trans(Tween.TRANS_SINE)
	_tap_motion.tween_property($Lift/Model, "rotation:z", 0.0, 0.19).set_trans(Tween.TRANS_SINE)
	reaction = 1.0
	touched.emit(self)

func advance(delta: float) -> void:
	reaction = maxf(0.0, reaction - delta * 1.6)
	flag.set_instance_shader_parameter("response", reaction)
