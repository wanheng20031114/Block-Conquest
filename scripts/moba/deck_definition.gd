class_name MobaDeckDefinition
extends Resource
@export var cards: Array[MobaCardDefinition] = []
@export var opening_hand: PackedStringArray
@export var starting_gold: int = 240
@export var hand_size: int = 5
@export var refill_seconds: float = 1.5
