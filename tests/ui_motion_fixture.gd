extends Control
## A native scene callback that must not receive shortcuts beneath a sheet.
var key_presses: int = 0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		key_presses += 1
