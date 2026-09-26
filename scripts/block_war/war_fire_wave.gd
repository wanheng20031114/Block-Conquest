class_name WarFireWave
extends Node3D
## The same expanding radius drives the ground material, emitters and casualties.

const EXPANSION_TIME := 1.15
const WINDUP_TIME := preload("res://scripts/block_war/war_skill_rules.gd").FIRE_WINDUP
const EMISSION_TIME := 1.65
const BURN_TIME := 2.15
const LIFETIME := 3.0
var age := LIFETIME
var radius := 4.5
var faction := 0
var hit_buildings: Dictionary = {}

func start(at: Vector3, reach: float, caster: int = 0) -> void:
	position = at
	radius = reach
	faction = caster
	age = -WINDUP_TIME
	hit_buildings.clear()
	$Ground.scale = Vector3.ONE * reach
	$Ground.material_override.set_shader_parameter("windup_time", WINDUP_TIME)
	show()
	_update_visual()
	for particles: GPUParticles3D in [$Flames, $Afterfire, $Smoke]:
		particles.emitting = false
	$Sparks.restart()

func front(at_age: float) -> float:
	if is_equal_approx(at_age, EXPANSION_TIME):
		return radius
	return radius * clampf(at_age / EXPANSION_TIME, 0.0, 1.0)

func segment(delta: float) -> Dictionary:
	return {"center": global_position, "from_radius": front(age), "to_radius": front(age + delta),
		"active_fraction": minf(1.0, (BURN_TIME - age) / delta)}

func tick(delta: float) -> void:
	if age >= LIFETIME:
		return
	var warming := age < 0.0
	age += delta
	if warming and age >= -0.000001:
		age = maxf(0.0, age)
		for particles: GPUParticles3D in [$Flames, $Afterfire, $Sparks, $Smoke]:
			particles.restart()
	_update_visual()
	if age >= EMISSION_TIME:
		$Flames.emitting = false
		$Afterfire.emitting = false
		$Sparks.emitting = false
		$Smoke.emitting = false
	if age >= LIFETIME:
		hide()

func _update_visual() -> void:
	var reach := maxf(0.05, front(age))
	for particles: GPUParticles3D in [$Flames, $Afterfire, $Sparks, $Smoke]:
		var material: ParticleProcessMaterial = particles.process_material
		material.emission_ring_radius = reach
		material.emission_ring_inner_radius = 0.0 if particles == $Afterfire else maxf(0.0, reach - 0.48)
	$Ground.material_override.set_shader_parameter("age", age)
	$Flames.draw_pass_1.material.set_shader_parameter("visual_time", age)
	$Light.light_energy = (0.3 + 0.5 * (1.0 + age / WINDUP_TIME)) if age < 0.0 else 2.2 * (1.0 - smoothstep(1.1, LIFETIME, age))

func set_running(value: bool) -> void:
	for particles: GPUParticles3D in [$Flames, $Afterfire, $Sparks, $Smoke]:
		particles.speed_scale = 1.0 if value else 0.0
