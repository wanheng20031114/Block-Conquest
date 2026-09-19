class_name MonsterDefinition
extends UnitDefinition
## Isolated PVE prototypes. Their level is a selection tier, not a stat multiplier.

enum Ability { NONE, RALLY }

@export_range(1, 3) var pve_tier: int = 1
@export var monster_faction: StringName = &"monsters"
@export_file("*.tscn") var visual_scene_path: String
@export var monster_ability: Ability = Ability.NONE
## Reserved PVE ability data; no runtime aura or recovery component consumes it yet.
@export var rally_radius: float = 0.0
@export var rally_speed_bonus: float = 0.0
@export var rally_duration: float = 0.0
@export var rally_period: float = 0.0

func _support_validation_errors() -> PackedStringArray:
	if monster_ability != Ability.RALLY:
		return super._support_validation_errors()
	var errors := PackedStringArray()
	if role != Role.SUPPORT:
		errors.append("摇铃鼓舞需要支援职责")
	if not support_kind.is_empty():
		errors.append("摇铃鼓舞不使用生命恢复支援能力")
	return errors

func validation_errors() -> PackedStringArray:
	var errors := super.validation_errors()
	if pve_tier < 1 or pve_tier > 3:
		errors.append("怪物强度级别必须为1至3级")
	if monster_faction != &"monsters":
		errors.append("怪物原型必须属于怪物阵营")
	if not visual_scene_path.begins_with("res://") or not visual_scene_path.ends_with(".tscn"):
		errors.append("怪物模型必须引用原生场景路径")
	if monster_ability not in [Ability.NONE, Ability.RALLY]:
		errors.append("未知怪物能力")
	if monster_ability == Ability.RALLY:
		if not is_finite(rally_radius) or rally_radius <= 0.0:
			errors.append("鼓舞半径必须为正有限数")
		if not is_finite(rally_speed_bonus) or rally_speed_bonus <= 0.0:
			errors.append("鼓舞移速增幅必须为正有限数")
		if not is_finite(rally_duration) or rally_duration <= 0.0:
			errors.append("鼓舞持续时间必须为正有限数")
		if not is_finite(rally_period) or rally_period < rally_duration:
			errors.append("鼓舞间隔必须为不短于持续时间的有限数")
	elif rally_radius != 0.0 or rally_speed_bonus != 0.0 or rally_duration != 0.0 or rally_period != 0.0:
		errors.append("无鼓舞能力的怪物不能配置鼓舞数值")
	return errors
