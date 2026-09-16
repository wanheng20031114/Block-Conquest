class_name HeroWeaponDefinition
extends Resource

@export var display_name: String = "连发火枪"
@export var attack_bonus: float = 20.0
@export var range: float = 20.0
@export var interval: float = .65
@export var magazine_size: int = 10
@export var reload_seconds: float = 1.8
@export var channel: CombatDefinition.DamageChannel = CombatDefinition.DamageChannel.RANGED
@export var armor_penetration: float = 0.0
@export var model: PackedScene
