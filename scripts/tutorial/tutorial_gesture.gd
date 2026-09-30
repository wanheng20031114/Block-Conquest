extends Control
## The AnimationPlayer owns timing; geometry follows the live screen targets.
## This is a native instructional diagram, not an interactive mouse cursor.

@export_range(0.0, 1.0) var phase := 0.0

@onready var player: AnimationPlayer = $AnimationPlayer
@onready var cursor: Node2D = $Cursor
@onready var mouse: Control = $Mouse
@onready var left_key: Panel = $Mouse/LeftKey
@onready var wheel: Panel = $Mouse/Wheel
@onready var caption: Label = $Caption

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _kind := "drag"
var _current := Vector2.ZERO
var _pressed := false
var _travel := 0.0
var _alpha := 1.0
var _previous_size := Vector2.ZERO


func _ready() -> void:
	_previous_size = size
	resized.connect(_resize_targets)
	hide()


func set_gesture(from: Vector2, to: Vector2, kind: String = "drag") -> void:
	var restart := not visible or kind != _kind
	_from = from
	_to = to
	_kind = kind
	show()
	if restart:
		player.play(&"demonstrate")
		player.seek(0.0, true)
	_update_diagram()


func clear_gesture() -> void:
	player.stop()
	hide()


func gesture_bounds() -> Rect2:
	# Reserve the whole demonstration, including the mouse and its caption.
	# Use the swept area rather than this animation frame, so nearby callouts
	# do not jump as the cursor travels from source to destination.
	var path := Rect2(_from, Vector2.ZERO).expand(_to).expand(_from + Vector2(-26.0, 26.0))
	var bounds := path.grow_individual(56.0, 80.0, 284.0, 84.0)
	if path.end.x + 282.0 > size.x:
		bounds = bounds.expand(Vector2(path.position.x - 254.0, bounds.position.y))
	return bounds.intersection(Rect2(Vector2.ZERO, size))


func _process(_delta: float) -> void:
	if visible:
		_update_diagram()


func _update_diagram() -> void:
	_alpha = minf(clampf(phase / 0.08, 0.0, 1.0), clampf((1.0 - phase) / 0.10, 0.0, 1.0))
	_travel = smoothstep(0.32, 0.69, phase)
	_pressed = phase >= 0.22 and phase < 0.73
	var approach := Vector2(-26.0, 26.0) * (1.0 - smoothstep(0.0, 0.17, phase))
	_current = _from + approach
	var description := "移到起点"
	if _kind == "drag" or _kind == "pan":
		_current = _from.lerp(_to, _travel) + approach
		if phase >= 0.73:
			description = "松开中键" if _kind == "pan" else "松开左键"
		elif phase >= 0.32:
			description = "按住中键拖动" if _kind == "pan" else "按住并拖动"
		elif phase >= 0.22:
			description = "按下中键" if _kind == "pan" else "按下左键"
	elif _kind == "scroll":
		_pressed = false
		description = "滚动滚轮 · 缩放视野"
	else:
		_pressed = phase >= 0.26 and phase < 0.49
		description = "点击左键" if phase >= 0.22 else "移到这里"
	cursor.position = _current
	cursor.scale = Vector2.ONE * (0.90 if _pressed else 1.0)
	cursor.modulate.a = _alpha
	var icon_pos := _current + Vector2(30.0, 20.0)
	if icon_pos.x + 252.0 > size.x:
		icon_pos.x = _current.x - 254.0
	if icon_pos.y + 64.0 > size.y:
		icon_pos.y = _current.y - 72.0
	icon_pos = icon_pos.clamp(Vector2(12.0, 12.0), (size - Vector2(254.0, 58.0)).max(Vector2(12.0, 12.0)))
	mouse.position = icon_pos
	mouse.modulate.a = _alpha
	left_key.modulate = Color(1.0, 0.75, 0.30, 1.0) if _pressed and _kind != "pan" else Color(1.0, 1.0, 1.0, 0.28)
	wheel.position.y = 9.0 + (sin(phase * TAU * 3.0) * 4.0 if _kind == "scroll" else 0.0)
	wheel.modulate = Color(1.0, 0.76, 0.28) if _kind == "scroll" or (_kind == "pan" and _pressed) else Color(0.63, 0.72, 0.63)
	caption.text = description
	caption.position = icon_pos + Vector2(38.0, 10.0)
	caption.modulate.a = _alpha
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var gold := Color(1.0, 0.83, 0.44, _alpha * 0.86)
	var paper := Color(1.0, 0.98, 0.85, _alpha * 0.72)
	if _kind == "drag" or _kind == "pan":
		var distance := _from.distance_to(_to)
		if distance > 1.0:
			var direction := (_to - _from) / distance
			for index: int in int(distance / 20.0):
				var start := _from + direction * (float(index) * 20.0 + 3.0)
				draw_line(start, start + direction * 7.0, Color(paper, paper.a * 0.42), 2.0, true)
			if _travel > 0.0 and phase < 0.82:
				draw_line(_from, _from.lerp(_to, _travel), Color(gold, gold.a * 0.25), 8.0, true)
				draw_line(_from, _from.lerp(_to, _travel), gold, 2.5, true)
			var normal := direction.orthogonal()
			draw_polyline(PackedVector2Array([_to - direction * 10.0 + normal * 6.0, _to, _to - direction * 10.0 - normal * 6.0]), paper, 2.0, true)
		draw_arc(_from, 13.0, 0.0, TAU, 40, paper, 1.5, true)
		draw_arc(_to, 18.0 + sin(phase * TAU) * 2.0, 0.0, TAU, 48, gold, 1.8, true)
	var press_phase := 0.22 if _kind == "drag" or _kind == "pan" else 0.26
	var release_phase := 0.73 if _kind == "drag" or _kind == "pan" else 0.49
	for beat: float in [press_phase, release_phase]:
		var age := (phase - beat) / 0.18
		if age >= 0.0 and age <= 1.0:
			var at := _to if (_kind == "drag" or _kind == "pan") and beat == release_phase else _from
			draw_arc(at, lerpf(10.0, 36.0, age), 0.0, TAU, 48, Color(gold, (1.0 - age) * _alpha * 0.76), 2.0, true)
	if _kind == "scroll":
		var rise := sin(phase * TAU * 3.0) * 4.0
		var at := _current + Vector2(-19.0, rise)
		draw_polyline(PackedVector2Array([at + Vector2(-5.0, -12.0), at + Vector2(0.0, -18.0), at + Vector2(5.0, -12.0)]), gold, 2.0, true)
		draw_polyline(PackedVector2Array([at + Vector2(-5.0, 12.0), at + Vector2(0.0, 18.0), at + Vector2(5.0, 12.0)]), gold, 2.0, true)


func _resize_targets() -> void:
	if _previous_size.x > 0.0 and _previous_size.y > 0.0:
		_from *= size / _previous_size
		_to *= size / _previous_size
	_previous_size = size
