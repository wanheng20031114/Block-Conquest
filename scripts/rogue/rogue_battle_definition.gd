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
@export_group("Outpost recruitment")
## Scenario training has no gold income or paid queues. A full garrison skips a
## recruitment slot instead of accumulating reinforcements for a later burst.
@export var barracks_first_recruit_seconds: float = 35.0
@export var barracks_recruit_stagger_seconds: float = 6.0
@export var barracks_recruit_interval: float = 32.0
@export var barracks_recruit_cycle: PackedStringArray = ["swordsman", "spearman", "archer"]
@export_group("Outpost tactics")
@export var guard_response_radius: float = 16.0
@export var support_response_radius: float = 24.0
@export var support_alert_seconds: float = 8.0
@export var guard_chase_radius: float = 26.0
@export var scout_start_seconds: float = 8.0
@export var raid_muster_size: int = 3
@export var raid_muster_radius: float = 12.0
@export var raid_muster_timeout: float = 18.0
@export var raid_muster_point: Vector3 = Vector3(22, 0, 0)
@export var search_waypoints: PackedVector3Array = [Vector3(-38, 0, -10), Vector3(-38, 0, 10), Vector3(-12, 0, 15), Vector3(-12, 0, -15)]
@export_group("Fortifications")
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
