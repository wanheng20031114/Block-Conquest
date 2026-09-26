extends Node3D
## A physical earth lip, dark opening, grass tufts and a courier pennant.
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var age := 100.0
var duration := 3.4
var last_batch := -1
var running := true

func start(at: Vector3, direction: Vector3, seconds: float, tint: Color) -> void:
	position = at
	rotation.y = atan2(-direction.x, -direction.z)
	age = 0.0
	duration = seconds
	last_batch = -1
	$Mouth.show()
	$Mouth/Pennant.material.set_shader_parameter("paper_color", tint.lightened(0.15))
	$Dust.restart()
	$Dust.emitting = true
	_soil(18)
	tick(0.0)

func _soil(count: int) -> void:
	for i: int in count:
		var angle := i * 2.399963 + age * 5.0
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		$Soil.emit_particle(Transform3D(Basis.IDENTITY, global_position + radial * 0.7 + Vector3.UP * 0.15), radial * 0.8 + Vector3.UP * (1.0 + float(i % 3) * 0.3), Color("876344"), Color(), FLAGS)

func tick(delta: float) -> void:
	if not running or age > duration + 0.5:
		return
	age += delta
	var open := 1.0 + sin(age * 24.0) * exp(-age * 10.0) * 0.12
	var close := 1.0 - smoothstep(duration, duration + 0.4, age)
	$Mouth.scale = Vector3(1.25 * open * close, maxf(0.05, close), open * close)
	$Mouth.position.y = sin(age * 31.0) * 0.018 * exp(-age * 14.0)
	$Mouth/Pennant.material.set_shader_parameter("visual_time", age)
	var batch := floori(age / RULES.BURROW_BATCH_INTERVAL)
	if batch >= 0 and batch != last_batch and age < duration:
		_soil(6)
		last_batch = batch
	$Dust.emitting = age < duration
	$Mouth.visible = age < duration + 0.4

func reset() -> void:
	age = 100.0
	last_batch = -1
	$Mouth.hide()
	for particles: GPUParticles3D in [$Soil, $Dust]:
		particles.restart()
		particles.emitting = false

func set_running(value: bool) -> void:
	running = value
	$Soil.speed_scale = 1.0 if value else 0.0
	$Dust.speed_scale = 1.0 if value else 0.0
