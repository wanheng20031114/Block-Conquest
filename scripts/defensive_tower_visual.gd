class_name DefensiveTowerVisual
extends Node3D
## Authored battery: one transform hierarchy and AnimationPlayer per gun.
const FIRE_LENGTH := DefensiveGunVisual.FIRE_LENGTH
@export var gun_paths: Array[NodePath] = [NodePath("Gun")]
var guns: Array[DefensiveGunVisual] = []

func _ready() -> void:
	for path: NodePath in gun_paths:
		var gun: DefensiveGunVisual = get_node(path)
		assert(gun != null and gun not in guns)
		guns.append(gun)

func set_manual() -> void:
	for gun: DefensiveGunVisual in guns:
		gun.animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

func sample_fire(phase: float) -> void:
	for gun: DefensiveGunVisual in guns:
		gun.sample_fire(phase)

func sample_remote(a: Array, b: Array, weight: float, playback: float) -> void:
	for index: int in guns.size():
		guns[index].sample_remote(a[index], b[index], weight, playback)
