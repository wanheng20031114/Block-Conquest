extends Node3D
## An authored wax stamp and crossed paper seal, advanced by the match clock.
const STAMP_TIME := 0.22
const RELEASE_TIME := 0.55

var age := 100.0
var duration := 6.0
var _stamped := false
var _released := false

@onready var _seal: Node3D = $Seal
@onready var _ground_ring: MeshInstance3D = $GroundRing
@onready var _impact_ring: MeshInstance3D = $ImpactRing
@onready var _paper: ShaderMaterial = $Seal/Paper.material
@onready var _ground_material: ShaderMaterial = $GroundRing.material_override
@onready var _impact_material: ShaderMaterial = $ImpactRing.material_override


func start(seconds: float) -> void:
	age = 0.0
	duration = seconds
	_stamped = false
	_released = false
	$PaperBits.emitting = false
	tick(0.0)


func finish() -> void:
	age = duration
	tick(0.0)


func tick(delta: float) -> void:
	if age > duration + RELEASE_TIME:
		return
	age += delta
	if not _stamped and age >= STAMP_TIME:
		_stamped = true
		$PaperBits.restart()
	if not _released and age >= duration:
		_released = true
		$PaperBits.restart()
	var arrival := clampf(age / STAMP_TIME, 0.0, 1.0)
	var landing := pow(1.0 - arrival, 2.0)
	var after_stamp := maxf(0.0, age - STAMP_TIME)
	var rebound := sin(after_stamp * 19.0) * exp(-after_stamp * 9.0) * 0.16
	var release := smoothstep(duration, duration + RELEASE_TIME, age)
	var pulse := sin(age * 5.2)
	var scale_factor := (1.0 + landing * 0.5 - rebound + pulse * 0.025) * (1.0 - release * 0.9)
	_seal.scale = Vector3.ONE * scale_factor
	_seal.position = Vector3(0, landing * 1.65 + sin(age * 2.6) * 0.055 + release * 1.1, landing * 0.45)
	_seal.rotation = Vector3(-0.65 + landing * 0.18, 0, -0.10 + sin(age * 3.1) * 0.045 + release * 0.55)
	$Seal/RibbonLeft.rotation.z = -0.3 + sin(age * 5.0) * 0.15
	$Seal/RibbonRight.rotation.z = 0.34 + sin(age * 5.0 + 1.4) * 0.15
	_paper.set_shader_parameter("visual_time", age * 1.7)
	_paper.set_shader_parameter("release", release)
	_seal.visible = age < duration + RELEASE_TIME

	# Fine, broken ground strokes leave the building and nearby troops readable.
	var ring_scale := lerpf(0.7, 1.0, smoothstep(STAMP_TIME, 0.65, age)) + release * 0.18
	_ground_ring.scale = Vector3.ONE * ring_scale
	_ground_ring.visible = age >= STAMP_TIME and age < duration + RELEASE_TIME
	_ground_material.set_shader_parameter("visual_time", age)
	_ground_material.set_shader_parameter("opacity", (1.0 - release) * 0.8)

	var impact := clampf(after_stamp / 0.5, 0.0, 1.0)
	_impact_ring.visible = age >= STAMP_TIME and impact < 1.0
	_impact_ring.scale = Vector3.ONE * lerpf(0.55, 1.8, impact)
	_impact_material.set_shader_parameter("visual_time", age)
	_impact_material.set_shader_parameter("opacity", (1.0 - impact) * 0.85)


func set_running(value: bool) -> void:
	$PaperBits.speed_scale = 1.0 if value else 0.0
