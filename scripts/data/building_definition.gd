class_name BuildingDefinition
extends CombatDefinition

@export var cost: int = 0
@export var cost_progression: PackedInt32Array = PackedInt32Array()
@export var build_seconds: float = 20.0
@export var radius: float = 3.0
@export var size: Vector3 = Vector3(6, 4, 5)
@export var bar_height: float = 5.9
@export var model: String
@export_range(-180, 180, 1, "radians_as_degrees") var model_yaw: float = 0.0
@export_range(-180, 180, 1, "radians_as_degrees") var weapon_rest_yaw: float = 0.0
@export var produces: PackedStringArray = PackedStringArray()
@export_enum("arrow", "cannon") var projectile: String = "arrow"
@export_range(1, 4) var weapon_count: int = 1

func cost_after_placements(paid_placements: int) -> int:
	if cost_progression.is_empty():
		return cost
	return cost_progression[clampi(paid_placements, 0, cost_progression.size() - 1)]
