class_name HeroItemDefinition
extends Resource
enum Effect { HEAL, SPEED }
@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var effect: Effect
@export var stack_limit: int = 5
@export var amount: float
@export var duration: float
@export var cooldown: float
