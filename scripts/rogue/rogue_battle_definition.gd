class_name RogueBattleDefinition
extends Resource
## Encounter balance, independent from the competitive catalog.
@export var id: String = "outpost"
@export var title: String = "前哨站"
@export_range(1, 5) var difficulty: int = 1
@export var emergency_hp_multiplier: float = 1.25
@export var emergency_damage_multiplier: float = 1.15
@export var emergency_reinforcements: Array[Dictionary] = []
@export var size: Vector2 = Vector2(112, 64)
@export var map_scene: PackedScene
@export var duration: float = 150.0
@export var enemy_cap: int = 24
@export var tower_hp: float = 360.0
@export var tower_armor: float = 2.0
## Base attack; existing anti-infantry/cavalry bonuses remain part of the unit matchup rules.
@export var tower_damage: float = 9.0
@export var tower_range: float = 10.0
@export var barracks_hp: float = 520.0
@export var base_hp: float = 1500.0
@export var base_armor: float = 3.0
@export var base_damage: float = 24.0
@export var base_range: float = 10.0
@export var base_cooldown: float = 2.0
@export var waves: Array[Dictionary] = []
