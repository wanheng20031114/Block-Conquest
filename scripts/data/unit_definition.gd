class_name UnitDefinition
extends CombatDefinition

enum Role { COMBAT, SUPPORT, CONSTRUCTION }
const ROLE_NAMES: PackedStringArray = ["作战", "支援", "建设"]
@export var role: Role = Role.COMBAT

## Seconds from attack start to melee contact or projectile release.
@export var attack_windup_seconds: float = 0.22
@export var health_bar_height: float = 2.45
## Full capsule height; keep the legacy diameter floor for large footprints.
@export var collision_height: float = 1.8
@export var death_rest_height: float = 0.15
@export var cost: int = 0
@export var supply: int = 1
@export var speed: float = 3.5
@export var radius: float = 0.5
@export var sight: float = 10.0
@export var min_range: float = 0.0
## Explicit eligibility for the academy barrel-length research.
@export var cannon_range_upgrades: bool = false
## Each weapon owns a target, windup and cooldown; no shared volley clock.
@export_range(1, 3) var independent_weapons: int = 1
@export var weapon_arc_degrees: float = 0.0
@export var splash_radius: float = 0.0
@export var projectile: String = ""
@export var production_building: StringName
@export var training_seconds: float = 0.0
## Derived from role: support uses military supply, construction uses worker slots.
var military: bool:
	get: return role != Role.CONSTRUCTION
## Authored support capability; recovery uses a separate authority-only channel.
@export var support_kind: StringName
@export var support_range: float = 0.0
@export var support_amount: float = 0.0
@export var support_period: float = 1.0
@export var support_windup_seconds: float = 1.0
@export var support_discovery_range: float = 0.0
@export var support_auto_chase: bool = true

func is_support() -> bool:
	return role == Role.SUPPORT

func is_construction() -> bool:
	return role == Role.CONSTRUCTION

func role_label() -> String:
	return ROLE_NAMES[role]

func validation_errors() -> PackedStringArray:
	var errors := super.validation_errors()
	if combat_class == &"building": errors.append("单位不能使用建筑类别")
	if role < Role.COMBAT or role > Role.CONSTRUCTION: errors.append("未知单位职责")
	if is_support() != (not support_kind.is_empty()): errors.append("支援职责必须与支援能力一致")
	if support_kind not in [&"", &"repair", &"heal"]: errors.append("未知支援能力")
	if is_construction() != (supply == 0): errors.append("建设单位使用农民名额，军事单位必须占人口")
	if (damage_channel == DamageChannel.RANGED) != (not projectile.is_empty()): errors.append("攻击方式与投射物配置不一致")
	if projectile not in ["", "arrow", "bolt", "bullet", "stone", "cannon"]: errors.append("未知投射物类型")
	return errors
