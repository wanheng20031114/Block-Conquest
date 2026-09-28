class_name WarFireWave
extends Node3D
## Read-only native renderer of an independent fire rule state.

const STATE := preload("res://scripts/block_war/war_fire_state.gd")
const EXPANSION_TIME := STATE.EXPANSION_TIME
const IGNITION_RADIUS := STATE.IGNITION_RADIUS
const EMISSION_TIME := STATE.EMISSION_TIME
const BURN_TIME := STATE.BURN_TIME
const LIFETIME := STATE.LIFETIME
var age := LIFETIME
var radius := 4.5
var faction := 0
var effect_id := 0

func start(at: Vector3, reach: float, caster: int = 0) -> void:
	position = at
	radius = reach
	faction = caster
	age = 0.0
	$Ground.scale = Vector3.ONE * reach
	$Ground.material_override.set_shader_parameter("expansion_time", EXPANSION_TIME)
	$Ground.material_override.set_shader_parameter("ignition_ratio", minf(1.0, IGNITION_RADIUS / reach))
	show()
	_update_visual()
	for particles: GPUParticles3D in [$Flames, $Afterfire, $Sparks, $Smoke]:
		particles.restart()
		particles.emitting = true

func front(at_age: float) -> float:
	return STATE.radius_at(radius, at_age)

func sync_state(state: RefCounted) -> void:
	if effect_id != state.effect_id:
		effect_id = state.effect_id
		start(state.global_position, state.radius, state.faction)
	age = state.age
	position = state.global_position
	radius = state.radius
	faction = state.faction
	_update_visual()
	visible = age < LIFETIME
	if age >= EMISSION_TIME:
		for particles: GPUParticles3D in [$Flames, $Afterfire, $Sparks, $Smoke]:
			particles.emitting = false

func clear_visual() -> void:
	if effect_id == 0:
		return
	effect_id = 0
	age = LIFETIME
	hide()
	$Light.light_energy = 0.0
	for particles: GPUParticles3D in [$Flames, $Afterfire, $Sparks, $Smoke]:
		particles.emitting = false

func tick(delta: float) -> void:
	if age >= LIFETIME:
		return
	age += delta
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
	$Light.light_energy = 2.2 * (1.0 - smoothstep(1.1, LIFETIME, age))

func set_running(value: bool) -> void:
	for particles: GPUParticles3D in [$Flames, $Afterfire, $Sparks, $Smoke]:
		particles.speed_scale = 1.0 if value else 0.0
