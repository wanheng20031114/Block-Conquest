class_name CombatDefinition
extends Resource
## Shared, editor-visible combat data. Catalog resources are never mutated at runtime.

enum DamageChannel { MELEE, RANGED }
const CLASS_NAMES: Dictionary = {&"infantry": "步兵", &"cavalry": "骑兵", &"siege": "攻城器", &"building": "建筑"}
const GROUP_NAMES: Dictionary = {&"infantry": "步兵", &"ranged_infantry": "远程步兵", &"melee_infantry": "近战步兵", &"cavalry": "骑兵", &"siege": "攻城器", &"building": "建筑"}

@export var id: StringName
@export var name: String
@export_multiline var description: String
@export var hp: float = 1.0
@export var damage: float = 0.0
@export var melee_armor: float = 0.0
@export var ranged_armor: float = 0.0
## Siege engines remain vulnerable to melee even after military defense research.
@export var melee_defense_upgrades: bool = true
@export var damage_channel: DamageChannel = DamageChannel.MELEE
## Fixed armor ignored after defense research; never turns excess penetration into damage.
@export_range(0.0, 100.0) var armor_penetration: float = 0.0
## Physical family, independent of attack channel and a unit's strategic role.
@export var combat_class: StringName
@export var bonuses: Dictionary = {}
@export var range: float = 0.0
@export var cooldown: float = 1.0
## Ground-plane impact radius. Zero keeps the projectile strictly single-target.
@export_range(0.0, 20.0) var splash_radius: float = 0.0

func is_ranged_infantry() -> bool:
	return combat_class == &"infantry" and damage_channel == DamageChannel.RANGED

func matches_combat_group(group: StringName) -> bool:
	match group:
		&"ranged_infantry": return is_ranged_infantry()
		&"melee_infantry": return combat_class == &"infantry" and damage_channel == DamageChannel.MELEE
	return combat_class == group

func channel_label() -> String:
	return "远程攻击" if damage_channel == DamageChannel.RANGED else "近战攻击"

func formation_label() -> String:
	if combat_class == &"infantry":
		return "远程步兵" if is_ranged_infantry() else "近战步兵"
	return CLASS_NAMES[combat_class]

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not CLASS_NAMES.has(combat_class): errors.append("未知兵种类别: " + combat_class)
	if damage_channel not in [DamageChannel.MELEE, DamageChannel.RANGED]: errors.append("未知攻击方式")
	if armor_penetration < 0.0: errors.append("穿甲值不能为负")
	if not is_finite(splash_radius) or splash_radius < 0.0: errors.append("溅射半径必须为非负有限数")
	for group: StringName in bonuses:
		if not GROUP_NAMES.has(group): errors.append("未知附伤类别: " + group)
		if float(bonuses[group]) < 0.0: errors.append("附伤不能为负")
	return errors
