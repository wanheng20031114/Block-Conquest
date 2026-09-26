extends Node3D
## A physical earth lip, dark opening, grass tufts and a courier pennant.
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
var age := 100.0
var duration := 3.4
var last_batch := -1

func start(at: Vector3, direction: Vector3, seconds: float) -> void:
	position = at
	rotation.y = atan2(-direction.x, -direction.z)
	age = 0.0
	duration = seconds
	last_batch = -1
	$Mouth.show()
	$Dust.restart()
	$Dust.emitting = true
	_soil(12)
	tick(0.0)

func _soil(count: int) -> void:
	for i: int in count:
		var angle := i * 2.399963 + age * 5.0
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		$Soil.emit_particle(Transform3D(Basis.IDENTITY, global_position + radial * 0.7 + Vector3.UP * 0.15), radial * 0.8 + Vector3.UP * (1.0 + float(i % 3) * 0.3), Color("876344"), Color(), FLAGS)

func tick(delta: float) -> void:
	if age > duration + 0.5:
		return
	age += delta
	var open := lerpf(0.18, 1.0, smoothstep(0.05, 1.2, age))
	var close := 1.0 - smoothstep(duration, duration + 0.4, age)
	$Mouth.scale = Vector3(1.25 * open * close, maxf(0.05, close), open * close)
	$Mouth.position.y = sin(age * 31.0) * 0.018 * (1.0 - smoothstep(0.5, 1.2, age))
	$Mouth/Pennant.material.set_shader_parameter("visual_time", age)
	var batch := floori((age - 1.2) / 0.4)
	if batch >= 0 and batch != last_batch and age < duration:
		_soil(6)
		last_batch = batch
	$Dust.emitting = age < duration
	$Mouth.visible = age < duration + 0.4

func set_running(value: bool) -> void:
	$Soil.speed_scale = 1.0 if value else 0.0
	$Dust.speed_scale = 1.0 if value else 0.0
