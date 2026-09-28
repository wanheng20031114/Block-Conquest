extends Control
## Bot Jump's white arrow, faction outline, name and held-button ring.

var tint := Color("5595ac")
var pressed := false

func setup(nickname: String, color: Color) -> void:
	tint = color
	$Name.text = nickname
	queue_redraw()

func show_at(point: Vector2, down: bool, viewport_size: Vector2) -> void:
	position = point.round()
	pressed = down
	var label: Label = $Name
	label.position = Vector2(19, 15)
	if point.x + 19.0 + label.size.x > viewport_size.x - 10.0:
		label.position.x = -label.size.x - 10.0
	if point.y + 15.0 + label.size.y > viewport_size.y - 10.0:
		label.position.y = -label.size.y - 8.0
	show()
	queue_redraw()

func _draw() -> void:
	var shape := PackedVector2Array([Vector2.ZERO, Vector2(3, 19), Vector2(8, 13), Vector2(16, 13)])
	draw_colored_polygon(shape, Color.WHITE)
	shape.append(Vector2.ZERO)
	draw_polyline(shape, tint, 2.0, true)
	if pressed:
		draw_arc(Vector2(4, 5), 17, 0, TAU, 32, tint, 2.0, true)
