extends Node3D
## Authored paper, wax and ribbon tails, driven by simulation time.
var age := 100.0
var duration := 6.0

func start(seconds: float) -> void:
	age = 0.0
	duration = seconds
	$Seal.show()
	$PaperBits.restart()
	tick(0.0)

func finish() -> void:
	age = duration

func tick(delta: float) -> void:
	if age > duration + 0.4:
		return
	age += delta
	var progress := clampf(age / 0.22, 0.0, 1.0)
	var rebound := 1.0 + 2.4 * pow(progress - 1.0, 3.0) + 1.4 * pow(progress - 1.0, 2.0)
	var release := smoothstep(duration - 0.12, duration + 0.35, age)
	$Seal.scale = Vector3.ONE * lerpf(0.5, 1.0, rebound) * (1.0 - release * 0.4)
	$Seal.position.y = release * 0.55
	$Seal.rotation.z = -0.10 + release * 0.7
	$Seal/Paper.material.set_shader_parameter("visual_time", age)
	$Seal/Paper.material.set_shader_parameter("release", release)
	$Seal.visible = age < duration + 0.35

func set_running(value: bool) -> void:
	$PaperBits.speed_scale = 1.0 if value else 0.0
