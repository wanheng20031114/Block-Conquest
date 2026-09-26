extends Node3D
## The match supplies remaining time; this node only animates its authored indicator.

const DURATION := 15.0
var remaining := 0.0
var age := 0.0
var running := true

func _ready() -> void:
	set_process(false)
	hide()

func set_remaining(seconds: float) -> void:
	if seconds > remaining + 0.1:
		age = 0.0
	remaining = maxf(0.0, seconds)
	visible = remaining > 0.0
	set_process(visible and running)
	$Countdown.text = "R · %d" % ceili(remaining)
	$Halo.material_override.set_shader_parameter("remaining_ratio", clampf(remaining / DURATION, 0.0, 1.0))
	_update_visual()

func _process(delta: float) -> void:
	age += delta
	_update_visual()

func _update_visual() -> void:
	$Halo.material_override.set_shader_parameter("visual_time", age)
	$Emblem.position.y = 4.85 + sin(age * 3.2) * 0.09
	$Emblem.rotation.y = sin(age * 1.8) * 0.16
	var pulse := 1.0 + sin(age * (7.0 if remaining < 3.0 else 3.2)) * 0.07
	$Emblem.scale = Vector3.ONE * pulse
	$Countdown.modulate = Color("f6d46b") if remaining < 3.0 else Color("e6ffe9")

func set_running(value: bool) -> void:
	running = value
	set_process(remaining > 0.0 and running)
