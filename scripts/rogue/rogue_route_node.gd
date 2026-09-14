extends Node3D
## A pre-authored miniature node. The graph owns its meaning and accessibility.
signal selected(id: int)
@export var node_id: int = 0
var _available: bool = false
var _current: bool = false

func _ready() -> void:
	$Pick.input_event.connect(_on_input)
	$Pick.mouse_entered.connect(_on_hover.bind(true))
	$Pick.mouse_exited.connect(_on_hover.bind(false))

func configure(data: Dictionary, available: bool, current: bool, chosen: bool) -> void:
	_available = available
	_current = current
	var kind: String = str(data.kind)
	for content: Node3D in $Content.get_children():
		content.hide()
	var content_name: String = {"battle":"Battle", "emergency":"Battle", "shop":"Shop", "event":"Event", "camp":"Camp", "road":"Road"}[kind]
	$Content.get_node(content_name).show()
	$Label.text = RogueCatalog.NODE_NAMES[kind]
	$Label.modulate = Color(0.63,0.72,0.61) if bool(data.completed) else Color(0.94,0.96,0.84)
	$Ring.visible = available or current or chosen
	$Ring.scale = Vector3.ONE * (1.13 if current else 1.0)
	$Flag.text = "驻 扎" if current else ("✓" if bool(data.completed) else ("!" if kind == "emergency" else ""))
	$Flag.modulate = Color(1,0.79,0.38) if current else (Color(0.84,0.37,0.23) if kind == "emergency" else Color(0.58,0.79,0.65))
	$Content.position.y = 0.12 if chosen else 0.0

func _on_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(node_id)

func _on_hover(hovering: bool) -> void:
	$Content.position.y = 0.22 if hovering else 0.0
	$Ring.scale = Vector3.ONE * (1.15 if hovering or _current else 1.0)
