extends Node3D
## A scene-authored native particle pool for short capture and ability bursts.

var _next: int = 0
var _light_remaining: float = 0.0

func burst(at: Vector3, color: Color, impact: bool = false) -> void:
	var particles: GPUParticles3D = $Bursts.get_child(_next)
	_next = (_next + 1) % $Bursts.get_child_count()
	particles.position = at + Vector3(0, 0.5, 0)
	var material: ParticleProcessMaterial = particles.process_material
	material.color = color
	material.initial_velocity_min = 3.0 if impact else 1.1
	material.initial_velocity_max = 6.0 if impact else 2.8
	particles.restart()
	particles.emitting = true
	if impact:
		$ImpactLight.position = at + Vector3(0, 2.0, 0)
		$ImpactLight.light_energy = 3.5
		_light_remaining = 0.35

func shield(at: Vector3) -> void:
	$Shield.position = at + Vector3(0, 1.0, 0)
	$Shield.show()

func tick(delta: float, shield_active: bool) -> void:
	_light_remaining = maxf(0.0, _light_remaining - delta)
	$ImpactLight.light_energy = _light_remaining * 10.0
	$Shield.visible = shield_active

func set_running(value: bool) -> void:
	for particles: GPUParticles3D in $Bursts.get_children():
		particles.speed_scale = 1.0 if value else 0.0
