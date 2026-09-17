class_name DefensiveGunVisual
extends Node3D
## Authored turret parts; this presenter never chooses targets or deals damage.
const TURN_SPEED := 3.6
const FIRE_LENGTH := 0.9
const MIN_PITCH := -.14
const MAX_PITCH := .35
@onready var turret: Node3D = $Turret
@onready var elevation: Node3D = $Turret/Elevation
@onready var muzzle: Marker3D = $Turret/Elevation/Barrel/Muzzle
@onready var animation: AnimationPlayer = $AnimationPlayer

func aim_at(target: Vector3, delta: float) -> bool:
	var local_target: Vector3 = to_local(target)
	var direction: Vector3 = local_target - turret.position - elevation.position
	var yaw: float = atan2(-direction.x, -direction.z)
	turret.rotation.y = wrapf(rotate_toward(turret.rotation.y, yaw, TURN_SPEED * delta), -PI, PI)
	# A bounded depression arc keeps the tube above its own stone platform.
	var pitch: float = clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), MIN_PITCH, MAX_PITCH)
	elevation.rotation.x = move_toward(elevation.rotation.x, pitch, TURN_SPEED * delta)
	return absf(angle_difference(turret.rotation.y, yaw)) < .06

func fire() -> void:
	animation.play("fire")
	animation.advance(0.0)

func sample_fire(phase: float) -> void:
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play("fire")
	animation.seek(clampf(phase, 0.0, FIRE_LENGTH), true, true)

func sample_remote(a: Dictionary, b: Dictionary, weight: float, playback: float) -> void:
	turret.rotation.y = lerp_angle(float(a.yaw), float(b.yaw), weight)
	elevation.rotation.x = lerpf(float(a.pitch), float(b.pitch), weight)
	var stamp: float = float(b.fired) if float(b.fired) <= playback else float(a.fired)
	sample_fire(playback - stamp if stamp >= 0.0 else FIRE_LENGTH)
