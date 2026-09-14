extends Control
## A native scene callback that must not receive shortcuts beneath a sheet.
var key_presses: int = 0
@export var initialization_delay_ms: int = 0

func _ready() -> void:
	if initialization_delay_ms > 0:
		OS.delay_msec(initialization_delay_ms)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		key_presses += 1
